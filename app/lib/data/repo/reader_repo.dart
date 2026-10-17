import 'dart:async';
import 'dart:collection';

import '../dao/chapters_dao.dart';
import '../dao/series_dao.dart';
import '../sources/source_api.dart';
import '../storage/blob_store.dart';
import '../storage/image_pipeline.dart';

/// One slot of the chapter's page list (doc 10 §Widget tree). [hash] non-
/// null means a fetch happened before — but the blob may have been evicted,
/// so `cached` is only a hint; disk truth is checked in the repo.
class ReaderPageRef {
  const ReaderPageRef({
    required this.idx,
    required this.url,
    this.hash,
    this.width,
    this.height,
  });

  final int idx;
  final String url;
  final String? hash;
  final int? width;
  final int? height;

  bool get hasDims => width != null && height != null && width! > 0;
}

/// A resolved page: relative path under the library root (+ dims sniffed
/// from the original bytes, doc 03). [hash] is the content hash — callers
/// use it to persist fallback results back onto the requested chapter.
class PageFile {
  const PageFile({required this.path, this.hash, this.width, this.height});

  final String path;
  final String? hash;
  final int? width;
  final int? height;
}

/// The chapter the reader is currently serving — which may be a FALLBACK
/// sibling when the tapped source failed (07 §5).
class LoadedChapter {
  const LoadedChapter({
    required this.chapter,
    required this.pages,
    required this.referer,
  });

  final Chapter chapter;
  final List<ReaderPageRef> pages;
  final String referer;
}

/// Max-N concurrent task pool (doc 10 §Prefetch: "serial worker queue,
/// max 2 active image fetches"). Pure microtask logic — no timers, safe
/// under FakeAsync.
class TaskQueue {
  TaskQueue({required this.maxActive});

  final int maxActive;
  final Queue<Completer<void>> _waiters = Queue();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= maxActive) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}

/// Reader-side orchestration (doc 10 + 07 §5): chapter page lists (with
/// whole-chapter source fallback), single-page fetch through the shared
/// pipeline, and adjacent-chapter resolution for auto-next.
class ReaderRepo {
  ReaderRepo({
    required this.sources,
    required this.seriesDao,
    required this.chaptersDao,
    required this.blobs,
    required this.pipeline,
  });

  final List<Source> sources;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final BlobStore blobs;
  final ImagePipeline pipeline;

  /// Image fetches go through the shared 2-slot pool (doc 10 §Prefetch).
  final TaskQueue queue = TaskQueue(maxActive: 2);

  Source? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Chapter open (doc 10 §Prefetch): serve the DB page list; missing →
  /// fetch from the chapter's own source; that failing → whole-chapter
  /// fallback across the sibling sources that carry the same number (07
  /// §5). Throws when every candidate fails.
  Future<LoadedChapter> loadChapter(Chapter chapter) async {
    final candidates = [chapter, ...await siblings(chapter)];
    Object? lastError;
    for (final candidate in candidates) {
      final source = sourceById(candidate.sourceId);
      try {
        final pages = await _pageList(candidate, source);
        return LoadedChapter(
          chapter: candidate,
          pages: pages,
          referer: source?.referer ?? '',
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw SourceException(chapter.sourceId, SourceErrorKind.notFound,
        detail: 'all sources failed for chapter '
            '${chapter.number} ($lastError)');
  }

  Future<List<ReaderPageRef>> _pageList(
      Chapter chapter, Source? source) async {
    var rows = await chaptersDao.pages(chapter.id!);
    if (rows.isEmpty) {
      if (source == null) {
        throw SourceException(chapter.sourceId, SourceErrorKind.notFound,
            detail: 'unknown source, no cached pages');
      }
      final fetched = await source.pages(chapter.url);
      if (fetched.imageUrls.isEmpty) {
        throw SourceException(source.id, SourceErrorKind.parse,
            detail: 'empty page list');
      }
      rows = [
        for (var i = 0; i < fetched.imageUrls.length; i++)
          ChapterPage(chapterId: chapter.id!, idx: i, url: fetched.imageUrls[i]),
      ];
      await chaptersDao.replacePages(chapter.id!, rows);
      await chaptersDao.setPageCount(chapter.id!, rows.length);
    }
    return [
      for (final r in rows)
        ReaderPageRef(
          idx: r.idx,
          url: r.url,
          hash: r.contentHash,
          width: r.width,
          height: r.height,
        ),
    ];
  }

  /// Other sources' copies of the same chapter number (epsilon match, tab
  /// order) — the per-page AND whole-chapter fallback chain (07 §5).
  Future<List<Chapter>> siblings(Chapter chapter) =>
      chaptersDao.siblings(chapter.seriesId, chapter.number,
          excludeSourceId: chapter.sourceId);

  /// Disk truth for a fetched-before page: hash row + file both present →
  /// local path, no network (R2). Null → the slot must fetch.
  Future<PageFile?> cachedFile(ReaderPageRef ref) async {
    final hash = ref.hash;
    if (hash == null) return null;
    final row = await blobs.blobRow(hash);
    if (row == null) return null;
    if (!await blobs.exists(hash)) return null;
    return PageFile(
        path: row.path, hash: hash, width: ref.width, height: ref.height);
  }

  /// Resolve one page: fetch through the pipeline inside the shared queue,
  /// persist hash + dims (R2). Throws on failure — the screen handles
  /// per-page fallback.
  Future<PageFile> fetchPage(
      int chapterId, ReaderPageRef ref, String referer) {
    return queue.run(() async {
      final result =
          await pipeline.fetchAndStore(ref.url, referer: referer);
      await chaptersDao.setPageHash(chapterId, ref.idx, result.hash);
      await chaptersDao.setPageBytes(chapterId, ref.idx, result.storedBytes);
      if (result.width != null && result.height != null) {
        await chaptersDao.setPageDims(
            chapterId, ref.idx, result.width!, result.height!);
      }
      return PageFile(
          path: result.path,
          hash: result.hash,
          width: result.width,
          height: result.height);
    });
  }

  /// Next/previous chapter for auto-next and the chrome buttons: the
  /// nearest number beyond the current one that ANY source carries;
  /// prefer the SAME source's copy, else the first in tab order.
  Future<Chapter?> adjacentChapter(Chapter current, {required bool forward}) {
    return chaptersDao.adjacent(current, forward: forward);
  }

  /// Novel chapter body (doc 06/11): `chapter_text` first; missing →
  /// fetch via the source, persist, return. Novels live on nekopost only,
  /// so there is no cross-source fallback here.
  Future<String> loadNovelText(Chapter chapter) async {
    final existing = await chaptersDao.text(chapter.id!);
    if (existing != null) return existing;
    final source = sourceById(chapter.sourceId);
    if (source == null) {
      throw SourceException(chapter.sourceId, SourceErrorKind.notFound,
          detail: 'unknown source');
    }
    final text = await source.novelText(chapter.url);
    if (text == null || text.isEmpty) {
      throw SourceException(chapter.sourceId, SourceErrorKind.parse,
          detail: 'empty novel text');
    }
    await chaptersDao.saveText(chapter.id!, text);
    return text;
  }

  /// Shared page resolver for every reader mode: disk-first → own source
  /// fetch → per-page fallback across sibling sources (07 §5).
  ///
  /// Fallback details that matter for repeat reads:
  /// - a sibling whose copy is already on disk serves WITHOUT a download;
  /// - the resolved hash is written back onto the REQUESTED chapter's page
  ///   row, so the next open is a plain cache hit on the original ref.
  /// [onFallback] fires with the serving source id for the UI badge.
  Future<PageFile> resolvePage(
    LoadedChapter loaded,
    int idx, {
    void Function(String sourceId)? onFallback,
  }) async {
    final cached = await cachedFile(loaded.pages[idx]);
    if (cached != null) return cached;
    try {
      return await fetchPage(
          loaded.chapter.id!, loaded.pages[idx], loaded.referer);
    } catch (_) {
      for (final sib in await siblings(loaded.chapter)) {
        try {
          final sibLoaded = await loadChapter(sib);
          if (idx >= sibLoaded.pages.length) continue;
          final sibRef = sibLoaded.pages[idx];
          PageFile pf;
          final sibCached = await cachedFile(sibRef);
          if (sibCached != null) {
            pf = sibCached;
          } else {
            pf = await fetchPage(sibLoaded.chapter.id!, sibRef,
                sibLoaded.referer);
          }
          if (pf.hash != null) {
            await chaptersDao.setPageHash(
                loaded.chapter.id!, idx, pf.hash!);
          }
          onFallback?.call(sibLoaded.chapter.sourceId);
          return pf;
        } catch (_) {
          continue;
        }
      }
      rethrow;
    }
  }
}

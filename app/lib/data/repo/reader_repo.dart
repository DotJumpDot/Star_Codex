import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

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
/// [bands] is non-null when the page is an oversized strip sliced into
/// GPU-safe pieces (see ImagePipeline.bandsFor) — render those instead
/// of the parent file, which exceeds the max texture size.
class PageFile {
  const PageFile({
    required this.path,
    this.hash,
    this.width,
    this.height,
    this.bands,
  });

  final String path;
  final String? hash;
  final int? width;
  final int? height;
  final List<PageBand>? bands;
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
    if (kDebugMode) debugPrint('LOADCH enter ch=${chapter.id}');
    final candidates = [chapter, ...await siblings(chapter)];
    Object? lastError;
    for (final candidate in candidates) {
      final source = sourceById(candidate.sourceId);
      try {
        final pages = await _pageList(candidate, source);
        if (kDebugMode) {
          debugPrint('LOADCH ok src=${candidate.sourceId} '
              'n=${pages.length}');
        }
        return LoadedChapter(
          chapter: candidate,
          pages: pages,
          referer: source?.imageReferer ?? '',
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('LOADCH candidate FAIL src=${candidate.sourceId}: $e');
        }
        lastError = e;
      }
    }
    if (kDebugMode) debugPrint('LOADCH all failed err=$lastError');
    throw SourceException(chapter.sourceId, SourceErrorKind.notFound,
        detail: 'all sources failed for chapter '
            '${chapter.number} ($lastError)');
  }

  Future<List<ReaderPageRef>> _pageList(
    Chapter chapter, Source? source) async {
    var rows = await chaptersDao.pages(chapter.id!);
    if (rows.isNotEmpty && source != null && source.pageUrlsExpire) {
      // Signed-URL sources (nekopost CDN, 2026-11-01): a cached list is
      // dead the moment its `?verify=` tokens lapse — and rows cached
      // before the rollout hold UNSIGNED links that 403 forever (user
      // report: chapters that "keep loading, never done" on titles
      // opened pre-change, while fresh titles worked). Re-fetch the list
      // on every open; disk-cached pages still serve instantly via the
      // by-path hash carry-over in [_fetchPages].
      try {
        rows = await _fetchPages(chapter, source, previous: rows);
      } on Exception {
        // Offline / source down: stale rows still serve disk-cached
        // pages; the per-page fetch path surfaces the failure.
      }
    }
    if (rows.isEmpty) {
      if (source == null) {
        throw SourceException(chapter.sourceId, SourceErrorKind.notFound,
            detail: 'unknown source, no cached pages');
      }
      rows = await _fetchPages(chapter, source);
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

  /// Fetch the page list from [source] and persist it. When [previous]
  /// rows exist, hash/dims/bytes carry over by URL PATH (the signature
  /// lives in the query string, so the same image keeps the same path)
  /// — already-downloaded pages stay disk cache hits.
  Future<List<ChapterPage>> _fetchPages(
    Chapter chapter,
    Source source, {
    List<ChapterPage>? previous,
  }) async {
    final fetched = await source.pages(chapter.url);
    if (fetched.imageUrls.isEmpty) {
      throw SourceException(source.id, SourceErrorKind.parse,
          detail: 'empty page list');
    }
    final byPath = <String, ChapterPage>{
      for (final r in previous ?? const <ChapterPage>[])
        if (r.contentHash != null) _urlPath(r.url): r,
    };
    final rows = <ChapterPage>[];
    for (var i = 0; i < fetched.imageUrls.length; i++) {
      final url = fetched.imageUrls[i];
      final old = byPath[_urlPath(url)];
      rows.add(ChapterPage(
        chapterId: chapter.id!,
        idx: i,
        url: url,
        contentHash: old?.contentHash,
        width: old?.width,
        height: old?.height,
        bytes: old?.bytes,
      ));
    }
    await chaptersDao.replacePages(chapter.id!, rows);
    await chaptersDao.setPageCount(chapter.id!, rows.length);
    return rows;
  }

  static String _urlPath(String url) {
    final q = url.indexOf('?');
    return q >= 0 ? url.substring(0, q) : url;
  }

  /// Chapter page rows for the download queue: same revalidation as
  /// [_pageList] — signed-URL sources get a FRESH list, because a
  /// multi-hour queue must never ride links that lapse in minutes.
  Future<List<ChapterPage>> pageRowsForDownload(
    Chapter chapter, Source source) async {
    final rows = await chaptersDao.pages(chapter.id!);
    if (rows.isNotEmpty && source.pageUrlsExpire) {
      try {
        return await _fetchPages(chapter, source, previous: rows);
      } on Exception {
        return rows; // stale rows still describe the chapter's pages
      }
    }
    if (rows.isEmpty) {
      return await _fetchPages(chapter, source);
    }
    return rows;
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
    if (cached != null) return await _withBands(cached);
    try {
      return await _withBands(await fetchPage(
          loaded.chapter.id!, loaded.pages[idx], loaded.referer));
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
          return await _withBands(pf);
        } catch (_) {
          continue;
        }
      }
      rethrow;
    }
  }

  /// Oversized strips (taller than the GPU texture limit) render as a
  /// BLACK VOID — attach the persisted GPU-safe band slices instead
  /// (2026-10-21). Best-effort: on any failure the page renders whole.
  Future<PageFile> _withBands(PageFile pf) async {
    if (pf.hash == null ||
        (pf.height ?? 0) <= ImagePipeline.gpuBandThreshold) {
      return pf;
    }
    try {
      final bands = await pipeline.bandsFor(PageResult(
        hash: pf.hash!,
        path: pf.path,
        storedBytes: 0,
        width: pf.width,
        height: pf.height,
        fromCache: true,
      ));
      if (bands.isEmpty) return pf;
      return PageFile(
        path: pf.path,
        hash: pf.hash,
        width: pf.width,
        height: pf.height,
        bands: bands,
      );
    } catch (_) {
      return pf;
    }
  }
}

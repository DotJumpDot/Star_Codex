import 'dart:async';

import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';
import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart';
import '../dao/search_history_dao.dart';
import '../dao/series_dao.dart';
import '../dao/tags_dao.dart';
import '../sources/source_api.dart';
import '../storage/image_pipeline.dart';
import 'browse_merge.dart';

export 'browse_merge.dart';

class _SourceResult {
  const _SourceResult(this.source, this.items, this.error);

  final Source source;
  final List<SourceSeries> items;
  final Object? error;
}

/// Orchestrates source adapters → normalize → group (Plan/07 §3) for the
/// Browse screen. Adapters stay dumb; this is the only merge point.
class BrowseRepo {
  BrowseRepo({
    required this.sources,
    required this.seriesDao,
    required this.chaptersDao,
    required this.libraryDao,
    required this.tagsDao,
    required this.historyDao,
    this.pipeline,
  });

  final List<Source> sources;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final LibraryDao libraryDao;
  final TagsDao tagsDao;
  final SearchHistoryDao historyDao;

  /// Null in unit tests that don't exercise cover downloads.
  final ImagePipeline? pipeline;

  Source? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Source> _active(Set<String> onlySourceIds) {
    if (onlySourceIds.isEmpty) return sources;
    return sources.where((s) => onlySourceIds.contains(s.id)).toList();
  }

  Future<BrowsePage> search(String query,
      {Set<String> onlySourceIds = const {}, int page = 1}) async {
    final q = query.trim();
    if (q.isEmpty) return const BrowsePage(groups: []);
    final results = await _gather(
        _active(onlySourceIds), (s) => s.search(q, page: page));
    // Fire-and-forget: history must never delay results (and a DB write
    // can't complete inside a widget-test FakeAsync zone anyway).
    unawaited(historyDao
        .record(q, atMs: DateTime.now().millisecondsSinceEpoch)
        .catchError((Object _) {}));
    final groups = mergeIntoGroups(const [], _candidates(results));
    // Search results: biggest series first (nulls last).
    groups.sort((a, b) => (b.chapterCount ?? -1).compareTo(a.chapterCount ?? -1));
    return BrowsePage(groups: groups, failures: _failures(results));
  }

  Future<BrowsePage> latest(
      {Set<String> onlySourceIds = const {}, int page = 1}) async {
    final results =
        await _gather(_active(onlySourceIds), (s) => s.latest(page: page));
    // Latest feed keeps append order: each site's listing is already
    // newest-first; sources are interleaved (Plan/05 drift addendum —
    // listings carry no timestamps to sort by).
    return BrowsePage(
        groups: mergeIntoGroups(const [], _candidates(results)),
        failures: _failures(results));
  }

  Future<BrowsePage> genre(Source source, String term, {int page = 1}) async {
    final results =
        await _gather([source], (s) => s.browseGenre(term, page: page));
    return BrowsePage(
        groups: mergeIntoGroups(const [], _candidates(results)),
        failures: _failures(results));
  }

  Future<List<SourceGenre>> genres(Source source) => source.genres();

  Future<List<_SourceResult>> _gather(List<Source> active,
      Future<List<SourceSeries>> Function(Source) call) {
    return Future.wait(active.map((s) async {
      try {
        return _SourceResult(s, await call(s), null);
      } catch (e) {
        return _SourceResult(s, const [], e);
      }
    }));
  }

  List<BrowseCandidate> _candidates(List<_SourceResult> results) => [
        for (final r in results)
          for (final item in r.items)
            BrowseCandidate(
              sourceId: r.source.id,
              referer: r.source.referer,
              url: item.url,
              title: item.title,
              coverUrl: item.coverUrl,
              chapterCountHint: item.chapterCountHint,
              type: item.type,
            ),
      ];

  List<SourceFailure> _failures(List<_SourceResult> results) => [
        for (final r in results)
          if (r.error != null) SourceFailure(r.source.id, r.error!),
      ];

  /// Long-press quick action (Plan/08): fetch the primary source's detail,
  /// create/merge the series row (Plan/07 §4), save chapters + source link
  /// + tags, then best-effort cross-probe other sources (§3.2) and insert
  /// the library row. Returns the series id. Idempotent.
  Future<int> addToLibrary(SearchGroup group) async {
    final primary = group.primary;
    final source = sourceById(primary.sourceId);
    if (source == null) {
      throw StateError('unknown source: ${primary.sourceId}');
    }
    final detail = await source.detail(primary.url);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Identity order: an existing (source, url) link IS this series —
    // stronger than any title match (titles drift between listings).
    // Without it, re-adding under a drifted title would create a second
    // series row for the same page.
    final existingId =
        await seriesDao.findSeriesIdBySourceLink(source.id, primary.url);

    var title = group.displayTitle;
    var norm = normalizeTitle(title);
    if (norm.isEmpty) {
      // Pure-noise titles ('มังงะ') normalize to '' — the unique index on
      // title_norm would then fuse unrelated series onto one row. Fall
      // back to the richer detail-page title, then to a per-page escape
      // key (same-URL re-adds are already caught by the link check above,
      // so distinct URLs must stay distinct rows).
      title = detail.title;
      norm = normalizeTitle(title);
      if (norm.isEmpty) norm = 'raw:${primary.url}';
    }

    // original_title (L5 order 2): first majority-Latin alt whose norm
    // differs; ts pages carry no alt titles → often null (subtitle hidden).
    String? originalTitle;
    for (final alt in detail.altTitles) {
      final altNorm = normalizeTitle(alt);
      if (isMostlyLatin(alt) && altNorm.isNotEmpty && altNorm != norm) {
        originalTitle = alt;
        break;
      }
    }

    final type = detail.type ?? group.type;

    String? coverHash;
    final coverUrl = detail.coverUrl ?? primary.coverUrl;
    final pipe = pipeline;
    if (coverUrl != null && pipe != null) {
      try {
        coverHash =
            (await pipe.fetchAndStore(coverUrl, referer: source.referer)).hash;
      } catch (_) {
        // Cover is optional; series row still created.
      }
    }

    final seriesId = existingId ??
        await seriesDao.upsertByTitleNorm(Series(
          title: title,
          titleNorm: norm,
          originalTitle: originalTitle,
          coverHash: coverHash,
          type: type,
          origin: originForType(type),
          status: detail.status,
          description: detail.description,
          createdAt: now,
          updatedAt: now,
        ));

    // One transaction: a 900-chapter series must not land half-written.
    await chaptersDao.upsertAll([
      for (final ch in detail.chapters)
        Chapter(
          seriesId: seriesId,
          sourceId: source.id,
          number: ch.number,
          title: ch.title,
          url: ch.url,
          uploadedAt: ch.uploadedAt,
          fetchedAt: now,
        ),
    ]);

    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: source.id,
      sourceUrl: primary.url,
      sourceTitle: detail.title,
      altTitles: detail.altTitles,
      coverUrl: coverUrl,
      lastChapterNumber:
          detail.chapters.isEmpty ? null : detail.chapters.last.number,
      lastUpdatedAt:
          detail.chapters.isEmpty ? null : detail.chapters.last.uploadedAt,
      fetchedAt: now,
    ));
    if (detail.tags.isNotEmpty) {
      await tagsDao.setForSeries(seriesId, detail.tags);
    }

    await _crossProbe(seriesId, group, title, norm, detail.altTitles);
    await libraryDao.add(seriesId, now);
    return seriesId;
  }

  /// Plan/07 §3.2: probe other enabled sources with exact title queries;
  /// any merge-hit gets a series_sources row (lazy detail later). Blocked
  /// (Cloudflare) or erroring sources are skipped silently — this is a
  /// best-effort enrichment, never a failure. A (source, url) already
  /// linked to another series is never re-linked.
  Future<void> _crossProbe(int seriesId, SearchGroup group, String title,
      String titleNorm, List<String> altTitles) async {
    final groupCand = TitleCandidate(
      norm: titleNorm,
      altNorms: [
        for (final a in altTitles) normalizeTitle(a),
        for (final m in group.members) normalizeTitle(m.title),
      ],
    );
    final queries = <String>{
      title,
      group.primary.title,
      for (final m in group.members) m.title,
    }.toList();

    for (final other in sources) {
      if (other.id == group.primary.sourceId) continue;
      var linked = false;
      for (final q in queries.take(3)) {
        try {
          final items = await other.search(q);
          for (final item in items) {
            if (!merges(matchTitles(
                groupCand, TitleCandidate.fromRaw(item.title)))) {
              continue;
            }
            final owner =
                await seriesDao.findSeriesIdBySourceLink(other.id, item.url);
            if (owner != null && owner != seriesId) {
              linked = true; // already on another series — leave it there
              break;
            }
            await seriesDao.upsertSource(SeriesSource(
              seriesId: seriesId,
              sourceId: other.id,
              sourceUrl: item.url,
              sourceTitle: item.title,
              coverUrl: item.coverUrl,
              lastChapterNumber: item.chapterCountHint?.toDouble(),
              fetchedAt: DateTime.now().millisecondsSinceEpoch,
            ));
            linked = true;
            break;
          }
        } catch (_) {
          break; // source unreachable/blocked — skip it
        }
        if (linked) break;
      }
    }
  }
}

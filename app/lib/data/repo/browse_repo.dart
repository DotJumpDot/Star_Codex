import 'dart:async';

import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart';
import '../dao/search_history_dao.dart';
import '../dao/series_dao.dart';
import '../dao/tags_dao.dart';
import '../sources/source_api.dart';
import '../storage/image_pipeline.dart';
import 'browse_merge.dart';
import 'series_repo.dart';

export 'browse_merge.dart';

class _SourceResult {
  const _SourceResult(this.source, this.items, this.error);

  final Source source;
  final List<SourceSeries> items;
  final Object? error;
}

/// Orchestrates source adapters → normalize → group (Plan/07 §3) for the
/// Browse screen. Adapters stay dumb; this is the only merge point.
/// Series-row creation/merge lives in [SeriesRepo] (shared with the detail
/// screen) — this class owns listing/search/group only.
class BrowseRepo {
  BrowseRepo({
    required this.sources,
    required this.seriesDao,
    required this.chaptersDao,
    required this.libraryDao,
    required this.tagsDao,
    required this.historyDao,
    required this.seriesRepo,
    this.pipeline,
  });

  final List<Source> sources;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final LibraryDao libraryDao;
  final TagsDao tagsDao;
  final SearchHistoryDao historyDao;
  final SeriesRepo seriesRepo;

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
      {Set<String> onlySourceIds = const {}, int page = 1, bool popular = false}) async {
    final results = await _gather(
        _active(onlySourceIds), (s) => s.latest(page: page, popular: popular));
    // Latest feed keeps append order: each site's listing is already
    // newest-first (or popularity-ordered when [popular] — server-side,
    // probed 2026-10-20); sources are interleaved (Plan/05 drift
    // addendum — listings carry no timestamps to sort by).
    return BrowsePage(
        groups: mergeIntoGroups(const [], _candidates(results)),
        failures: _failures(results));
  }

  /// Offline catalog (user request 2026-10-21): the series rows the user
  /// has visited/materialized, as browse cards — when the network can't
  /// answer (airplane mode, every source failing), the feed goes STALE
  /// instead of blank. DB-only; covers/dates/types are the stored ones.
  Future<List<SearchGroup>> cachedCatalog({int limit = 60}) async {
    final out = <SearchGroup>[];
    for (final row in await seriesDao.recentSeries(limit: limit)) {
      final links = await seriesDao.sourcesOf(row.id!);
      if (links.isEmpty) continue;
      final members = <BrowseCandidate>[
        for (final l in links)
          BrowseCandidate(
            sourceId: l.sourceId,
            referer: sourceById(l.sourceId)?.referer ?? '',
            url: l.sourceUrl,
            title: l.sourceTitle ?? row.title,
            coverUrl: l.coverUrl,
            chapterCountHint: l.lastChapterNumber?.toInt(),
            lastUpdatedMs: l.lastUpdatedAt,
          ),
      ];
      final g = SearchGroup(members);
      g.dbStatus = row.status;
      g.dbType = row.type;
      g.dbLastUpdatedMs = await seriesDao.lastUpdatedAt(row.id!);
      g.dbTags = await tagsDao.tagsOf(row.id!);
      for (final l in links) {
        if ((l.coverUrl ?? '').isNotEmpty) {
          g.dbCoverUrl = l.coverUrl;
          g.dbCoverReferer = sourceById(l.sourceId)?.referer;
          break;
        }
      }
      out.add(g);
    }
    return out;
  }

  Future<BrowsePage> genre(Source source, String term, {int page = 1}) async {
    final results =
        await _gather([source], (s) => s.browseGenre(term, page: page));
    return BrowsePage(
        groups: mergeIntoGroups(const [], _candidates(results)),
        failures: _failures(results));
  }

  /// Fill each group's [SearchGroup.dbStatus]/[dbType]/[dbTags]/
  /// [dbLastUpdatedMs] (+ db cover) from a materialized series row
  /// (matched by the primary member's normalized title). Listing payloads
  /// carry none of these — without the join, the filter sheet's
  /// status/tag controls and the card's update stamp would never fire.
  /// Callers run this fire-and-forget so the DB round-trips never delay
  /// the listing.
  Future<void> enrichGroups(List<SearchGroup> groups) async {
    // 120 (raised from 60, 2026-10-20): DB-only reads, and cards past the
    // window showed no date even when the series row already had one —
    // with unbudgeted date backfill the window must cover deep lists.
    for (final g in groups.take(120)) {
      // Row lookup by the primary tile's norm, then its Latin-only
      // variant — a solo bully card ("English title + Thai subtitle")
      // materializes under the Latin norm, and the suffixed tile alone
      // would never find the row again.
      final row = await _seriesByTileNorm(normalizeTitle(g.primary.title)) ??
          await _seriesByTileNorm(latinOnlyNorm(g.primary.title));
      if (row == null) continue;
      try {
        await _applyRowToGroup(g, row);
      } catch (_) {
        // enrichment is best-effort — never fail a listing over it
      }
    }
  }

  /// Copy a series row's data onto a browse card. Norm lookup can miss
  /// when a site's tile title differs from the row's (each site's Thai
  /// subtitle differs, "(Remake)" stripped from the row norm — the
  /// Overgeared search report 2026-10-20), so the materialize pass calls
  /// this with the row id it ALREADY knows instead of re-guessing.
  Future<void> _applyRowToGroup(SearchGroup g, Series row) async {
    g.dbStatus = row.status;
    g.dbType = row.type;
    g.dbLastUpdatedMs = await seriesDao.lastUpdatedAt(row.id!);
    g.dbTags = await tagsDao.tagsOf(row.id!);
    // DB cover: first link that carries one, paired with ITS source's
    // referer (a first link without a cover must not donate its
    // referer to a later link's cover — same rule as library cards).
    for (final link in await seriesDao.sourcesOf(row.id!)) {
      if ((link.coverUrl ?? '').isNotEmpty) {
        g.dbCoverUrl = link.coverUrl;
        g.dbCoverReferer = sourceById(link.sourceId)?.referer;
        break;
      }
    }
  }

  Future<Series?> _seriesByTileNorm(String? norm) async {
    if (norm == null || norm.isEmpty) return null;
    try {
      return await seriesDao.findByTitleNorm(norm);
    } catch (_) {
      return null;
    }
  }

  /// Background pass over cards missing a date or cover
  /// ([SearchGroup.needsMaterialization]): run the same path as opening
  /// the card — primary detail → series row (chapters carry the dates) →
  /// cross-probe other sources (a sibling site's cover can render where
  /// the primary's tile is dead/AVIF) — without adding anything to the
  /// library. Results persist, so each card pays this once; [onCardDone]
  /// receives the finished group so the caller can re-enrich JUST it
  /// (progressive re-render). Session-memoized so pagination re-runs
  /// skip done cards.
  ///
  /// The DETAIL fetch is unbudgeted and covers every incomplete card:
  /// ts search tiles carry no dates, so a card's newest-chapter date can
  /// only come from this pass — capping it left most search results
  /// permanently dateless while their detail pages showed every chapter
  /// stamp (user report 2026-10-20: Overgeared on up/go-manga). One
  /// fetch per series, persisted → once ever. Workers run CONCURRENTLY
  /// (a strictly sequential pass dated ~1 card/second — a big search
  /// filled only its first 30–40 cards in the time a user waits,
  /// 2026-10-20 report) — safe_http's per-host limiter is the real
  /// politeness gate and paces each host independently. [budget] caps
  /// only the expensive cross-probe (one search query per unlinked
  /// source per card).
  Future<void> materializeIncompleteGroups(
    List<SearchGroup> groups, {
    int budget = 12,
    Future<void> Function(SearchGroup done)? onCardDone,
  }) async {
    final pending = <SearchGroup>[];
    for (final g in groups) {
      if (!g.needsMaterialization) continue;
      if (!_materialized.add(g.primary.url)) continue;
      pending.add(g);
    }
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (next >= pending.length) return;
        final g = pending[next++];
        try {
          final primary = g.primary;
          final source = sourceById(primary.sourceId);
          if (source == null) continue;
          final seriesId = await seriesRepo.ensureSeries(g);
          final row = await seriesDao.byId(seriesId);
          if (row != null) {
            // EXACT row → card (no title-norm guessing): this is what puts
            // the newest-chapter date on a tile that carries none.
            await _applyRowToGroup(g, row);
            if (budget > 0) {
              budget--;
              await seriesRepo.probeOtherSources(
                seriesId,
                candidate: TitleCandidate(
                  norm: row.titleNorm,
                  altNorms: [
                    for (final m in g.members) normalizeTitle(m.title),
                  ],
                ),
                // One query per unlinked source — the interactive open path
                // can afford retries with alternates, the background pass
                // must stay polite (probeOtherSources tries queries.take(3)
                // per source).
                queries: <String>[g.displayTitle],
              );
            }
          }
        } catch (_) {
          // best-effort — an unreachable source never breaks the feed
        }
        if (onCardDone != null) {
          try {
            await onCardDone(g);
          } catch (_) {}
        }
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
  }

  /// Primary URLs already sent to materialization this session — filter
  /// toggles and pagination re-present the same cards constantly.
  final _materialized = <String>{};

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
              lastUpdatedMs: item.lastUpdatedMs,
            ),
      ];

  List<SourceFailure> _failures(List<_SourceResult> results) => [
        for (final r in results)
          if (r.error != null) SourceFailure(r.source.id, r.error!),
      ];

  /// Long-press quick action (Plan/08): fetch the primary source's detail,
  /// create/merge the series row (Plan/07 §4 — shared [SeriesRepo] logic),
  /// then best-effort cross-probe other sources (§3.2) and insert the
  /// library row. Returns the series id. Idempotent.
  Future<int> addToLibrary(SearchGroup group) async {
    final primary = group.primary;
    final source = sourceById(primary.sourceId);
    if (source == null) {
      throw StateError('unknown source: ${primary.sourceId}');
    }
    final detail = await source.detail(primary.url);
    final seriesId = await seriesRepo.upsertFromDetail(
      source: source,
      sourceUrl: primary.url,
      fallbackTitle: group.displayTitle,
      fallbackCoverUrl: primary.coverUrl,
      fallbackType: group.type,
      detail: detail,
    );
    final seriesRow = (await seriesDao.byId(seriesId))!;
    await seriesRepo.probeOtherSources(
      seriesId,
      candidate: TitleCandidate(
        norm: seriesRow.titleNorm,
        altNorms: [
          for (final a in detail.altTitles) normalizeTitle(a),
          for (final m in group.members) normalizeTitle(m.title),
        ],
      ),
      queries: <String>{
        group.displayTitle,
        group.primary.title,
        for (final m in group.members) m.title,
      }.toList(),
    );
    await libraryDao.add(seriesId, DateTime.now().millisecondsSinceEpoch);
    return seriesId;
  }

  /// Browse card tap (Plan/09): resolve/materialize the series id, then
  /// open the detail screen on it.
  Future<int> ensureSeries(SearchGroup group) => seriesRepo.ensureSeries(group);
}

import 'dart:async';

import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';
import '../dao/chapters_dao.dart';
import '../dao/feed_anchor_dao.dart';
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
    this.feedAnchors,
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

  /// Null in unit tests that don't exercise sticky feed time anchors
  /// (db v10) — [latest] then keeps the raw adapter stamps.
  final FeedAnchorDao? feedAnchors;

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

  Future<BrowsePage> search(
    String query, {
    Set<String> onlySourceIds = const {},
    int page = 1,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const BrowsePage(groups: []);
    final results = await _gather(
      _active(onlySourceIds),
      (s) => s.search(q, page: page),
    );
    // Fire-and-forget: history must never delay results (and a DB write
    // can't complete inside a widget-test FakeAsync zone anyway).
    unawaited(
      historyDao
          .record(q, atMs: DateTime.now().millisecondsSinceEpoch)
          .catchError((Object _) {}),
    );
    final groups = mergeIntoGroups(const [], _candidates(results));
    // Search results: biggest series first (nulls last).
    groups.sort(
      (a, b) => (b.chapterCount ?? -1).compareTo(a.chapterCount ?? -1),
    );
    return BrowsePage(groups: groups, failures: _failures(results));
  }

  Future<BrowsePage> latest({
    Set<String> onlySourceIds = const {},
    int page = 1,
    bool popular = false,
  }) async {
    final results = await _gather(
      _active(onlySourceIds),
      (s) => s.latest(page: page, popular: popular),
    );
    await _stickifyStamps(results);
    // Latest feed keeps append order: each site's listing is already
    // newest-first (or popularity-ordered when [popular] — server-side,
    // probed 2026-10-20); sources are interleaved (Plan/05 drift
    // addendum — listings carry no timestamps to sort by).
    return BrowsePage(
      groups: mergeIntoGroups(const [], _candidates(results)),
      failures: _failures(results),
    );
  }

  /// Sticky time anchors (user report 2026-10-24 — see [stickyStamp] /
  /// FeedAnchorDao): fin/dark serve WP-cache copies whose relative labels
  /// stay "2 นาที" for 10+ hours; without this every refetch re-anchored
  /// the stamp at fetch-now and the feed froze on a wrong "just updated"
  /// age. Best-effort: any DB hiccup leaves the raw stamps untouched.
  Future<void> _stickifyStamps(List<_SourceResult> results) async {
    final anchors = feedAnchors;
    if (anchors == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in results) {
      if (r.error != null) continue;
      for (var i = 0; i < r.items.length; i++) {
        final item = r.items[i];
        final stamp = item.lastUpdatedMs;
        if (stamp == null) continue;
        try {
          final stored = await anchors.get(r.source.id, item.url);
          final adjusted = stickyStamp(
            storedHint: stored?.chapterHint,
            storedStampMs: stored?.stampMs,
            newHint: item.chapterCountHint,
            newStampMs: stamp,
          );
          await anchors.upsert(
            r.source.id,
            item.url,
            // A tile that lost its chapter pill this round must not wipe
            // the stored identity — stickiness survives on the old hint.
            chapterHint: item.chapterCountHint ?? stored?.chapterHint,
            stampMs: adjusted,
            atMs: now,
          );
          if (adjusted != stamp) {
            r.items[i] = SourceSeries(
              url: item.url,
              title: item.title,
              coverUrl: item.coverUrl,
              chapterCountHint: item.chapterCountHint,
              type: item.type,
              lastUpdatedMs: adjusted,
            );
          }
        } catch (_) {
          // anchors are an improvement, never a feed failure
        }
      }
    }
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
      g.dbDescription = row.description;
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
    final results = await _gather([
      source,
    ], (s) => s.browseGenre(term, page: page));
    return BrowsePage(
      groups: mergeIntoGroups(const [], _candidates(results)),
      failures: _failures(results),
    );
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
      final row =
          await _seriesByTileNorm(normalizeTitle(g.primary.title)) ??
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
    // Description: the card's leftover space under the chip row shows it
    // (user request 2026-10-22) — only materialized rows carry one.
    g.dbDescription = row.description;
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

  /// Background pass over two classes of card:
  ///
  /// 1. INCOMPLETE — missing a date or cover ([SearchGroup
  ///    .needsMaterialization]): run the same path as opening the card —
  ///    primary detail → series row (chapters carry the dates) →
  ///    cross-probe other sources (a sibling site's cover can render where
  ///    the primary's tile is dead/AVIF) — without adding anything to the
  ///    library.
  /// 2. STALE — dated, but the date is older than [dateStaleAfter]: one
  ///    detail re-check refreshes the persisted stamp. The date used to
  ///    freeze at the first materialization FOREVER, so a chapter that
  ///    dropped 16 hours ago still showed "3 days ago" on the card while
  ///    the site's own tile said "16 ชั่วโมงที่แล้ว" (user report
  ///    2026-10-22: ts/madara listing tiles carry no timestamps, so the
  ///    detail chapters are the only fresh date signal).
  ///
  /// [onCardDone] receives each finished group so the caller can
  /// re-enrich JUST it (progressive re-render). A card is attempted at
  /// most once per [dateStaleAfter] (memoized per primary URL with the
  /// attempt time — pagination and filter toggles re-present the same
  /// cards constantly). Cross-probe stays an incomplete-card-only extra,
  /// capped by [budget]; the DETAIL fetch itself is unbudgeted — capping
  /// it left most search results permanently dateless (user report
  /// 2026-10-20: Overgeared on up/go-manga) — safe_http's per-host
  /// limiter is the real politeness gate. Workers run CONCURRENTLY (a
  /// strictly sequential pass dated ~1 card/second, 2026-10-20 report).
  Future<void> materializeIncompleteGroups(
    List<SearchGroup> groups, {
    int budget = 12,
    Duration staleAfter = dateStaleAfter,
    Future<void> Function(SearchGroup done)? onCardDone,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final staleMs = staleAfter.inMilliseconds;
    final pending = <({SearchGroup group, bool crossProbe})>[];
    for (final g in groups) {
      final url = g.primary.url;
      final at = _materializedAt[url];
      if (at != null && nowMs - at < staleMs) continue;
      _materializedAt[url] = nowMs;
      final crossProbe = g.needsMaterialization;
      if (!crossProbe) {
        final date = g.lastUpdatedMs;
        if (date == null || nowMs - date < staleMs) continue;
      }
      pending.add((group: g, crossProbe: crossProbe));
    }
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (next >= pending.length) return;
        final rec = pending[next++];
        final g = rec.group;
        try {
          final primary = g.primary;
          final source = sourceById(primary.sourceId);
          if (source == null) continue;
          final seriesId = rec.crossProbe
              ? await seriesRepo.ensureSeries(g)
              : await _refreshStale(g, source);
          final row = await seriesDao.byId(seriesId);
          if (row != null) {
            // EXACT row → card (no title-norm guessing): this is what puts
            // the newest-chapter date on a tile that carries none.
            await _applyRowToGroup(g, row);
            if (rec.crossProbe && budget > 0) {
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

  /// How old a card's date may get before the background pass re-checks
  /// the site for a newer chapter (class 2 above). 6 h: site updates land
  /// in bursts; a refresh after this window corrects every lagging stamp.
  static const dateStaleAfter = Duration(hours: 6);

  /// Primary URL → last materialize attempt (ms epoch) this session.
  /// Filter toggles and pagination re-present the same cards constantly;
  /// the timestamp (not a set) lets a card re-attempt after
  /// [dateStaleAfter].
  final _materializedAt = <String, int>{};

  /// STALE re-check for one card: prefer the source's homepage-grid stamp
  /// (precise to the minute — chapterdate rows are date-only in a lagging
  /// site timezone, user reports 2026-10-22: slow-manga read exact at a
  /// 20:00 anchor while go-manga read 16 h for a 6 h chapter and
  /// dark-manga "สักครู่" for a 2-minute one). No grid hit (or no existing
  /// row to stamp) → the detail re-fetch as before. Returns the series id.
  Future<int> _refreshStale(SearchGroup g, Source source) async {
    final primary = g.primary;
    final stamps = await _recentStamps(source);
    final hit =
        stamps[normalizeTitle(primary.title)] ??
        stamps[normalizeTitle(g.displayTitle)];
    if (hit != null) {
      final seriesId = await seriesDao.findSeriesIdBySourceLink(
        source.id,
        primary.url,
      );
      if (seriesId != null) {
        final link = await seriesDao.sourceLinkByUrl(
          seriesId,
          source.id,
          primary.url,
        );
        // Never regress a link to an older stamp than it already holds.
        if (link != null &&
            (link.lastUpdatedAt == null || hit > link.lastUpdatedAt!)) {
          await seriesDao.upsertSource(
            SeriesSource(
              seriesId: seriesId,
              sourceId: link.sourceId,
              sourceUrl: link.sourceUrl,
              sourceTitle: link.sourceTitle,
              altTitles: link.altTitles,
              coverUrl: link.coverUrl,
              lastChapterNumber: link.lastChapterNumber,
              lastUpdatedAt: hit,
              fetchedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
        return seriesId;
      }
    }
    return seriesRepo.refreshDetail(g);
  }

  /// Homepage-grid stamps per source, keyed by title norm. One fetch per
  /// source per [dateStaleAfter] window; best-effort (an unreachable grid
  /// just leaves the map empty and the detail re-fetch takes over).
  final _stamps = <String, Map<String, int>>{};
  final _stampsAt = <String, int>{};

  Future<Map<String, int>> _recentStamps(Source source) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final at = _stampsAt[source.id];
    if (at != null && nowMs - at < dateStaleAfter.inMilliseconds) {
      return _stamps[source.id] ?? const {};
    }
    final map = <String, int>{};
    try {
      for (final e in await source.recentStamps()) {
        final norm = normalizeTitle(e.title);
        if (norm.isNotEmpty) map[norm] = e.stampMs;
      }
    } catch (_) {}
    _stamps[source.id] = map;
    _stampsAt[source.id] = nowMs;
    return map;
  }

  Future<List<SourceGenre>> genres(Source source) => source.genres();

  Future<List<_SourceResult>> _gather(
    List<Source> active,
    Future<List<SourceSeries>> Function(Source) call,
  ) {
    return Future.wait(
      active.map((s) async {
        try {
          return _SourceResult(s, await call(s), null);
        } catch (e) {
          return _SourceResult(s, const [], e);
        }
      }),
    );
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

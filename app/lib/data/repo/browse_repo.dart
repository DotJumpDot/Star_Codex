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

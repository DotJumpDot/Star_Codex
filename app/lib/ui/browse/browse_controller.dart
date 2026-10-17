import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repo/browse_repo.dart';

enum BrowseMode { latest, search, genre }

/// Keep-semantics marker for [BrowseState.copyWith] nullable fields.
const _keep = Object();

class BrowseState {
  const BrowseState({
    this.initialized = false,
    this.mode = BrowseMode.latest,
    this.query = '',
    this.genreSourceId,
    this.genreTerm,
    this.activeSourceIds = const {},
    this.filters = const BrowseFilters(),
    this.groups = const [],
    this.failedSources = const {},
    this.loading = false,
    this.loadingMore = false,
    this.endReached = false,
    this.page = 0,
  });

  final bool initialized;
  final BrowseMode mode;
  final String query; // '' in latest/genre mode
  final String? genreSourceId;
  final String? genreTerm;

  /// Per-site filter (Plan/08 §2): empty set = all sources on.
  final Set<String> activeSourceIds;
  final BrowseFilters filters;

  final List<SearchGroup> groups;

  /// Sources that errored in the last fetch — chips show a red dot and the
  /// other sources' results still display (Plan/08 §Behavior).
  final Set<String> failedSources;

  final bool loading;
  final bool loadingMore;
  final bool endReached;
  final int page;

  BrowseState copyWith({
    bool? initialized,
    BrowseMode? mode,
    String? query,
    Object? genreSourceId = _keep,
    Object? genreTerm = _keep,
    Set<String>? activeSourceIds,
    BrowseFilters? filters,
    List<SearchGroup>? groups,
    Set<String>? failedSources,
    bool? loading,
    bool? loadingMore,
    bool? endReached,
    int? page,
  }) =>
      BrowseState(
        initialized: initialized ?? this.initialized,
        mode: mode ?? this.mode,
        query: query ?? this.query,
        genreSourceId:
            genreSourceId == _keep ? this.genreSourceId : genreSourceId as String?,
        genreTerm: genreTerm == _keep ? this.genreTerm : genreTerm as String?,
        activeSourceIds: activeSourceIds ?? this.activeSourceIds,
        filters: filters ?? this.filters,
        groups: groups ?? this.groups,
        failedSources: failedSources ?? this.failedSources,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        endReached: endReached ?? this.endReached,
        page: page ?? this.page,
      );
}

/// Browse tab state machine (Plan/08): latest feed ⇄ merged search ⇄
/// single-source genre view, with session-only filters and per-site chips.
class BrowseController extends StateNotifier<BrowseState> {
  BrowseController(this._repo) : super(const BrowseState());

  final BrowseRepo _repo;

  /// First tab shown — load the latest feed once.
  Future<void> ensureLoaded() async {
    if (state.initialized || state.loading) return;
    state = state.copyWith(initialized: true, loading: true);
    await _replace(page: 1);
  }

  /// Search on submit ONLY — no debounce-as-you-type (Plan/08 §1: hitting
  /// five sites per keystroke is rude).
  Future<void> submitSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    state = state.copyWith(
      mode: BrowseMode.search,
      query: q,
      genreSourceId: null,
      genreTerm: null,
      groups: const [],
      failedSources: const {},
      loading: true,
      endReached: false,
      page: 0,
    );
    await _replace(page: 1);
  }

  /// Back to the latest feed.
  Future<void> clearSearch() async {
    state = state.copyWith(
      mode: BrowseMode.latest,
      query: '',
      genreSourceId: null,
      genreTerm: null,
      groups: const [],
      failedSources: const {},
      loading: true,
      endReached: false,
      page: 0,
    );
    await _replace(page: 1);
  }

  /// Toggling a chip re-runs the current search/latest limited to that site
  /// (Plan/08 §2 — this IS the per-site tab).
  Future<void> toggleSource(String id) async {
    final active = {...state.activeSourceIds};
    if (!active.remove(id)) active.add(id);
    state = state.copyWith(
      activeSourceIds: active,
      groups: const [],
      failedSources: const {},
      loading: true,
      endReached: false,
      page: 0,
    );
    await _replace(page: 1);
  }

  /// "ทั้งหมด" chip — clear the per-site filter and re-run.
  Future<void> clearSourceFilter() async {
    if (state.activeSourceIds.isEmpty) return;
    state = state.copyWith(
      activeSourceIds: const {},
      groups: const [],
      failedSources: const {},
      loading: true,
      endReached: false,
      page: 0,
    );
    await _replace(page: 1);
  }

  /// Long-press chip → genre picker → results in the same merged list.
  Future<void> showGenre(String sourceId, String term) async {
    state = state.copyWith(
      mode: BrowseMode.genre,
      genreSourceId: sourceId,
      genreTerm: term,
      query: '',
      groups: const [],
      failedSources: const {},
      loading: true,
      endReached: false,
      page: 0,
    );
    await _replace(page: 1);
  }

  Future<void> leaveGenre() => clearSearch();

  /// Filters are view-level: re-filter cached groups, never re-fetch.
  void setFilters(BrowseFilters filters) =>
      state = state.copyWith(filters: filters);

  /// Infinite scroll: one more page per source per batch (Plan/08).
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.endReached) return;
    state = state.copyWith(loadingMore: true);
    final next = state.page + 1;
    try {
      final batch = await _fetch(next);
      final groups = mergeGroupLists(state.groups, batch.groups);
      final failed = {...state.failedSources};
      failed.addAll(batch.failures.map((f) => f.sourceId));
      state = state.copyWith(
        groups: groups,
        failedSources: failed,
        page: next,
        loadingMore: false,
        // Batch empty → no more pages from any source.
        endReached: batch.groups.isEmpty,
      );
    } catch (_) {
      state = state.copyWith(loadingMore: false, endReached: true);
    }
  }

  Future<void> _replace({required int page}) async {
    try {
      final result = await _fetch(page);
      state = state.copyWith(
        groups: result.groups,
        failedSources: {for (final f in result.failures) f.sourceId},
        loading: false,
        page: page,
        endReached: result.groups.isEmpty,
      );
    } catch (_) {
      // Per-source errors never reach here (guarded in the repo); a total
      // failure (no sources at all) shows the empty state.
      state = state.copyWith(loading: false, endReached: true);
    }
  }

  Future<BrowsePage> _fetch(int page) {
    switch (state.mode) {
      case BrowseMode.search:
        return _repo.search(state.query,
            onlySourceIds: state.activeSourceIds, page: page);
      case BrowseMode.genre:
        final source = state.genreSourceId == null
            ? null
            : _repo.sourceById(state.genreSourceId!);
        final term = state.genreTerm;
        if (source == null || term == null) {
          return Future.value(const BrowsePage(groups: []));
        }
        return _repo.genre(source, term, page: page);
      case BrowseMode.latest:
        return _repo.latest(onlySourceIds: state.activeSourceIds, page: page);
    }
  }
}

final browseControllerProvider =
    StateNotifierProvider<BrowseController, BrowseState>(
        (ref) => BrowseController(ref.watch(browseRepoProvider)));

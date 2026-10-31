import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/repo/browse_repo.dart';
import '../../data/sources/source_registry.dart';

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
    this.offline = false,
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

  /// True when the current view shows the servers' popularity ordering
  /// (feed fetch param — see BrowseSortOrder.popular; merged UI
  /// 2026-10-21).
  bool get feedPopular => filters.sort == BrowseSortOrder.popular;

  /// True when the last fetch could not reach ANY source and the list
  /// shows the offline catalog instead (2026-10-21) — the UI banners it.
  final bool offline;

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
    bool? offline,
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
        offline: offline ?? this.offline,
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
  BrowseController(this._repo,
      {Set<String>? allowedSourceIds,
      this.initialFeedPopular = false,
      this.onFeedPopularChanged,
      bool Function()? hideYaoiResolver})
      : _allowedSourceIds = allowedSourceIds, // ignore: prefer_initializing_formals
        _hideYaoiResolver = hideYaoiResolver ?? _neverHide,
        super(BrowseState(
          filters: initialFeedPopular
              ? const BrowseFilters(sort: BrowseSortOrder.popular)
              : const BrowseFilters(),
        ));

  final BrowseRepo _repo;

  /// Optional universe for scoped controllers (the adult page): the feed
  /// and the site sheet only ever see these sources. Null = all.
  final Set<String>? _allowedSourceIds;

  /// Mix tab (2026-10-28): drop yaoi-tagged titles from the feed — the
  /// mix catalogs carry a heavy yaoi share (user preference; yuri stays;
  /// live-toggled via the `mix_hide_yaoi` setting, checked per fetch).
  final bool Function() _hideYaoiResolver;

  static bool _neverHide() => false;

  /// Popular-ordering seed + persistence hook (wired by the providers to
  /// the `browse_feed_popular` setting; the choice lives in the sort
  /// section since 2026-10-21).
  final bool initialFeedPopular;
  final void Function(bool popular)? onFeedPopularChanged;

  /// Monotonic fetch sequence — every `_fetch` invalidates all earlier
  /// in-flight ones. Without this, quickly toggling site filters let an
  /// OLDER fetch finish last and overwrite the feed with results for a
  /// filter the user had already changed away from (on-device bug report
  /// 2026-10-19: "select bully, tap Done, feed flips back to slow-manga").
  int _fetchSeq = 0;

  /// Sources this controller may query: its allowed universe intersected
  /// with the active per-site selection (empty selection = all allowed).
  /// An out-of-scope-only selection must never fall back to "all" (the
  /// repo treats an empty set as no filter) — the sentinel queries nothing.
  Set<String> get _effectiveSourceIds {
    final allowed = _allowedSourceIds;
    if (allowed == null) return state.activeSourceIds;
    if (state.activeSourceIds.isEmpty) return allowed;
    final scoped = state.activeSourceIds.where(allowed.contains).toSet();
    return scoped.isEmpty ? const {'__no_source__'} : scoped;
  }

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
  /// (Plan/08 §2 — this IS the per-site tab). In genre mode a chip tap
  /// leaves the single-source genre view and filters the latest feed —
  /// genre results are bound to their own source and can't be re-scoped.
  Future<void> toggleSource(String id) async {
    final active = {...state.activeSourceIds};
    if (!active.remove(id)) active.add(id);
    final leavingGenre = state.mode == BrowseMode.genre;
    state = state.copyWith(
      mode: leavingGenre ? BrowseMode.latest : null,
      genreSourceId: leavingGenre ? null : _keep,
      genreTerm: leavingGenre ? null : _keep,
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
    if (state.activeSourceIds.isEmpty && state.mode != BrowseMode.genre) {
      return;
    }
    final leavingGenre = state.mode == BrowseMode.genre;
    state = state.copyWith(
      mode: leavingGenre ? BrowseMode.latest : null,
      genreSourceId: leavingGenre ? null : _keep,
      genreTerm: leavingGenre ? null : _keep,
      activeSourceIds: const {},
      groups: const [],
      failedSources: const {},
      loading: true,
      endReached: false,
      page: 0,
    );
    await _replace(page: 1);
  }

  /// Empty-state retry: re-run the current mode from page 1 (Plan/08 —
  /// never leave a blank page after a total failure).
  Future<void> retry() async {
    state = state.copyWith(
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

  /// Filters are view-level: re-filter cached groups, never re-fetch —
  /// ONE exception: popular is a SERVER fetch parameter (the ts archive's
  /// own ordering), so crossing into/out of it re-fetches the feed
  /// (2026-10-21, merged sort section).
  void setFilters(BrowseFilters filters) {
    final wasPopular = state.feedPopular;
    state = state.copyWith(filters: filters);
    final isPopular = filters.sort == BrowseSortOrder.popular;
    if (isPopular != wasPopular) {
      onFeedPopularChanged?.call(isPopular);
      state = state.copyWith(
        groups: const [],
        failedSources: const {},
        loading: true,
        endReached: false,
        page: 0,
      );
      _replace(page: 1);
    }
  }

  /// Tag chip on the detail screen (Plan/09 §4): pre-filter browse,
  /// session-only. Listings carry no tags yet, so enforcement stays an
  /// honest no-op until a detail fetch lands tags — same policy as the
  /// filter sheet.
  void applyTagFilter(String tag) =>
      state = state.copyWith(filters: state.filters.copyWith(tags: {tag}));

  /// Infinite scroll: one more page per source per batch (Plan/08).
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.endReached) return;
    state = state.copyWith(loadingMore: true);
    final seq = ++_fetchSeq;
    final next = state.page + 1;
    try {
      final batch = await _fetch(next);
      if (seq != _fetchSeq) {
        // A filter/mode change superseded this page — it owns the feed.
        state = state.copyWith(loadingMore: false);
        return;
      }
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
      _enrichInBackground(batch.groups);
    } catch (_) {
      state = state.copyWith(loadingMore: false, endReached: true);
    }
  }

  Future<void> _replace({required int page}) async {
    final seq = ++_fetchSeq;
    try {
      final result = await _fetch(page);
      if (seq != _fetchSeq) return; // superseded — a newer fetch owns state
      if (result.groups.isEmpty && result.failures.isNotEmpty &&
          await _offlineFallback(seq)) {
        return;
      }
      // The fallback attempt may itself have been superseded (the double
      // ensureLoaded on mount) — its false return must NOT fall through
      // to a stale emission that clobbers the newer fetch's offline
      // state (observed on-device 2026-10-21).
      if (seq != _fetchSeq) return;
      state = state.copyWith(
        groups: result.groups,
        failedSources: {for (final f in result.failures) f.sourceId},
        loading: false,
        loadingMore: false,
        page: page,
        endReached: result.groups.isEmpty,
        offline: false,
      );
      _enrichInBackground(result.groups);
    } catch (_) {
      // Per-source errors never reach here (guarded in the repo); a total
      // failure (no sources at all) shows the empty state — or the
      // offline catalog when the DB has anything (2026-10-21).
      if (seq != _fetchSeq) return;
      if (!await _offlineFallback(seq)) {
        state = state.copyWith(
            loading: false, endReached: true, offline: false);
      }
    }
  }

  /// Feed fallback for airplane mode / total network failure: show the
  /// visited series from the DB instead of a blank page. LATEST-mode
  /// only (search/genre are server-bound by nature).
  Future<bool> _offlineFallback(int seq) async {
    if (state.mode != BrowseMode.latest) return false;
    try {
      final cached = await _repo.cachedCatalog();
      if (kDebugMode) {
        debugPrint('OFFLINE FB mode=latest cached=${cached.length} '
            'seq=$seq fetchSeq=$_fetchSeq');
      }
      if (seq != _fetchSeq || cached.isEmpty) return false;
      state = state.copyWith(
        groups: cached,
        failedSources: const {},
        loading: false,
        loadingMore: false,
        endReached: true, // no pagination offline
        offline: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// DB enrichment (status/type/tags/last-update for materialized series)
  /// runs after the page renders and re-emits the SAME group list once it
  /// lands — the DB round-trips must never delay the listing itself.
  void _enrichInBackground(List<SearchGroup> groups) {
    if (groups.isEmpty) return;
    unawaited(() async {
      try {
        await _repo.enrichGroups(groups);
        if (mounted) state = state.copyWith();
        // Cards the listing alone left incomplete (madara/bully tiles
        // carry no dates; some covers are dead/AVIF): backfill EVERY
        // undated card in the background (one detail fetch, persisted —
        // the newest chapter's stamp becomes the card date; the
        // cross-source probe stays budgeted) — re-enriching JUST the
        // finished card each time so its date/cover pops in.
        await _repo.materializeIncompleteGroups(groups,
            onCardDone: (done) async {
          await _repo.enrichGroups([done]);
          if (mounted) state = state.copyWith();
        });
        await _repo.enrichGroups(groups);
        if (mounted) state = state.copyWith();
      } catch (_) {
        // enrichment/materialization is best-effort
      }
    }());
  }

  /// Progressive first paint (2026-10-28): the repo emits the merged
  /// feed after EACH source lands; page-1 fetches show partial results
  /// immediately instead of waiting 10+ s for the slowest (WAF-ladder)
  /// host. Only used by _replace (page 1 / refreshes) — loadMore still
  /// appends whole batches.
  void Function(BrowsePage)? get _onPartial {
    final seq = _fetchSeq;
    return (partial) {
      if (seq != _fetchSeq || !mounted) return;
      if (partial.groups.isEmpty) return;
      state = state.copyWith(
        groups: partial.groups,
        failedSources: {for (final f in partial.failures) f.sourceId},
        loading: false,
        offline: false,
      );
    };
  }

  Future<BrowsePage> _fetch(int page) {
    final only = _effectiveSourceIds;
    switch (state.mode) {
      case BrowseMode.search:
        return _repo.search(
          state.query,
          onlySourceIds: only,
          page: page,
          hideYaoi: _hideYaoiResolver(),
        );
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
        return _repo.latest(
            onlySourceIds: only,
            page: page,
            popular: state.feedPopular,
            hideYaoi: _hideYaoiResolver(),
            onPartial: _onPartial);
    }
  }
}

final browseControllerProvider =
    StateNotifierProvider<BrowseController, BrowseState>((ref) {
  final repo = ref.watch(browseRepoProvider);
  final settings = ref.read(settingsProvider);
  return BrowseController(repo,
      allowedSourceIds: {
        // The main feed/search never touch the 18+ or mix sources —
        // they live on their own tabs' controllers (user request
        // 2026-10-19 + 2026-10-28).
        for (final s in repo.sources)
          if (!adultSourceIds.contains(s.id) && !mixSourceIds.contains(s.id))
            s.id,
      },
      initialFeedPopular: settings.getBool('browse_feed_popular', false),
      onFeedPopularChanged: (popular) => unawaited(ref
          .read(settingsProvider.notifier)
          .set('browse_feed_popular', popular ? '1' : '0')));
});

/// Doujin (18+) page — same repo, universe = the adult sources only.
final adultBrowseControllerProvider =
    StateNotifierProvider<BrowseController, BrowseState>(
        (ref) => BrowseController(ref.watch(browseRepoProvider),
            allowedSourceIds: adultSourceIds,
            initialFeedPopular:
                ref.read(settingsProvider).getBool('browse_feed_popular', false),
            onFeedPopularChanged: (popular) => unawaited(ref
                .read(settingsProvider.notifier)
                .set('browse_feed_popular', popular ? '1' : '0'))));

/// Search Mix page (2026-10-28) — universe = the mix sources only
/// (mangary/whytoon: normal + 18+ mixed catalogs). Yaoi titles are
/// dropped while the setting allows (default on).
final mixBrowseControllerProvider =
    StateNotifierProvider<BrowseController, BrowseState>(
        (ref) => BrowseController(ref.watch(browseRepoProvider),
            allowedSourceIds: mixSourceIds,
            initialFeedPopular:
                ref.read(settingsProvider).getBool('browse_feed_popular', false),
            hideYaoiResolver: () =>
                ref.read(settingsProvider).getBool('mix_hide_yaoi', true),
            onFeedPopularChanged: (popular) => unawaited(ref
                .read(settingsProvider.notifier)
                .set('browse_feed_popular', popular ? '1' : '0'))));

/// Scope → controller provider (BrowseScreen picks its provider by tab).
StateNotifierProvider<BrowseController, BrowseState> browseControllerProviderFor(
    BrowseScope scope) {
  switch (scope) {
    case BrowseScope.main:
      return browseControllerProvider;
    case BrowseScope.mix:
      return mixBrowseControllerProvider;
    case BrowseScope.adult:
      return adultBrowseControllerProvider;
  }
}

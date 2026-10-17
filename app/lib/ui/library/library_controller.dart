import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/dao/library_dao.dart';
import '../../data/repo/library_cards.dart';

/// Library tab state (Plan/12): the full card list stays in memory;
/// tab/filter/search/sort apply over it via the pure
/// [filterAndSortCards]. User actions write through to the DB and reload.
class LibraryState {
  const LibraryState({
    this.cards = const [],
    this.userCategories = const [],
    this.categoryMembers = const {},
    this.loading = true,
    this.tab = const AllTab(),
    this.sort = LibrarySort.lastRead,
    this.filters = const LibraryFilters(),
    this.search = '',
    this.listView = false,
    this.selection = const [],
  });

  final List<LibraryCard> cards;
  final List<Category> userCategories;
  final Map<int, Set<int>> categoryMembers;
  final bool loading;
  final LibraryTab tab;
  final LibrarySort sort;
  final LibraryFilters filters;
  final String search;

  /// Persisted `library_view`; grid (false) is the default.
  final bool listView;

  /// Multi-select in TAP order — selection[0] is the merge target
  /// (Plan/12 §4: "target = the one user tapped first").
  final List<int> selection;

  List<LibraryCard> get visible => filterAndSortCards(
        cards,
        tab: tab,
        filters: filters,
        search: search,
        sort: sort,
        categoryMembers: categoryMembers,
      );

  LibraryState copyWith({
    List<LibraryCard>? cards,
    List<Category>? userCategories,
    Map<int, Set<int>>? categoryMembers,
    bool? loading,
    LibraryTab? tab,
    LibrarySort? sort,
    LibraryFilters? filters,
    String? search,
    bool? listView,
    List<int>? selection,
    bool clearSelection = false,
  }) =>
      LibraryState(
        cards: cards ?? this.cards,
        userCategories: userCategories ?? this.userCategories,
        categoryMembers: categoryMembers ?? this.categoryMembers,
        loading: loading ?? this.loading,
        tab: tab ?? this.tab,
        sort: sort ?? this.sort,
        filters: filters ?? this.filters,
        search: search ?? this.search,
        listView: listView ?? this.listView,
        selection: clearSelection ? const [] : (selection ?? this.selection),
      );
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this.ref) : super(const LibraryState()) {
    final settings = ref.read(settingsProvider);
    state = state.copyWith(
      sort: parseLibrarySort(settings.get('library_sort', 'last_read')),
      listView: settings.get('library_view', 'grid') == 'list',
    );
  }

  final Ref ref;

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final repo = ref.read(libraryRepoProvider);
      final dao = ref.read(libraryDaoProvider);
      final cats = await dao.categories();
      final members = <int, Set<int>>{};
      for (final c in cats) {
        members[c.id] = await dao.membersOf(c.id);
      }
      if (!mounted) return;
      state = state.copyWith(
        cards: await repo.load(),
        userCategories: cats,
        categoryMembers: members,
        loading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(loading: false, cards: const []);
    }
  }

  void setTab(LibraryTab tab) => state = state.copyWith(tab: tab);

  void setSearch(String q) => state = state.copyWith(search: q);

  void setFilters(LibraryFilters f) => state = state.copyWith(filters: f);

  Future<void> setSort(LibrarySort sort) async {
    state = state.copyWith(sort: sort);
    await ref
        .read(settingsDaoProvider)
        .upsert('library_sort', switch (sort) {
          LibrarySort.lastRead => 'last_read',
          LibrarySort.updated => 'updated',
          LibrarySort.added => 'added',
          LibrarySort.titleAz => 'title_az',
          LibrarySort.unread => 'unread',
        });
  }

  Future<void> toggleView() async {
    final next = !state.listView;
    state = state.copyWith(listView: next);
    await ref
        .read(settingsDaoProvider)
        .upsert('library_view', next ? 'list' : 'grid');
  }

  // --- multi-select ---

  void toggleSelect(int seriesId) {
    final sel = [...state.selection];
    if (!sel.remove(seriesId)) sel.add(seriesId);
    state = state.copyWith(selection: sel);
  }

  void clearSelection() => state = state.copyWith(clearSelection: true);

  Future<void> moveSelectionTo(int categoryId) async {
    final dao = ref.read(libraryDaoProvider);
    for (final id in state.selection) {
      await dao.addToCategory(id, categoryId);
    }
    clearSelection();
    await load();
  }

  /// Delete from library (13 §C): keepFiles=false also drops the pinned
  /// downloads; keepFiles=true leaves blobs to the cache LRU.
  Future<void> deleteSelection({required bool keepFiles}) async {
    final repo = ref.read(libraryRepoProvider);
    for (final id in state.selection) {
      await repo.deleteFromLibrary(id, keepFiles: keepFiles);
    }
    clearSelection();
    await load();
  }

  /// Remove downloads only (multi-select action, Plan/12 §1).
  Future<void> removeSelectionDownloads() async {
    final repo = ref.read(libraryRepoProvider);
    for (final id in state.selection) {
      await repo.removeSeriesDownloads(id);
    }
    clearSelection();
    await load();
  }

  /// Merge selection[0] ← the rest (Plan/12 §4), first tap = target.
  Future<void> mergeSelection() async {
    if (state.selection.length < 2) return;
    final primary = state.selection.first;
    final absorbed = state.selection.sublist(1);
    clearSelection();
    await ref.read(libraryRepoProvider).merge(primary, absorbed);
    await load();
  }

  // --- categories ---

  Future<void> createCategory(String name) async {
    await ref.read(libraryDaoProvider).addCategory(name.trim());
    await load();
  }

  Future<void> renameCategory(int id, String name) async {
    await ref.read(libraryDaoProvider).renameCategory(id, name.trim());
    await load();
  }

  Future<void> deleteCategory(int id) async {
    await ref.read(libraryDaoProvider).deleteCategory(id);
    if (state.tab is CategoryTab && (state.tab as CategoryTab).categoryId == id) {
      state = state.copyWith(tab: const AllTab());
    }
    await load();
  }

  /// ล้างหมวด — memberships only (Plan/12 §1 long-press menu).
  Future<void> clearCategory(int id) async {
    await ref.read(libraryDaoProvider).clearCategoryMembers(id);
    await load();
  }
}

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>(
        (ref) => LibraryController(ref));

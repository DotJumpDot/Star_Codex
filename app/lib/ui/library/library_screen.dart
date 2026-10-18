import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../data/dao/library_dao.dart';
import '../../data/repo/library_cards.dart';
import '../detail/detail_screen.dart';
import '../shell/star_app_bar.dart';
import 'library_card.dart';
import 'updates_sheet.dart';
import 'library_controller.dart';
import 'updates_controller.dart';
import 'library_sheets.dart';

/// Library tab (Plan/12): category chips → toolbar (search / sort / view /
/// filter) → grid or list of `library` series. Long-press enters
/// multi-select (move category / merge / delete / remove downloads).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(libraryControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);
    final selectionMode = state.selection.isNotEmpty;

    return Scaffold(
      appBar: starAppBar(
        context,
        ref: ref,
        leadingOverride: selectionMode
            ? IconButton(
                tooltip: t(context, 'common.cancel'),
                icon: const Icon(Icons.close),
                onPressed: controller.clearSelection,
              )
            : null,
        title: Text(selectionMode
            ? tFmt(
                context, 'library.selected', {'n': '${state.selection.length}'})
            : t(context, 'tab.library')),
        actions: selectionMode
            ? _selectionActions(context, ref, state, controller)
            : [
                // Updates check (doc 13 §B): cheap, polite, gated at 6 h.
                IconButton(
                  tooltip: t(context, 'updates.refresh'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    controller.load();
                    await ref
                        .read(updatesControllerProvider.notifier)
                        .check();
                  },
                ),
                const UpdatesBell(),
              ],
      ),
      body: Column(
        children: [
          // In-library search replaces the toolbar's category dropdown
          // while open (fewer stacked rows was the #1 usability complaint
          // about this page).
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      onChanged: controller.setSearch,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: t(context, 'library.search_hint'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            controller.setSearch('');
                            setState(() => _searchOpen = false);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _Toolbar(
            state: state,
            searchOpen: _searchOpen,
            onSearchTap: () => setState(() => _searchOpen = !_searchOpen),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(child: _LibraryBody(state: state)),
        ],
      ),
    );
  }

  List<Widget> _selectionActions(BuildContext context, WidgetRef ref,
      LibraryState state, LibraryController controller) {
    return [
      if (state.selection.length >= 2)
        IconButton(
          tooltip: t(context, 'library.merge.go'),
          icon: const Icon(Icons.merge),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(t(context, 'library.merge.title')),
                content: Text(t(context, 'library.merge.body')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(t(context, 'common.cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(t(context, 'library.merge.go')),
                  ),
                ],
              ),
            );
            if (ok == true) await controller.mergeSelection();
          },
        ),
      IconButton(
        tooltip: t(context, 'library.move_category'),
        icon: const Icon(Icons.drive_file_move_outlined),
        onPressed: () => showMoveToCategorySheet(context, ref),
      ),
      IconButton(
        tooltip: t(context, 'library.remove_downloads'),
        icon: const Icon(Icons.download_done),
        onPressed: controller.removeSelectionDownloads,
      ),
      IconButton(
        tooltip: t(context, 'library.delete_from_library'),
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final keep = await showDeleteFromLibraryDialog(context);
          if (keep == null) return;
          await controller.deleteSelection(keepFiles: keep);
        },
      ),
      IconButton(
        tooltip: t(context, 'common.cancel'),
        icon: const Icon(Icons.close),
        onPressed: controller.clearSelection,
      ),
    ];
  }
}

/// Category selector (user QA 2026-10-18): a compact dropdown button in
/// the toolbar replacing the long sliding chip row. Opens a bottom sheet
/// with the built-ins, user categories (with per-category edit), and
/// create-new.
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({super.key, required this.state});

  final LibraryState state;

  static String tabName(BuildContext context, LibraryTab tab,
      List<Category> userCategories) {
    return switch (tab) {
      AllTab() => t(context, 'library.cat.all'),
      SmartTab(:final kind) => t(context, switch (kind) {
            SmartKind.reading => 'library.cat.reading',
            SmartKind.hasNew => 'library.cat.has_new',
            SmartKind.novel => 'library.cat.novel',
            SmartKind.downloaded => 'library.cat.downloaded',
          }),
      CategoryTab(:final categoryId) => userCategories
              .where((c) => c.id == categoryId)
              .firstOrNull
              ?.name ??
          '',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: () => _openSheet(context, ref),
      icon: const Icon(Icons.category_outlined, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              tabName(context, state.tab, state.userCategories),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    // At most ~7 rows — a plain min Column, no scroll view needed.
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Text(t(sheetContext, 'library.category.title'),
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              _sheetRow(
                sheetContext,
                label: t(sheetContext, 'library.cat.all'),
                selected: state.tab is AllTab,
                onTap: () {
                  controller.setTab(const AllTab());
                  Navigator.pop(sheetContext);
                },
              ),
              for (final kind in SmartKind.values)
                _sheetRow(
                  sheetContext,
                  label:
                      tabName(sheetContext, SmartTab(kind), state.userCategories),
                  selected:
                      state.tab is SmartTab && (state.tab as SmartTab).kind == kind,
                  onTap: () {
                    controller.setTab(SmartTab(kind));
                    Navigator.pop(sheetContext);
                  },
                ),
              for (final c in state.userCategories)
                _sheetRow(
                  sheetContext,
                  label: c.name,
                  selected: state.tab is CategoryTab &&
                      (state.tab as CategoryTab).categoryId == c.id,
                  onTap: () {
                    controller.setTab(CategoryTab(c.id));
                    Navigator.pop(sheetContext);
                  },
                  onEdit: () {
                    Navigator.pop(sheetContext);
                    showCategoryActions(sheetContext, ref, c);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add, size: 20),
                title: Text(t(sheetContext, 'library.cat.create')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  promptCategoryName(sheetContext, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onEdit,
  }) {
    return ListTile(
      dense: true,
      leading: selected
          ? const Icon(Icons.check, size: 20)
          : const SizedBox(width: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: onEdit == null
          ? null
          : IconButton(
              tooltip: t(context, 'library.category.edit'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
      onTap: onTap,
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.state,
    required this.searchOpen,
    required this.onSearchTap,
  });

  final LibraryState state;
  final bool searchOpen;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          // 3× the Spacer's flex: on a 411-logical-px screen an even split
          // left the dropdown ~95px and "ทั้งหมด" truncated to "ทั้…".
          Flexible(
            flex: 3,
            child: CategoryDropdown(state: state),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: t(context, 'library.search_hint'),
            icon: Icon(searchOpen ? Icons.search : Icons.search_outlined),
            onPressed: onSearchTap,
          ),
          const Spacer(),
          PopupMenuButton<LibrarySort>(
            tooltip: t(context, 'library.sort'),
            icon: const Icon(Icons.sort),
            onSelected: controller.setSort,
            itemBuilder: (context) => [
              for (final s in LibrarySort.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: state.sort == s,
                  child: Text(t(context, switch (s) {
                    LibrarySort.lastRead => 'library.sort.last_read',
                    LibrarySort.updated => 'library.sort.updated',
                    LibrarySort.added => 'library.sort.added',
                    LibrarySort.titleAz => 'library.sort.title_az',
                    LibrarySort.unread => 'library.sort.unread',
                  })),
                ),
            ],
          ),
          IconButton(
            tooltip: t(context,
                state.listView ? 'library.view_grid' : 'library.view_list'),
            icon: Icon(state.listView ? Icons.grid_view_outlined : Icons.list),
            onPressed: controller.toggleView,
          ),
          Badge(
            isLabelVisible: !state.filters.isEmpty,
            child: IconButton(
              tooltip: t(context, 'library.filter'),
              icon: const Icon(Icons.filter_list),
              onPressed: () => showLibraryFilterSheet(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final visible = state.visible;
    if (visible.isEmpty) {
      return Center(child: Text(t(context, state.cards.isEmpty
          ? 'library.empty'
          : 'library.no_match')));
    }
    final selectionMode = state.selection.isNotEmpty;

    if (state.listView) {
      return ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, i) => _row(context, ref, visible[i],
            selectionMode),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final cols = (constraints.maxWidth ~/ 170).clamp(2, 3);
      return GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.58,
        ),
        itemCount: visible.length,
        itemBuilder: (context, i) =>
            _card(context, ref, visible[i], selectionMode),
      );
    });
  }

  void _open(BuildContext context, WidgetRef ref, LibraryCard card) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DetailScreen(seriesId: card.seriesId),
    ));
  }

  Widget _card(BuildContext context, WidgetRef ref, LibraryCard card,
      bool selectionMode) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return LibraryCardView(
      card: card,
      selected: state.selection.contains(card.seriesId),
      selectionMode: selectionMode,
      onTap: () {
        if (selectionMode) {
          controller.toggleSelect(card.seriesId);
        } else {
          _open(context, ref, card);
        }
      },
      onLongPress: () => controller.toggleSelect(card.seriesId),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, LibraryCard card,
      bool selectionMode) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return LibraryRowView(
      card: card,
      selected: state.selection.contains(card.seriesId),
      selectionMode: selectionMode,
      onTap: () {
        if (selectionMode) {
          controller.toggleSelect(card.seriesId);
        } else {
          _open(context, ref, card);
        }
      },
      onLongPress: () => controller.toggleSelect(card.seriesId),
    );
  }
}

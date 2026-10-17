import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../data/repo/library_cards.dart';
import '../detail/detail_screen.dart';
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
      appBar: AppBar(
        title: Text(selectionMode
            ? tFmt(context, 'library.selected', {'n': '${state.selection.length}'})
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
          _CategoryChips(state: state),
          _Toolbar(state: state),
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

/// Horizontal category chip row (Plan/12 §1): built-ins, divider, user
/// categories, "+".
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    final active = state.tab;

    bool sel(LibraryTab tab) {
      if (tab.runtimeType != active.runtimeType) return false;
      if (tab is CategoryTab && active is CategoryTab) {
        return tab.categoryId == active.categoryId;
      }
      if (tab is SmartTab && active is SmartTab) return tab.kind == active.kind;
      return true;
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          ChoiceChip(
            label: Text(t(context, 'library.cat.all')),
            selected: sel(const AllTab()),
            onSelected: (_) => controller.setTab(const AllTab()),
          ),
          for (final kind in SmartKind.values)
            ChoiceChip(
              label: Text(t(context, switch (kind) {
                SmartKind.reading => 'library.cat.reading',
                SmartKind.hasNew => 'library.cat.has_new',
                SmartKind.novel => 'library.cat.novel',
                SmartKind.downloaded => 'library.cat.downloaded',
              })),
              selected: sel(SmartTab(kind)),
              onSelected: (_) => controller.setTab(SmartTab(kind)),
            ),
          for (final c in state.userCategories) ...[
            const VerticalDivider(width: 16),
            GestureDetector(
              onLongPress: () => showCategoryActions(context, ref, c),
              child: ChoiceChip(
                label: Text(c.name),
                selected: sel(CategoryTab(c.id)),
                onSelected: (_) => controller.setTab(CategoryTab(c.id)),
              ),
            ),
          ],
          IconButton(
            tooltip: t(context, 'library.cat.create'),
            icon: const Icon(Icons.add),
            onPressed: () => promptCategoryName(context, ref),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(libraryControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: controller.setSearch,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: t(context, 'library.search_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
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

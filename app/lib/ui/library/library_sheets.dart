import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/dao/library_dao.dart';
import '../../data/repo/library_cards.dart';
import 'library_controller.dart';

/// Toolbar filter icon → quick-filter chips (Plan/12): มีตอนใหม่ /
/// ดาวน์โหลดแล้ว / ตามประเภท / ตามแหล่ง — AND-combined with the tab.
void showLibraryFilterSheet(BuildContext context, WidgetRef ref) {
  final controller = ref.read(libraryControllerProvider.notifier);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(builder: (context, ref, _) {
      final filters = ref.watch(libraryControllerProvider.select((s) => s.filters));
      final sources = ref.watch(sourcesProvider);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: Text(t(context, 'library.filter.has_new')),
                    selected: filters.hasNew,
                    onSelected: (v) => controller.setFilters(
                        filters.copyWith(hasNew: v)),
                  ),
                  FilterChip(
                    label: Text(t(context, 'library.filter.downloaded')),
                    selected: filters.downloaded,
                    onSelected: (v) => controller.setFilters(
                        filters.copyWith(downloaded: v)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(t(context, 'library.filter.by_type'),
                  style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final ty in const ['manga', 'manhwa', 'manhua', 'novel'])
                    FilterChip(
                      label: Text(t(context, 'browse.type.$ty')),
                      selected: filters.types.contains(ty),
                      onSelected: (v) {
                        final next = {...filters.types};
                        if (v) { next.add(ty); } else { next.remove(ty); }
                        controller.setFilters(filters.copyWith(types: next));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(t(context, 'library.filter.by_source'),
                  style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in sources)
                    FilterChip(
                      label: Text(s.name),
                      selected: filters.sources.contains(s.id),
                      onSelected: (v) {
                        final next = {...filters.sources};
                        if (v) { next.add(s.id); } else { next.remove(s.id); }
                        controller.setFilters(filters.copyWith(sources: next));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      controller.setFilters(const LibraryFilters());
                    },
                    child: Text(t(context, 'library.filter.clear')),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t(context, 'common.done')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }),
  );
}

/// Name prompt for create / rename (Plan/12 §1 "+ chip", long-press menu).
Future<void> promptCategoryName(BuildContext context, WidgetRef ref,
    {Category? existing}) async {
  final controller = ref.read(libraryControllerProvider.notifier);
  final field = TextEditingController(text: existing?.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t(context,
          existing == null ? 'library.cat.create' : 'library.cat.rename')),
      content: TextField(
        controller: field,
        autofocus: true,
        maxLength: 40,
        decoration: InputDecoration(
            hintText: t(context, 'library.cat.name_hint')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(field.text.trim()),
          child: Text(t(context, 'common.ok')),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return;
  if (existing == null) {
    await controller.createCategory(name);
  } else {
    await controller.renameCategory(existing.id, name);
  }
}

/// Long-press a user-category chip → เปลี่ยนชื่อ / ล้างหมวด / ลบหมวด.
void showCategoryActions(BuildContext context, WidgetRef ref, Category cat) {
  final controller = ref.read(libraryControllerProvider.notifier);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(t(context, 'library.cat.rename')),
            onTap: () {
              Navigator.of(context).pop();
              promptCategoryName(context, ref, existing: cat);
            },
          ),
          ListTile(
            leading: const Icon(Icons.layers_clear_outlined),
            title: Text(t(context, 'library.cat.clear')),
            onTap: () {
              Navigator.of(context).pop();
              controller.clearCategory(cat.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(t(context, 'library.cat.delete')),
            onTap: () {
              Navigator.of(context).pop();
              controller.deleteCategory(cat.id);
            },
          ),
        ],
      ),
    ),
  );
}

/// Multi-select "ย้ายหมวด" → pick (or create) a target category.
Future<void> showMoveToCategorySheet(
    BuildContext context, WidgetRef ref) async {
  final state = ref.read(libraryControllerProvider);
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final c in state.userCategories)
            ListTile(
              title: Text(c.name),
              onTap: () => Navigator.of(context).pop(c.id),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(t(context, 'library.cat.create')),
            onTap: () => Navigator.of(context).pop(-1),
          ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  if (picked == -1) {
    final before = ref.read(libraryControllerProvider).userCategories;
    await promptCategoryName(context, ref);
    final after = ref.read(libraryControllerProvider).userCategories;
    final created = after.where((c) => !before.contains(c)).toList();
    if (created.isNotEmpty) {
      await ref
          .read(libraryControllerProvider.notifier)
          .moveSelectionTo(created.first.id);
    }
    return;
  }
  await ref.read(libraryControllerProvider.notifier).moveSelectionTo(picked);
}

/// "ลบออกจากคลัง" confirm (Plan/12 §1): returns null = cancel,
/// true = keep downloaded files, false = remove downloads too.
Future<bool?> showDeleteFromLibraryDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t(context, 'library.delete.title')),
      content: Text(t(context, 'library.delete.body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t(context, 'common.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t(context, 'library.delete.keep_files')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t(context, 'library.delete.remove_files')),
        ),
      ],
    ),
  );
}

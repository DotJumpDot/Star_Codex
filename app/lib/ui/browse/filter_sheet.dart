import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/repo/browse_repo.dart';
import 'browse_controller.dart';

/// Filter panel bottom sheet (Plan/08 §3). Values are session-only (never
/// written to settings) — defaults OFF per decision L1, restart ⇒ defaults.
void showBrowseFilterSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Cap the WHOLE sheet (handle + safe areas included) at 70% of the
    // screen — content scrolls inside (user QA 2026-10-18).
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
      ),
      child: const _FilterSheetBody(),
    ),
  );
}

class _FilterSheetBody extends ConsumerStatefulWidget {
  const _FilterSheetBody();

  @override
  ConsumerState<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends ConsumerState<_FilterSheetBody> {
  late Future<List<String>> _tags;

  @override
  void initState() {
    super.initState();
    _tags = ref.read(tagsDaoProvider).allNames();
  }

  BrowseController get _controller =>
      ref.read(browseControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(browseControllerProvider).filters;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t(context, 'browse.filter.title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _controller.setFilters(const BrowseFilters()),
                    child: Text(t(context, 'browse.filter.reset')),
                  ),
                ],
              ),
              _sectionLabel(context, 'browse.filter.type'),
              Wrap(
                spacing: 6,
                children: [
                  for (final entry in <String?, String>{
                    null: 'browse.filter.off',
                    'manga': 'browse.type.manga',
                    'manhwa': 'browse.type.manhwa',
                    'manhua': 'browse.type.manhua',
                    'novel': 'browse.type.novel',
                  }.entries)
                    ChoiceChip(
                      label: Text(t(context, entry.value)),
                      selected: filters.type == entry.key,
                      onSelected: (_) => _controller.setFilters(
                        filters.copyWith(
                          type: entry.key,
                          clearType: entry.key == null,
                        ),
                      ),
                    ),
                ],
              ),
              _sectionLabel(context, 'browse.filter.status'),
              // Honest no-op on browse listings until detail data exists
              // (Plan/08 §3): keep the control, say when it engages.
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  t(context, 'browse.filter.status_hint'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final entry in <String?, String>{
                    null: 'browse.filter.off',
                    'ongoing': 'browse.status.ongoing',
                    'completed': 'browse.status.completed',
                  }.entries)
                    ChoiceChip(
                      label: Text(t(context, entry.value)),
                      selected: filters.status == entry.key,
                      onSelected: (_) => _controller.setFilters(
                        filters.copyWith(
                          status: entry.key,
                          clearStatus: entry.key == null,
                        ),
                      ),
                    ),
                ],
              ),
              _sectionLabel(context, 'browse.filter.min_chapters'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: filters.minChapters.toDouble(),
                      min: 0,
                      max: 50,
                      divisions: 50,
                      label: '${filters.minChapters}',
                      onChanged: (v) => _controller.setFilters(
                        filters.copyWith(minChapters: v.round()),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${filters.minChapters}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t(context, 'browse.filter.hide_oneshot')),
                value: filters.hideOneshot,
                onChanged: (v) =>
                    _controller.setFilters(filters.copyWith(hideOneshot: v)),
              ),
              _sectionLabel(context, 'browse.filter.tags'),
              FutureBuilder<List<String>>(
                future: _tags,
                builder: (context, snap) {
                  final names = snap.data ?? const [];
                  if (names.isEmpty) {
                    return Text(
                      t(context, 'common.empty'),
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  }
                  return Wrap(
                    spacing: 6,
                    children: [
                      for (final name in names)
                        FilterChip(
                          label: Text(name),
                          selected: filters.tags.contains(name),
                          onSelected: (on) {
                            final tags = {...filters.tags};
                            on ? tags.add(name) : tags.remove(name);
                            _controller.setFilters(
                              filters.copyWith(tags: tags),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String key) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(t(context, key), style: Theme.of(context).textTheme.labelLarge),
  );
}

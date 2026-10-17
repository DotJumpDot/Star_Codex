import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/dao/series_dao.dart';
import 'detail_controller.dart';

/// ผสานเรื่อง (Plan/12 §4, detail ⋯ menu): pick the OTHER series to absorb
/// into this one, confirm with both titles shown, then merge.
Future<void> showMergeDialog(BuildContext context, ProviderContainer container,
    int seriesId, String thisTitle) async {
  final messenger = ScaffoldMessenger.of(context);
  final all = await container.read(seriesDaoProvider).all();
  final candidates =
      all.where((s) => s.id != seriesId).toList(growable: false);
  if (candidates.isEmpty || !context.mounted) return;

  final picked = await showDialog<Series>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(t(context, 'library.merge.pick')),
      children: [
        for (final s in candidates)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(s.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t(context, 'library.merge.title')),
      content: Text(tFmt(context, 'library.merge.confirm', {
        'a': thisTitle,
        'b': picked.title,
      })),
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
  if (ok != true || !context.mounted) return;

  try {
    await container
        .read(detailControllerProvider(seriesId).notifier)
        .mergeIn([picked.id!]);
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text(t(context, 'common.error.title'))));
    return;
  }
  if (!context.mounted) return;
  messenger.showSnackBar(
      SnackBar(content: Text(t(context, 'library.merge.done'))));
}

/// แยกเรื่อง (Plan/12 §4): pick one of this series' source links to lift
/// onto its own standalone series row.
Future<void> showSplitDialog(
    BuildContext context, ProviderContainer container, int seriesId) async {
  final messenger = ScaffoldMessenger.of(context);
  final links = await container.read(seriesDaoProvider).sourcesOf(seriesId);
  if (!context.mounted) return;
  if (links.length < 2) {
    messenger.showSnackBar(
        SnackBar(content: Text(t(context, 'library.split.need_two'))));
    return;
  }
  final names = container.read(sourcesProvider);
  String nameOf(String id) {
    for (final s in names) {
      if (s.id == id) return s.name;
    }
    return id;
  }

  final picked = await showDialog<SeriesSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(t(context, 'library.split.pick')),
      children: [
        for (final link in links)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(link),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(nameOf(link.sourceId)),
            ),
          ),
      ],
    ),
  );
  if (picked == null) return;

  try {
    await container
        .read(detailControllerProvider(seriesId).notifier)
        .splitOut(picked.sourceId);
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text(t(context, 'common.error.title'))));
    return;
  }
  if (!context.mounted) return;
  messenger.showSnackBar(
      SnackBar(content: Text(t(context, 'library.split.done'))));
}

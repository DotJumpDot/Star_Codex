import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/series_repo.dart';
import '../browse/source_palette.dart';
import '../reader/reader_router.dart';
import 'detail_controller.dart';

/// Long-press chapter sheet (Plan/09 §6): read-from picker (doc 09
/// addendum — "อ่านจากเว็บไหน"), mark read/unread, download now, delete
/// downloaded files.
Future<void> showChapterActions(
  BuildContext context,
  WidgetRef ref, {
  required SeriesDetailVm vm,
  required Chapter chapter,
  required List<String> carryingSourceIds,
  required int controllerKey,
}) {
  final controller = ref.read(detailControllerProvider(controllerKey).notifier);
  final downloaded = vm.downloadedChapterIds.contains(chapter.id);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(t(sheetContext, 'detail.read_from'),
                style: Theme.of(sheetContext).textTheme.titleSmall),
          ),
          for (final sid in carryingSourceIds)
            ListTile(
              leading: SourceDot(
                  color: sourceDotColor(
                      vm.links.indexWhere((l) => l.sourceId == sid)),
                  size: 12),
              title: Text(vm.sourceNames[sid] ?? sid),
              trailing: const Icon(Icons.play_arrow, size: 20),
              dense: true,
              onTap: () {
                final copy =
                    (vm.chaptersByNumber[chapter.number] ?? const [])
                        .where((c) => c.sourceId == sid)
                        .first;
                Navigator.pop(sheetContext);
                final settings = ref.read(settingsProvider);
                openReader(context,
                    chapter: copy,
                    sourceId: sid,
                    seriesDao: ref.read(seriesDaoProvider),
                    modeOverride: effectiveModeOverride(
                        settings.get(
                            'reader_mode_${chapter.seriesId}', 'auto'),
                        settings.get('reader_mode_default', 'auto')));
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.done_all),
            title: Text(t(sheetContext,
                (vm.progress[chapter.id]?.completed ?? false)
                    ? 'detail.mark_unread'
                    : 'detail.mark_read')),
            onTap: () {
              final completed =
                  !(vm.progress[chapter.id]?.completed ?? false);
              Navigator.pop(sheetContext);
              controller.markRead(chapter.id!, completed: completed);
            },
          ),
          if (!downloaded)
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(t(sheetContext, 'detail.download_chapter')),
              onTap: () {
                Navigator.pop(sheetContext);
                controller.enqueueDownload(chapter.id!);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t(context, 'detail.queued'))));
              },
            ),
          if (downloaded)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(t(sheetContext, 'detail.delete_downloaded')),
              onTap: () {
                Navigator.pop(sheetContext);
                controller.deleteDownload(chapter.id!);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t(context, 'detail.deleted'))));
              },
            ),
        ],
      ),
    ),
  );
}

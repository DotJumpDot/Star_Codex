import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/thai.dart';
import '../../data/repo/downloads_repo.dart';
import 'downloads_controller.dart';

/// Offline tab section 2 (doc 13 §A): queue / running / failed rows with
/// live page progress + per-row pause/resume/delete.
class QueueSection extends ConsumerWidget {
  const QueueSection({super.key, required this.rows});

  final List<QueueRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(downloadsControllerProvider.notifier);
    return Column(
      children: [
        for (final row in rows)
          ListTile(
            dense: true,
            leading: const Icon(Icons.download_outlined),
            title: Text(
              '${row.seriesTitle} · ${t(context, 'history.chapter')} '
              '${formatChapterNumber(row.number)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.state == 'error' && row.error != null)
                  Text(
                    t(context, 'offline.failed'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 11),
                  )
                else if (row.isNovel)
                  Text(t(context, 'offline.novel_progress'),
                      style: Theme.of(context).textTheme.labelSmall)
                else ...[
                  Text(
                    tFmt(context, 'offline.page_progress', {
                      'done': '${row.pagesDone}',
                      'total': '${row.pagesTotal}',
                    }),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  LinearProgressIndicator(
                    value: row.pagesTotal == 0
                        ? null
                        : (row.pagesDone / row.pagesTotal)
                            .clamp(0.0, 1.0),
                    minHeight: 3,
                  ),
                ],
              ],
            ),
            trailing: _trailing(context, ref, controller, row),
          ),
      ],
    );
  }

  Widget? _trailing(BuildContext context, WidgetRef ref,
      DownloadsController controller, QueueRow row) {
    switch (row.state) {
      case 'running':
        return IconButton(
          tooltip: t(context, 'offline.pause'),
          icon: const Icon(Icons.pause, size: 20),
          onPressed: () => controller.pause(row.chapterId),
        );
      case 'paused':
        return IconButton(
          tooltip: t(context, 'offline.resume'),
          icon: const Icon(Icons.play_arrow, size: 20),
          onPressed: () => controller.resume(row.chapterId),
        );
      case 'error':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: t(context, 'offline.retry'),
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => controller.resume(row.chapterId),
          ),
          IconButton(
            tooltip: t(context, 'history.delete_go'),
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => controller.delete(row.chapterId),
          ),
        ]);
      default:
        return null; // queued: nothing to do but wait
    }
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/relative_time.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/blobs_dao.dart';
import '../../data/repo/updates_repo.dart';
import '../reader/reader_router.dart';
import 'updates_controller.dart';

/// Library AppBar bell (doc 13 §B): badge = unseen chapters; opens the
/// merged updates timeline. Opening consumes the badge (mark-seen).
class UpdatesBell extends ConsumerStatefulWidget {
  const UpdatesBell({super.key});

  @override
  ConsumerState<UpdatesBell> createState() => _UpdatesBellState();
}

class _UpdatesBellState extends ConsumerState<UpdatesBell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(updatesControllerProvider.notifier).reload();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unseen = ref.watch(updatesControllerProvider.select((s) => s.unseen));
    return IconButton(
      tooltip: t(context, 'updates.title'),
      icon: Badge(
        isLabelVisible: unseen > 0,
        label: Text('$unseen'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => showUpdatesSheet(context, ref),
    );
  }
}

/// Full-height merged timeline (doc 13 §B): per series groups —
/// "title — ตอนที่ 921, 922 (slow-manga, 2 ชม. ที่แล้ว)" — tap a chapter
/// row opens the reader; mark-seen happens on open.
Future<void> showUpdatesSheet(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(updatesControllerProvider.notifier);
  await controller.reload();
  await controller.markSeen();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(builder: (context, ref, _) {
      final state = ref.watch(updatesControllerProvider);
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(t(context, 'updates.title'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: t(context, 'updates.refresh'),
                    icon: state.checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    onPressed: state.checking
                        ? null
                        : () => ref
                            .read(updatesControllerProvider.notifier)
                            .check(force: true),
                  ),
                ],
              ),
              if (state.groups.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(t(context, 'updates.empty'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      for (final g in state.groups) _GroupTile(group: g),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }),
  );
  // Returning from the sheet: reopen may have read chapters — refresh.
  await controller.reload();
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});

  final UpdateGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers =
        group.items.map((i) => formatChapterNumber(i.number)).join(', ');
    final first = group.items.first;
    final age = relativeParts(first.uploadedAt);
    final ageText = tFmt(context, age.key, age.params);
    final meta = first.sourceName == null
        ? ageText
        : '(${first.sourceName}, $ageText)';
    return ExpansionTile(
      leading: _FeedCover(hash: group.coverHash),
      title: Text(group.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (group.originalTitle != null)
            Text(group.originalTitle!,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$numbers $meta',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      children: [
        for (final item in group.items)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.image_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text('${t(context, 'history.chapter')} '
                '${formatChapterNumber(item.number)}'),
            trailing: item.sourceName == null
                ? null
                : Text(item.sourceName!,
                    style: Theme.of(context).textTheme.labelSmall),
            onTap: () => _open(context, ref, item),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _open(context, ref, group.items.first),
            child: Text(t(context, 'updates.read_all')),
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, UpdateItem item) async {
    final chapter = await ref.read(chaptersDaoProvider).byId(item.chapterId);
    if (chapter == null || !context.mounted) return;
    final settings = ref.read(settingsProvider);
    await openReader(context,
        chapter: chapter,
        sourceId: chapter.sourceId,
        seriesDao: ref.read(seriesDaoProvider),
        modeOverride: effectiveModeOverride(
            settings.get('reader_mode_${chapter.seriesId}', 'auto'),
            settings.get('reader_mode_default', 'auto')));
  }
}

class _FeedCover extends ConsumerStatefulWidget {
  const _FeedCover({required this.hash});

  final String? hash;

  @override
  ConsumerState<_FeedCover> createState() => _FeedCoverState();
}

class _FeedCoverState extends ConsumerState<_FeedCover> {
  Future<BlobRow?>? _future;

  @override
  Widget build(BuildContext context) {
    final hash = widget.hash;
    if (hash == null) return _placeholder(context);
    _future ??= ref.read(blobStoreProvider).blobRow(hash);
    final dir = ref.watch(libraryDirProvider);
    return FutureBuilder<BlobRow?>(
      future: _future,
      builder: (context, snap) {
        final path = snap.data?.path;
        if (path == null) return _placeholder(context);
        return Image.file(
          File('${dir.path}/$path'),
          width: 48,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(context),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        width: 48,
        height: 68,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.notifications_outlined,
            size: 18, color: Theme.of(context).colorScheme.outline),
      );
}

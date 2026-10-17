import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/blobs_dao.dart';
import '../../data/repo/downloads_repo.dart';
import 'downloads_controller.dart';
import 'queue_section.dart';

/// Offline tab (doc 13 §A): the TRUTHFUL ready-offline list (files on disk
/// only) + the live download queue. "ล้างแคช" never touches this list —
/// downloads are pinned by definition.
class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({super.key});

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  List<OfflineSeries>? _ready;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ready = await ref.read(downloadsRepoProvider).readyOffline();
    if (!mounted) return;
    setState(() => _ready = ready);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(downloadsControllerProvider);
    // Queue finished something → the ready list may have grown.
    ref.listen(downloadsControllerProvider, (prev, next) {
      if (prev?.rows != next.rows) _reload();
    });
    // Tab re-entry (IndexedStack keeps state) → refresh too.
    ref.listen(tabIndexProvider, (prev, next) {
      if (next == 3) _reload();
    });

    final quota = ref
        .watch(settingsProvider)
        .getInt('total_quota_bytes', 107374182400);

    final ready = _ready;
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'tab.offline')),
        actions: [
          IconButton(
            tooltip: t(context, 'offline.pause_all'),
            icon: const Icon(Icons.pause_circle_outline),
            onPressed:
                snapshot.hasActive ? () async {
                  await ref.read(downloadsControllerProvider.notifier).pauseAll();
                } : null,
          ),
        ],
      ),
      body: ready == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _StorageHeader(pinnedBytes: snapshot.pinnedBytes, quotaBytes: quota),
                if (snapshot.wifiPaused)
                  ListTile(
                    leading: const Icon(Icons.wifi_off),
                    dense: true,
                    title: Text(t(context, 'offline.wifi_paused'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (snapshot.rows.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(t(context, 'offline.queue_section'),
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  QueueSection(rows: snapshot.rows),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(t(context, 'offline.ready_section'),
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (ready.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(t(context, 'offline.empty'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  )
                else
                  for (final s in ready)
                    _ReadySeriesTile(
                        series: s, onChanged: _reload),
                ListTile(
                  dense: true,
                  title: Text(
                    t(context, 'offline.foreground_note'),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                  ),
                ),
              ],
            ),
    );
  }
}

/// "ใช้ไป 42.1 GB / 100 GB" (doc 13 §A).
class _StorageHeader extends StatelessWidget {
  const _StorageHeader({required this.pinnedBytes, required this.quotaBytes});

  final int pinnedBytes;
  final int quotaBytes;

  String _gb(int bytes) => (bytes / 1073741824).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tFmt(context, 'offline.storage', {
              'used': _gb(pinnedBytes),
              'total': _gb(quotaBytes),
            }),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: quotaBytes == 0 ? 0 : (pinnedBytes / quotaBytes).clamp(0.0, 1.0),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}

/// Ready row: cover, dual titles (L5), "12 ตอน · 148 MB", per-series
/// actions เลือกลบบางตอน / ลบทั้งหมด (doc 13 §A).
class _ReadySeriesTile extends ConsumerWidget {
  const _ReadySeriesTile({required this.series, required this.onChanged});

  final OfflineSeries series;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      leading: _OfflineCover(hash: series.coverHash),
      title: Text(series.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (series.originalTitle != null)
            Text(series.originalTitle!,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            tFmt(context, 'offline.ready_summary', {
              'n': '${series.chapterCount}',
              'mb': (series.bytes / 1048576).round().toString(),
            }),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(t(context, 'offline.pick_delete')),
              onPressed: () =>
                  _pickChaptersToDelete(context, ref),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(t(context, 'offline.delete_all')),
              onPressed: () => _deleteAll(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(libraryRepoProvider);
    await repo.removeSeriesDownloads(series.seriesId);
    onChanged();
  }

  Future<void> _pickChaptersToDelete(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<Set<int>>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ChapterDeleteSheet(series: series),
    );
    if (picked == null || picked.isEmpty) return;
    final dao = ref.read(downloadsDaoProvider);
    final janitor = ref.read(cacheJanitorProvider);
    for (final id in picked) {
      await dao.delete(id);
    }
    await janitor.recomputePins();
    onChanged();
  }
}

/// Per-chapter delete picker (เลือกลบบางตอน).
class _ChapterDeleteSheet extends ConsumerStatefulWidget {
  const _ChapterDeleteSheet({required this.series});

  final OfflineSeries series;

  @override
  ConsumerState<_ChapterDeleteSheet> createState() =>
      _ChapterDeleteSheetState();
}

class _ChapterDeleteSheetState extends ConsumerState<_ChapterDeleteSheet> {
  final _picked = <int>{};

  @override
  Widget build(BuildContext context) {
    final dao = ref.watch(chaptersDaoProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: FutureBuilder(
          future: dao.byIds(widget.series.chapterIds),
          builder: (context, snap) {
            final chapters = snap.data ?? const <(int, double)>[];
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      for (final (id, number) in chapters)
                        CheckboxListTile(
                          dense: true,
                          value: _picked.contains(id),
                          title: Text(formatChapterNumber(number)),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _picked.add(id);
                            } else {
                              _picked.remove(id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(tFmt(context,
                        'downloads.go', {'n': '${_picked.length}'})),
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_picked),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OfflineCover extends ConsumerStatefulWidget {
  const _OfflineCover({required this.hash});

  final String? hash;

  @override
  ConsumerState<_OfflineCover> createState() => _OfflineCoverState();
}

class _OfflineCoverState extends ConsumerState<_OfflineCover> {
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
        child: Icon(Icons.image_outlined,
            size: 18, color: Theme.of(context).colorScheme.outline),
      );
}

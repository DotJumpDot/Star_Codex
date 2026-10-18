import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/blobs_dao.dart';
import '../../data/dao/library_dao.dart';
import '../reader/reader_router.dart';
import '../shell/star_app_bar.dart';
import 'history_group.dart';

/// History tab (Plan/12 §5): `reading_history` grouped วันนี้ / เมื่อวาน /
/// "17 ต.ค.". Tap reopens the chapter at its saved position; long-press
/// deletes the row; the AppBar button clears ALL history (reading_history
/// ONLY — read_progress and library stay).
///
/// Grouped mode (setting `history_group_series`, default ON): one row per
/// series showing the read-chapter range ("ตอน 1-3"); tap reopens the
/// LAST-read chapter; long-press deletes the whole series' history.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<HistoryRow>? _rows;
  String _filter = '';
  bool _refreshOnNextEnter = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await ref.read(historyDaoProvider).recent();
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps this tab alive — refresh whenever the shell
    // switches back to it so a just-finished chapter shows up.
    ref.listen(tabIndexProvider, (prev, next) {
      if (next == 2 && _refreshOnNextEnter) {
        _refreshOnNextEnter = false;
        _reload();
      }
      if (next != 2) _refreshOnNextEnter = true;
    });

    final rows = _rows;
    return Scaffold(
      appBar: starAppBar(
        context,
        ref: ref,
        title: Text(t(context, 'tab.history')),
        actions: [
          IconButton(
            tooltip: t(context, 'history.clear_all'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClearAll(context),
          ),
        ],
      ),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, rows),
    );
  }

  Widget _body(BuildContext context, List<HistoryRow> rows) {
    final q = _filter.trim().toLowerCase();
    final visible = q.isEmpty
        ? rows
        : rows
            .where((r) =>
                r.title.toLowerCase().contains(q) ||
                (r.originalTitle?.toLowerCase().contains(q) ?? false))
            .toList();
    final grouped = ref
        .read(settingsProvider)
        .get('history_group_series', 'true') == 'true';
    if (visible.isEmpty) {
      return Center(
          child: Text(
              t(context,
                  rows.isEmpty ? 'history.empty' : 'library.no_match')));
    }

    String labelFor(int diffDays, DateTime day) => switch (diffDays) {
          0 => t(context, 'history.today'),
          1 => t(context, 'history.yesterday'),
          _ => DateFormat('d MMM', I18nService.lang).format(day),
        };
    final entries =
        grouped ? collapseBySeries(visible) : const <HistorySeriesEntry>[];
    final groups = groupByDay(
        grouped ? [for (final e in entries) e.latest] : visible, labelFor);
    final entryGroups = grouped
        ? _groupEntriesByDay(entries, labelFor)
        : const <String, List<HistorySeriesEntry>>{};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            onChanged: (v) => setState(() => _filter = v),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: t(context, 'history.filter_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: grouped
              ? ListView(
                  children: [
                    for (final g in entryGroups.entries) ...[
                      _DayHeader(label: g.key),
                      for (final e in g.value)
                        _GroupedHistoryTile(entry: e, onChanged: _reload),
                    ],
                  ],
                )
              : ListView(
                  children: [
                    for (final g in groups.entries) ...[
                      _DayHeader(label: g.key),
                      for (final row in g.value) _HistoryTile(row: row),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  /// Day-bucketing for collapsed entries — same rules as [groupByDay],
  /// keyed on each entry's latest read.
  Map<String, List<HistorySeriesEntry>> _groupEntriesByDay(
    List<HistorySeriesEntry> entries,
    String Function(int diffDays, DateTime day) labelFor,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final map = <String, List<HistorySeriesEntry>>{};
    for (final e in entries) {
      final local = DateTime.fromMillisecondsSinceEpoch(e.latest.readAt);
      final day = DateTime(local.year, local.month, local.day);
      final label = labelFor(today.difference(day).inDays, day);
      (map[label] ??= []).add(e);
    }
    return map;
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, 'history.clear_all')),
        content: Text(t(context, 'history.clear_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, 'history.clear_go')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(historyDaoProvider).clear();
    await _reload();
  }
}

/// Group newest-first rows under day headers: วันนี้ / เมื่อวาน / a
/// localized date for older ones. [labelFor] gets the whole-day difference
/// from today and the LOCAL calendar day (doc 12 §5).
Map<String, List<HistoryRow>> groupByDay(
  List<HistoryRow> rows,
  String Function(int diffDays, DateTime day) labelFor,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final map = <String, List<HistoryRow>>{};
  for (final r in rows) {
    final local = DateTime.fromMillisecondsSinceEpoch(r.readAt);
    final day = DateTime(local.year, local.month, local.day);
    final label = labelFor(today.difference(day).inDays, day);
    (map[label] ??= []).add(r);
  }
  return map;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.row});

  final HistoryRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = DateTime.fromMillisecondsSinceEpoch(row.readAt);
    final time = DateFormat('HH:mm', I18nService.lang).format(local);
    final isNovel = row.type == 'novel';
    return ListTile(
      leading: _HistoryCover(row: row),
      title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.originalTitle != null)
            Text(row.originalTitle!,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${t(context, 'history.chapter')} ${formatChapterNumber(row.number)} · $time',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      trailing: Icon(
          isNovel ? Icons.menu_book_outlined : Icons.image_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onLongPress: () => _deleteRow(context, ref),
      onTap: () => _reopen(context, ref),
    );
  }

  Future<void> _deleteRow(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, 'history.delete_row')),
        content: Text(row.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, 'history.delete_go')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(historyDaoProvider).deleteForChapter(row.chapterId);
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final chapter = await ref.read(chaptersDaoProvider).byId(row.chapterId);
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

/// Collapsed series row: title + chapter range ("ตอน 1-3") + latest-read
/// time. Tap reopens the LAST-read chapter; long-press wipes the series'
/// whole history.
class _GroupedHistoryTile extends ConsumerWidget {
  const _GroupedHistoryTile({required this.entry, this.onChanged});

  final HistorySeriesEntry entry;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = entry.latest;
    final local = DateTime.fromMillisecondsSinceEpoch(row.readAt);
    final time = DateFormat('HH:mm', I18nService.lang).format(local);
    final isNovel = row.type == 'novel';
    final range = entry.singleChapter
        ? formatChapterNumber(entry.maxNumber)
        : '${formatChapterNumber(entry.minNumber)}-'
            '${formatChapterNumber(entry.maxNumber)}';
    return ListTile(
      leading: _HistoryCover(row: row),
      title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.originalTitle != null)
            Text(row.originalTitle!,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${t(context, 'history.chapter')} $range · $time',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      trailing: Icon(
          isNovel ? Icons.menu_book_outlined : Icons.image_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onLongPress: () => _deleteSeries(context, ref),
      onTap: () => _reopen(context, ref),
    );
  }

  Future<void> _deleteSeries(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, 'history.delete_series')),
        content: Text(entry.latest.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, 'history.delete_go')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(historyDaoProvider)
        .deleteForSeries(entry.latest.seriesId);
    onChanged?.call();
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final chapter =
        await ref.read(chaptersDaoProvider).byId(entry.latest.chapterId);
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

/// 48×68 cover from the blob store; missing/evicted → placeholder. The
/// timeline never refetches covers over the network (cache-only).
class _HistoryCover extends ConsumerStatefulWidget {
  const _HistoryCover({required this.row});

  final HistoryRow row;

  @override
  ConsumerState<_HistoryCover> createState() => _HistoryCoverState();
}

class _HistoryCoverState extends ConsumerState<_HistoryCover> {
  Future<BlobRow?>? _future;

  @override
  Widget build(BuildContext context) {
    final hash = widget.row.coverHash;
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

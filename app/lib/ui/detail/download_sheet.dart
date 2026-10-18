import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/utils/relative_time.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/series_repo.dart';
import '../../data/storage/blob_store.dart';
import 'detail_controller.dart';

/// Detail ⬇ button → download sheet (doc 13 §A): site picker (the sheet
/// used to be locked to the primary source), unread / next 10 / all /
/// pick-your-own (range + list), per-chapter upload stamps, size
/// estimate, quota refusal with the remaining GB.
Future<void> showDownloadSheet(
  BuildContext context,
  WidgetRef ref,
  SeriesDetailVm vm,
  DetailKey key,
) async {
  var sourceId = vm.primaryLink.sourceId;
  var chapters = vm.chaptersBySource[sourceId] ?? const <Chapter>[];
  if (chapters.isEmpty) {
    // A lazily-probed link can be "primary" by last_chapter_number yet
    // carry no chapters until opened — fall back to the first source
    // that actually has a list.
    for (final entry in vm.chaptersBySource.entries) {
      if (entry.value.isNotEmpty) {
        sourceId = entry.key;
        chapters = entry.value;
        break;
      }
    }
  }
  if (chapters.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t(context, 'downloads.none'))));
    return;
  }

  final picked = await showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DownloadSheet(vm: vm, initialSourceId: sourceId),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  try {
    await ref
        .read(detailControllerProvider(key).notifier)
        .enqueueDownloads(picked.toList());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tFmt(context, 'downloads.queued', {'n': '${picked.length}'}),
        ),
      ),
    );
  } on QuotaException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tFmt(context, 'downloads.quota', {
            'gb': (e.freeBytes / 1073741824).toStringAsFixed(1),
          }),
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t(context, 'common.error.title'))));
  }
}

class _DownloadSheet extends ConsumerStatefulWidget {
  const _DownloadSheet({required this.vm, required this.initialSourceId});

  final SeriesDetailVm vm;
  final String initialSourceId;

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  late String _sourceId;
  final _selected = <int>{};
  int? _rangeFrom;
  int? _rangeTo;

  /// Memoized size estimate — recomputed only when the selection count
  /// changes (the query reads every chapter's page rows).
  Future<int>? _estimate;
  int _estimateForCount = -1;

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId;
  }

  List<Chapter> get _chapters =>
      widget.vm.chaptersBySource[_sourceId] ?? const <Chapter>[];

  /// Ascending display for range picking (the VM's list arrives number-DESC).
  List<Chapter> get _asc => _chapters.reversed.toList(growable: false);

  List<int> get _unreadIds => [
    for (final c in _asc)
      if (!(widget.vm.progress[c.id]?.completed ?? false)) c.id!,
  ];

  Set<int> get effectiveSelection {
    if (_rangeFrom != null && _rangeTo != null) {
      return _rangeIds.toSet();
    }
    return _selected.toSet();
  }

  List<int> get _rangeIds => [
    for (var i = 0; i < _asc.length; i++)
      if (i >= _rangeFrom! && i <= _rangeTo!) _asc[i].id!,
  ];

  void _switchSource(String id) {
    setState(() {
      _sourceId = id;
      _selected.clear();
      _rangeFrom = null;
      _rangeTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ids = effectiveSelection;
    if (ids.length != _estimateForCount) {
      _estimateForCount = ids.length;
      _estimate = ids.isEmpty
          ? Future.value(0)
          : ref.read(downloadsRepoProvider).estimateBytes(ids.toList());
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    t(context, 'downloads.title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  _sourcePicker(context),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_unreadIds.toSet()),
                    child: Text(
                      tFmt(context, 'downloads.unread', {
                        'n': '${_unreadIds.length}',
                      }),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_unreadIds.take(10).toSet()),
                    child: Text(t(context, 'downloads.next10')),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context)
                        .pop(_asc.map((c) => c.id!).toSet()),
                    child: Text(
                      tFmt(context, 'downloads.all', {
                        'n': '${_asc.length}',
                      }),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    t(context, 'downloads.pick_range'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  _rangeDropdown(context, true),
                  const SizedBox(width: 8),
                  _rangeDropdown(context, false),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _asc.length,
                itemBuilder: (context, i) {
                  final id = _asc[i].id!;
                  final checked = _inRange(i) || _selected.contains(id);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(_label(i)),
                    subtitle: _stamp(i),
                    onChanged: (_) => setState(() {
                      if (_selected.contains(id)) {
                        _selected.remove(id);
                      } else {
                        _selected.add(id);
                      }
                    }),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: FutureBuilder<int>(
                      future: _estimate,
                      builder: (context, snap) => Text(
                        tFmt(context, 'downloads.estimate', {
                          'mb': ((snap.data ?? 0) / 1048576).round().toString(),
                        }),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(
                      tFmt(context, 'downloads.go', {'n': '${ids.length}'}),
                    ),
                    onPressed: ids.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(ids),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcePicker(BuildContext context) {
    final vm = widget.vm;
    if (vm.links.length <= 1) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: t(context, 'downloads.site'),
      position: PopupMenuPosition.under,
      onSelected: _switchSource,
      itemBuilder: (context) => [
        for (final link in vm.links)
          PopupMenuItem(
            value: link.sourceId,
            child: Text(
              '${vm.sourceNames[link.sourceId] ?? link.sourceId} · '
              '${vm.chaptersBySource[link.sourceId]?.length ?? 0}',
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            vm.sourceNames[_sourceId] ?? _sourceId,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  bool _inRange(int i) =>
      _rangeFrom != null &&
      _rangeTo != null &&
      i >= _rangeFrom! &&
      i <= _rangeTo!;

  Widget _rangeDropdown(BuildContext context, bool isFrom) {
    final value = isFrom ? _rangeFrom : _rangeTo;
    return DropdownButton<int>(
      hint: Text(t(context, isFrom ? 'downloads.from' : 'downloads.to')),
      value: value,
      items: [
        for (var i = 0; i < _asc.length; i++)
          DropdownMenuItem(value: i, child: Text(_label(i))),
      ],
      onChanged: (v) => setState(() {
        if (isFrom) {
          _rangeFrom = v;
          if (_rangeTo != null &&
              _rangeFrom != null &&
              _rangeTo! < _rangeFrom!) {
            _rangeTo = _rangeFrom;
          }
        } else {
          _rangeTo = v;
        }
      }),
    );
  }

  String _label(int i) {
    final c = _asc[i];
    final num = formatChapterNumber(c.number);
    return c.title == null || c.title!.contains(num)
        ? num
        : '$num · ${c.title!}';
  }

  /// Relative upload stamp under each chapter row.
  Widget? _stamp(int i) {
    final at = _asc[i].uploadedAt;
    if (at == null) return null;
    final parts =
        relativeParts(at, nowMs: DateTime.now().millisecondsSinceEpoch);
    return Text(
      tFmt(context, parts.key, parts.params),
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

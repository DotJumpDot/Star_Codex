import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/relative_time.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/series_repo.dart';
import '../browse/source_palette.dart';
import '../reader/reader_router.dart';
import 'chapter_sheet.dart';
import 'detail_controller.dart';

/// Chapter list for ONE selected source (the old per-source tab bar was
/// replaced by the site switcher in the action row — same data, more room
/// for the list). Search-in-chapters + sort toggle (newest-first default)
/// + per-chapter source dots stay.
class ChapterList extends ConsumerStatefulWidget {
  const ChapterList({
    super.key,
    required this.vm,
    required this.controllerKey,
    required this.sourceId,
  });

  final SeriesDetailVm vm;

  /// The screen's provider-family key (-1 when opened from browse) — NOT
  /// vm.series.id, which resolves to a different controller there.
  final DetailKey controllerKey;

  final String sourceId;

  @override
  ConsumerState<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends ConsumerState<ChapterList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final sources = ref.watch(sourcesProvider);
    int registryIndex(String id) {
      for (var i = 0; i < sources.length; i++) {
        if (sources[i].id == id) return i;
      }
      return 0;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: t(context, 'detail.search_chapters'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: t(
                  context,
                  vm.sortOldestFirst ? 'detail.sort.newest' : 'detail.sort.oldest',
                ),
                icon: Icon(
                  vm.sortOldestFirst
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                onPressed: () => ref
                    .read(detailControllerProvider(widget.controllerKey).notifier)
                    .setSort(oldestFirst: !vm.sortOldestFirst),
              ),
            ],
          ),
        ),
        Expanded(
          child: _SourceChapters(
            vm: vm,
            sourceId: widget.sourceId,
            query: _search.text,
            controllerKey: widget.controllerKey,
            registryIndex: registryIndex,
          ),
        ),
      ],
    );
  }
}

class _SourceChapters extends ConsumerWidget {
  const _SourceChapters({
    required this.vm,
    required this.sourceId,
    required this.query,
    required this.controllerKey,
    required this.registryIndex,
  });

  final SeriesDetailVm vm;
  final String sourceId;
  final String query;
  final DetailKey controllerKey;

  /// Source → index in the registry sort order (same colors as browse).
  final int Function(String) registryIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var chapters = [
      ...(vm.chaptersBySource[sourceId] ?? const <Chapter>[]),
    ];
    chapters.sort(
      (a, b) => vm.sortOldestFirst
          ? a.number.compareTo(b.number)
          : b.number.compareTo(a.number),
    );
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      bool hit(Chapter c) =>
          c.title?.toLowerCase().contains(q) == true ||
          formatChapterNumber(c.number).contains(q);
      chapters = chapters.where(hit).toList(growable: false);
    }
    if (chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            q.isEmpty
                ? t(context, 'detail.chapters_empty')
                : t(context, 'common.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (context, i) => _ChapterRow(
        vm: vm,
        chapter: chapters[i],
        sourceId: sourceId,
        controllerKey: controllerKey,
        registryIndex: registryIndex,
      ),
    );
  }
}

class _ChapterRow extends ConsumerWidget {
  const _ChapterRow({
    required this.vm,
    required this.chapter,
    required this.sourceId,
    required this.controllerKey,
    required this.registryIndex,
  });

  final SeriesDetailVm vm;
  final Chapter chapter;
  final String sourceId;
  final DetailKey controllerKey;

  /// Source → index in the registry sort order (same colors as browse).
  final int Function(String) registryIndex;

  /// Sources carrying this exact chapter number (epsilon), in link order —
  /// the colored chips of the doc 09 addendum.
  List<String> get _carrying {
    final copies = vm.chaptersByNumber[chapter.number] ?? <Chapter>[chapter];
    return [
      for (final l in vm.links)
        if (copies.any((c) => c.sourceId == l.sourceId)) l.sourceId,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = vm.progress[chapter.id];
    final completed = progress?.completed ?? false;
    final downloaded = vm.downloadedChapterIds.contains(chapter.id);
    final carrying = _carrying;
    final extra = _stripNumberPrefix(chapter.title);

    final uploadedAt = chapter.uploadedAt;
    String? dateText;
    if (uploadedAt != null) {
      final parts = relativeParts(
        uploadedAt,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      dateText = tFmt(context, parts.key, parts.params);
    }

    return ListTile(
      dense: true,
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: tFmt(context, 'detail.chapter_number', {
                'n': formatChapterNumber(chapter.number),
              }),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (extra != null)
              TextSpan(
                text: '  $extra',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: dateText == null ? null : Text(dateText),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sid in carrying)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: SourceDot(color: sourceDotColor(registryIndex(sid))),
            ),
          if (downloaded) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.download,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
          const SizedBox(width: 6),
          if (completed)
            Icon(
              Icons.check_circle,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        final settings = ref.read(settingsProvider);
        openReader(
          context,
          chapter: chapter,
          sourceId: sourceId,
          seriesDao: ref.read(seriesDaoProvider),
          modeOverride: effectiveModeOverride(
            settings.get('reader_mode_${chapter.seriesId}', 'auto'),
            settings.get('reader_mode_default', 'auto'),
          ),
        );
      },
      onLongPress: () => showChapterActions(
        context,
        ref,
        vm: vm,
        chapter: chapter,
        carryingSourceIds: carrying,
        controllerKey: controllerKey,
      ),
    );
  }

  /// Chapter titles repeat the number (`ตอนที่ 155`) — strip it so the row
  /// doesn't read "ตอนที่ 155  ตอนที่ 155".
  String? _stripNumberPrefix(String? title) {
    if (title == null) return null;
    final stripped = title.replaceFirst(
      RegExp(
        r'^\s*[-–]?\s*(?:ตอนที่|ตอน|chapter|ch\.?)\s*[:#]?\s*[\d.]+\s*[-–:]?\s*',
        caseSensitive: false,
      ),
      '',
    );
    final trimmed = stripped.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

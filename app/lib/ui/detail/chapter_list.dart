import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/relative_time.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/dao/series_dao.dart';
import '../../data/repo/series_repo.dart';
import '../browse/source_palette.dart';
import '../reader/reader_router.dart';
import 'chapter_sheet.dart';
import 'detail_controller.dart';

/// Source switcher + chapter list (Plan/09 §5–6): one tab per
/// series_sources member, per-chapter source dots (09 addendum), sort
/// toggle, search-in-chapters.
class ChapterList extends ConsumerStatefulWidget {
  const ChapterList(
      {super.key, required this.vm, required this.controllerKey});

  final SeriesDetailVm vm;

  /// The screen's provider-family key (-1 when opened from browse) — NOT
  /// vm.series.id, which resolves to a different controller there.
  final int controllerKey;

  @override
  ConsumerState<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends ConsumerState<ChapterList>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _tabs?.dispose();
    super.dispose();
  }

  TabController _controller() {
    final length = widget.vm.links.length;
    if (_tabs == null || _tabs!.length != length) {
      _tabs?.dispose();
      _tabs = TabController(length: length, vsync: this)
        ..addListener(() {
          if (mounted) setState(() {}); // rebuild TabBar selection
        });
    }
    return _tabs!;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final tabs = _controller();
    final primaryCount = vm.chaptersBySource[vm.primaryLink.sourceId]?.length ?? 0;

    return Column(
      children: [
        TabBar(
          controller: tabs,
          isScrollable: vm.links.length > 3,
          tabAlignment: vm.links.length > 3 ? TabAlignment.start : null,
          tabs: [
            for (final link in vm.links)
              Tab(
                height: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(vm.sourceNames[link.sourceId] ?? link.sourceId,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if ((vm.chaptersBySource[link.sourceId]?.length ?? 0) >
                        primaryCount)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tFmt(
                              context,
                              'detail.more_chapters',
                              {
                                'n':
                                    '${vm.chaptersBySource[link.sourceId]!.length}',
                              },
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
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
                        borderRadius: BorderRadius.circular(20)),
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
                tooltip: t(context, vm.sortOldestFirst
                    ? 'detail.sort.newest'
                    : 'detail.sort.oldest'),
                icon: Icon(vm.sortOldestFirst
                    ? Icons.arrow_downward
                    : Icons.arrow_upward),
                onPressed: () => ref
                    .read(
                        detailControllerProvider(widget.controllerKey).notifier)
                    .setSort(oldestFirst: !vm.sortOldestFirst),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              for (final link in vm.links)
                _SourceChapters(
                    vm: vm,
                    link: link,
                    query: _search.text,
                    controllerKey: widget.controllerKey),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceChapters extends ConsumerWidget {
  const _SourceChapters({
    required this.vm,
    required this.link,
    required this.query,
    required this.controllerKey,
  });

  final SeriesDetailVm vm;
  final SeriesSource link;
  final String query;
  final int controllerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var chapters = [...(vm.chaptersBySource[link.sourceId] ?? const <Chapter>[])];
    chapters.sort((a, b) => vm.sortOldestFirst
        ? a.number.compareTo(b.number)
        : b.number.compareTo(a.number));
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
          sourceId: link.sourceId,
          controllerKey: controllerKey),
    );
  }
}

class _ChapterRow extends ConsumerWidget {
  const _ChapterRow({
    required this.vm,
    required this.chapter,
    required this.sourceId,
    required this.controllerKey,
  });

  final SeriesDetailVm vm;
  final Chapter chapter;
  final String sourceId;
  final int controllerKey;

  /// Sources carrying this exact chapter number (epsilon), in tab order —
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
    final dateText = uploadedAt == null
        ? null
        : (() {
            final parts = relativeParts(uploadedAt,
                nowMs: DateTime.now().millisecondsSinceEpoch);
            return tFmt(context, parts.key, parts.params);
          })();

    return ListTile(
      dense: true,
      title: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: tFmt(context, 'detail.chapter_number',
                {'n': formatChapterNumber(chapter.number)}),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (extra != null)
            TextSpan(
                text: '  $extra',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
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
              child: SourceDot(
                color: sourceDotColor(
                    vm.links.indexWhere((l) => l.sourceId == sid)),
              ),
            ),
          if (downloaded) ...[
            const SizedBox(width: 6),
            Icon(Icons.download,
                size: 16, color: Theme.of(context).colorScheme.primary),
          ],
          const SizedBox(width: 6),
          if (completed)
            Icon(Icons.check_circle,
                size: 18, color: Theme.of(context).colorScheme.primary)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 1.5),
              ),
            ),
        ],
      ),
      onTap: () {
          final settings = ref.read(settingsProvider);
          openReader(context,
              chapter: chapter,
              sourceId: sourceId,
              seriesDao: ref.read(seriesDaoProvider),
              modeOverride: effectiveModeOverride(
                  settings.get('reader_mode_${chapter.seriesId}', 'auto'),
                  settings.get('reader_mode_default', 'auto')));
        },
      onLongPress: () => showChapterActions(context, ref,
          vm: vm,
          chapter: chapter,
          carryingSourceIds: carrying,
          controllerKey: controllerKey),
    );
  }

  /// Chapter titles repeat the number (`ตอนที่ 155`) — strip it so the row
  /// doesn't read "ตอนที่ 155  ตอนที่ 155".
  String? _stripNumberPrefix(String? title) {
    if (title == null) return null;
    final stripped = title.replaceFirst(
        RegExp(r'^\s*[-–]?\s*(?:ตอนที่|ตอน|chapter|ch\.?)\s*[:#]?\s*[\d.]+\s*[-–:]?\s*',
            caseSensitive: false),
        '');
    final trimmed = stripped.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

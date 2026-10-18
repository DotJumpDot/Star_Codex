import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/settings_provider.dart';
import '../../data/repo/browse_merge.dart' show SearchGroup;
import '../../data/repo/series_repo.dart';
import 'chapter_list.dart';
import 'detail_controller.dart';
import 'detail_dialogs.dart';
import 'detail_hero.dart';

/// Series detail (Plan/09). Opened with an id (library) or with the browse
/// listing group ([DetailScreen.fromGroup] — the row materializes on load).
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.seriesId}) : group = null;
  const DetailScreen.fromGroup(this.group, {super.key}) : seriesId = null;

  final int? seriesId;
  final SearchGroup? group;

  /// Provider-family key; groups key by identity (row materializes).
  DetailKey get _key =>
      seriesId != null ? DetailKey.id(seriesId!) : DetailKey.forGroup(group!);

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(detailControllerProvider(widget._key).notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(detailControllerProvider(widget._key));
    final controller = ref.read(detailControllerProvider(widget._key).notifier);
    final vm = async.valueOrNull;

    Widget body;
    if (vm == null && async.hasError) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(context, 'common.error.title')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(t(context, 'common.retry')),
              onPressed: controller.retry,
            ),
          ],
        ),
      );
    } else if (vm == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      // Children must talk to THIS screen's controller (DetailKey =
      // -1-keyed when opened from a browse card — vm.series.id would
      // resolve to a different, empty controller and every action button
      // would dead-end).
      body = _DetailBody(vm: vm, controllerKey: widget._key);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          vm?.series.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [_Menu(vm: vm, controllerKey: widget._key)],
      ),
      body: body,
    );
  }
}

/// ⋯ menu (Plan/09 §2): หาในเว็บอื่น, เปิดในเว็บ, คัดลอกลิงก์. ผสาน/แยก
/// (manual merge) hides behind settings `hide_merge_split` (default on).
class _Menu extends ConsumerWidget {
  const _Menu({required this.vm, required this.controllerKey});

  final SeriesDetailVm? vm;
  final DetailKey controllerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = vm;
    if (current == null) return const SizedBox.shrink();
    final hideMerge =
        ref.watch(settingsProvider).getBool('hide_merge_split', true);
    final link = current.links.first;
    Future<void> onSelected(String action) async {
      final container = ProviderScope.containerOf(context);
      switch (action) {
        case 'probe':
          final added = await container
              .read(detailControllerProvider(controllerKey).notifier)
              .probeOthers();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t(context, added ? 'detail.probe_found' : 'detail.probe_done'),
              ),
            ),
          );
        case 'open':
          launchUrl(
            Uri.parse(link.sourceUrl),
            mode: LaunchMode.externalApplication,
          );
        case 'copy':
          await Clipboard.setData(ClipboardData(text: link.sourceUrl));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'detail.link_copied'))),
          );
        case 'merge':
          final id = current.series.id!;
          await showMergeDialog(context, container, id, current.series.title);
        case 'split':
          await showSplitDialog(context, container, current.series.id!);
      }
    }

    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'probe',
          child: Text(t(context, 'detail.menu.find_other')),
        ),
        PopupMenuItem(
          value: 'open',
          child: Text(t(context, 'detail.menu.open_site')),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Text(t(context, 'detail.menu.copy_link')),
        ),
        if (!hideMerge) ...[
          PopupMenuItem(
            value: 'merge',
            child: Text(t(context, 'detail.menu.merge')),
          ),
          if (current.links.length > 1)
            PopupMenuItem(
              value: 'split',
              child: Text(t(context, 'detail.menu.split')),
            ),
        ],
      ],
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.vm, required this.controllerKey});

  final SeriesDetailVm vm;
  final DetailKey controllerKey;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _altExpanded = false;
  bool _introExpanded = false;
  String? _selectedSourceId;
  final _chapterSearch = TextEditingController();

  @override
  void dispose() {
    _chapterSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final series = vm.series;
    final selectedSource = _selectedSourceId ?? vm.primaryLink.sourceId;
    final hasIntro =
        series.description != null && series.description!.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailCover(vm: vm),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (series.originalTitle != null)
                      Text(
                        series.originalTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    if (vm.altTitles.isNotEmpty)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _altExpanded = !_altExpanded),
                        child: Text(
                          '${t(context, 'detail.alt_titles')}: '
                          '${vm.altTitles.join(', ')}',
                          maxLines: _altExpanded ? null : 1,
                          overflow:
                              _altExpanded ? null : TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    HeroChips(vm: vm),
                    // Compact intro toggle rides in the leftover hero
                    // space under the chips — truncated so the hero never
                    // outgrows the cover; tapping slides the full text
                    // open below the action row. Always present: with no
                    // description the expansion still carries the FULL
                    // untruncated title (user QA 2026-10-18).
                    IntroductionToggle(
                      snippet: hasIntro
                          ? series.description!
                          : (series.originalTitle ?? series.title),
                      expanded: _introExpanded,
                      onToggle: () =>
                          setState(() => _introExpanded = !_introExpanded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DetailActionRow(
          vm: vm,
          controllerKey: widget.controllerKey,
          selectedSourceId: selectedSource,
          onSourceSelected: (id) => setState(() => _selectedSourceId = id),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _introExpanded
              ? IntroductionExpansion(vm: vm)
              : const SizedBox(width: double.infinity, height: 0),
        ),
        // Chapter search + sort moved onto the row the intro used to
        // occupy — one fewer stacked full-width row.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chapterSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: t(context, 'detail.search_chapters'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    suffixIcon: _chapterSearch.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _chapterSearch.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: t(
                  context,
                  vm.sortOldestFirst
                      ? 'detail.sort.newest'
                      : 'detail.sort.oldest',
                ),
                icon: Icon(
                  vm.sortOldestFirst
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                onPressed: () => ref
                    .read(detailControllerProvider(widget.controllerKey)
                        .notifier)
                    .setSort(oldestFirst: !vm.sortOldestFirst),
              ),
            ],
          ),
        ),
        Expanded(
          child: ChapterList(
            vm: vm,
            controllerKey: widget.controllerKey,
            sourceId: selectedSource,
            query: _chapterSearch.text,
          ),
        ),
      ],
    );
  }
}

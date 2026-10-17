import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/dao/blobs_dao.dart';
import '../../data/repo/browse_merge.dart' show SearchGroup;
import '../../data/repo/series_repo.dart';
import '../browse/cover_thumb.dart';
import '../browse/browse_controller.dart';
import '../browse/source_palette.dart';
import '../reader/reader_router.dart';
import 'chapter_list.dart';
import 'detail_controller.dart';

/// Series detail (Plan/09). Opened with an id (library) or with the browse
/// listing group ([DetailScreen.fromGroup] — the row materializes on load).
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.seriesId}) : group = null;
  const DetailScreen.fromGroup(this.group, {super.key}) : seriesId = null;

  final int? seriesId;
  final SearchGroup? group;

  /// Provider-family key; -1 = "materialize from [group]".
  int get _key => seriesId ?? -1;

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
    final controller =
        ref.read(detailControllerProvider(widget._key).notifier);
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
      // Children must talk to THIS screen's controller (family key = -1
      // when opened from a browse card — vm.series.id would resolve to a
      // different, empty controller and every action button would
      // dead-end).
      body = _DetailBody(vm: vm, controllerKey: widget._key);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(vm?.series.title ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [_Menu(vm: vm, seriesId: widget._key)],
      ),
      body: body,
    );
  }
}

/// ⋯ menu (Plan/09 §2): หาในเว็บอื่น, เปิดในเว็บ, คัดลอกลิงก์ (share needs
/// a dependency outside the allowed table — clipboard is the substitute,
/// noted in PLAN_NOTES). ผสานเรื่อง arrives with Phase 9's manual merge.
class _Menu extends StatelessWidget {
  const _Menu({required this.vm, required this.seriesId});

  final SeriesDetailVm? vm;
  final int seriesId;

  @override
  Widget build(BuildContext context) {
    final current = vm;
    if (current == null) return const SizedBox.shrink();
    final link = current.links.first;
    Future<void> onSelected(String action) async {
      final container = ProviderScope.containerOf(context);
      switch (action) {
        case 'probe':
          final added = await container
              .read(detailControllerProvider(seriesId).notifier)
              .probeOthers();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                t(context, added ? 'detail.probe_found' : 'detail.probe_done')),
          ));
        case 'open':
          launchUrl(Uri.parse(link.sourceUrl),
              mode: LaunchMode.externalApplication);
        case 'copy':
          await Clipboard.setData(ClipboardData(text: link.sourceUrl));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'detail.link_copied'))));
      }
    }

    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
            value: 'probe',
            child: Text(t(context, 'detail.menu.find_other'))),
        PopupMenuItem(
            value: 'open',
            child: Text(t(context, 'detail.menu.open_site'))),
        PopupMenuItem(
            value: 'copy',
            child: Text(t(context, 'detail.menu.copy_link'))),
      ],
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.vm, required this.controllerKey});

  final SeriesDetailVm vm;
  final int controllerKey;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _altExpanded = false;
  bool _descExpanded = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final series = vm.series;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(vm: vm),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(series.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    if (series.originalTitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(series.originalTitle!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
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
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (series.type != null)
                          _chip(t(context, 'browse.type.${series.type}')),
                        if (series.origin != null)
                          _chip(t(context, 'detail.origin.${series.origin}')),
                        if (series.status != null)
                          _chip(t(context, 'browse.status.${series.status}')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Source badges row (Plan/09 §1 header).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var i = 0; i < vm.links.length; i++)
                _chip(
                    vm.sourceNames[vm.links[i].sourceId] ??
                        vm.links[i].sourceId,
                    dotIndex: i),
            ],
          ),
        ),
        _ActionRow(vm: vm, controllerKey: widget.controllerKey),
        if (series.description != null && series.description!.isNotEmpty)
          _Description(
              vm: vm,
              expanded: _descExpanded,
              onToggle: () => setState(() => _descExpanded = !_descExpanded)),
        if (vm.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _TagRow(tags: vm.tags),
          ),
        Expanded(
            child: ChapterList(vm: vm, controllerKey: widget.controllerKey)),
      ],
    );
  }

  Widget _chip(String label, {int? dotIndex}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotIndex != null) ...[
              SourceDot(color: sourceDotColor(dotIndex)),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Cover: `series.cover_hash` blob file first; evicted → fetch the first
/// link's cover URL through the pipeline; nothing → placeholder. The
/// blob-row future is created once per cover hash — recreating it every
/// build re-reads the DB on each mark-read/sort setState.
class _Cover extends ConsumerStatefulWidget {
  const _Cover({required this.vm});

  final SeriesDetailVm vm;

  @override
  ConsumerState<_Cover> createState() => _CoverState();
}

class _CoverState extends ConsumerState<_Cover> {
  Future<BlobRow?>? _future;

  @override
  Widget build(BuildContext context) {
    final hash = widget.vm.series.coverHash;
    if (hash != null) {
      final blobs = ref.watch(blobStoreProvider);
      final dir = ref.watch(libraryDirProvider);
      _future ??= blobs.blobRow(hash);
      return FutureBuilder<BlobRow?>(
        future: _future,
        builder: (context, snap) {
          final path = snap.data?.path;
          if (path == null) return _fallback(context, ref);
          return Image.file(
            File('${dir.path}/$path'),
            width: 120,
            height: 170,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(context, ref),
          );
        },
      );
    }
    return _fallback(context, ref);
  }

  Widget _fallback(BuildContext context, WidgetRef ref) {
    if (widget.vm.coverUrl != null && widget.vm.coverReferer != null) {
      return CoverThumb(
        url: widget.vm.coverUrl!,
        referer: widget.vm.coverReferer!,
        width: 120,
        height: 170,
      );
    }
    return Container(
      width: 120,
      height: 170,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined,
          size: 32, color: Theme.of(context).colorScheme.outline),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.vm, required this.controllerKey});

  final SeriesDetailVm vm;
  final int controllerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.read(detailControllerProvider(controllerKey).notifier);
    final target = continueTarget(vm);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow, size: 20),
              label: Text(t(context, 'detail.continue_reading')),
              onPressed: target == null
                  ? null
                  : () => openReader(context,
                      chapter: target.chapter,
                      sourceId: target.sourceId,
                      seriesDao: ref.read(seriesDaoProvider),
                      modeOverride: ref
                          .read(settingsProvider)
                          .get('reader_mode_${target.chapter.seriesId}', 'auto')),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: t(
                context,
                vm.inLibrary ? 'detail.remove_library' : 'detail.add_library'),
            icon: Icon(vm.inLibrary ? Icons.delete_outline : Icons.add),
            onPressed: controller.toggleLibrary,
          ),
          IconButton(
            tooltip: t(context, 'detail.download'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () {
              // Real download sheet is Phase 10 (doc 13).
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t(context, 'coming.soon'))));
            },
          ),
        ],
      ),
    );
  }
}

class _Description extends StatelessWidget {
  const _Description(
      {required this.vm, required this.expanded, required this.onToggle});

  final SeriesDetailVm vm;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final captionSource = vm.descriptionSourceId != null
        ? vm.sourceNames[vm.descriptionSourceId]
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Text(
              vm.series.description!,
              maxLines: expanded ? null : 4,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Row(
            children: [
              if (captionSource != null)
                Text(
                  tFmt(context, 'detail.description_from',
                      {'source': captionSource}),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              const Spacer(),
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    t(context,
                        expanded ? 'detail.read_less' : 'detail.read_more'),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tag chips (Plan/09 §4): tap → browse pre-filtered by tag (session-only
/// filter; listings enforce it once detail data flows — same honest policy
/// as the browse sheet).
class _TagRow extends ConsumerWidget {
  const _TagRow({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          ActionChip(
            label: Text(tag, style: Theme.of(context).textTheme.labelSmall),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              ref.read(browseControllerProvider.notifier).applyTagFilter(tag);
              ref.read(tabIndexProvider.notifier).state = 0;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
      ],
    );
  }
}

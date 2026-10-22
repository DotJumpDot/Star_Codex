import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/blobs_dao.dart';
import '../../data/repo/series_repo.dart';
import '../browse/cover_thumb.dart';
import '../browse/source_palette.dart';
import '../reader/reader_router.dart';
import 'detail_controller.dart';
import 'download_sheet.dart';

/// Compact hero widgets for the detail screen (split from
/// detail_screen.dart): cover, chip row, action row (continue / heart /
/// download / site switch), collapsible introduction.

/// Cover: `series.cover_hash` blob file first; evicted → fetch the first
/// link's cover URL through the pipeline; nothing → placeholder. The
/// blob-row future is created once per cover hash — recreating it every
/// build re-reads the DB on each mark-read/sort setState.
class DetailCover extends ConsumerStatefulWidget {
  const DetailCover({super.key, required this.vm});

  final SeriesDetailVm vm;

  @override
  ConsumerState<DetailCover> createState() => _DetailCoverState();
}

class _DetailCoverState extends ConsumerState<DetailCover> {
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
            width: 96,
            height: 136,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(context, ref),
          );
        },
      );
    }
    return _fallback(context, ref);
  }

  Widget _fallback(BuildContext context, WidgetRef ref) {
    final vm = widget.vm;
    // Merged series: when this member's cover is dead (slow-manga AVIF
    // uploads / 404 thumbnails), a sibling site's cover is the next best
    // thing — CoverThumb walks the list.
    final sources = ref.read(sourcesProvider);
    String refererFor(String sourceId) =>
        sources.where((s) => s.id == sourceId).firstOrNull?.referer ?? '';
    final fallbacks = <(String, String)>[
      for (final l in vm.links)
        if (l.coverUrl != null && l.coverUrl != vm.coverUrl)
          (l.coverUrl!, refererFor(l.sourceId)),
    ];
    if (vm.coverUrl != null && vm.coverReferer != null) {
      return CoverThumb(
        url: vm.coverUrl!,
        referer: vm.coverReferer!,
        fallbacks: fallbacks,
        width: 96,
        height: 136,
      );
    }
    if (fallbacks.isNotEmpty) {
      return CoverThumb(
        url: fallbacks.first.$1,
        referer: fallbacks.first.$2,
        fallbacks: fallbacks.skip(1).toList(),
        width: 96,
        height: 136,
      );
    }
    return Container(
      width: 96,
      height: 136,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// Type / status / per-site chips in ONE wrap (status carries its own
/// color so it reads differently from the neutral type chip; site chips
/// reuse the browse source palette — same color per site everywhere).
/// Tag chips live ONLY inside the expanded introduction now — in the hero
/// they crowded the right column and unbalanced it against the cover
/// (user QA 2026-10-18).
class HeroChips extends ConsumerWidget {
  const HeroChips({super.key, required this.vm});

  final SeriesDetailVm vm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sources = ref.watch(sourcesProvider);
    int registryIndex(String id) {
      for (var i = 0; i < sources.length; i++) {
        if (sources[i].id == id) return i;
      }
      return 0;
    }

    Widget neutral(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        );

    Widget tinted(String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        );

    Widget site(String sourceId) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SourceDot(
                  color: sourceDotColor(registryIndex(sourceId)), size: 8),
              const SizedBox(width: 5),
              Text(
                vm.sourceNames[sourceId] ?? sourceId,
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (vm.series.type != null)
          neutral(t(context, 'browse.type.${vm.series.type}')),
        if (vm.series.status != null)
          tinted(
            t(context, 'browse.status.${vm.series.status}'),
            vm.series.status == 'ongoing'
                ? const Color(0xFF43A047)
                : Colors.blueGrey,
          ),
        for (final link in vm.links) site(link.sourceId),
      ],
    );
  }
}

/// Compact action row: Continue (small), heart (library), download, and
/// the site switcher that replaces the old chapter-list tab bar.
class DetailActionRow extends ConsumerWidget {
  const DetailActionRow({
    super.key,
    required this.vm,
    required this.controllerKey,
    required this.selectedSourceId,
    required this.onSourceSelected,
  });

  final SeriesDetailVm vm;
  final DetailKey controllerKey;
  final String selectedSourceId;
  final ValueChanged<String> onSourceSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.read(detailControllerProvider(controllerKey).notifier);
    final target = continueTarget(vm);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(
                target == null
                    ? t(context, 'detail.continue_reading')
                    : tFmt(context, 'detail.continue_with', {
                        'n': formatChapterNumber(target.chapter.number),
                      }),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: target == null
                  ? null
                  : () async {
                      final settings = ref.read(settingsProvider);
                      await openReader(
                        context,
                        chapter: target.chapter,
                        sourceId: target.sourceId,
                        seriesDao: ref.read(seriesDaoProvider),
                        modeOverride: effectiveModeOverride(
                          settings.get(
                            'reader_mode_${target.chapter.seriesId}',
                            'auto',
                          ),
                          settings.get('reader_mode_default', 'auto'),
                        ),
                      );
                      // Show the chapter's new state on return.
                      if (!context.mounted) return;
                      await ref
                          .read(detailControllerProvider(controllerKey).notifier)
                          .refreshProgress();
                    },
            ),
          ),
          IconButton(
            tooltip: t(
              context,
              vm.inLibrary ? 'detail.remove_library' : 'detail.add_library',
            ),
            icon: Icon(
              vm.inLibrary ? Icons.favorite : Icons.favorite_border,
              color:
                  vm.inLibrary ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: controller.toggleLibrary,
          ),
          IconButton(
            tooltip: t(context, 'detail.download'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => showDownloadSheet(context, ref, vm, controllerKey),
          ),
          SiteSwitchButton(
            vm: vm,
            selectedSourceId: selectedSourceId,
            onSelected: onSourceSelected,
          ),
        ],
      ),
    );
  }
}

/// Site switcher (replaces the chapter-list tab bar): current site name +
/// colored dot; opens a menu with each site and its chapter count.
class SiteSwitchButton extends ConsumerWidget {
  const SiteSwitchButton({
    super.key,
    required this.vm,
    required this.selectedSourceId,
    required this.onSelected,
  });

  final SeriesDetailVm vm;
  final String selectedSourceId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sources = ref.watch(sourcesProvider);
    int registryIndex(String id) {
      for (var i = 0; i < sources.length; i++) {
        if (sources[i].id == id) return i;
      }
      return 0;
    }

    final name = vm.sourceNames[selectedSourceId] ?? selectedSourceId;
    final count = vm.chaptersBySource[selectedSourceId]?.length ?? 0;
    return PopupMenuButton<String>(
      tooltip: t(context, 'detail.site_switch'),
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final link in vm.links)
          PopupMenuItem(
            value: link.sourceId,
            child: Row(
              children: [
                SourceDot(
                    color: sourceDotColor(registryIndex(link.sourceId))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vm.sourceNames[link.sourceId] ?? link.sourceId,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${vm.chaptersBySource[link.sourceId]?.length ?? 0}',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SourceDot(
                color: sourceDotColor(registryIndex(selectedSourceId))),
            const SizedBox(width: 6),
            Text(name, style: theme.textTheme.labelMedium),
            const SizedBox(width: 4),
            Text(
              '· $count',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Compact เรื่องย่อ toggle INSIDE the hero (under the chips): label row +
/// a 2-line truncated snippet so the hero never grows past the cover.
/// Tapping slides the full introduction open below the action row.
class IntroductionToggle extends StatelessWidget {
  const IntroductionToggle({
    super.key,
    required this.snippet,
    required this.expanded,
    required this.onToggle,
  });

  final String snippet;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              Text(
                t(context, 'detail.introduction'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          // Truncated preview only while collapsed — the expansion shows
          // the full text, so the snippet never duplicates it.
          if (!expanded)
            Text(
              snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
        ],
      ),
    );
  }
}

/// Slide-down panel opened by the hero [IntroductionToggle], rendered
/// under the action row. First line is ALWAYS the full untruncated title
/// (the hero/app-bar copies ellipsize; this is where the whole name is
/// readable — user QA 2026-10-18), then the description when present,
/// every tag, and the description-source caption.
class IntroductionExpansion extends StatelessWidget {
  const IntroductionExpansion({super.key, required this.vm});

  final SeriesDetailVm vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = vm.series;
    final captionSource = vm.descriptionSourceId != null
        ? vm.sourceNames[vm.descriptionSourceId]
        : null;
    final description = series.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            series.originalTitle ?? series.title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (vm.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in vm.tags)
                  Chip(
                    label: Text(tag, style: theme.textTheme.labelSmall),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (captionSource != null)
            Text(
              tFmt(context, 'detail.description_from', {'source': captionSource}),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

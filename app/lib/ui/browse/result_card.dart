import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repo/browse_repo.dart';
import '../../data/sources/source_api.dart';
import 'cover_thumb.dart';
import 'source_palette.dart';

/// One merged result card: bigger cover on the left with the site count
/// and type chips layered over it, title + meta (chapters · last update)
/// and per-site colored chips on the right, optional similar-group strip.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.group,
    required this.allGroups,
    required this.sources,
    required this.onTap,
    required this.onLongPress,
  });

  final SearchGroup group;

  /// Full list (unfiltered) — [SearchGroup.similarTo] indexes into it.
  final List<SearchGroup> allGroups;

  /// Source registry in sort order — badge order + dot colors.
  final List<Source> sources;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  String? _typeLabel(BuildContext context, String? type) => switch (type) {
        'manga' => t(context, 'browse.type_short.manga'),
        'manhwa' => t(context, 'browse.type_short.manhwa'),
        'manhua' => t(context, 'browse.type_short.manhua'),
        'novel' => t(context, 'browse.type_short.novel'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = group.primary;
    final type = group.type ?? group.dbType;

    String? updated;
    final lastMs = group.dbLastUpdatedMs;
    if (lastMs != null) {
      final parts =
          relativeParts(lastMs, nowMs: DateTime.now().millisecondsSinceEpoch);
      updated = tFmt(context, parts.key, parts.params);
    }

    final meta = <String>[
      if (group.chapterCount != null)
        '${group.chapterCount} ${t(context, 'browse.chapters_suffix')}',
      ?updated,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(
                    group: group,
                    primary: primary,
                    typeLabel: _typeLabel(context, type),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            meta,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                        if (group.dbStatus != null) ...[
                          const SizedBox(height: 6),
                          _StatusChip(status: group.dbStatus!),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final m in group.members)
                              _SourceBadge(
                                label: _sourceName(m.sourceId),
                                color:
                                    sourceDotColor(_sourceIndex(m.sourceId)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (group.similarTo.isNotEmpty)
                _SimilarStrip(group: group, allGroups: allGroups),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceName(String id) =>
      sources.where((s) => s.id == id).firstOrNull?.name ?? id;

  int _sourceIndex(String id) {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id == id) return i;
    }
    return 0;
  }
}

/// Cover column: image with layered site-count + type chips.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.group,
    required this.primary,
    required this.typeLabel,
  });

  final SearchGroup group;
  final BrowseCandidate primary;
  final String? typeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cover source: primary first, then any member with a cover —
    // slow-manga tiles can point at AVIF uploads or 404 thumbnails that
    // can never render, so a sibling site's JPEG must win over a dead
    // primary (CoverThumb walks the fallback chain).
    final coverMembers = <BrowseCandidate>[
      primary,
      ...group.members.where((m) => m != primary),
    ].where((m) => (m.coverUrl ?? '').isNotEmpty).toList();
    return SizedBox(
      width: 92,
      height: 128,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverMembers.isNotEmpty)
            CoverThumb(
              url: coverMembers.first.coverUrl!,
              referer: coverMembers.first.referer,
              fallbacks: [
                for (final m in coverMembers.skip(1)) (m.coverUrl!, m.referer),
              ],
              width: 92,
              height: 128,
            )
          else
            Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Icon(Icons.image_outlined,
                  size: 24, color: theme.colorScheme.outline),
            ),
          Positioned(
            top: 4,
            left: 4,
            child: _OverlayChip(
              icon: Icons.public,
              label: '${group.members.length}',
            ),
          ),
          if (typeLabel != null)
            Positioned(
              bottom: 4,
              left: 4,
              child: _OverlayChip(label: typeLabel!),
            ),
        ],
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ongoing = status == 'ongoing';
    final color = ongoing ? const Color(0xFF43A047) : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        t(context, 'browse.status.$status'),
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// "คล้ายกับเรื่องอื่น?" — expands the similar-band groups inline (Plan/08).
/// Never auto-merged (Plan/07 §2).
class _SimilarStrip extends StatefulWidget {
  const _SimilarStrip({required this.group, required this.allGroups});

  final SearchGroup group;
  final List<SearchGroup> allGroups;

  @override
  State<_SimilarStrip> createState() => _SimilarStripState();
}

class _SimilarStripState extends State<_SimilarStrip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16),
          label: Text(t(context, 'browse.similar'),
              style: theme.textTheme.labelSmall),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
        ),
        if (_open)
          for (final index in widget.group.similarTo)
            if (index < widget.allGroups.length)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  '· ${widget.allGroups[index].displayTitle} '
                  '(${widget.allGroups[index].members.length})',
                  style: theme.textTheme.bodySmall,
                ),
              ),
      ],
    );
  }
}

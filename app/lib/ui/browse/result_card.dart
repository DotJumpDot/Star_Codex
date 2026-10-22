import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repo/browse_repo.dart';
import '../../data/sources/source_api.dart';
import 'age_colors.dart';
import 'cover_thumb.dart';
import 'source_palette.dart';

/// One merged result card: bigger cover on the left (no overlay chips —
/// the globe site-count and cover-corner type chips read as noise, user QA
/// 2026-10-18), title + meta (chapters · aged-color last update), and on
/// the right a chip row that ALWAYS leads with the colored type chip
/// (มังงะ/มังฮวา/นิยาย each with its own color) followed by the per-site
/// badges. Optional similar-group strip below.
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
    final typeLabel = _typeLabel(context, type);

    String? updated;
    String updatedKey = '';
    final lastMs = group.lastUpdatedMs;
    if (lastMs != null) {
      final parts = relativeParts(
        lastMs,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      updatedKey = parts.key;
      updated = tFmt(context, parts.key, parts.params);
    }

    // Intro text for the space under the chip row — only materialized
    // series have one (listing tiles carry no description).
    final desc = group.dbDescription?.trim();
    final description = (desc == null || desc.isEmpty) ? null : desc;

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
                  _Cover(group: group, primary: primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (group.chapterCount != null || updated != null) ...[
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              children: [
                                if (group.chapterCount != null)
                                  TextSpan(
                                    text:
                                        '${group.chapterCount} ${t(context, 'browse.chapters_suffix')}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                if (group.chapterCount != null &&
                                    updated != null)
                                  const TextSpan(text: ' · '),
                                if (updated != null)
                                  TextSpan(
                                    text: updated,
                                    style: TextStyle(
                                      color: relativeAgeColor(
                                        theme.colorScheme,
                                        updatedKey,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // Type chip always leads the row (user QA
                            // 2026-10-18) — per-type color, one glance.
                            if (typeLabel != null)
                              TypeChip(label: typeLabel, type: type),
                            // One badge per SITE even when a source
                            // returned the series at two URLs (a merged
                            // card showed "Bully Manga" twice).
                            for (final badge in {
                              for (final m in group.members)
                                m.sourceId: (
                                  _sourceName(m.sourceId),
                                  sourceDotColor(_sourceIndex(m.sourceId)),
                                ),
                            }.entries)
                              _SourceBadge(
                                label: badge.value.$1,
                                color: badge.value.$2,
                              ),
                          ],
                        ),
                        // Series intro fills the space under the chip row
                        // (user request 2026-10-22: short-title cards
                        // left a dead gap next to the cover) — truncated
                        // to the lines that fit.
                        if (description != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
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

/// Cover column: the merged-group image with member fallbacks — no
/// overlay chips (site count + corner type chip removed, user QA
/// 2026-10-18: the type chip moved into the right-side chip row).
class _Cover extends StatelessWidget {
  const _Cover({required this.group, required this.primary});

  final SearchGroup group;
  final BrowseCandidate primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cover source: primary first, then any member with a cover —
    // slow-manga tiles can point at AVIF uploads or 404 thumbnails that
    // can never render, so a sibling site's JPEG must win over a dead
    // primary (CoverThumb walks the fallback chain). Last resort: the
    // materialized series' DB cover (background cross-probe may have
    // linked a site whose listing never appeared in this feed).
    final coverMembers = <BrowseCandidate>[
      primary,
      ...group.members.where((m) => m != primary),
    ].where((m) => (m.coverUrl ?? '').isNotEmpty).toList();
    final Widget cover;
    if (coverMembers.isNotEmpty) {
      cover = CoverThumb(
        url: coverMembers.first.coverUrl!,
        referer: coverMembers.first.referer,
        fallbacks: [
          for (final m in coverMembers.skip(1)) (m.coverUrl!, m.referer),
        ],
        width: 92,
        height: 128,
      );
    } else if ((group.dbCoverUrl ?? '').isNotEmpty) {
      cover = CoverThumb(
        url: group.dbCoverUrl!,
        referer: group.dbCoverReferer ?? '',
        width: 92,
        height: 128,
      );
    } else {
      cover = Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_outlined,
          size: 24,
          color: theme.colorScheme.outline,
        ),
      );
    }
    return SizedBox(width: 92, height: 128, child: cover);
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
          label: Text(
            t(context, 'browse.similar'),
            style: theme.textTheme.labelSmall,
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
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

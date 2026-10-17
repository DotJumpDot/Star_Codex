import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../data/repo/browse_repo.dart';
import '../../data/sources/source_api.dart';
import 'cover_thumb.dart';
import 'source_palette.dart';

/// One merged result card (Plan/08 §Result card): cover from the primary
/// source, Thai-preferred display title, type · chapters meta line, one
/// colored badge per member source, optional similar-group expansion.
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
        'manga' => t(context, 'browse.type.manga'),
        'manhwa' => t(context, 'browse.type.manhwa'),
        'manhua' => t(context, 'browse.type.manhua'),
        'novel' => t(context, 'browse.type.novel'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = group.primary;

    final meta = <String>[
      ?_typeLabel(context, group.type),
      if (group.chapterCount != null)
        '${group.chapterCount} ${t(context, 'browse.chapters_suffix')}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  if (primary.coverUrl != null)
                    CoverThumb(
                      url: primary.coverUrl!,
                      referer: primary.referer,
                    )
                  else
                    Container(
                      width: 64,
                      height: 92,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.image_outlined,
                          size: 20, color: theme.colorScheme.outline),
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
                          style: theme.textTheme.titleMedium,
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(meta,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline)),
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
                                      sourceDotColor(_sourceIndex(m.sourceId))),
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

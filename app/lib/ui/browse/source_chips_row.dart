import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../data/sources/source_api.dart';
import 'source_palette.dart';

/// Source filter row (Plan/08 §2): "ทั้งหมด" + one chip per enabled source
/// with a colored dot. Toggle re-runs the current search/latest limited to
/// that site; long-press opens that site's genre browser. Red dot = that
/// source errored in the last fetch.
class SourceChipsRow extends StatelessWidget {
  const SourceChipsRow({
    super.key,
    required this.sources,
    required this.selectedIds,
    required this.failedIds,
    required this.onToggle,
    required this.onAll,
    required this.onLongPress,
  });

  final List<Source> sources;
  final Set<String> selectedIds;
  final Set<String> failedIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onAll;
  final void Function(Source source) onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(t(context, 'browse.sources_all')),
              selected: selectedIds.isEmpty,
              onSelected: (_) => onAll(),
            ),
          ),
          for (var i = 0; i < sources.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              // ChoiceChip has no long-press — wrap for the genre picker.
              child: GestureDetector(
                onLongPress: () => onLongPress(sources[i]),
                child: ChoiceChip(
                  selected: selectedIds.contains(sources[i].id),
                  onSelected: (_) => onToggle(sources[i].id),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: sourceDotColor(i),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(sources[i].name),
                      if (failedIds.contains(sources[i].id)) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.error,
                            size: 13, color: Colors.redAccent),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

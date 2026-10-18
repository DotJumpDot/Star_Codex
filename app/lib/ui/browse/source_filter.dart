import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../data/sources/source_api.dart';
import 'genre_browser.dart';
import 'source_palette.dart';

/// Per-site filter (Plan/08 §2) — a compact app-bar button opening a
/// bottom sheet of wrapped toggle chips, replacing the old horizontal
/// chip row that had to be scrolled and hunting-tapped. Empty selection
/// means every site. Long-press a site for its genre browser.
class SourceFilterButton extends StatelessWidget {
  const SourceFilterButton({
    super.key,
    required this.sources,
    required this.selectedIds,
    required this.failedIds,
    required this.onToggle,
    required this.onAll,
    required this.onGenre,
  });

  final List<Source> sources;
  final Set<String> selectedIds;
  final Set<String> failedIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onAll;

  /// Long-press a site chip → its genre browser; a picked term routes back
  /// to the browse controller through here.
  final void Function(Source source, String term) onGenre;

  @override
  Widget build(BuildContext context) {
    final filtered = selectedIds.isNotEmpty;
    return Badge(
      isLabelVisible: filtered,
      label: Text('${selectedIds.length}'),
      child: IconButton(
        tooltip: t(context, 'browse.sources'),
        icon: Icon(filtered ? Icons.language : Icons.language_outlined),
        onPressed: () => _openSheet(context),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t(sheetContext, 'browse.sources'),
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                t(sheetContext, 'browse.sources_hint'),
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.outline),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(t(sheetContext, 'browse.sources_all')),
                    selected: selectedIds.isEmpty,
                    onSelected: (_) {
                      Navigator.pop(sheetContext);
                      onAll();
                    },
                  ),
                  for (var i = 0; i < sources.length; i++)
                    _SiteChip(
                      source: sources[i],
                      color: sourceDotColor(i),
                      selected: selectedIds.contains(sources[i].id),
                      failed: failedIds.contains(sources[i].id),
                      onToggle: () {
                        Navigator.pop(sheetContext);
                        onToggle(sources[i].id);
                      },
                      onGenre: onGenre,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteChip extends StatelessWidget {
  const _SiteChip({
    required this.source,
    required this.color,
    required this.selected,
    required this.failed,
    required this.onToggle,
    required this.onGenre,
  });

  final Source source;
  final Color color;
  final bool selected;
  final bool failed;
  final VoidCallback onToggle;
  final void Function(Source source, String term) onGenre;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () async {
        final term = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => GenreBrowserScreen(source: source)),
        );
        if (term != null) {
          if (context.mounted) Navigator.of(context).pop(); // close the sheet
          onGenre(source, term);
        }
      },
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onToggle(),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SourceDot(color: color, size: 8),
            const SizedBox(width: 6),
            Text(source.name),
            if (failed) ...[
              const SizedBox(width: 4),
              const Icon(Icons.error, size: 13, color: Colors.redAccent),
            ],
          ],
        ),
      ),
    );
  }
}

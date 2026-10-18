import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../data/sources/source_api.dart';
import 'genre_browser.dart';
import 'source_palette.dart';

/// Per-site filter (Plan/08 §2) — a compact app-bar button opening a
/// bottom sheet of wrapped toggle chips, replacing the old horizontal
/// chip row that had to be scrolled and hunting-tapped. Empty selection
/// means every site. Long-press a site for its genre browser. Chips
/// toggle live — the sheet only closes on the Done button or an outside
/// tap (user QA 2026-10-18: it snapping shut on every chip made
/// multi-site selection a tap-war).
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
      builder: (sheetContext) => _SourceSheet(
        sources: sources,
        initialSelected: selectedIds,
        failedIds: failedIds,
        onToggle: onToggle,
        onAll: onAll,
        onGenre: onGenre,
      ),
    );
  }
}

/// Stateful sheet: selection lives here while open and mirrors every
/// change out through the callbacks immediately (the feed refetches per
/// toggle behind the sheet), so Done/outside-tap is purely dismissal.
class _SourceSheet extends StatefulWidget {
  const _SourceSheet({
    required this.sources,
    required this.initialSelected,
    required this.failedIds,
    required this.onToggle,
    required this.onAll,
    required this.onGenre,
  });

  final List<Source> sources;
  final Set<String> initialSelected;
  final Set<String> failedIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onAll;
  final void Function(Source source, String term) onGenre;

  @override
  State<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<_SourceSheet> {
  late final Set<String> _selected = {...widget.initialSelected};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t(context, 'browse.sources'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t(context, 'common.done')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t(context, 'browse.sources_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t(context, 'browse.sources_all')),
                  selected: _selected.isEmpty,
                  onSelected: (_) {
                    setState(() => _selected.clear());
                    widget.onAll();
                  },
                ),
                for (var i = 0; i < widget.sources.length; i++)
                  _SiteChip(
                    source: widget.sources[i],
                    color: sourceDotColor(i),
                    selected: _selected.contains(widget.sources[i].id),
                    failed: widget.failedIds.contains(widget.sources[i].id),
                    onToggle: () => setState(() {
                      final id = widget.sources[i].id;
                      if (!_selected.remove(id)) {
                        _selected.add(id);
                      }
                      widget.onToggle(id);
                    }),
                    onGenre: widget.onGenre,
                  ),
              ],
            ),
          ],
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

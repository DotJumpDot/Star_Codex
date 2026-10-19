import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../data/sources/source_api.dart';
import 'age_colors.dart';
import 'genre_browser.dart';
import 'source_palette.dart';

/// Per-site filter (Plan/08 §2) — a compact app-bar button opening a
/// bottom sheet listing one site per line (selection circle left, colored
/// dot + name, mostly-carries type pills right), replacing the old
/// horizontal chip row that had to be scrolled and hunting-tapped. Empty
/// selection means every site. Long-press a site for its genre browser.
/// Rows toggle live in LOCAL state; the feed is updated on a short debounce
/// (rapid multi-select = ONE refetch, not a storm) and flushed when the
/// sheet closes via the Done button or an outside tap.
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

/// Stateful sheet: chips drive a local selection immediately; provider
/// changes are queued and applied on a 300 ms debounce, flushed on Done
/// (and on dispose, so an outside-tap close never drops pending changes).
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
  Timer? _applyTimer;
  final _pending = <VoidCallback>[];

  void _queue(VoidCallback apply) {
    _pending.add(apply);
    _applyTimer?.cancel();
    _applyTimer = Timer(const Duration(milliseconds: 300), _flush);
  }

  void _flush() {
    _applyTimer?.cancel();
    _applyTimer = null;
    final fns = List.of(_pending);
    _pending.clear();
    for (final fn in fns) {
      fn();
    }
  }

  @override
  void dispose() {
    _applyTimer?.cancel();
    _applyTimer = null;
    final fns = List.of(_pending);
    _pending.clear();
    for (final fn in fns) {
      fn();
    }
    super.dispose();
  }

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
                  onPressed: () {
                    _flush();
                    Navigator.of(context).pop();
                  },
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
            Align(
              alignment: Alignment.centerLeft,
              child: ChoiceChip(
                label: Text(t(context, 'browse.sources_all')),
                selected: _selected.isEmpty,
                onSelected: (_) {
                  setState(() => _selected.clear());
                  _queue(widget.onAll);
                },
              ),
            ),
            const SizedBox(height: 4),
            // One site per line, capped at half the screen (user QA
            // 2026-10-19) — rows never resize, the list scrolls instead.
            // Trailing 12 px INSIDE the scroll so the last row never sits
            // flush against the sheet's bottom edge.
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    for (var i = 0; i < widget.sources.length; i++)
                      _SiteRow(
                        source: widget.sources[i],
                        color: sourceDotColor(i),
                        selected: _selected.contains(widget.sources[i].id),
                        failed:
                            widget.failedIds.contains(widget.sources[i].id),
                        onToggle: () => setState(() {
                          final id = widget.sources[i].id;
                          if (!_selected.remove(id)) {
                            _selected.add(id);
                          }
                          _queue(() => widget.onToggle(id));
                        }),
                        onGenre: widget.onGenre,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One site per line (user QA 2026-10-19): selection circle on the LEFT,
/// colored identity dot + name, small what-the-site-carries type pills on
/// the right. The row is always full width — toggling only flips the
/// leading circle, so nothing shifts or resizes (the old Wrap chips jumped
/// around on select). Long-press still opens the genre browser.
class _SiteRow extends StatelessWidget {
  const _SiteRow({
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
    final types = sourceContentTypes[source.id] ?? const <String>[];
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
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              _SelectDot(
                  selected: selected,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              SourceDot(color: color, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (failed) ...[
                const SizedBox(width: 4),
                const Icon(Icons.error, size: 14, color: Colors.redAccent),
              ],
              const SizedBox(width: 6),
              for (final type in types)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: TypeChip(
                    label: t(context, 'browse.type_short.$type'),
                    type: type,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed-size selection circle — the ONLY part of the row that changes on
/// toggle, so widths stay put.
class _SelectDot extends StatelessWidget {
  const _SelectDot({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(
          color: selected ? color : color.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check,
              size: 15, color: Theme.of(context).colorScheme.onPrimary)
          : null,
    );
  }
}

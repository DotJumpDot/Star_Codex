import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../browse/browse_controller.dart';

/// Global search overlay: slides in over every tab from the top right,
/// replacing the old inline browse search field. Submit (or a history
/// pick) jumps to the Browse tab and runs the merged search. Recent
/// queries list under the field while it is empty.
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _animatingOut = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    _focus.unfocus();
    setState(() => _animatingOut = true);
    // Let the slide-out finish before removing the subtree.
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _animatingOut = false);
    });
    ref.read(searchOpenProvider.notifier).state = false;
  }

  void _submit(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    ref.read(searchOpenProvider.notifier).state = false;
    // Scope follows the tab the overlay was opened from: a search started
    // on the Doujin (18+) page stays in the adult sources, everything
    // else goes to the main browse.
    final tab = ref.read(tabIndexProvider);
    const adultTab = 5;
    if (tab == adultTab) {
      ref.read(adultBrowseControllerProvider.notifier).submitSearch(q);
    } else {
      ref.read(tabIndexProvider.notifier).state = 0;
      ref.read(browseControllerProvider.notifier).submitSearch(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(searchOpenProvider);
    if (!open && !_animatingOut) return const SizedBox.shrink();
    final slideIn = open && !_animatingOut;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _close,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          color: slideIn ? Colors.black54 : Colors.transparent,
          child: Align(
            alignment: Alignment.topRight,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: slideIn ? Offset.zero : const Offset(1, 0),
              child: Material(
                elevation: 6,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 8),
                            const Icon(Icons.search, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _text,
                                focusNode: _focus,
                                autofocus: slideIn,
                                textInputAction: TextInputAction.search,
                                onSubmitted: _submit,
                                onChanged: (_) => setState(() {}),
                                style: Theme.of(context).textTheme.bodyLarge,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: t(context, 'browse.search_hint'),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _text.text.isEmpty ? Icons.close : Icons.clear,
                                size: 22,
                              ),
                              onPressed: () {
                                if (_text.text.isEmpty) {
                                  _close();
                                } else {
                                  _text.clear();
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        if (_text.text.isEmpty)
                          FutureBuilder<List<String>>(
                            future: ref
                                .read(searchHistoryDaoProvider)
                                .recent(limit: 10),
                            builder: (context, snap) {
                              final history = snap.data ?? const [];
                              if (history.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Divider(
                                      height: 1,
                                      color: Theme.of(context).dividerColor),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 4),
                                    child: Text(
                                      t(context, 'browse.history'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                  for (final q in history)
                                    InkWell(
                                      onTap: () => _submit(q),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 9),
                                        child: Row(
                                          children: [
                                            Icon(Icons.history,
                                                size: 16,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(q,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

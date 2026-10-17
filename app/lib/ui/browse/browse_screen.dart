import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/repo/browse_repo.dart';
import '../detail/detail_screen.dart';
import 'browse_controller.dart';
import 'filter_sheet.dart';
import 'genre_browser.dart';
import 'result_card.dart';
import 'source_chips_row.dart';

/// Browse tab (Plan/08) — the front door: search all sources at once,
/// merged via Plan/07; latest feed when no search yet.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(browseControllerProvider.notifier).ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(browseControllerProvider);
    final sources = ref.watch(sourcesProvider);
    final repo = ref.watch(browseRepoProvider);
    final controller = ref.read(browseControllerProvider.notifier);
    final visible = filterGroups(state.groups, state.filters);

    final genreHeader = (state.mode == BrowseMode.genre &&
            state.genreSourceId != null &&
            state.genreTerm != null)
        ? '${repo.sourceById(state.genreSourceId!)?.name ?? state.genreSourceId}'
            ' · ${state.genreTerm}'
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'browse.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: t(context, 'browse.filter.title'),
            onPressed: () => showBrowseFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _SearchBar(
              onSubmitted: controller.submitSearch,
              onClear: () => controller.clearSearch(),
            ),
          ),
          SourceChipsRow(
            sources: sources,
            selectedIds: state.activeSourceIds,
            failedIds: state.failedSources,
            onToggle: controller.toggleSource,
            onAll: controller.clearSourceFilter,
            onLongPress: (source) async {
              final term = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                    builder: (_) => GenreBrowserScreen(source: source)),
              );
              if (term != null && mounted) {
                await controller.showGenre(source.id, term);
              }
            },
          ),
          if (genreHeader != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${t(context, 'browse.genre.label')}: $genreHeader',
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: controller.leaveGenre,
                  ),
                ],
              ),
            ),
          if (state.failedSources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 15, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t(context, 'browse.sources_error'),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: state.loading && visible.isEmpty
                ? const _SkeletonList()
                : visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(t(context, 'browse.empty'),
                              textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final isLast = i == visible.length - 1;
                          if (isLast &&
                              !state.endReached &&
                              !state.loadingMore) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref
                                  .read(browseControllerProvider.notifier)
                                  .loadMore();
                            });
                          }
                          return Column(
                            children: [
                              ResultCard(
                                group: visible[i],
                                allGroups: state.groups,
                                sources: sources,
                                onTap: () =>
                                    Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => DetailScreen(
                                      title: visible[i].displayTitle),
                                )),
                                onLongPress: () =>
                                    _quickActions(context, visible[i]),
                              ),
                              if (isLast && state.loadingMore)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Long-press quick actions (Plan/08 §Result card): add to library
  /// (Plan/07 §3.2 merge) + open the source page in the browser.
  void _quickActions(BuildContext context, SearchGroup group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(t(sheetContext, 'browse.add_library')),
              onTap: () async {
                final okMsg = t(sheetContext, 'browse.added_ok');
                final failMsg = t(sheetContext, 'browse.added_fail');
                final messenger = ScaffoldMessenger.of(sheetContext);
                Navigator.pop(sheetContext);
                try {
                  await ref.read(browseRepoProvider).addToLibrary(group);
                  if (mounted) {
                    messenger.showSnackBar(SnackBar(content: Text(okMsg)));
                  }
                } catch (_) {
                  if (mounted) {
                    messenger.showSnackBar(SnackBar(content: Text(failMsg)));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(t(sheetContext, 'browse.open_site')),
              onTap: () {
                Navigator.pop(sheetContext);
                launchUrl(Uri.parse(group.primary.url),
                    mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Search field: submit-only (no per-keystroke network), dropdown of the
/// last 10 queries while focused and empty (Plan/08 §1).
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar({required this.onSubmitted, required this.onClear});

  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _text,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _focus.unfocus();
            if (v.trim().isNotEmpty) widget.onSubmitted(v);
          },
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: t(context, 'browse.search_hint'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            suffixIcon: _text.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _text.clear();
                      widget.onClear();
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_focused && _text.text.isEmpty)
          FutureBuilder<List<String>>(
            future: ref.read(searchHistoryDaoProvider).recent(limit: 10),
            builder: (context, snap) {
              final history = snap.data ?? const [];
              if (history.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(t(context, 'browse.history'),
                        style: Theme.of(context).textTheme.labelSmall),
                    for (final q in history)
                      InkWell(
                        onTap: () {
                          _focus.unfocus();
                          _text.text = q;
                          widget.onSubmitted(q);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.history,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.outline),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(q,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Static skeleton cards while loading (Plan/08: skeleton, not spinners;
/// deliberately not animated so widget tests stay FakeAsync-safe).
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.builder(
      itemCount: 6,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, i) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(width: 64, height: 92, color: shade),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 16,
                        width: double.infinity,
                        color: shade),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 140, color: shade),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

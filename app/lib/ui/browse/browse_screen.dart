import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/repo/browse_repo.dart';
import '../../data/sources/source_registry.dart';
import '../detail/detail_screen.dart';
import '../shell/star_app_bar.dart';
import 'browse_controller.dart';
import 'filter_sheet.dart';
import 'result_card.dart';
import 'source_filter.dart';

/// Browse tab (Plan/08) — the front door. Search lives in the shared
/// header (opens the global overlay); the body is results only: filter +
/// site pickers in the app bar, one thin context row for genre mode /
/// failed sources.
///
/// [adult] scopes the screen to the 18+ source set on its own controller
/// (`adultBrowseControllerProvider`) — the Doujin page is a separate
/// destination in the drawer, and its feed/search/site sheet never touch
/// the main sources (user request 2026-10-19).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key, this.adult = false});

  final bool adult;

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  BrowseController get _controller => ref
      .read((widget.adult ? adultBrowseControllerProvider : browseControllerProvider)
          .notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.adult
        ? adultBrowseControllerProvider
        : browseControllerProvider;
    final state = ref.watch(provider);
    final allSources = ref.watch(sourcesProvider);
    final sources = widget.adult
        ? allSources
            .where((s) => adultSourceIds.contains(s.id))
            .toList(growable: false)
        : allSources
            .where((s) => !adultSourceIds.contains(s.id))
            .toList(growable: false);
    final repo = ref.watch(browseRepoProvider);
    final controller = ref.read(provider.notifier);
    final visible =
        sortGroups(filterGroups(state.groups, state.filters), state.filters.sort);

    final genreHeader =
        (state.mode == BrowseMode.genre &&
            state.genreSourceId != null &&
            state.genreTerm != null)
        ? '${repo.sourceById(state.genreSourceId!)?.name ?? state.genreSourceId}'
              ' · ${state.genreTerm}'
        : null;

    return Scaffold(
      appBar: starAppBar(
        context,
        ref: ref,
        title: Text(
          state.mode == BrowseMode.search
              ? state.query
              : t(context, 'browse.title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Left of the site filter (user QA 2026-10-18): re-runs whatever
          // is showing — latest feed, search, or genre view.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t(context, 'common.refresh'),
            onPressed: () => controller.retry(),
          ),
          SourceFilterButton(
            sources: sources,
            selectedIds: state.activeSourceIds,
            failedIds: state.failedSources,
            onToggle: controller.toggleSource,
            onAll: controller.clearSourceFilter,
            onGenre: (source, term) => controller.showGenre(source.id, term),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: !state.filters.isDefault,
              child: const Icon(Icons.tune),
            ),
            tooltip: t(context, 'browse.filter.title'),
            onPressed: () => showBrowseFilterSheet(context, provider),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off,
                      size: 15, color: Colors.orangeAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t(context, 'browse.offline_cached'),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: Colors.orangeAccent),
                    ),
                  ),
                ],
              ),
            ),
          // ล่าสุด ⇄ ยอดนิยม ordering for the latest feed (server-side on
          // the madara family; other sources keep their update order).
          if (state.mode == BrowseMode.latest)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(t(context, 'browse.feed.latest')),
                    selected: !state.feedPopular,
                    onSelected: (_) => controller.setFeedPopular(false),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(t(context, 'browse.feed.popular')),
                    selected: state.feedPopular,
                    onSelected: (_) => controller.setFeedPopular(true),
                  ),
                ],
              ),
            ),
          if (genreHeader != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                  const Icon(
                    Icons.error_outline,
                    size: 15,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t(context, 'browse.sources_error'),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: Colors.redAccent),
                    ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t(context, 'browse.empty'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(t(context, 'common.retry')),
                            onPressed: () => controller.retry(),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final isLast = i == visible.length - 1;
                      if (isLast && !state.endReached && !state.loadingMore) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          controller.loadMore();
                        });
                      }
                      return Column(
                        children: [
                          ResultCard(
                            group: visible[i],
                            allGroups: state.groups,
                            sources: sources,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                // Detail opens from a browse card too
                                // (doc 09): the row materializes on load
                                // via the controller's DetailKey.forGroup
                                // (the previous nested-ProviderScope
                                // override tripped riverpod's dependency
                                // check — see PLAN_NOTES on-device QA).
                                builder: (_) =>
                                    DetailScreen.fromGroup(visible[i]),
                              ),
                            ),
                            onLongPress: () =>
                                _quickActions(context, visible[i]),
                          ),
                          if (isLast && state.loadingMore)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                launchUrl(
                  Uri.parse(group.primary.url),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
      ),
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
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(width: 92, height: 128, color: shade),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 16, width: double.infinity, color: shade),
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

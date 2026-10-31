import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';

/// Left navigation drawer (replaces the old bottom bar): every top-level
/// destination in one place, current tab highlighted. Opened by the
/// hamburger on each tab's app bar; the edge-swipe gesture is opt-in via
/// settings (`nav_edge_swipe`, default off).
class AppNavDrawer extends ConsumerWidget {
  const AppNavDrawer({super.key, required this.current});

  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = <(IconData, IconData, String)>[
      (Icons.search_outlined, Icons.search, 'tab.browse'),
      // Search Mix (2026-10-28) — mangary/whytoon: catalogs that mix
      // normal AND 18+ content get their own universe so neither the
      // main feed nor the Doujin page absorbs them. Yaoi is filtered by
      // default on this tab (setting `mix_hide_yaoi`).
      (Icons.blur_on_outlined, Icons.blur_on, 'tab.mix'),
      // Doujin (18+) — its own scoped browse page (user request
      // 2026-10-19): separated from the main feed on purpose.
      (Icons.eighteen_up_rating_outlined, Icons.eighteen_up_rating,
          'tab.adult'),
      (Icons.collections_bookmark_outlined, Icons.collections_bookmark,
          'tab.library'),
      (Icons.history_outlined, Icons.history, 'tab.history'),
      (Icons.download_outlined, Icons.download, 'tab.offline'),
      (Icons.settings_outlined, Icons.settings, 'tab.settings'),
    ];
    return NavigationDrawer(
      selectedIndex: current,
      onDestinationSelected: (i) {
        ref.read(tabIndexProvider.notifier).state = i;
        Navigator.of(context).pop();
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Star Codex',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(t(context, 'nav.subtitle'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        for (final (i, (icon, selectedIcon, label)) in items.indexed)
          NavigationDrawerDestination(
            key: ValueKey('nav-dest-$i'),
            icon: Icon(icon),
            selectedIcon: Icon(selectedIcon),
            label: Text(t(context, label)),
          ),
      ],
    );
  }
}

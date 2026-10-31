import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/sources/source_registry.dart' show BrowseScope;
import '../browse/browse_screen.dart';
import '../downloads/offline_screen.dart';
import '../library/history_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import 'app_drawer.dart';
import 'search_overlay.dart';

/// Navigation shell: the seven tabs live in an IndexedStack; navigation
/// is the LEFT drawer (hamburger on every tab header, edge-swipe opt-in
/// via `nav_edge_swipe`) and the global search overlay slides in
/// top-right. Tab 2 is the Search Mix page (mangary/whytoon — normal +
/// 18+ mixed catalogs, own universe), tab 3 the Doujin (18+) page — both
/// scoped BrowseScreens (user requests 2026-10-19 + 2026-10-28; Settings
/// stays last).
class NavigationShell extends ConsumerWidget {
  const NavigationShell({super.key});

  static const _pages = <Widget>[
    BrowseScreen(),
    BrowseScreen(scope: BrowseScope.mix),
    BrowseScreen(scope: BrowseScope.adult),
    LibraryScreen(),
    HistoryScreen(),
    OfflineScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    final edgeSwipe =
        ref.watch(settingsProvider).getBool('nav_edge_swipe', false);
    return Scaffold(
      key: ref.watch(shellScaffoldKeyProvider),
      drawerEnableOpenDragGesture: edgeSwipe,
      drawer: AppNavDrawer(current: index),
      body: Stack(
        children: [
          IndexedStack(index: index, children: _pages),
          const SearchOverlay(),
        ],
      ),
    );
  }
}

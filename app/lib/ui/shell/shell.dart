import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../browse/browse_screen.dart';
import '../downloads/offline_screen.dart';
import '../library/history_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import 'app_drawer.dart';
import 'search_overlay.dart';

/// Navigation shell: the six tabs live in an IndexedStack; navigation is
/// the LEFT drawer (hamburger on every tab header, edge-swipe opt-in via
/// `nav_edge_swipe`) and the global search overlay slides in top-right.
/// Tab 1 is the Doujin (18+) page — a scoped BrowseScreen whose universe
/// is the adult source set only (sits under ค้นหา in the drawer, user
/// request 2026-10-19; Settings stays last).
class NavigationShell extends ConsumerWidget {
  const NavigationShell({super.key});

  static const _pages = <Widget>[
    BrowseScreen(),
    BrowseScreen(adult: true),
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

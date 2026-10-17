import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../browse/browse_screen.dart';
import '../downloads/offline_screen.dart';
import '../library/history_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';

/// Bottom navigation shell — exactly 5 tabs (decision 00 §Navigation):
/// Browse / Library / History / Offline / Settings. The index lives in
/// [tabIndexProvider] so pushed screens can jump to a tab (detail tag
/// chips → browse, Plan/09 §4).
class NavigationShell extends ConsumerWidget {
  const NavigationShell({super.key});

  static const _pages = <Widget>[
    BrowseScreen(),
    LibraryScreen(),
    HistoryScreen(),
    OfflineScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(tabIndexProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search),
            label: t(context, 'tab.browse'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.collections_bookmark_outlined),
            selectedIcon: const Icon(Icons.collections_bookmark),
            label: t(context, 'tab.library'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            label: t(context, 'tab.history'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.download_outlined),
            selectedIcon: const Icon(Icons.download),
            label: t(context, 'tab.offline'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: t(context, 'tab.settings'),
          ),
        ],
      ),
    );
  }
}

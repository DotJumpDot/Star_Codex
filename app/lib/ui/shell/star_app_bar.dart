import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';

/// Shared tab header: hamburger (opens the shell's navigation drawer) on
/// the left, a search button on the right that expands the global search
/// overlay (slides in from the top right), plus the tab's own actions.
/// [leadingOverride] replaces the hamburger (e.g. library selection mode).
AppBar starAppBar(
  BuildContext context, {
  required WidgetRef ref,
  Widget? title,
  List<Widget> actions = const [],
  Widget? leadingOverride,
}) {
  return AppBar(
    leading: leadingOverride ??
        IconButton(
          tooltip: t(context, 'nav.menu'),
          icon: const Icon(Icons.menu),
          onPressed: () =>
              ref.read(shellScaffoldKeyProvider).currentState?.openDrawer(),
        ),
    title: title,
    actions: [
      ...actions,
      IconButton(
        tooltip: t(context, 'browse.title'),
        icon: const Icon(Icons.search),
        onPressed: () => ref.read(searchOpenProvider.notifier).state = true,
      ),
    ],
  );
}

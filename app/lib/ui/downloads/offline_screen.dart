import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Placeholder until Phase 10 fills it in (Plan/13 — truthful Offline tab).
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(context, 'tab.offline'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(t(context, 'coming.soon')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Placeholder until Phase 11 fills it in (Plan/14).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(context, 'tab.settings'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(t(context, 'coming.soon')),
        ],
      ),
    );
  }
}

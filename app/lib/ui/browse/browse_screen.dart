import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Placeholder until Phase 5 fills it in (Plan/08).
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(context, 'tab.browse'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(t(context, 'coming.soon')),
        ],
      ),
    );
  }
}

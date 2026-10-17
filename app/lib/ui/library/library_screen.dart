import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Placeholder until Phase 9 fills it in (Plan/12).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t(context, 'tab.library'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(t(context, 'coming.soon')),
        ],
      ),
    );
  }
}

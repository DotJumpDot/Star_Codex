import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Stub replaced by Phase 6 (Plan/09 — detail screen, source tabs, chapter
/// list). Browse cards push this so taps navigate somewhere real.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(child: Text(t(context, 'coming.soon'))),
    );
  }
}

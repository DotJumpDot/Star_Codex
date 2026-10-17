import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/sources/source_api.dart';
import 'source_palette.dart';

/// Full-screen genre picker (Plan/08 §2 long-press). Pops with the chosen
/// term; BrowseScreen feeds it into the same merged result list.
class GenreBrowserScreen extends ConsumerStatefulWidget {
  const GenreBrowserScreen({super.key, required this.source});

  final Source source;

  @override
  ConsumerState<GenreBrowserScreen> createState() => _GenreBrowserScreenState();
}

class _GenreBrowserScreenState extends ConsumerState<GenreBrowserScreen> {
  late Future<List<SourceGenre>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref.read(browseRepoProvider).genres(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.name)),
      body: FutureBuilder<List<SourceGenre>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t(context, 'common.error.title')),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => setState(_load),
                    child: Text(t(context, 'common.retry')),
                  ),
                ],
              ),
            );
          }
          final genres = snap.data ?? const [];
          return ListView.builder(
            itemCount: genres.length,
            itemBuilder: (context, i) {
              final g = genres[i];
              return ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: sourceDotColor(i),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(g.name),
                onTap: () => Navigator.of(context).pop(g.term),
              );
            },
          );
        },
      ),
    );
  }
}

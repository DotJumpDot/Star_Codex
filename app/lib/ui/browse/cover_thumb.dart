import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/providers.dart';
import '../../data/storage/image_pipeline.dart';

/// Session memo for cover fetches — every rebuild of a card must not
/// re-download/re-hash the same cover. Failures are cached as null too
/// (no retry storm on a dead CDN).
class CoverCache {
  final _cache = <String, Future<PageResult?>>{};

  Future<PageResult?> get(String url, String referer, ImagePipeline pipeline) {
    return _cache.putIfAbsent(url, () async {
      try {
        return await pipeline.fetchAndStore(url, referer: referer);
      } catch (_) {
        return null; // covers are optional
      }
    });
  }
}

final coverCacheProvider = Provider((ref) => CoverCache());

/// Cover image fetched through the pipeline (Plan/03 single write path):
/// first view downloads + WebP-compresses into the blob store, later views
/// hit dedup. Placeholder while loading / on failure.
class CoverThumb extends ConsumerStatefulWidget {
  const CoverThumb({
    super.key,
    required this.url,
    required this.referer,
    this.width = 64,
    this.height = 92,
  });

  final String url;
  final String referer;
  final double width;
  final double height;

  @override
  ConsumerState<CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends ConsumerState<CoverThumb> {
  late final Future<PageResult?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(coverCacheProvider).get(
          widget.url,
          widget.referer,
          ref.read(imagePipelineProvider),
        );
  }

  @override
  Widget build(BuildContext context) {
    final libraryDir = ref.watch(libraryDirProvider);
    return FutureBuilder<PageResult?>(
      future: _future,
      builder: (context, snap) {
        final result = snap.data;
        if (result == null) return _placeholder(context);
        final file = File(p.join(libraryDir.path, result.path));
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(context),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        width: widget.width,
        height: widget.height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.image_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.outline),
      );
}

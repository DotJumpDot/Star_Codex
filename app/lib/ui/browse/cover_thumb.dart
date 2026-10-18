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

/// WP thumbnail size suffix on upload URLs ("-214x300" before the ext).
final _wpSizeSuffix = RegExp(r'-\d{2,4}x\d{2,4}(?=\.[a-zA-Z0-9]+$)');

/// Flutter's engine cannot decode AVIF, and the pipeline keeps originals
/// it can't re-encode — a cover on such a URL can never render.
bool _renderable(String url) =>
    !url.toLowerCase().endsWith('.avif') &&
    !url.toLowerCase().endsWith('.svg') &&
    !url.startsWith('data:');

/// Cover image fetched through the pipeline (Plan/03 single write path):
/// first view downloads + WebP-compresses into the blob store, later views
/// hit dedup. Placeholder while loading / on failure.
///
/// Failure walking (slow-manga QA 2026-10-18): sites reference covers that
/// 404 (WP thumbnail missing while the full-size original lives on) or ship
/// AVIF uploads Flutter can't decode. Candidates are tried in order through
/// the [CoverCache] — [url], its un-suffixed full-size variant, then each
/// [fallbacks] entry (merged cards pass sibling sites' covers).
class CoverThumb extends ConsumerStatefulWidget {
  const CoverThumb({
    super.key,
    required this.url,
    required this.referer,
    this.fallbacks = const [],
    this.width = 64,
    this.height = 92,
  });

  final String url;
  final String referer;

  /// Extra (url, referer) candidates tried after [url] fails.
  final List<(String, String)> fallbacks;

  final double width;
  final double height;

  @override
  ConsumerState<CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends ConsumerState<CoverThumb> {
  late Future<PageResult?> _future;

  List<(String, String)> get _candidates {
    final seen = <String>{};
    final out = <(String, String)>[];
    void add(String url, String referer) {
      if (!_renderable(url) || !seen.add(url)) return;
      out.add((url, referer));
      final bare = url.replaceFirst(_wpSizeSuffix, '');
      if (bare != url && _renderable(bare) && seen.add(bare)) {
        out.add((bare, referer));
      }
    }

    add(widget.url, widget.referer);
    for (final (u, r) in widget.fallbacks) {
      add(u, r);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(CoverThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Callers rebuild with fresh (non-identical) fallback lists — compare
    // by content so an unchanged cover doesn't flash its placeholder.
    if (oldWidget.url != widget.url ||
        oldWidget.referer != widget.referer ||
        !_sameList(oldWidget.fallbacks, widget.fallbacks)) {
      _future = _load();
    }
  }

  static bool _sameList(List<(String, String)> a, List<(String, String)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1 || a[i].$2 != b[i].$2) return false;
    }
    return true;
  }

  Future<PageResult?> _load() async {
    final cache = ref.read(coverCacheProvider);
    final pipeline = ref.read(imagePipelineProvider);
    for (final (u, r) in _candidates) {
      final result = await cache.get(u, r, pipeline);
      if (result != null) return result;
    }
    return null;
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

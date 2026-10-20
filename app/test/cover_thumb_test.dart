import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/data/storage/blob_store.dart';
import 'package:star_codex/data/storage/image_pipeline.dart';
import 'package:star_codex/ui/browse/cover_thumb.dart';

/// CoverThumb fallback walking (slow-manga QA 2026-10-18): dead primary
/// URLs (404 WP thumbnails) must fall through to the un-suffixed
/// full-size original, then to sibling sites' covers; AVIF URLs must
/// never be fetched at all.

/// 1×1 transparent PNG.
const _tinyPngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _StubPipeline implements ImagePipeline {
  _StubPipeline(this._behavior);

  final Future<PageResult> Function(String url) _behavior;
  final requested = <String>[];

  @override
  SafeHttp get http => throw UnimplementedError();

  @override
  BlobStore get blobs => throw UnimplementedError();

  @override
  Future<PageResult> fetchAndStore(String url, {String? referer}) {
    requested.add(url);
    return _behavior(url);
  }

  @override
  Future<PageResult> fetchAndStoreIndexed(String url, {String? referer}) {
    requested.add(url);
    return _behavior(url);
  }
}

Future<void> main() async {
  late Directory tmp;
  late String pngRelPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cover-thumb-test');
    final blobsDir = Directory('${tmp.path}${Platform.pathSeparator}blobs');
    await blobsDir.create(recursive: true);
    final bytes = const Base64Decoder().convert(_tinyPngB64);
    await File(
            '${blobsDir.path}${Platform.pathSeparator}cover.png')
        .writeAsBytes(bytes);
    pngRelPath = 'blobs${Platform.pathSeparator}cover.png';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  PageResult ok() => PageResult(
        hash: 'h',
        path: pngRelPath,
        storedBytes: 70,
        width: 1,
        height: 1,
        fromCache: false,
      );

  Widget host(Widget child, ImagePipeline pipeline) => ProviderScope(
        overrides: [
          libraryDirProvider.overrideWithValue(tmp),
          imagePipelineProvider.overrideWithValue(pipeline),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  // Drain-loop pattern (project rule — pumpAndSettle times out once real
  // file I/O pends under FakeAsync).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  testWidgets('dead primary walks un-suffixed original then fallbacks',
      (tester) async {
    final pipeline = _StubPipeline((url) async {
      if (url == 'https://other.example/cover-b.jpg') return ok();
      throw Exception('dead: $url');
    });
    await tester.pumpWidget(host(
      CoverThumb(
        url: 'https://site.example/a-cover-214x300.jpg',
        referer: 'https://site.example/',
        fallbacks: const [
          ('https://other.example/cover-b.jpg', 'https://other.example/'),
        ],
      ),
      pipeline,
    ));
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(pipeline.requested, [
      'https://site.example/a-cover-214x300.jpg',
      'https://site.example/a-cover.jpg',
      'https://other.example/cover-b.jpg',
    ]);
  });

  testWidgets('AVIF candidates are never fetched', (tester) async {
    final pipeline = _StubPipeline((url) async => ok());
    await tester.pumpWidget(host(
      CoverThumb(
        url: 'https://site.example/x.avif',
        referer: 'https://site.example/',
        fallbacks: const [
          ('https://site.example/y-100x150.avif', 'https://site.example/'),
        ],
      ),
      pipeline,
    ));
    await settle(tester);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(pipeline.requested, isEmpty);
  });

  testWidgets('live primary renders without touching fallbacks',
      (tester) async {
    final pipeline = _StubPipeline((url) async => ok());
    await tester.pumpWidget(host(
      CoverThumb(
        url: 'https://site.example/primary.jpg',
        referer: 'https://site.example/',
        fallbacks: const [
          ('https://other.example/cover-b.jpg', 'https://other.example/'),
        ],
      ),
      pipeline,
    ));
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
    expect(pipeline.requested, ['https://site.example/primary.jpg'],
        reason: 'suffix-less URL has no un-suffixed variant — exactly one '
            'fetch, fallbacks untouched');
  });
}

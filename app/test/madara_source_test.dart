import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/madara/configs.dart';
import 'package:star_codex/data/sources/madara/madara_source.dart';

/// Madara tile parsing against slow-manga markup trimmed from the live
/// site (2026-10-18). Focus: cover URL selection — lazy data-src vs
/// placeholder src vs AVIF uploads Flutter's engine cannot decode
/// (on-device QA: "Poison Master of Sacheon Tang Clan" rendered blank).
Future<void> main() async {
  final dir = '${Directory.current.path}\\test\\fixtures';
  final tiles =
      await File('$dir\\slow_tiles.html').readAsString(encoding: utf8);

  MadaraSource slowMangaServing(String body) {
    return MadaraSource(
      madaraConfigs.firstWhere((c) => c.id == 'slow-manga'),
      SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async => Response<List<int>>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: Uint8List.fromList(const Utf8Encoder().convert(body)),
        ),
        delay: (_) async {},
      ),
    );
  }

  group('MadaraSource tiles — cover selection', () {
    test('AVIF-only covers are dropped (no decoder ⇒ never renderable)',
        () async {
      final items = await slowMangaServing(tiles).latest();
      final poison = items.firstWhere((s) => s.title.contains('Poison'));
      expect(poison.coverUrl, isNull);
    });

    test('lazy data-src preferred over placeholder src', () async {
      final items = await slowMangaServing(tiles).latest();
      final lazy = items.firstWhere((s) => s.title.contains('Lazy'));
      expect(lazy.coverUrl, endsWith('lazy-loaded-cover-197x300.jpg'));
      expect(lazy.chapterCountHint, 42);
      expect(lazy.type, 'manga');
    });

    test('data-src AVIF falls through to a renderable src', () async {
      final items = await slowMangaServing(tiles).latest();
      final mixed = items.firstWhere((s) => s.title.contains('Mixed'));
      expect(mixed.coverUrl, endsWith('mixed-cover-197x300.jpg'));
    });
  });
}

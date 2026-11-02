import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/manghaha/manghaha_source.dart';

/// Manghaha adapter parsers against fixtures trimmed from the LIVE pages
/// (probed 2026-11-03 — "obito" custom theme, scoped to the Doujin 18+
/// page: the same `.latest-item-contain` grid serves the feed, search and
/// tag pages).
Future<void> main() async {
  final dir = '${Directory.current.path}\\test\\fixtures';
  String fixture(String name) =>
      File('$dir\\$name').readAsStringSync(encoding: utf8);

  SafeHttp httpServing(String body) => SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async => Response<List<int>>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: Uint8List.fromList(utf8.encode(body)),
        ),
        delay: (_) async {},
      );

  group('parseManghahaTiles', () {
    test('feed tile: url/title/cover/chapter-hint + relative stamp', () {
      final items = parseManghahaTiles(fixture('manghaha_feed.html'));
      expect(items, isNotEmpty);
      final cleaning =
          items.firstWhere((s) => s.title == 'Cleaning Service');
      expect(cleaning.url, 'https://manghaha.com/cleaning-service/');
      expect(cleaning.coverUrl,
          'https://manghaha.com/uploads/thumbnail/866045644dcf5518cab87541b134fb30.jpg');
      expect(cleaning.chapterCountHint, 87); // "ตอนที่  087"
      // "7 ชั่วโมง" relative label → an epoch ms within the last day.
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(cleaning.lastUpdatedMs, isNotNull);
      expect(now - cleaning.lastUpdatedMs!, lessThan(24 * 3600 * 1000));
    });

    test('every tile carries a series URL and title', () {
      final items = parseManghahaTiles(fixture('manghaha_feed.html'));
      for (final s in items) {
        expect(s.url, startsWith('https://manghaha.com/'));
        expect(s.title, isNotEmpty);
      }
    });
  });

  group('parseManghahaDetail', () {
    final d = parseManghahaDetail(fixture('manghaha_series.html'),
        'https://manghaha.com/cleaning-service/');

    test('h1 prefix/suffix stripped into a clean title', () {
      // Raw h1: "อ่านมังงะ Cleaning Service แปลไทย"
      expect(d.title, 'Cleaning Service');
    });

    test('cover from img.manga-thumb', () {
      expect(d.coverUrl,
          'https://manghaha.com/uploads/thumbnail/866045644dcf5518cab87541b134fb30.jpg');
    });

    test('status row (ยังไม่จบ) normalizes to ongoing', () {
      expect(d.status, 'ongoing');
    });

    test('description drops the embedded tag-list buttons', () {
      expect(d.description, isNull); // fixture series has no story
      expect(d.tags, contains('ยังไม่จบ'));
    });

    test('chapters ascend, carry numbers and relative stamps', () {
      expect(d.chapters, isNotEmpty);
      expect(d.chapters.last.number, 87);
      expect(d.chapters.last.title, contains('ตอนที่ 087'));
      expect(
        d.chapters.last.uploadedAt,
        isNotNull,
        reason: '"7 ชั่วโมง" stamp must parse',
      );
      for (var i = 1; i < d.chapters.length; i++) {
        expect(d.chapters[i].number,
            greaterThanOrEqualTo(d.chapters[i - 1].number));
      }
    });
  });

  group('ManghahaSource.pages', () {
    test('page-img tags in order', () async {
      final source = ManghahaSource(httpServing(fixture('manghaha_chapter.html')));
      final pages = await source.pages(
          'https://manghaha.com/cleaning-service/cleaning-service-x-087/');
      expect(pages.imageUrls, isNotEmpty);
      expect(pages.imageUrls.first, startsWith('https://manghaha.com/uploads/'));
      expect(pages.imageUrls.length, greaterThan(10));
    });
  });
}

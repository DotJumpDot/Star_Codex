import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/oremanga/oremanga_source.dart';

/// Oremanga adapter parsers against fixtures trimmed from the LIVE pages
/// (probed 2026-11-03 — custom WP theme, main feed: flexbox4 feed tiles
/// with explicit type badges, /?s= search with flexbox2 cards, Thai-month
/// chapter dates).
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

  group('parseOremangaTiles', () {
    test('flexbox4 tile: url/title/cover/type + relative stamp', () {
      final items = parseOremangaTiles(fixture('oremanga_home.html'));
      expect(items, isNotEmpty);
      final momiji = items.firstWhere((s) => s.title == 'Momiji to Kouyou');
      expect(momiji.url,
          'https://www.oremanga.net/series/Momiji-to-Kouyou/');
      expect(momiji.type, 'manga'); // span.type badge → /genre/manga/
      expect(momiji.chapterCountHint, 8); // "ตอนที่ 8"
      // "5 ชั่วโมง ที่แล้ว" → within the last day.
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(momiji.lastUpdatedMs, isNotNull);
      expect(now - momiji.lastUpdatedMs!, lessThan(24 * 3600 * 1000));
      expect(momiji.coverUrl, startsWith('https://www.oremanga.net/wp-content/'));
    });

    test('duplicate URLs within a page collapse', () {
      final items = parseOremangaTiles(fixture('oremanga_home.html'));
      final urls = items.map((s) => s.url).toList();
      expect(urls.toSet().length, urls.length);
    });
  });

  group('parseOremangaSearchCards', () {
    test('flexbox2 card: url/title/type + genre chips (genre page)', () {
      final items =
          parseOremangaSearchCards(fixture('oremanga_genre.html'));
      expect(items.length, greaterThan(5));
      final first = items.first;
      expect(first.url, startsWith('https://www.oremanga.net/series/'));
      expect(first.title, isNotEmpty);
      expect(first.type, anyOf('manhwa', 'manga', 'manhua', isNull));
    });
  });

  group('parseOremangaDetail', () {
    final d = parseOremangaDetail(fixture('oremanga_series.html'),
        'https://www.oremanga.net/series/the-lazy-prince-becomes-a-genius/');

    test('title/type badge/status', () {
      expect(d.title, 'The Lazy Prince Becomes A Genius');
      expect(d.type, 'manhwa'); // <span class="type Manhwa">
      expect(d.status, 'ongoing'); // <span class="status Ongoing">
    });

    test('genres + cover', () {
      expect(d.tags, containsAll(['Action', 'Adventure', 'Fantasy', 'Manhwa']));
      expect(d.coverUrl,
          startsWith('https://www.oremanga.net/wp-content/uploads/'));
    });

    test('chapters: Thai-month dates, ascending, 161 = newest', () {
      expect(d.chapters, isNotEmpty);
      expect(d.chapters.last.number, 161);
      // "2 พฤศจิกายน 2026" must parse (Thai month, day-first order).
      expect(d.chapters.last.uploadedAt, isNotNull);
      for (var i = 1; i < d.chapters.length; i++) {
        expect(d.chapters[i].number,
            greaterThanOrEqualTo(d.chapters[i - 1].number));
      }
    });
  });

  group('OremangaSource.pages', () {
    test('reader-area-main imgs in order', () async {
      final source =
          OremangaSource(httpServing(fixture('oremanga_chapter.html')));
      final pages = await source.pages(
          'https://www.oremanga.net/the-lazy-prince-becomes-a-genius/161-x/');
      expect(pages.imageUrls.length, greaterThan(20));
      expect(pages.imageUrls.first, startsWith('https://img.oremanga.net/'));
    });
  });

  group('OremangaSource.latest pagination', () {
    test('page 1 hits /, page 2 hits /page/2/', () async {
      final fetched = <Uri>[];
      final http = SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async {
          fetched.add(uri);
          return Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 200,
            data: Uint8List.fromList(
                utf8.encode(fixture('oremanga_home.html'))),
          );
        },
        delay: (_) async {},
      );
      final source = OremangaSource(http);
      await source.latest();
      await source.latest(page: 2);
      expect(fetched[0].toString(), 'https://www.oremanga.net/');
      expect(fetched[1].toString(), 'https://www.oremanga.net/page/2/');
    });
  });
}

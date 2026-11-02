import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/niceoppai/niceoppai_source.dart';

/// Niceoppai adapter parsers against fixtures trimmed from the LIVE pages
/// (probed 2026-11-03 — NOPOrange theme, MIX scope: fcard grid feed,
/// POST-only search, chrow chapter list, absolute data-ago stamps).
Future<void> main() async {
  final dir = '${Directory.current.path}\\test\\fixtures';
  String fixture(String name) =>
      File('$dir\\$name').readAsStringSync(encoding: utf8);

  group('parseNiceoppaiCards', () {
    test('fcard: url/title/cover(+%20)/hint + data-ago absolute stamp', () {
      final items = parseNiceoppaiCards(fixture('niceoppai_list.html'));
      expect(items.length, greaterThan(10));
      final first = items.first;
      expect(first.url, startsWith('https://www.niceoppai.net/'));
      expect(first.title, isNotEmpty);
      // Cover paths carry literal spaces — they must arrive encoded.
      expect(first.coverUrl, isNot(contains(' ')));
      // data-ago is unix SECONDS; the parser must hand back ms.
      expect(first.lastUpdatedMs, isNotNull);
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(first.lastUpdatedMs! ~/ 1000, lessThan(nowSec + 60));
      expect(first.lastUpdatedMs! ~/ 1000,
          greaterThan(nowSec - 365 * 24 * 3600));
      expect(first.chapterCountHint, isNotNull);
    });
  });

  group('parseNiceoppaiDetail', () {
    final d = parseNiceoppaiDetail(fixture('niceoppai_series.html'),
        'https://www.niceoppai.net/The-Lazy-Prince-Becomes-A-Genius/');

    test('title, genre chips, manhwa type from chips', () {
      expect(d.title, 'The Lazy Prince Becomes A Genius');
      expect(d.tags, containsAll(['Action', 'Fantasy', 'Manhwa', 'Shounen']));
      expect(d.type, 'manhwa');
    });

    test('status (ยังไม่จบ) + Thai-label facts', () {
      expect(d.status, 'ongoing');
    });

    test('cover spaces encoded', () {
      expect(d.coverUrl, isNot(contains(' ')));
      expect(d.coverUrl, contains('%20'));
    });

    test('chapters: data-ch numbers, English dates, ascending', () {
      // The live page server-renders the newest ~70 chrow rows; the rest
      // of the 167 arrive via its own JS — 70 is what an adapter sees.
      expect(d.chapters.length, greaterThan(50));
      expect(d.chapters.last.number, 155);
      final dated = d.chapters.lastWhere((c) => c.uploadedAt != null);
      expect(dated.uploadedAt, isNotNull); // "Sep 20, 2026"
      for (var i = 1; i < d.chapters.length; i++) {
        expect(d.chapters[i].number,
            greaterThanOrEqualTo(d.chapters[i - 1].number));
      }
    });
  });

  group('NiceoppaiSource.search', () {
    test('POSTs the form fields and parses fcard results', () async {
      Uri? postedUri;
      Options? postedOptions;
      final http = SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async {
          postedUri = uri;
          postedOptions = options;
          return Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 200,
            data: Uint8List.fromList(
                utf8.encode(fixture('niceoppai_list.html'))),
          );
        },
        delay: (_) async {},
      );
      final results =
          await NiceoppaiSource(http).search('lazy prince');
      expect(postedUri.toString(),
          'https://www.niceoppai.net/manga_list/search/');
      expect(postedOptions!.method, 'POST');
      expect(postedOptions!.contentType, 'application/x-www-form-urlencoded');
      final body = postedOptions!.extra?['safe_http_body'] as String;
      expect(body,
          contains('txt_wpm_wgt_mng_sch_nme=lazy+prince')); // form-encoded
      expect(body, contains('cmd_wpm_wgt_mng_sch_sbm=Search'));
      expect(results, isNotEmpty);

      // Search results are a single page.
      expect(await NiceoppaiSource(http).search('lazy prince', page: 2),
          isEmpty);
    });
  });

  group('NiceoppaiSource.pages', () {
    test('#image-container imgs in order', () async {
      final http = SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async => Response<List<int>>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: Uint8List.fromList(
              utf8.encode(fixture('niceoppai_chapter.html'))),
        ),
        delay: (_) async {},
      );
      final pages = await NiceoppaiSource(http)
          .pages('https://www.niceoppai.net/The-Lazy-Prince-Becomes-A-Genius/155/');
      expect(pages.imageUrls.length, greaterThan(10));
      expect(pages.imageUrls.first, startsWith('https://image7.niceoppai.net/'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/data/sources/toonary/configs.dart';
import 'package:star_codex/data/sources/toonary/toonary_source.dart';

/// Toonary-platform parsers against fixtures trimmed from the LIVE pages
/// (mangary.com / whytoon.com, probed 2026-10-28). The chapter list and
/// reader images live ONLY in the Next.js flight payload — these tests
/// pin that format.
String fixture(String name) =>
    File('test/fixtures/toonary/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('toonary listing', () {
    test('mangary cards: slug dedupe, title, cover, genre chips', () {
      final items = parseToonaryListing(
          fixture('mangary_listing.html'), 'https://mangary.com');
      expect(items, hasLength(2));
      expect(items.first.url, 'https://mangary.com/content/debut-or-die');
      expect(items.first.title, contains('Debut or Die!'));
      expect(items.first.coverUrl, startsWith('https://storage.mangary.com/'));
      // Card chips feed the Mix tab's default-on yaoi filter.
      expect(items.first.genres.join(' ').toLowerCase(), contains('drama'));
      expect(items.first.genres.join(' ').toLowerCase(), isNot(contains('yaoi')));
      // The second card carries a yaoi chip → the feed filter drops it.
      expect(items.last.genres.join(' ').toLowerCase(), contains('yaoi'));
    });

    test('toonarySlug rejects episode tails and junk', () {
      expect(toonarySlug('/content/jinx'), 'jinx');
      expect(toonarySlug('https://mangary.com/content/jinx/episode/102'), 'jinx');
      expect(toonarySlug('/content/123/episode/1'), isNull);
      expect(toonarySlug('/latest'), isNull);
    });
  });

  group('toonary detail', () {
    test('mangary: title/desc/cover, HTML categories, flight episodes', () {
      final d = parseToonaryDetail(
        fixture('mangary_detail.html'),
        'https://mangary.com/content/jinx',
        genresFromHtmlLinks: true,
      );
      expect(d, isNotNull);
      expect(d!.title, 'Jinx (Mingwa) - จิงซ์');
      expect(d.description, 'เรื่องย่อทดสอบ');
      expect(d.coverUrl, startsWith('https://storage.mangary.com/'));
      expect(d.tags, contains('Yaoi - มังงะวาย'));
      // Platform truth (2026-11-01): Toonary sites host ONLY vertical
      // webtoons — the old genre-derived guess mislabeled titles via
      // mangary's "Manga - มังงะญี่ปุ่น" category.
      expect(d.type, 'manhwa');
      // Premium (coin) episodes are excluded — no paywall bypass.
      expect(d.chapters, hasLength(2));
      expect(d.chapters.map((c) => c.number), [1, 2]);
      expect(d.chapters.first.url,
          'https://mangary.com/content/jinx/episode/1');
      expect(d.chapters.last.title, contains('END'));
      expect(d.chapters.last.uploadedAt, isNotNull);
    });

    test('whytoon: skips the genre dictionary, episodes in flight', () {
      final d = parseToonaryDetail(
        fixture('whytoon_detail.html'),
        'https://whytoon.com/content/now-come-and-regret',
        genresFromHtmlLinks: false,
        episodeInPath: false,
      );
      expect(d, isNotNull);
      expect(d!.title, 'Now Come and Regret - สายเกินจะเสียใจ');
      // The 33-entry site dictionary must NOT leak in as series tags.
      expect(d.tags, isNot(contains('sports')));
      expect(d.tags, contains('Yaoi - มังงะวาย'));
      expect(d.chapters, hasLength(2));
      // whytoon chapter URLs drop the /episode/ segment.
      expect(d.chapters.first.url,
          'https://whytoon.com/content/now-come-and-regret/1');
    });
  });

  group('toonary reader images', () {
    test('mangary: absolute storage URLs in order', () {
      final urls = parseToonaryImages(fixture('mangary_episode.html'));
      expect(urls, [
        'https://storage.mangary.com/content/c1/2/a.webp',
        'https://storage.mangary.com/content/c1/2/b.webp',
      ]);
    });

    test('whytoon: relative content/ paths resolve against the CDN', () {
      final urls = parseToonaryImages(
        fixture('whytoon_episode.html'),
        cdnPrefix: 'https://gd.whytoon.com/',
      );
      expect(urls, [
        'https://gd.whytoon.com/content/cm1/1/aa.webp',
        'https://gd.whytoon.com/content/cm1/1/bb.webp',
      ]);
    });
  });

  group('toonary configs', () {
    test('listing URLs per site shape', () {
      final mangary = toonaryConfigs.firstWhere((c) => c.id == 'mangary');
      final whytoon = toonaryConfigs.firstWhere((c) => c.id == 'whytoon');
      expect(mangary.listingUri(1).toString(), 'https://mangary.com/latest');
      expect(mangary.listingUri(2).toString(),
          'https://mangary.com/latest?page=2');
      expect(whytoon.listingUri(1).toString(), 'https://whytoon.com/browse');
      expect(whytoon.listingUri(3).toString(),
          'https://whytoon.com/browse/page/3');
    });

    test('search URLs per site shape (?q= server-side filter, 2026-11-01)',
        () {
      final mangary = toonaryConfigs.firstWhere((c) => c.id == 'mangary');
      final whytoon = toonaryConfigs.firstWhere((c) => c.id == 'whytoon');
      expect(mangary.searchUri('divorce', 1).toString(),
          'https://mangary.com/latest?q=divorce');
      final thai = mangary.searchUri('สายเด็ก อัจฉริยะ', 2);
      expect(thai.path, '/latest');
      expect(thai.queryParameters['q'], 'สายเด็ก อัจฉริยะ');
      expect(thai.queryParameters['page'], '2');
      expect(whytoon.searchUri('divorce', 1).toString(),
          'https://whytoon.com/browse?q=divorce');
      expect(whytoon.searchUri('divorce', 3).toString(),
          'https://whytoon.com/browse/page/3?q=divorce');
    });
  });
}

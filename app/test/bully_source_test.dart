import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/data/sources/bully/bully_source.dart';

/// Bully Manga adapter parsers against fixtures trimmed from the LIVE
/// pages (probed 2026-10-18 — the site is a custom static engine, not
/// WordPress/ts, so every selector here is site-specific).
Future<void> main() async {
  final dir = '${Directory.current.path}\\test\\fixtures';
  final listing =
      await File('$dir\\bully_listing.html').readAsString(encoding: utf8);
  final series =
      await File('$dir\\bully_series.html').readAsString(encoding: utf8);
  final chapter =
      await File('$dir\\bully_chapter.html').readAsString(encoding: utf8);

  group('parseBullyListing', () {
    test('cards: url/title/cover-from-data-src/type/chapter-hint', () {
      final items = parseBullyListing(listing, 'https://bully-manga.com');
      expect(items, isNotEmpty);
      final first = items.first;
      // Series URL is absolute from the relative /slug href.
      expect(first.url,
          'https://bully-manga.com/sovereign-infinite-clones');
      expect(first.title,
          contains('Sovereign of the Infinite Clones'));
      // Real cover rides in data-src (src is the default placeholder).
      expect(first.coverUrl,
          'https://bully-manga.com/img/facecat/sovereign-infinite-clones-cover.jpg');
      expect(first.type, 'manhwa');
      // "ตอน 101" badge → chapter count hint.
      expect(first.chapterCountHint, 101);
    });

    test('data:-placeholder covers never leak through', () {
      final items = parseBullyListing(listing, 'https://bully-manga.com');
      for (final s in items) {
        expect(s.coverUrl == null || !s.coverUrl!.contains('data:'), isTrue);
      }
    });
  });

  group('parseBullyGenres', () {
    test('nav /genres/<Term> links, "all" excluded, deduped', () {
      final genres = parseBullyGenres(listing);
      final terms = [for (final g in genres) g.term];
      // The fixture carries the type-group nav; the live page adds the
      // full Thai genre cloud further down (Action, Drama, …).
      expect(terms, containsAll(['Manga', 'Manhwa', 'Manhua']));
      expect(terms, isNot(contains('all')));
      expect(terms.toSet().length, terms.length);
    });
  });

  group('parseBullyDetail', () {
    test('JSON-LD title/cover/description + genres/status/type/chapters', () {
      final d = parseBullyDetail(
          series, 'https://bully-manga.com/chainsaw-man', 'https://bully-manga.com')!;
      expect(d.title, 'Chainsaw Man');
      expect(d.coverUrl,
          'https://bully-manga.com/img/facecat/chainsaw-man-cover.jpg');
      expect(d.description, isNotNull);
      expect(d.tags, containsAll(['ต่อสู้', 'ดราม่า', 'แฟนตาซี']));
      expect(d.status, 'ongoing'); // "On Going" badge
      expect(d.type, 'manga'); // sh-badge-type "MANGA"
      // Fixture carries the first two + last two chapter rows; all map to
      // numeric data-title values and land ascending.
      expect(d.chapters.length, 4);
      expect(d.chapters.first.number, 1);
      expect(d.chapters.last.number, 232);
      expect(d.chapters.first.url,
          'https://bully-manga.com/chainsaw-man-ep0001');
      // Relative Thai stamps ("48 สัปดาห์") resolve to epoch ms.
      expect(d.chapters.first.uploadedAt, isNotNull);
      expect(d.chapters.first.uploadedAt! < DateTime.now().millisecondsSinceEpoch,
          isTrue);
    });
  });

  group('parseBullyImageMap', () {
    test('chapter page script array → absolute urls in order', () {
      final urls =
          parseBullyImageMap(chapter, 'https://bully-manga.com');
      expect(urls.length, greaterThanOrEqualTo(10));
      expect(urls.first,
          'https://bully-manga.com/img/backcat/chainsaw-man-ep0001_1.jpg');
      expect(urls[1],
          'https://bully-manga.com/img/backcat/chainsaw-man-ep0001_2.jpg');
    });
  });

  group('parseRelativeThaiDate', () {
    test('units map to durations; garbage → null', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final week = parseRelativeThaiDate('48 สัปดาห์')!;
      expect(now - week, closeTo(48 * 7 * 86400000, 60000));
      final day = parseRelativeThaiDate('1 วัน')!;
      expect(now - day, closeTo(86400000, 60000));
      expect(parseRelativeThaiDate('ตุลาคม 18, 2026'), isNull);
      expect(parseRelativeThaiDate(''), isNull);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/madara/configs.dart';
import 'package:star_codex/data/sources/madara/madara_source.dart';
import 'package:star_codex/data/sources/miku/miku_source.dart';
import 'package:star_codex/data/sources/hentaithai/hentaithai_source.dart';
import 'package:star_codex/data/sources/source_api.dart';

/// Adult-source adapter parsers against fixtures trimmed from the LIVE
/// pages (probed 2026-10-19). doujin-lc = classic Madara layout;
/// miku-doujin and hentaithai are one-shot custom engines (series page
/// IS the reader).
Future<void> main() async {
  final dir = '${Directory.current.path}\\test\\fixtures';
  Future<String> fixture(String name) =>
      File('$dir\\$name').readAsString(encoding: utf8);

  final lc = MadaraSource(
      madaraConfigs.firstWhere((c) => c.id == 'doujin-lc'), SafeHttp());

  group('doujin-lc (classic Madara)', () {
    test('archive rows: page-item-detail url/title/cover/hint/type',
        () async {
      final items = lc.parseClassicRows(await fixture('lc_archive_rows.html'));
      expect(items, isNotEmpty);
      final first = items.first;
      expect(first.url, startsWith('https://doujin-lc.net/doujin/'));
      expect(first.title, isNotEmpty);
      // Lazy covers: data-src must win over the base64 svg placeholder.
      if (first.coverUrl != null) {
        expect(first.coverUrl, isNot(startsWith('data:')));
      }
      final typed = items.where((s) => s.type != null).toList();
      expect(typed, isNotEmpty, reason: 'manga-title-badges carry the type');
    });

    test('search rows: c-tabs-item__content parse', () async {
      final items = lc.parseClassicRows(await fixture('lc_search_rows.html'));
      expect(items, isNotEmpty);
      expect(items.first.url, startsWith('https://doujin-lc.net/doujin/'));
      expect(items.first.title, isNotEmpty);
    });

    test('classic detail: title/genres/status/chapters', () async {
      final detail = lc.parseClassicDetail(
          await fixture('lc_series.html'), 'https://doujin-lc.net/x/');
      expect(detail.title, isNotEmpty);
      expect(detail.tags, isNotEmpty);
      expect(detail.chapters, isNotEmpty);
      // Chapter URLs are deeper than the series URL (season/chapter path).
      expect(detail.chapters.first.url,
          startsWith('https://doujin-lc.net/doujin/'));
      expect(detail.chapters.first.number, greaterThan(0));
      expect(detail.chapters.last.number,
          greaterThanOrEqualTo(detail.chapters.first.number));
    });

    test('config sanity: classic layout + doujin archive', () {
      final config = madaraConfigs.firstWhere((c) => c.id == 'doujin-lc');
      expect(config.classicLayout, isTrue);
      expect(config.archivePath, 'doujin');
    });
  });

  group('miku-doujin (one-shot WP custom)', () {
    test('listing cards: inz-a href/title/cover', () async {
      final items = parseMikuListing(
          await fixture('miku_listing.html'), 'https://miku-doujin.com');
      expect(items, isNotEmpty);
      expect(items.first.url, startsWith('https://miku-doujin.com/'));
      expect(items.first.title, isNotEmpty);
      expect(items.first.coverUrl, isNotNull);
    });

    test('series = reader: title + single chapter + pages', () async {
      const url = 'https://miku-doujin.com/pohma1/';
      final detail =
          parseMikuDetail(await fixture('miku_series.html'), url, url);
      expect(detail, isNotNull);
      expect(detail!.title, isNotEmpty);
      expect(detail.title.toLowerCase(), isNot(contains('miku-doujin')));
      expect(detail.chapters, hasLength(1));
      expect(detail.chapters.first.url, url);
      // Tags come from /genre/ links (2026-10-28 — was /category/).
      expect(detail.tags, contains('NTR'));
      expect(detail.tags, contains('โล'));
      final pages = parseMikuPages(await fixture('miku_series.html'));
      expect(pages, isNotEmpty);
      expect(pages.first, startsWith('https://miku-doujin.com/uploads/'));
      expect(pages.every((u) => !u.startsWith('data:')), isTrue);
    });

    test('genre cloud: /genre/<term> links, Thai terms decoded', () {
      const html = '<a href="https://miku-doujin.com/genre/NTR/">NTR</a>'
          '<a href="https://miku-doujin.com/genre/%E0%B9%82%E0%B8%A5/">โล</a>';
      final genres = parseMikuGenres(html);
      expect(genres.map((g) => g.term), containsAll(['NTR', 'โล']));
      // Nav /category/ links must NOT leak into the cloud.
      expect(genres.map((g) => g.term), isNot(contains('ติดต่อเรา')));
    });
  });

  group('hentaithai (forum one-shot)', () {
    test('listing cards: number-even/odd href from title attr', () async {
      final items = parseHentaiThaiListing(await fixture('ht_listing.html'));
      expect(items, isNotEmpty);
      expect(items.first.url, startsWith('https://hentaithai.net/t'));
      expect(items.first.title, isNotEmpty);
    });

    test('/page-N feed listing (2026-10-23 probe): col-6 card family, '
        '24 per page, newest-first, cover + date from the style block',
        () async {
      final items =
          parseHentaiThaiFeedListing(await fixture('ht_feed_page.html'));
      expect(items, hasLength(24),
          reason: 'the /page-N listing renders exactly 24 cards');
      expect(items.first.url, 'https://hentaithai.net/t51966',
          reason: 'the feed page is newest-first');
      for (var i = 1; i < items.length; i++) {
        final prev = int.parse(
            items[i - 1].url.split('/t').last.split(RegExp(r'[^0-9]')).first);
        final cur = int.parse(
            items[i].url.split('/t').last.split(RegExp(r'[^0-9]')).first);
        expect(prev, greaterThan(cur),
            reason: 'thread ids descend down the page');
      }
      expect(items.first.coverUrl, isNotNull,
          reason: 'cover = the sibling <style> background');
      expect(items.first.coverUrl, contains('s1.hentaithai.net'));
      expect(items.first.lastUpdatedMs, isNotNull,
          reason: 'the CDN path carries the upload date');
    });

    test('tag pages render the col-6 family, not number-even/odd — the '
        'union parser keeps genre browse alive (2026-10-23 review fix)',
        () async {
      final body = await fixture('ht_tag_page.html');
      expect(parseHentaiThaiListing(body), isEmpty,
          reason: 'the landing-grid parser alone finds nothing on a tag '
              'page (this was the genre-browse bug)');
      final items = parseHentaiThaiUnionListing(body);
      expect(items, hasLength(24));
      expect(items.first.url, startsWith('https://hentaithai.net/t'));
      expect(items.first.coverUrl, contains('s1.hentaithai.net'));
      expect(items.first.lastUpdatedMs, isNotNull);
    });

    test('listing cards carry the CDN-path upload date (2026-10-21 probe: '
        'no <time> stamps anywhere — the date lives only in the image path)',
        () async {
      final items = parseHentaiThaiListing(await fixture('ht_listing.html'));
      expect(items.first.lastUpdatedMs, isNotNull,
          reason: 'cards must sort by date like every other source');
      expect(items.first.coverUrl, contains('/thai/'),
          reason: 'the style-block background is also the card cover');
    });

    test('thread: title + single chapter + s1 CDN pages only', () async {
      const url = 'https://hentaithai.net/t51996';
      final detail =
          parseHentaiThaiDetail(await fixture('ht_thread.html'), url);
      expect(detail, isNotNull);
      expect(detail!.title, isNotEmpty);
      expect(detail.chapters, hasLength(1));
      expect(detail.chapters.first.url, url);
      expect(detail.chapters.first.uploadedAt, isNotNull,
          reason: 'chapter stamp from the first image path');
      final pages = parseHentaiThaiPages(await fixture('ht_thread.html'));
      expect(pages, isNotEmpty);
      expect(pages.every((p) => p.contains('hentaithai.net/thai/')), isTrue);
    });

    test('thread with /image/<year>/ pages parses (2026-10-22 bug: t51989 '
        'served its pages under /image/…, not /thai/… — the detail page '
        'failed with "can\'t load")', () async {
      const url = 'https://hentaithai.net/t51989';
      final detail = parseHentaiThaiDetail(
        await fixture('ht_thread_image_variant.html'),
        url,
      );
      expect(detail, isNotNull,
          reason: 'the /image/ layout must yield pages, not a parse error');
      expect(detail!.chapters, hasLength(1));
      expect(detail.chapters.first.uploadedAt, isNotNull,
          reason: 'the date lives in the /image/<year>/<yyyy-mm-dd>/ path too');
      final pages = parseHentaiThaiPages(
        await fixture('ht_thread_image_variant.html'),
      );
      expect(pages, isNotEmpty);
      expect(pages.every((p) => p.contains('hentaithai.net/image/')), isTrue);
      expect(pages.every((p) => !p.contains('/image/other/')), isTrue,
          reason: 'favicon/sticker/credit are not page images');
      expect(pages.every((p) => !p.contains('/image/sticker/')), isTrue);
    });

    test('benign Cloudflare JSD snippet is NOT a challenge (2026-10-19 '
        'on-device report: every fetch threw cloudflare)', () async {
      // The REAL homepage embeds Cloudflare's JS-detect script; the old
      // marker check treated that as a challenge page and hentaithai never
      // rendered. looksLikeCloudflarePage must stay false for it.
      final body = '<html><head>'
          '<script src="//hentaithai.net/cdn-cgi/challenge-platform/scripts/'
          'jsd/main.js"></script>'
          '</head><body>${await fixture('ht_listing.html')}</body></html>';
      expect(looksLikeCloudflarePage(body), isFalse);
      final http = SafeHttp(fetcher: (uri, options) async {
        return Response<List<int>>(
          data: utf8.encode(body),
          statusCode: 200,
          requestOptions: RequestOptions(path: uri.toString()),
        );
      });
      final items = await HentaiThaiSource(http).latest();
      expect(items, isNotEmpty);
    });

    test('a real block page IS detected', () {
      expect(
          looksLikeCloudflarePage(
              '<title>Attention Required! | Cloudflare</title>'),
          isTrue);
      expect(
          looksLikeCloudflarePage('<title>Just a moment...</title>'),
          isTrue);
    });
  });
}

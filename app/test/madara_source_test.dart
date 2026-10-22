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
  final tiles = await File('$dir\\slow_tiles.html')
      .readAsString(encoding: utf8);

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
    test(
      'AVIF-only covers are dropped (no decoder ⇒ never renderable)',
      () async {
        final items = await slowMangaServing(tiles).latest();
        final poison = items.firstWhere((s) => s.title.contains('Poison'));
        expect(poison.coverUrl, isNull);
      },
    );

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

    test(
      'WP Fastest Cache lazy attribute (data-wpfc-original-src) wins over '
      'the base64 src placeholder — fin-manga enabled it 2026-10-23 and '
      'every Fin cover went placeholder',
      () async {
        const wpfc = '''
<div class="listupd"><div class="bs"><div class="bsx">
  <a href="https://www.fin-manga.com/wpfc-title/" title="WPFC Title">
   <div class="limit"><img onload="Wpfcll.r(this,true);"
        src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
        data-wpfc-original-src="https://www.fin-manga.com/wp-content/uploads/2026/06/real-cover.jpg"/></div>
  </a>
 </div></div></div>''';
        final items = await slowMangaServing(wpfc).latest();
        expect(items, hasLength(1));
        expect(
          items.single.coverUrl,
          'https://www.fin-manga.com/wp-content/uploads/2026/06/real-cover.jpg',
        );
      },
    );
  });

  group('latest() leads with the homepage grid (2026-10-22)', () {
    // Homepage: one go/dark-style .chfiv tile (series link + stamp), one
    // slow-manga-style .epxdate tile (chapter link only), and a popularity
    // slider tile with NO time label (must never inject).
    const home = '''
<div class="listupd">
 <div class="bs"><div class="bsx">
  <a href="https://www.slow-manga.net/manga/myst/" title="Myst Might Mayhem">
   <div class="limit"><img src="https://www.slow-manga.net/myst.jpg"/></div>
   <div class="bigor">
    <div class="tt"><a href="https://www.slow-manga.net/manga/myst/" title="Myst Might Mayhem">Myst Might Mayhem</a></div>
    <ul class="chfiv"><li><a href="x"><span class="fivchap">ตอนที่ 121</span><span class="fivtime">6 ชั่วโมง</span></a></li></ul>
   </div></a>
 </div></div>
 <div class="bs"><div class="bsx">
  <a href="https://www.slow-manga.com/heal-10/" title="Academy Store 10">
   <div class="limit"><img src="https://www.slow-manga.net/heal.jpg"/></div>
   <div class="bigor"><div class="tt">Academy Store</div><div class="epxs">ตอนที่ 10</div></div>
   <div class="epxdate text-center">38 วินาที ที่แล้ว</div>
 </a></div></div>
</div>
<div class="listupd popularslider"><div class="bs"><div class="bsx">
  <a href="https://www.slow-manga.net/manga/pop/" title="Pop Series"><div class="bigor"><div class="tt">Pop Series</div></div></a>
</div></div></div>''';
    // Archive page: Myst (same URL — deduped), Academy Store (stamp
    // BORROWED from the grid by title), Other (kept as-is, in order).
    const archive = '''
<div class="listupd">
 <div class="bs"><div class="bsx"><a href="https://www.slow-manga.net/manga/myst/" title="Myst Might Mayhem"><img src="https://www.slow-manga.net/myst.jpg"/><div class="epxs">ตอนที่ 121</div></a></div></div>
 <div class="bs"><div class="bsx"><a href="https://www.slow-manga.net/manga/academy-store/" title="Academy Store"><img src="https://www.slow-manga.net/heal.jpg"/><div class="epxs">ตอนที่ 10</div></a></div></div>
 <div class="bs"><div class="bsx"><a href="https://www.slow-manga.net/manga/other/" title="Other Series"><img src="https://www.slow-manga.net/other.jpg"/><div class="epxs">ตอนที่ 5</div></a></div></div>
</div>''';

    MadaraSource servingTwo() => MadaraSource(
      madaraConfigs.firstWhere((c) => c.id == 'slow-manga'),
      SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async => Response<List<int>>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: Uint8List.fromList(
            const Utf8Encoder().convert(uri.path == '/' ? home : archive),
          ),
        ),
        delay: (_) async {},
      ),
    );

    test(
      'grid entries inject first with stamps; archive tail dedupes',
      () async {
        final items = await servingTwo().latest();
        expect(items, hasLength(3)); // Myst (grid), Academy, Other
        expect(items[0].url, 'https://www.slow-manga.net/manga/myst/');
        expect(items[0].lastUpdatedMs, isNotNull);
        expect(items[0].chapterCountHint, 121);
        expect(items[0].coverUrl, endsWith('myst.jpg'));
        // Chapter-link grid entry can't inject — its ARCHIVE twin borrows
        // the precise stamp by title instead.
        expect(items[1].url, endsWith('/manga/academy-store/'));
        expect(items[1].lastUpdatedMs, isNotNull);
        expect(items[2].url, endsWith('/manga/other/')); // no grid hit
        expect(items[2].lastUpdatedMs, isNull);
      },
    );

    test('grid parse failure degrades to archive-only', () async {
      final src = MadaraSource(
        madaraConfigs.firstWhere((c) => c.id == 'slow-manga'),
        SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async => Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: uri.path == '/' ? 403 : 200,
            data: Uint8List.fromList(const Utf8Encoder().convert(archive)),
          ),
          delay: (_) async {},
        ),
      );
      final items = await src.latest();
      expect(items.map((s) => s.title), contains('Myst Might Mayhem'));
    });
  });

  group('grid labels anchor at the cache-generation time (2026-10-23)',
      () {
    // WP Fastest Cache + the CF edge serve the homepage ~a day old; a
    // "24 วินาที" label inside is true only at page generation (user
    // report: fin/up cards stuck at "24 วินาที" for days).
    const home = '''
<div class="listupd">
 <div class="bs"><div class="bsx">
  <a href="https://www.fin-manga.com/manga/myst/" title="Myst Might Mayhem">
   <div class="limit"><img src="https://www.fin-manga.com/myst.jpg"/></div>
   <div class="bigor">
    <div class="tt"><a href="https://www.fin-manga.com/manga/myst/" title="Myst Might Mayhem">Myst Might Mayhem</a></div>
    <ul class="chfiv"><li><a href="x"><span class="fivtime">24 วินาที</span></a></li></ul>
   </div></a>
 </div></div>
</div>''';

    MadaraSource serving({Map<String, List<String>>? headers}) =>
        MadaraSource(
          madaraConfigs.firstWhere((c) => c.id == 'fin-manga'),
          SafeHttp(
            rateLimiter: RateLimiter(seed: 1),
            fetcher: (uri, options) async => Response<List<int>>(
              requestOptions: RequestOptions(path: uri.toString()),
              statusCode: 200,
              data: Uint8List.fromList(const Utf8Encoder().convert(home)),
              headers: Headers.fromMap(headers ?? const {}),
            ),
            delay: (_) async {},
          ),
        );

    test('Last-Modified anchors the label exactly (not at fetch-now)',
        () async {
      // 21 h stale, second-truncated (HttpDate carries no sub-seconds).
      final utcNow = DateTime.now().toUtc();
      final lm = DateTime.utc(utcNow.year, utcNow.month, utcNow.day,
              utcNow.hour, utcNow.minute, utcNow.second)
          .subtract(const Duration(hours: 21));
      final stamps = await serving(headers: {
        'Last-Modified': [HttpDate.format(lm)],
      }).recentStamps();
      expect(stamps, hasLength(1));
      expect(stamps.single.stampMs, lm.millisecondsSinceEpoch - 24 * 1000);
    });

    test('no anchor header keeps the old fetch-now behavior', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      final stamps = await serving().recentStamps();
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(
        stamps.single.stampMs,
        inInclusiveRange(before - 24 * 1000, after),
      );
    });

    test('Date − Age anchors when Last-Modified is absent', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final stamps = await serving(headers: {
        'Date': [HttpDate.format(DateTime.fromMillisecondsSinceEpoch(now, isUtc: true))],
        'Age': ['900'],
      }).recentStamps();
      expect(
        stamps.single.stampMs,
        inInclusiveRange(now - 900 * 1000 - 24 * 1000 - 2000, now - 900 * 1000),
      );
    });
  });
}

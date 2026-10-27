import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/nekopost/nekopost_crypto.dart';
import 'package:star_codex/data/sources/nekopost/nekopost_source.dart';

/// Live-probed fixtures (www.nekopost.net, 2026-10-17) committed under
/// test/fixtures/nekopost/ — the whole adapter runs offline through the
/// injectable SafeHttp fetcher (Plan/06 §DoD).
String fixture(String name) =>
    File('test/fixtures/nekopost/$name').readAsStringSync();

/// Fake transport: matches URL + JSON body → canned bytes, and records
/// the last request body so tests can assert the wire format.
class FakeApi {
  final handlers = <bool Function(Uri, Object?)>[];
  final responses = <List<int>>[];
  Object? lastBody;

  void on(bool Function(Uri, Object?) match, String body) {
    handlers.add(match);
    responses.add(utf8.encode(body));
  }

  SafeHttp http() => SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, Options options) async {
          final body = options.extra?['safe_http_body'];
          lastBody = body;
          for (var i = 0; i < handlers.length; i++) {
            if (handlers[i](uri, body)) {
              return Response<List<int>>(
                requestOptions:
                    RequestOptions(path: uri.toString(), data: body),
                statusCode: 200,
                data: responses[i],
              );
            }
          }
          return Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 404,
            data: utf8.encode('{"message":"Not Found"}'),
          );
        },
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nekopost_crypto', () {
    test('decrypts the live cinfo payload (OpenSSL salted + AeyTest)', () {
      final plain = decryptCryptoJs(fixture('nekopost-cinfo-encrypted.txt'));
      final json = jsonDecode(plain) as Map<String, Object?>;
      expect(json['projectId'], '4013');
      expect(json['pageCount'], 25);
      final pages = json['pageItem'] as List<Object?>;
      expect(pages, hasLength(25));
      expect((pages.first as Map<String, Object?>)['fileName'], '1.jpg');
    });

    test('rejects garbage', () {
      expect(() => decryptCryptoJs('aGVsbG8='), throwsFormatException);
    });
  });

  group('NekopostSource (offline via fixtures)', () {
    late FakeApi api;
    late NekopostSource source;

    setUp(() {
      api = FakeApi();
      api.on((u, b) =>
              u.path.endsWith('/api/project/latest') &&
              (b as Map)['type'] == 'f',
          '{"listChapter":null}');
      api.on((u, _) => u.path.endsWith('/api/project/latest'),
          fixture('nekopost-latest.json'));
      api.on((u, _) => u.path.endsWith('/api/project/search'),
          fixture('nekopost-search.json'));
      api.on((u, b) =>
              u.path.endsWith('/api/project/detail2') &&
              (b as Map)['pid'] == 4013,
          fixture('nekopost-detail-manga.json'));
      api.on((u, b) =>
              u.path.endsWith('/api/project/detail2') &&
              (b as Map)['pid'] == 8262,
          fixture('nekopost-detail-novel-8262.json'));
      api.on((u, b) =>
              u.path.endsWith('/api/handler/cinfo') &&
              (b as Map)['p'] == 8262,
          fixture('nekopost-cinfo-novel-enc.txt'));
      api.on((u, b) =>
              u.path.endsWith('/api/handler/cinfo') &&
              (b as Map)['p'] == 99999,
          fixture('nekopost-cinfo-fullurl-enc.txt'));
      api.on((u, _) => u.path.endsWith('/api/handler/cinfo'),
          fixture('nekopost-cinfo-encrypted.txt'));
      source = NekopostSource(api.http());
    });

    test('latest: series from the m feed, opaque URLs, manga type',
        () async {
      final items = await source.latest();
      expect(items, isNotEmpty);
      expect(items.first.url, 'nekopost:project:15696');
      expect(items.first.type, 'manga');
      expect(items.first.title, contains('โชคร้ายเหลือหลาย'));
      expect(items.first.coverUrl, contains('osemocphoto.com/collectManga'));
    });

    test('search: novels surface as type=novel with chapter hints',
        () async {
      final results = await source.search('one piece');
      expect(results, isNotEmpty);
      final novel = results.firstWhere((r) => r.url == 'nekopost:project:8262');
      expect(novel.type, 'novel');
      expect(novel.chapterCountHint, 12);
      expect(api.lastBody, isA<Map>());
      expect((api.lastBody as Map)['paging'], isNotNull);
    });

    test('detail: manga — tags, status, ascending chapters', () async {
      final detail = await source.detail('nekopost:project:4013');
      expect(detail.title, 'One Piece dj - -A');
      expect(detail.status, 'completed');
      expect(detail.type, 'manga');
      expect(detail.tags, contains('Doujinshi'));
      expect(detail.chapters, hasLength(1));
      expect(detail.chapters.first.url, 'nekopost:chapter:4013:28967');
      expect(detail.chapters.first.number, 0);
    });

    test('detail: novel — typed novel with Thai chapter names', () async {
      final detail = await source.detail('nekopost:project:8262');
      expect(detail.type, 'novel');
      expect(detail.chapters.last.title, contains('ดาบลับ')); // ch 12
      // Early chapters carry an empty PublishDate; later ones are set.
      expect(detail.chapters.map((c) => c.uploadedAt), contains(isNotNull));
    });

    test('pages: decrypted page list sorted by pageNo → osemocphoto URLs',
        () async {
      final pages = await source.pages('nekopost:chapter:4013:28967');
      expect(pages.imageUrls, hasLength(25));
      // Sorted numerically: 1.jpg first, NOT lexicographic 1/10/100…
      expect(pages.imageUrls.first, endsWith('/4013/28967/1.jpg'));
      expect(
          pages.imageUrls[1], endsWith('/4013/28967/10.jpg'));
      expect(pages.imageUrls.first,
          startsWith('https://www.osemocphoto.com/collectManga/4013/'));
    });

    test('pages: full-URL pageName used as-is (site rebuild 2026-10-28)',
        () async {
      final pages = await source.pages('nekopost:chapter:99999:88888');
      expect(pages.imageUrls, hasLength(1));
      expect(
        pages.imageUrls.single,
        'https://fs.osemocphoto.com/collectManga/99999/88888/x.jpg',
      );
    });

    test('novelText: HTML → \\n\\n paragraphs, Thai kept, style stripped',
        () async {
      final text = await source.novelText('nekopost:chapter:8262:86915');
      expect(text, isNotNull);
      expect(text!, contains('ตอนที่ 12 ดาบลับ'));
      expect(text.contains('style='), isFalse);
      expect(text.contains('{file_fs}'), isFalse);
      expect(text.contains('\n\n'), isTrue);
    });
  });
}

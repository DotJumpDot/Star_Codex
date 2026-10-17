import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/net/net_exception.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/utils/image_dimensions.dart';
import 'package:star_codex/core/utils/thai.dart';

void main() {
  group('imageDimensions (header sniffing)', () {
    test('PNG', () {
      final b = Uint8List(24);
      b.setAll(0, [0x89, 0x50, 0x4E, 0x47]);
      // 32-bit BE width=1000 at 16, height=1430 at 20
      b.setAll(16, [0x00, 0x00, 0x03, 0xE8]);
      b.setAll(20, [0x00, 0x00, 0x05, 0x96]);
      final d = imageDimensions(b);
      expect((d!.width, d.height), (1000, 1430));
    });

    test('GIF', () {
      final b = Uint8List(10);
      b.setAll(0, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      b[6] = 0x64; b[7] = 0x00; // 100
      b[8] = 0xC8; b[9] = 0x00; // 200
      final d = imageDimensions(b);
      expect((d!.width, d.height), (100, 200));
    });

    test('JPEG SOF0', () {
      final b = Uint8List.fromList([
        0xFF, 0xD8,             // SOI
        0xFF, 0xE0, 0x00, 0x04, // APP0, length 4 (2 length bytes + 2 payload)
        0x41, 0x42,             // APP0 payload
        0xFF, 0xC0, 0x00, 0x0B, // SOF0, length 11
        0x08,                   // precision
        0x05, 0x96,             // height 1430
        0x03, 0xE8,             // width 1000
      ]);
      final d = imageDimensions(b);
      expect((d!.width, d.height), (1000, 1430));
    });

    test('WebP VP8X canvas', () {
      final b = Uint8List(31);
      b.setAll(0, [0x52, 0x49, 0x46, 0x46]); // RIFF
      b.setAll(8, [0x57, 0x45, 0x42, 0x50]); // WEBP
      b.setAll(12, 'VP8X'.codeUnits);
      // canvas width-1 = 999 (0x03E7), height-1 = 1429 (0x0595), 24-bit LE
      b[24] = 0xE7; b[25] = 0x03; b[26] = 0x00;
      b[27] = 0x95; b[28] = 0x05; b[29] = 0x00;
      final d = imageDimensions(b);
      expect((d!.width, d.height), (1000, 1430));
    });

    test('garbage → null', () {
      expect(imageDimensions(Uint8List(20)), isNull);
    });
  });

  group('SafeHttp retries (Plan/04 §5)', () {
    // Loopback servers are forbidden by the security rule itself, so retry
    // behavior is tested through an injected fetcher.
    SafeHttp httpWith(SafeHttpFetcher fetcher) => SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: fetcher,
          delay: (_) async {}, // no real backoff sleeps in tests
        );

    final okUri = Uri.parse('https://www.example.com/x');

    test('500, 500, 200 → succeeds on 3rd attempt, 3 calls total', () async {
      var calls = 0;
      final http = httpWith((uri, options) async {
        calls++;
        if (calls < 3) {
          throw DioException(
            requestOptions: RequestOptions(path: uri.toString()),
            response: Response<List<int>>(
              requestOptions: RequestOptions(path: uri.toString()),
              statusCode: 500,
            ),
            type: DioExceptionType.badResponse,
          );
        }
        return Response<List<int>>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: [104, 105],
        );
      });

      final bytes = await http.getBytes(okUri);
      expect(bytes, [104, 105]);
      expect(calls, 3);
    });

    test('404 is not retried (clean not-found)', () async {
      var calls = 0;
      final http = httpWith((uri, options) async {
        calls++;
        throw DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          response: Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 404,
          ),
          type: DioExceptionType.badResponse,
        );
      });

      await expectLater(
        () => http.getBytes(okUri),
        throwsA(isA<NetException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
      expect(calls, 1);
    });

    test('three 500s in a row → NetException after 3 attempts', () async {
      var calls = 0;
      final http = httpWith((uri, options) async {
        calls++;
        throw DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          response: Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 503,
          ),
          type: DioExceptionType.badResponse,
        );
      });

      await expectLater(
        () => http.getBytes(okUri),
        throwsA(isA<NetException>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
      expect(calls, 3);
    });
  });

  group('SafeHttp URL validation (Plan/04 §2)', () {
    final http = SafeHttp(rateLimiter: RateLimiter(seed: 1));

    Future<void> expectRejected(String url) async {
      // getBytes validates before any network touch: a rejection proves the
      // guard fired (no listener needed).
      await expectLater(
        () => http.getBytes(Uri.parse(url)),
        throwsA(isA<NetException>()),
      );
    }

    test('rejects file:// and ftp://', () async {
      await expectRejected('file:///C:/Windows/win.ini');
      await expectRejected('ftp://example.com/pub');
    });

    test('rejects localhost and loopback', () async {
      await expectRejected('http://localhost/');
      await expectRejected('http://sub.localhost/');
      await expectRejected('http://127.0.0.1/');
      await expectRejected('http://127.8.9.10/');
      await expectRejected('http://[::1]/');
    });

    test('rejects unspecified and private ranges', () async {
      await expectRejected('http://0.0.0.0/');
      await expectRejected('http://[::]/');
      await expectRejected('http://10.0.0.1/');
      await expectRejected('http://172.16.0.1/');
      await expectRejected('http://172.31.255.255/');
      await expectRejected('http://192.168.1.1/');
      await expectRejected('http://169.254.169.254/'); // cloud metadata
      await expectRejected('http://169.254.1.1/'); // link-local
      await expectRejected('http://[fe80::1]/');
      await expectRejected('http://[fc00::1]/');
      await expectRejected('http://[fd12::1]/');
    });

    test('getHtml decodes UTF-8 (Thai text intact)', () async {
      // Regression: getHtml once decoded as Latin-1, mojibake-ing every
      // Thai string from the sites (titles, tags, ตอนที่ labels, dates).
      const thai = '<title>มังงะ ตอนที่ 155.5 มิถุนายน</title>';
      final utf8Bytes = Uint8List.fromList(
          const Utf8Encoder().convert(thai));
      final http = SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async => Response<List<int>>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: utf8Bytes,
        ),
        delay: (_) async {},
      );
      final html = await http.getHtml(Uri.parse('https://www.example.com/x'));
      expect(html, thai);
    });
  });

  group('RateLimiter (Plan/04 §4)', () {
    test('strict host: 5 rapid acquires never exceed 2 concurrent', () async {
      final limiter = RateLimiter(seed: 7);
      var inFlight = 0;
      var maxInFlight = 0;

      Future<void> task() async {
        final release = await limiter.acquire('www.example.com');
        inFlight++;
        maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        inFlight--;
        release();
      }

      await Future.wait([task(), task(), task(), task(), task()]);
      expect(maxInFlight, lessThanOrEqualTo(2));
    });

    test('observes the min gap between starts on one host', () async {
      final limiter = RateLimiter(seed: 7);
      final starts = <int>[];

      Future<void> task() async {
        final release = await limiter.acquire('gap.example.com');
        starts.add(DateTime.now().millisecondsSinceEpoch);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        release();
      }

      // 3 sequential-ish tasks: start gaps must be >= ~700ms minus jitter
      // slop (jitter only ever delays, never advances).
      final sw = Stopwatch()..start();
      await Future.wait([task(), task(), task()]);
      final wall = sw.elapsedMilliseconds;
      expect(starts.length, 3);
      expect(wall, greaterThanOrEqualTo(1300), reason:
          '3 starts on a strict host need >= 2 gaps of 700ms');
    });

    test('image-class hosts get relaxed rules', () async {
      final limiter = RateLimiter(seed: 7);
      limiter.registerImageHost('img9.cdn-fast.net');
      expect(limiter.isImageHost('img9.cdn-fast.net'), isTrue);
      expect(limiter.isImageHost('deep.img9.cdn-fast.net'), isTrue);
      expect(limiter.isImageHost('www.go-manga.com'), isFalse);

      var inFlight = 0;
      var maxInFlight = 0;
      Future<void> task() async {
        final release = await limiter.acquire('img9.cdn-fast.net');
        inFlight++;
        maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
        // Hold long enough that even worst-case jitter (+300ms per gap)
        // leaves 3+ tasks overlapping: last start <= 3*(200+300) = 1500ms,
        // first release at 1000ms — tasks 2..4 are all still in flight.
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        inFlight--;
        release();
      }

      await Future.wait([task(), task(), task(), task()]);
      expect(maxInFlight, greaterThanOrEqualTo(3), reason:
          'image hosts allow 4 concurrent');
    });

    test('different hosts do not queue behind each other', () async {
      final limiter = RateLimiter(seed: 7);
      final sw = Stopwatch()..start();
      final release1 = await limiter.acquire('a.example.com');
      final release2 = await limiter.acquire('b.example.com');
      expect(sw.elapsedMilliseconds, lessThan(500));
      release1();
      release2();
    });
  });

  group('parseChapterNumber (L4)', () {
    test('Thai forms', () {
      expect(parseChapterNumber('ตอนที่ 922'), 922);
      expect(parseChapterNumber('ตอนที่ 155.5'), 155.5);
      expect(parseChapterNumber('- ตอนที่ 9 [จบ]'), 9);
      expect(parseChapterNumber('ตอน 12'), 12);
    });
    test('English forms', () {
      expect(parseChapterNumber('Chapter 45'), 45);
      expect(parseChapterNumber('chapter 45'), 45);
      expect(parseChapterNumber('Ch. 7'), 7);
      expect(parseChapterNumber('Ch 7'), 7);
    });
    test('bare numbers and fallbacks', () {
      expect(parseChapterNumber('920'), 920);
      expect(parseChapterNumber('Episode 3.2 — finale'), 3.2);
      expect(parseChapterNumber('no number here'), isNull);
    });
  });

  group('parseSiteDate', () {
    test('Thai month names', () {
      final ms = parseSiteDate('มิถุนายน 8, 2026');
      final dt = DateTime.fromMillisecondsSinceEpoch(ms!, isUtc: true);
      expect((dt.year, dt.month, dt.day), (2026, 6, 8));
    });
    test('English months and ISO', () {
      final dt = DateTime.fromMillisecondsSinceEpoch(
          parseSiteDate('June 8, 2026')!, isUtc: true);
      expect((dt.year, dt.month, dt.day), (2026, 6, 8));
      final iso = DateTime.fromMillisecondsSinceEpoch(
          parseSiteDate('2026-06-08')!, isUtc: true);
      expect((iso.year, iso.month, iso.day), (2026, 6, 8));
    });
    test('garbage → null', () {
      expect(parseSiteDate('3 วันก่อน'), isNull);
      expect(parseSiteDate(''), isNull);
    });
  });
}

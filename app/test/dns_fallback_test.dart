// DoH fallback (2026-11-07): True Internet's resolver answers NXDOMAIN
// for slow-manga.net (site fine via 8.8.8.8/1.1.1.1). These tests pin
// the pure pieces: answer parsing (public IPv4s only), the
// positive/negative cache, single-flight, and the endpoint fallback.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/dns_fallback.dart';

String _cfJson(List<Map<String, Object>> answers) =>
    jsonEncode({'Status': 0, 'Answer': answers});

void main() {
  group('parseDohAnswers', () {
    test('keeps public A records in order', () {
      final body = _cfJson([
        {'name': 'x.net.', 'type': 5, 'data': 'target.net'}, // CNAME
        {'name': 'x.net.', 'type': 1, 'data': '104.21.64.125'},
        {'name': 'x.net.', 'type': 28, 'data': '2606:4700::6815'}, // AAAA
        {'name': 'x.net.', 'type': 1, 'data': '172.67.185.23'},
      ]);
      expect(parseDohAnswers(body), ['104.21.64.125', '172.67.185.23']);
    });

    test('drops private/loopback/link-local answers (SSRF guard)', () {
      final body = _cfJson([
        {'name': 'x.net.', 'type': 1, 'data': '10.0.0.5'},
        {'name': 'x.net.', 'type': 1, 'data': '192.168.1.2'},
        {'name': 'x.net.', 'type': 1, 'data': '172.16.0.1'},
        {'name': 'x.net.', 'type': 1, 'data': '169.254.169.254'},
        {'name': 'x.net.', 'type': 1, 'data': '127.0.0.1'},
        {'name': 'x.net.', 'type': 1, 'data': '0.0.0.0'},
      ]);
      expect(parseDohAnswers(body), isEmpty);
    });

    test('malformed bodies parse to empty, never throw', () {
      expect(parseDohAnswers('not json'), isEmpty);
      expect(parseDohAnswers('{"Answer": "oops"}'), isEmpty);
      expect(parseDohAnswers('{"Status":2}'), isEmpty); // SERVFAIL, no Answer
    });
  });

  group('DnsFallback.resolve', () {
    test('cloudflare first, google as fallback endpoint', () async {
      final asked = <Uri>[];
      final dns = DnsFallback(fetchJson: (uri) async {
        asked.add(uri);
        if (uri.host == 'cloudflare-dns.com') return null; // unreachable
        return _cfJson([
          {'name': 's.net.', 'type': 1, 'data': '104.21.64.125'},
        ]);
      });
      expect(await dns.resolve('slow-manga.net'), ['104.21.64.125']);
      expect(asked.map((u) => u.host).toList(),
          ['cloudflare-dns.com', 'dns.google']);
    });

    test('single-flight: concurrent resolves fire one DoH query',
        () async {
      var calls = 0;
      final dns = DnsFallback(fetchJson: (uri) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _cfJson([
          {'name': 's.net.', 'type': 1, 'data': '104.21.64.125'},
        ]);
      });
      final results = await Future.wait([
        dns.resolve('slow-manga.net'),
        dns.resolve('slow-manga.net'),
        dns.resolve('SLOW-MANGA.net'), // case-insensitive key
      ]);
      expect(calls, 1);
      expect(results, everyElement(['104.21.64.125']));
    });

    test('negative result cached — no query storm while offline',
        () async {
      var calls = 0;
      var now = DateTime(2026, 11, 7, 12);
      final dns = DnsFallback(
        fetchJson: (uri) async {
          calls++;
          return null;
        },
        clock: () => now,
      );
      expect(await dns.resolve('dead.example'), isEmpty);
      expect(await dns.resolve('dead.example'), isEmpty);
      expect(calls, 2); // cloudflare + google, ONCE
      expect(dns.ipFor('dead.example'), isNull);
    });

    test('positive answer expires after TTL and refetches', () async {
      var calls = 0;
      var now = DateTime(2026, 11, 7, 12);
      String jsonBody() => _cfJson([
            {'name': 's.net.', 'type': 1, 'data': '104.21.64.125'},
          ]);
      final dns = DnsFallback(
        fetchJson: (uri) async {
          calls++;
          return uri.host == 'cloudflare-dns.com' ? jsonBody() : null;
        },
        clock: () => now,
      );
      await dns.resolve('slow-manga.net');
      expect(dns.ipFor('slow-manga.net'), '104.21.64.125');
      now = now.add(const Duration(minutes: 11)); // past the 10-min TTL
      expect(dns.ipFor('slow-manga.net'), isNull); // expired
      await dns.resolve('slow-manga.net'); // refetch
      expect(calls, 2);
    });
  });
}

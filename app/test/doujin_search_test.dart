// Doujin-page search behavior (2026-11-04 round): miku's real search
// endpoint is the theme's ajax POST (the /search/?keyword= page only
// hosts the widget); hentaithai has NO server-side search — its form is
// a Google Programmable Search engine whose index returns zero results
// even in a real desktop browser (probed 'test'/'a'/'นรก' in live
// Chrome), and the .com search page the widget ships on serves an
// INVALID TLS certificate the app can never accept — so hentaithai
// returns an EMPTY result, never a throw (a throw rendered the red
// "failed" dot the user reported).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/hentaithai/hentaithai_source.dart';
import 'package:star_codex/data/sources/miku/miku_source.dart';

void main() {
  test('hentaithai search returns empty (no server-side search)', () async {
    final s = HentaiThaiSource(SafeHttp(rateLimiter: RateLimiter(seed: 1)));
    expect(await s.search('anything'), isEmpty);
  });

  test('miku search: POSTs keysearch to the ajax endpoint and parses '
      'the inz-card fragment', () async {
    Options? opts;
    Uri? posted;
    final fixture = File(
      '${Directory.current.path}\\test\\fixtures\\miku_search.html',
    ).readAsStringSync(encoding: utf8);
    final s = MikuDoujinSource(
      SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (uri, options) async {
          posted = uri;
          opts = options;
          return Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 200,
            data: Uint8List.fromList(const Utf8Encoder().convert(fixture)),
          );
        },
        delay: (_) async {},
      ),
    );

    final cards = await s.search('test');
    expect(posted.toString(),
        'https://miku-doujin.com/controller/search/general/');
    expect(opts!.method, 'POST');
    final body = opts!.extra?['safe_http_body'] as String;
    expect(body, 'keysearch=test');
    expect(cards, isNotEmpty);
    expect(cards.first.url, startsWith('https://miku-doujin.com/'));
    expect(cards.first.title, isNotEmpty);
  });
}

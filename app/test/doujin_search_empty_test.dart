// Sites with no server-side search return EMPTY results, never a throw —
// a throw surfaced their search row with a red "failed" dot on every
// Doujin-page search (user report 2026-11-04), which reads as a bug when
// the site simply has no search to offer.

import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/hentaithai/hentaithai_source.dart';
import 'package:star_codex/data/sources/miku/miku_source.dart';

void main() {
  test('hentaithai search returns empty (form posts to google.com)',
      () async {
    final s = HentaiThaiSource(SafeHttp(rateLimiter: RateLimiter(seed: 1)));
    expect(await s.search('anything'), isEmpty);
  });

  test('miku-doujin search returns empty (?s= ignored, wp-json 404)',
      () async {
    final s = MikuDoujinSource(SafeHttp(rateLimiter: RateLimiter(seed: 1)));
    expect(await s.search('anything'), isEmpty);
  });
}

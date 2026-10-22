import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/utils/page_time.dart';

/// The cache-generation anchor for relative page labels (page_time.dart,
/// PLAN_NOTES 2026-10-23): WP Fastest Cache + the CF edge serve the ts
/// homepages ~a day old, and the labels inside are true only at
/// generation time — the fin/up "stuck at 24 วินาที" bug.
void main() {
  // 2026-10-23 02:20:06 GMT — fin-manga's probed generation time.
  final genMs = DateTime.utc(2026, 10, 23, 2, 20, 6).millisecondsSinceEpoch;
  // Fixed "now": 21 h after generation (the probed staleness).
  final nowMs = genMs + 21 * 3600 * 1000;

  test('last-modified anchors generation', () {
    expect(
      pageGenerationMs(
        {'last-modified': 'Thu, 23 Oct 2026 02:20:06 GMT'},
        nowMs: nowMs,
      ),
      genMs,
    );
  });

  test('date − age anchors the edge-copy age back', () {
    expect(
      pageGenerationMs(
        {
          'date': 'Thu, 23 Oct 2026 23:20:06 GMT',
          'age': '3600',
        },
        nowMs: nowMs,
      ),
      DateTime.utc(2026, 10, 23, 22, 20, 6).millisecondsSinceEpoch,
    );
  });

  test('age ≤ 0 changes nothing', () {
    final date = 'Thu, 23 Oct 2026 23:20:06 GMT';
    expect(
      pageGenerationMs({'date': date, 'age': '0'}, nowMs: nowMs),
      DateTime.utc(2026, 10, 23, 23, 20, 6).millisecondsSinceEpoch,
    );
  });

  test('future anchor clamps to now (bad server clock)', () {
    expect(
      pageGenerationMs(
        {'last-modified': 'Fri, 24 Oct 2026 02:20:06 GMT'},
        nowMs: nowMs,
      ),
      nowMs,
    );
  });

  test('garbage or missing headers → null (caller falls back)', () {
    expect(pageGenerationMs(const {}, nowMs: nowMs), isNull);
    expect(
      pageGenerationMs({'last-modified': 'not a date'}, nowMs: nowMs),
      isNull,
    );
  });

  test('epoch-ish static mtime is distrusted → null', () {
    expect(
      pageGenerationMs(
        {'last-modified': 'Thu, 01 Jan 1970 00:00:01 GMT'},
        nowMs: nowMs,
      ),
      isNull,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/ui/reader/reader_router.dart';

/// Auto-shape detection flags (user reports 2026-10-28 + 2026-11-01):
/// type tags are only as good as the SITE's tagging, so default modes
/// self-correct by page aspect — but an EXPLICIT choice is never
/// second-guessed.
void main() {
  group('autoDetectFlags', () {
    test('untyped: webtoon reader may swap to paged', () {
      final f = autoDetectFlags(null, null);
      expect(f.toPaged, isTrue);
      expect(f.toWebtoon, isFalse);
    });

    test("manhwa-typed: still swaps to paged if pages are manga-shaped", () {
      final f = autoDetectFlags('manhwa', null);
      expect(f.toPaged, isTrue);
      expect(f.toWebtoon, isFalse);
    });

    test("manga-typed: paged reader may swap to webtoon on tall strips", () {
      final f = autoDetectFlags('manga', null);
      expect(f.toPaged, isFalse);
      expect(f.toWebtoon, isTrue);
    });

    test('novel-typed: no auto swaps', () {
      final f = autoDetectFlags('novel', null);
      expect(f.toPaged, isFalse);
      expect(f.toWebtoon, isFalse);
    });

    test('explicit per-series override disables both swaps', () {
      final f = autoDetectFlags('manga', 'webtoon');
      expect(f.toPaged, isFalse);
      expect(f.toWebtoon, isFalse);
    });
  });
}

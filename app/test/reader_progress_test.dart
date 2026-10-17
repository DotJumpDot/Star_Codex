import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/ui/reader/reader_progress.dart';

void main() {
  // Three slots of heights 100/200/300 → offsets 0/100/300.
  final heights = [100.0, 200.0, 300.0];
  final offsets = slotOffsets(heights);

  test('slotOffsets builds prefix sums', () {
    expect(offsets, [0, 100, 300]);
  });

  test('currentPageIndex: first slot below the 40% line (doc 10 §5)', () {
    const viewport = 500.0;
    // At top: the 40% line is at 200 → slot 0 bottom (100) is above it,
    // slot 1 bottom (300) is below → page 1.
    expect(currentPageIndex(offsets, heights, 0, viewport), 1);
    // Deep into slot 2: line at 550+300=... slot 2 bottom 600 > 540 → page 2.
    expect(currentPageIndex(offsets, heights, 240, viewport), 2);
    // Clamps to the last slot past the end.
    expect(currentPageIndex(offsets, heights, 1000, viewport), 2);
    expect(currentPageIndex(const [], const [], 0, viewport), 0);
  });

  test('reachedEnd: within one viewport of max extent', () {
    const viewport = 500.0;
    expect(reachedEnd(0, 1000, viewport), isFalse);
    expect(reachedEnd(500, 1000, viewport), isTrue);
    expect(reachedEnd(0, 0, viewport), isFalse); // no layout yet
  });

  test('shouldAutoNext: last page bottom past 65% viewport (doc 10 §6)', () {
    const viewport = 500.0;
    // Total height 600; last bottom 600 < 0.65*500 + offset until offset ≥ 275.
    expect(shouldAutoNext(offsets, heights, 200, viewport), isFalse);
    expect(shouldAutoNext(offsets, heights, 275, viewport), isTrue);
    expect(shouldAutoNext(const [], const [], 500, viewport), isFalse);
  });
}

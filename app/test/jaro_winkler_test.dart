import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/jaro_winkler.dart';

void main() {
  group('jaroWinkler (standard reference pairs)', () {
    test('identical strings → 1.0', () {
      expect(jaroWinkler('nano machine', 'nano machine'), 1.0);
    });

    test('empty vs non-empty → 0', () {
      expect(jaroWinkler('', 'abc'), 0.0);
      expect(jaroWinkler('abc', ''), 0.0);
    });

    test('both empty → 1.0 (mathematical definition)', () {
      expect(jaroWinkler('', ''), 1.0);
    });

    test('classic transposition pair martha/marhta ≈ 0.9611', () {
      expect(jaroWinkler('martha', 'marhta'), closeTo(0.9611, 0.0005));
    });

    test('classic dixon/dicksonx ≈ 0.8133', () {
      expect(jaroWinkler('dixon', 'dicksonx'), closeTo(0.8133, 0.0005));
    });

    test('lookism vs lukism lands below the merge band (Plan/07 §6)', () {
      final jw = jaroWinkler('lookism', 'lukism');
      expect(jw, closeTo(0.8643, 0.001));
      expect(jw, lessThan(0.88)); // must NOT auto-merge
    });

    test("typo'd name lands in the similar band 0.88–0.95", () {
      final jw = jaroWinkler('ovegeared', 'overgeared');
      expect(jw, inInclusiveRange(0.88, 0.95));
    });

    test('works on Thai strings', () {
      expect(jaroWinkler('นาโน แมชชีน', 'นาโน แมชชีน'), 1.0);
      expect(jaroWinkler('นาโน แมชชีน', 'นาโน แมน'),
          lessThan(1.0)); // prefix boost keeps it high but not equal
    });
  });
}

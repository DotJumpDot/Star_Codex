import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/core/utils/thai.dart';

void main() {
  group('compareTitlesThai (Plan/12 §3)', () {
    test('tone marks never reorder consonants', () {
      // ก่า / กา / ก้า — same consonant, marks ignored → equal keys.
      expect(compareTitlesThai('ก่า', 'กา'), 0);
      expect(compareTitlesThai('ก้า', 'ก่า'), 0);
    });

    test('non-ordering marks ็ ์ ํ are stripped too', () {
      expect(compareTitlesThai('เก๋ง', 'เกง'), 0);
      expect(compareTitlesThai('กังวล', 'กังวลน์'), lessThan(0));
    });

    test('dictionary order: ก < ข < ค < ฆ', () {
      final list = ['ค้าง', 'ฆ่า', 'ขาว', 'กาว']..sort(compareTitlesThai);
      expect(list, ['กาว', 'ขาว', 'ค้าง', 'ฆ่า']);
    });

    test('tone marks do not jump between consonants (DoD wording)', () {
      // 'ไก่' vs 'ไข่' — ก before ข even though both carry ่.
      expect(compareTitlesThai('ไก่', 'ไข่'), lessThan(0));
      expect(compareTitlesThai('ไข่', 'ไก๋'), greaterThan(0));
    });

    test('Latin (lowercased) sorts BEFORE Thai codepoints; case-insensitive',
        () {
      // Codepoint compare: Latin U+0061.. < Thai U+0E01.. — the doc's
      // "(higher codepoints)" parenthetical is inverted, but the spec's
      // algorithm is followed exactly (noted in PLAN_NOTES).
      expect(compareTitlesThai('กาว', 'zeta'), greaterThan(0));
      expect(compareTitlesThai('abc  def', 'ABC DEF'), 0);
    });

    test('thaiSortKey strips exactly the documented marks', () {
      expect(thaiSortKey('ก่๊ำ  ้า'), 'กำ า');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/jaro_winkler.dart';
import 'package:star_codex/core/utils/title_match.dart';
import 'package:star_codex/core/utils/title_norm.dart';

TitleCandidate c(String raw, {List<String> alts = const []}) =>
    TitleCandidate.fromRaw(raw, altTitles: alts);

void main() {
  group('matchTitles — Plan/07 §6 test table', () {
    test('Nano Machine vs "nano machine (แปลไทย)" → merge exact', () {
      expect(matchTitles(c('Nano Machine'), c('nano machine (แปลไทย)')),
          TitleMatchKind.exact);
    });

    test('Nano Machine vs Thai title with English alt → merge alt', () {
      final nano = c('Nano Machine');
      final thai = c('นาโน แมชชีน', alts: ['Nano Machine']);
      expect(matchTitles(nano, thai), TitleMatchKind.alt);
      expect(matchTitles(thai, nano), TitleMatchKind.alt); // symmetric
    });

    test('Lookism vs Lukism → no merge (jw < 0.88)', () {
      expect(jaroWinkler(normalizeTitle('Lookism'), normalizeTitle('Lukism')),
          lessThan(0.88));
      expect(
          matchTitles(c('Lookism'), c('Lukism')), TitleMatchKind.none);
    });

    test('Solo Leveling vs Solo Max-Level Newbie → hint only, no merge', () {
      // jw ≈ 0.899 — inside the doc's 0.88–0.95 "similar" band. The §6 table
      // row says "no": these are never auto-merged, only UI-hinted.
      final kind = matchTitles(c('Solo Leveling'), c('Solo Max-Level Newbie'));
      expect(kind, TitleMatchKind.similar);
      expect(merges(kind), isFalse);
    });

    test('Overgeared vs Overgeared (Novel) → merge (bracket stripped)', () {
      expect(matchTitles(c('Overgeared'), c('Overgeared (Novel)')),
          TitleMatchKind.exact);
    });
  });

  group('band thresholds', () {
    test('jw ≥ 0.95 → fuzzy merge', () {
      expect(matchTitles(c('martha'), c('marhta')), TitleMatchKind.fuzzy);
    });

    test('0.88 ≤ jw < 0.95 → similar hint, never merged', () {
      expect(matchTitles(c('ovegeared'), c('overgeared')),
          TitleMatchKind.similar);
      expect(merges(TitleMatchKind.similar), isFalse);
    });

    test('empty norms never match anything', () {
      expect(matchTitles(c(''), c('')), TitleMatchKind.none);
      expect(matchTitles(c(''), c('Nano Machine')), TitleMatchKind.none);
    });

    test('alt-match wins even when fuzzy would also fire', () {
      expect(matchTitles(c('Overgeared'), c('Overgeared 2', alts: ['Overgeared'])),
          TitleMatchKind.alt);
    });

    test('merges() true for exact/alt/fuzzy only', () {
      expect(merges(TitleMatchKind.exact), isTrue);
      expect(merges(TitleMatchKind.alt), isTrue);
      expect(merges(TitleMatchKind.fuzzy), isTrue);
      expect(merges(TitleMatchKind.similar), isFalse);
      expect(merges(TitleMatchKind.none), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/title_norm.dart';

void main() {
  group('normalizeTitle (Plan/07 §1)', () {
    test('strips Thai bracket credits', () {
      expect(normalizeTitle('Nano Machine (แปลไทย)'), 'nano machine');
    });

    test('keeps Thai titles as-is', () {
      expect(normalizeTitle('นาโน แมชชีน'), 'นาโน แมชชีน');
    });

    test('punctuation becomes spaces (doc example)', () {
      expect(normalizeTitle('SSS-Class Suicide Hunter'),
          'sss class suicide hunter');
    });

    test('bracketed "Novel" suffix stripped', () {
      expect(normalizeTitle('Overgeared (Novel)'), 'overgeared');
    });

    test('drops noise tokens as whole words', () {
      expect(normalizeTitle('Solo Leveling Manhwa'), 'solo leveling');
      expect(normalizeTitle('มังงะ Nano RAW Machine'),
          'nano machine'); // case-insensitive noise
      // "romance" contains "raw"? no — whole-word only:
      expect(normalizeTitle('Romance'), 'romance');
    });

    test('collapses whitespace and trims', () {
      expect(normalizeTitle('  Solo   Leveling  '), 'solo leveling');
    });

    test('empty and punctuation-only → empty', () {
      expect(normalizeTitle(''), '');
      expect(normalizeTitle('!!!'), '');
    });

    test('digits kept (chapter-style titles)', () {
      expect(normalizeTitle('One Piece 100'), 'one piece 100');
    });

    test('mixed Thai-Latin title kept whole', () {
      final t = normalizeTitle('Solo Max-Level Newbie ผู้เล่นหน้าใหม่เลเวลแมกซ์');
      expect(t, 'solo max level newbie ผู้เล่นหน้าใหม่เลเวลแมกซ์');
    });
  });

  group('script helpers (L5)', () {
    test('hasThaiScript', () {
      expect(hasThaiScript('นาโน'), isTrue);
      expect(hasThaiScript('Nano Machine'), isFalse);
      expect(hasThaiScript('Solo Max-Level ผู้เล่น'), isTrue);
    });

    test('isMostlyLatin', () {
      expect(isMostlyLatin('Nano Machine'), isTrue);
      expect(isMostlyLatin('นาโน แมชชีน'), isFalse);
      expect(isMostlyLatin('ผู้เล่นหน้าใหม่เลเวลแมกซ์'), isFalse);
      // mixed, latin majority:
      expect(isMostlyLatin('Solo Max-Level Newbie ผู้เล่น'), isTrue);
      expect(isMostlyLatin(''), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/ui/browse/source_palette.dart';

/// Compact site labels for the browse card chips (user request
/// 2026-10-22): 3+ merged sites used to wrap the chip row to three lines.
void main() {
  test('shortSourceName drops the generic "Manga" word only', () {
    expect(shortSourceName('Slow Manga'), 'Slow');
    expect(shortSourceName('Go-Manga'), 'Go');
    expect(shortSourceName('Up-Manga'), 'Up');
    expect(shortSourceName('Dark Manga'), 'Dark');
    expect(shortSourceName('Bully Manga'), 'Bully');
    expect(shortSourceName('Fin-Manga'), 'Fin');
    expect(shortSourceName('NTR-Manga'), 'NTR');
    // Brands without the word stay as they are.
    expect(shortSourceName('Nekopost'), 'Nekopost');
    expect(shortSourceName('Hentai Thai'), 'Hentai Thai');
    expect(shortSourceName('Doujin-LC'), 'Doujin-LC');
    // A name that IS the word keeps it (never empty).
    expect(shortSourceName('Manga'), 'Manga');
  });
}

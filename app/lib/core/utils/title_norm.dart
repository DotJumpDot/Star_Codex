/// Cross-site title normalization key (Plan/07 §1).
library;

/// Noise tokens dropped at the end (whole words, both languages). "novel"
/// is deliberately absent — "(Novel)" is already stripped by the bracket
/// pass, and "Novel" alone is a meaningful word in Thai listings.
const _noiseTokens = <String>{
  'manga', 'manhwa', 'manhua', 'thai', 'raw', 'eng', //
  'แปลไทย', 'มังงะ', 'การ์ตูน', 'ครั้งแรก',
};

final _bracketed =
    RegExp(r'[(\[【{][^)\]】}]*[)\]】}]'); // (…), [..], 【…】, {…}
final _keepChars = RegExp(r'[^a-z0-9\u0E00-\u0E7F ]');
final _spaces = RegExp(r'\s+');
final _thaiChar = RegExp(r'[\u0E00-\u0E7F]');

/// Normalize a raw site title into the merge key.
///
/// Plan/07 asks for NFC first; `String.normalize` is a web-only Dart API
/// (absent on the VM), so NFC is skipped — WordPress content is NFC in
/// practice and NFKC-compat on Thai would destroy vowel marks anyway
/// (see PLAN_NOTES). Steps: lowercase → strip bracketed scanlator credits →
/// keep only latin/digits/Thai/spaces (punctuation like `-` becomes a
/// space) → collapse spaces → drop noise words.
String normalizeTitle(String raw) {
  var s = raw.toLowerCase();
  s = s.replaceAll(_bracketed, ' ');
  s = s.replaceAll(_keepChars, ' ');
  s = s.trim().replaceAll(_spaces, ' ');
  return s
      .split(' ')
      .where((w) => w.isNotEmpty && !_noiseTokens.contains(w))
      .join(' ');
}

/// True when the string contains any Thai script character — used to prefer
/// Thai display titles (decision L5).
bool hasThaiScript(String s) => _thaiChar.hasMatch(s);

/// True when latin letters outnumber Thai characters (for original-title
/// picking, L5 order 2: "majority Latin-script").
bool isMostlyLatin(String s) {
  var latin = 0;
  var thai = 0;
  for (final rune in s.runes) {
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
      latin++;
    } else if (rune >= 0x0E00 && rune <= 0x0E7F) {
      thai++;
    }
  }
  return latin > 0 && latin > thai;
}

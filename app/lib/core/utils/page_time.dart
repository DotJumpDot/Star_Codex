import 'dart:io' show HttpDate;

/// The moment the server GENERATED this HTML — the only correct anchor
/// for relative time labels inside it. The ts homepages ride WP Fastest
/// Cache behind the Cloudflare edge (`max-age=16070400`, probed
/// 2026-10-23): a `.fivtime` "24 วินาที" in the served copy is 24 s
/// before page generation, which can sit a day behind the fetch. The
/// cache plugin stamps `Last-Modified` with that generation moment
/// (fin-manga's header probed equal to its "file was created … @ 9:20
/// am" comment), so the header is the anchor and `Date − Age` the
/// fallback for edge-only caches. null → no anchor (the caller falls
/// back to fetch-now, the pre-fix behavior).
int? pageGenerationMs(Map<String, String> headers, {int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  // A pathological static-file mtime (e.g. epoch-ish) would date every
  // label by years — past the coarsest real label (~1 ปี), distrust it.
  const maxTrustAgeMs = 400 * 24 * 3600 * 1000;

  int? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return HttpDate.parse(raw).millisecondsSinceEpoch;
    } on Exception {
      // HttpException (dart:io's own message), not FormatException.
      return null;
    }
  }

  final lm = parse(headers['last-modified']);
  if (lm != null && now - lm <= maxTrustAgeMs) {
    return lm > now ? now : lm; // never anchor in the future
  }
  final date = parse(headers['date']);
  final age = int.tryParse(headers['age'] ?? '');
  if (date != null && now - date <= maxTrustAgeMs) {
    final anchored = date - (age == null || age <= 0 ? 0 : age * 1000);
    return anchored > now ? now : anchored;
  }
  return null;
}

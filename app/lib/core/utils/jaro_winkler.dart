import 'dart:math';

/// Standard Jaro–Winkler string similarity (Plan/07 §2). Operates on UTF-16
/// code units — fine for Thai and Latin (both BMP, no surrogate pairs in
/// practice for titles).
double jaroWinkler(String a, String b,
    {double prefixScale = 0.1, int maxPrefix = 4, double boostThreshold = 0.7}) {
  final j = _jaro(a, b);
  if (j < boostThreshold) return j;
  final prefixMax = maxPrefix < a.length ? maxPrefix : a.length;
  final limit = prefixMax < b.length ? prefixMax : b.length;
  var prefix = 0;
  while (prefix < limit && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
    prefix++;
  }
  return j + prefix * prefixScale * (1 - j);
}

double _jaro(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;

  final la = a.length;
  final lb = b.length;
  final window = max(0, max(la, lb) ~/ 2 - 1);
  final aMatched = List<bool>.filled(la, false);
  final bMatched = List<bool>.filled(lb, false);

  var matches = 0;
  for (var i = 0; i < la; i++) {
    final start = max(0, i - window);
    final end = min(lb - 1, i + window);
    for (var j = start; j <= end; j++) {
      if (bMatched[j] || a.codeUnitAt(i) != b.codeUnitAt(j)) continue;
      aMatched[i] = true;
      bMatched[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0.0;

  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < la; i++) {
    if (!aMatched[i]) continue;
    while (!bMatched[k]) {
      k++;
    }
    if (a.codeUnitAt(i) != b.codeUnitAt(k)) transpositions++;
    k++;
  }

  final m = matches.toDouble();
  return (m / la + m / lb + (m - transpositions / 2) / m) / 3;
}

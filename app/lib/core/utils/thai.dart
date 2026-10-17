/// Thai-specific parsing helpers (Plan/01 utils; decisions L4) + the
/// Library A–Z collation (Plan/12 §3).
library;

/// Parses chapter numbers like `ตอนที่ 922`, `Chapter 45`, `920`,
/// `ตอนที่ 155.5`, `- ตอนที่ 9 [จบ]` to a double (decision L4).
/// Returns null when no number can be extracted — the adapter then falls
/// back to list index (flagged low-confidence by the caller).
double? parseChapterNumber(String raw) {
  final explicit = RegExp(
    r'(?:ตอนที่|ตอน|chapter|ch\.?)\s*[:#]?\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (explicit != null) {
    return double.tryParse(explicit.group(1)!);
  }
  final standalone = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
  return standalone != null ? double.tryParse(standalone.group(1)!) : null;
}

/// `920.0` → `920`, `155.5` → `155.5` — display form for chapter numbers.
String formatChapterNumber(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : '$n';

const _thaiMonths = {
  'มกราคม': 1, 'กุมภาพันธ์': 2, 'มีนาคม': 3, 'เมษายน': 4,
  'พฤษภาคม': 5, 'มิถุนายน': 6, 'กรกฎาคม': 7, 'สิงหาคม': 8,
  'กันยายน': 9, 'ตุลาคม': 10, 'พฤศจิกายน': 11, 'ธันวาคม': 12,
  // short forms
  'ม.ค.': 1, 'ก.พ.': 2, 'มี.ค.': 3, 'เม.ย.': 4, 'พ.ค.': 5, 'มิ.ย.': 6,
  'ก.ค.': 7, 'ส.ค.': 8, 'ก.ย.': 9, 'ต.ค.': 10, 'พ.ย.': 11, 'ธ.ค.': 12,
};

/// Thai+English month date strings from ts theme chapter rows:
/// `มิถุนายน 8, 2026`, `June 8, 2026`, `8 มิถุนายน 2026`, `2026-06-08`.
int? parseSiteDate(String raw) {
  final s = raw.trim();
  // ISO first
  final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    return _utcMs(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
        int.parse(iso.group(3)!));
  }
  // Month-name day, year
  final monthName = RegExp(
    r'([A-Za-z\u0E00-\u0E7F]+\.?)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})',
  ).firstMatch(s);
  if (monthName != null) {
    final month = _monthFromName(monthName.group(1)!);
    if (month != null) {
      return _utcMs(int.parse(monthName.group(3)!), month,
          int.parse(monthName.group(2)!));
    }
  }
  // Day month-name year (Thai order)
  final dayFirst = RegExp(
    r'(\d{1,2})\s+([A-Za-z\u0E00-\u0E7F]+\.?)\s+(\d{4})',
  ).firstMatch(s);
  if (dayFirst != null) {
    final month = _monthFromName(dayFirst.group(2)!);
    if (month != null) {
      return _utcMs(int.parse(dayFirst.group(3)!), month,
          int.parse(dayFirst.group(1)!));
    }
  }
  return null;
}

int? _monthFromName(String name) {
  final n = name.trim().toLowerCase();
  final thai = _thaiMonths.entries
      .firstWhereOrNull((e) => e.key.toLowerCase() == n);
  if (thai != null) return thai.value;
  const en = [
    'january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december',
  ];
  final exact = en.indexWhere((m) => n == m || n == '${m.substring(0, 3)}.');
  return exact >= 0 ? exact + 1 : null;
}

int _utcMs(int year, int month, int day) =>
    DateTime.utc(year, month, day).millisecondsSinceEpoch;

// --- Thai collation (Plan/12 §3 — exact spec) ---

const _thaiToneMarks = '\u0E48\u0E49\u0E4A\u0E4B'; // ่ ้ ๊ ๋
const _thaiNonOrdering = '\u0E47\u0E4C\u0E4D'; // ็ ์ ํ

/// Sort key: strip tone marks (่ ้ ๊ ๋) and non-ordering marks
/// (็ ์ ํ), collapse whitespace, lowercase. Consonants are already in
/// dictionary order, so plain codepoint compare on the cleaned key reads
/// naturally; Latin sorts after Thai (higher codepoints).
///
/// Known v1 limitation (doc 12): ำ (U+0E33) and the legacy ฤ/ฤๅ order can
/// be imperfect — acceptable; no ICU collation package is imported.
String thaiSortKey(String s) => s
    .replaceAll(RegExp('[$_thaiToneMarks$_thaiNonOrdering]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Library sort ชื่อ A–Z (Plan/12 sort table).
int compareTitlesThai(String a, String b) =>
    thaiSortKey(a).compareTo(thaiSortKey(b));

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

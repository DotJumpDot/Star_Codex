/// Manual relative timestamps for chapter rows (doc 09: timeago-style;
/// intl's Thai locale needs locale-data init, so this is hand-rolled).
///
/// Pure: returns an i18n key + `{n}` params — the UI renders it with
/// `tFmt(context, key, params)` so TH/EN both work.
library;

({String key, Map<String, String> params}) relativeParts(int atMs,
    {int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  // Site clocks occasionally run ahead — a negative delta reads as "just now".
  final seconds = (now - atMs) ~/ 1000;
  if (seconds < 60) return (key: 'relative.now', params: const {});

  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return (key: 'relative.minutes', params: {'n': '$minutes'});
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return (key: 'relative.hours', params: {'n': '$hours'});
  }
  final days = hours ~/ 24;
  if (days < 7) {
    return (key: 'relative.days', params: {'n': '$days'});
  }
  if (days < 30) {
    return (key: 'relative.weeks', params: {'n': '${days ~/ 7}'});
  }
  if (days < 365) {
    return (key: 'relative.months', params: {'n': '${days ~/ 30}'});
  }
  return (key: 'relative.years', params: {'n': '${days ~/ 365}'});
}

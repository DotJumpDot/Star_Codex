import '../../data/dao/library_dao.dart';

/// One collapsed History row (user QA 2026-10-18): a series read across
/// several chapters shows ONCE — latest-read row for identity/time, plus
/// the chapter range spanned by its rows in the loaded window.
class HistorySeriesEntry {
  const HistorySeriesEntry({
    required this.latest,
    required this.minNumber,
    required this.maxNumber,
    required this.chapterCount,
  });

  final HistoryRow latest;
  final double minNumber;
  final double maxNumber;
  final int chapterCount;

  bool get singleChapter => minNumber == maxNumber;
}

/// Collapse newest-first history rows to one entry per series. First-seen
/// order is kept, so entries stay ordered by series recency. The day
/// header for an entry comes from `latest.readAt` (the screen re-uses
/// groupByDay on the entries' latest rows).
List<HistorySeriesEntry> collapseBySeries(List<HistoryRow> rows) {
  final order = <int>[];
  final bySeries = <int, HistorySeriesEntry>{};
  void expand(HistoryRow r) {
    final existing = bySeries[r.seriesId];
    if (existing == null) {
      bySeries[r.seriesId] = HistorySeriesEntry(
          latest: r, minNumber: r.number, maxNumber: r.number,
          chapterCount: 1);
      order.add(r.seriesId);
      return;
    }
    bySeries[r.seriesId] = HistorySeriesEntry(
      latest: existing.latest,
      minNumber: r.number < existing.minNumber ? r.number : existing.minNumber,
      maxNumber: r.number > existing.maxNumber ? r.number : existing.maxNumber,
      chapterCount: existing.chapterCount + 1,
    );
  }

  for (final r in rows) {
    expand(r);
  }
  return [for (final id in order) bySeries[id]!];
}

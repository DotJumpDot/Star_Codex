import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/ui/library/history_group.dart';

HistoryRow _row(int seriesId, double number, int readAt) => HistoryRow(
      chapterId: seriesId * 1000 + number.toInt(),
      seriesId: seriesId,
      readAt: readAt,
      timesRead: 1,
      number: number,
      title: 'series $seriesId',
    );

void main() {
  test('collapses to one entry per series: recency order, min–max range',
      () {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Series 1 read ch 3 → ch 1 → ch 2, interleaved with series 2.
    final rows = [
      _row(1, 3, now),
      _row(2, 5, now - 1000),
      _row(1, 1, now - 2000),
      _row(1, 2, now - 3000),
      _row(2, 4, now - 4000),
    ];
    final entries = collapseBySeries(rows);
    expect(entries.length, 2);
    // First-seen order = series recency (newest read first).
    expect(entries[0].latest.seriesId, 1);
    expect(entries[0].latest.readAt, now, reason: 'latest row of series 1');
    expect(entries[0].minNumber, 1);
    expect(entries[0].maxNumber, 3);
    expect(entries[0].chapterCount, 3);
    expect(entries[0].singleChapter, isFalse);
    expect(entries[1].minNumber, 4);
    expect(entries[1].maxNumber, 5);
    expect(entries[1].latest.number, 5);
  });

  test('single-chapter series collapses to itself', () {
    final entries = collapseBySeries([_row(7, 12.5, 1000)]);
    final e = entries.single;
    expect(e.singleChapter, isTrue);
    expect(e.latest.number, 12.5);
    expect(e.chapterCount, 1);
  });

  test('empty input stays empty', () {
    expect(collapseBySeries(const []), isEmpty);
  });
}

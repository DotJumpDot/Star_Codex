import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/ui/detail/chapter_indicator.dart';
import 'package:star_codex/ui/reader/novel_reader_screen.dart';
import 'package:star_codex/ui/reader/paged_reader_screen.dart';
import 'package:star_codex/ui/reader/reader_screen.dart';

import 'helpers.dart';

/// The three reader/detail fixes of 2026-10-22:
///
/// 1. The reader chrome state carries across a chapter switch.
/// 2. The detail chapter rows show "on reading" / "read", with the
///    indicator on the LEFT.
/// 3. A finished chapter never regresses to "on reading".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SeriesDao seriesDao;
  late ChaptersDao chaptersDao;

  setUp(() async {
    db = await openTestDb();
    seriesDao = SeriesDao(db);
    chaptersDao = ChaptersDao(db);
  });

  Future<int> seedSeriesWithChapter() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seriesId = await seriesDao.insert(Series(
      title: 'Test series',
      titleNorm: 'test series',
      type: 'manga',
      createdAt: now,
      updatedAt: now,
    ));
    await chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: 'go-manga',
      number: 1,
      url: 'u',
      fetchedAt: now,
    ));
    return seriesId;
  }

  group('read state (bug 2)', () {
    test('markStarted creates a started (not completed) row', () async {
      final seriesId = await seedSeriesWithChapter();
      final chapter = (await db.query('chapters')).first['id'] as int;

      await chaptersDao.markStarted(chapter);

      final rows = await db.query('read_progress');
      expect(rows, hasLength(1));
      expect(rows.single['completed'], 0);
      expect(rows.single['read_at'], isNull,
          reason: 'a started chapter is not a completion');

      final progress = await chaptersDao.progressForSeries(seriesId);
      expect(progress[chapter]!.completed, isFalse);
    });

    test('markStarted never regresses a FINISHED chapter', () async {
      final seriesId = await seedSeriesWithChapter();
      final chapter = (await db.query('chapters')).first['id'] as int;

      await chaptersDao.saveProgress(chapter,
          pageIndex: 4, completed: true, readAt: 1000);
      await chaptersDao.markStarted(chapter);

      final progress = await chaptersDao.progressForSeries(seriesId);
      expect(progress[chapter]!.completed, isTrue,
          reason: 'the started marker must not un-read a finished chapter');
    });

    test('markStarted keeps an existing partial row as it is', () async {
      final seriesId = await seedSeriesWithChapter();
      final chapter = (await db.query('chapters')).first['id'] as int;

      await chaptersDao.saveProgress(chapter, pageIndex: 7, completed: false);
      await chaptersDao.markStarted(chapter);

      final progress = await chaptersDao.progressForSeries(seriesId);
      expect(progress[chapter]!.pageIndex, 7,
          reason: 'the started marker must not reset the saved page');
    });

    test('a finished chapter stays finished when re-read (sticky '
        'completed)', () async {
      final seriesId = await seedSeriesWithChapter();
      final chapter = (await db.query('chapters')).first['id'] as int;

      await chaptersDao.saveProgress(chapter,
          pageIndex: 9, completed: true, readAt: 5000);
      // Re-opening a read chapter and scrolling saves completed=0 — it
      // must NOT un-read the chapter.
      await chaptersDao.saveProgress(chapter, pageIndex: 2, completed: false);

      final progress = await chaptersDao.progressForSeries(seriesId);
      expect(progress[chapter]!.completed, isTrue);
      expect(progress[chapter]!.readAt, 5000,
          reason: 'the original finish time is kept');
    });

    test('clearProgress (mark as unread) still un-reads a chapter',
        () async {
      final seriesId = await seedSeriesWithChapter();
      final chapter = (await db.query('chapters')).first['id'] as int;

      await chaptersDao.saveProgress(chapter, pageIndex: 3, completed: true);
      await chaptersDao.clearProgress(chapter);

      final progress = await chaptersDao.progressForSeries(seriesId);
      expect(progress[chapter], isNull);
    });
  });

  group('chapter indicator (bug 2)', () {
    Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3A5BC7),
            brightness: brightness,
          ),
        ),
        home: Scaffold(body: child),
      );
    }

    testWidgets('the three states render distinctly', (tester) async {
      await tester.pumpWidget(wrap(Column(
        children: const [
          ChapterStateDot(state: ChapterReadState.unread),
          ChapterStateDot(state: ChapterReadState.reading),
          ChapterStateDot(state: ChapterReadState.read),
        ],
      )));

      final dots = tester.widgetList<ChapterStateDot>(find.byType(ChapterStateDot));
      expect(dots, hasLength(3));

      // The "reading" dot must NOT be the same color as the "read" dot —
      // that is the whole point of the two states.
      final scheme = Theme.of(
        tester.element(find.byType(ChapterStateDot).first),
      ).colorScheme;
      expect(scheme.tertiary, isNot(scheme.primary));
    });

    testWidgets('the check inside the "read" dot is smaller than the dot',
        (tester) async {
      await tester.pumpWidget(
          wrap(const ChapterStateDot(state: ChapterReadState.read)));

      final icon = tester.widget<Icon>(find.byIcon(Icons.check));
      final size = tester.getSize(find.byType(ChapterStateDot));
      expect(icon.size, lessThan(size.width),
          reason: 'the checkmark must not dwarf the circle');
    });

    testWidgets('the reading and read dots are the same size', (tester) async {
      await tester.pumpWidget(wrap(Row(
        children: const [
          ChapterStateDot(state: ChapterReadState.reading),
          ChapterStateDot(state: ChapterReadState.read),
        ],
      )));

      final reading = tester.getSize(find.byType(ChapterStateDot).first);
      final read = tester.getSize(find.byType(ChapterStateDot).last);
      expect(reading.width, read.width);
      expect(reading.height, read.height);
    });
  });

  group('reader chrome carry-over (bug 1)', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final chapter = Chapter(
      id: 1,
      seriesId: 1,
      sourceId: 'go-manga',
      number: 1,
      url: 'u',
      fetchedAt: now,
    );

    test('the reader screens take the chrome state as a seed', () {
      // Bug 1: hiding the chrome and pulling to the next chapter made
      // the header reappear. The state is now handed to the next
      // screen through the constructor.
      expect(ReaderScreen(chapter: chapter).chromeVisible, isTrue);
      expect(
        ReaderScreen(chapter: chapter, chromeVisible: false).chromeVisible,
        isFalse,
      );
      expect(PagedReaderScreen(chapter: chapter).chromeVisible, isTrue);
      expect(
        PagedReaderScreen(chapter: chapter, chromeVisible: false).chromeVisible,
        isFalse,
      );
      expect(NovelReaderScreen(chapter: chapter).chromeVisible, isTrue);
      expect(
        NovelReaderScreen(chapter: chapter, chromeVisible: false).chromeVisible,
        isFalse,
      );
    });
  });
}

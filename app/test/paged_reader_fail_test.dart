import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/ui/reader/paged_reader_screen.dart';

import 'fake_source.dart';
import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_prf_wt');

  // Regression (on-device QA 2026-10-18, Bug #7): manga-type chapters
  // route to the PAGED reader, whose _open() catch used to swallow the
  // error into an eternal "กำลังโหลด…" + หน้า 1/0 spinner — no error
  // panel, no retry, while the webtoon/novel readers failed gracefully.
  // Source whose pages() throws for this chapter URL (no pagesResults
  // entry) drives loadChapter's all-candidates-failed path.
  final fake = FakeSource('slow-manga');

  final now = DateTime.now().millisecondsSinceEpoch;
  final seriesDao = SeriesDao(db);
  final chaptersDao = ChaptersDao(db);
  final seriesId = await seriesDao.insert(Series(
    title: 'Paged Fail QA',
    titleNorm: normalizeTitle('Paged Fail QA'),
    type: 'manga',
    createdAt: now,
    updatedAt: now,
  ));
  await db.insert('series_sources', {
    'series_id': seriesId,
    'source_id': 'slow-manga',
    'source_url': 'https://www.slow-manga.net/qa/pagedfail/',
    'fetched_at': now,
  });
  await chaptersDao.upsert(Chapter(
    seriesId: seriesId,
    sourceId: 'slow-manga',
    number: 1,
    url: 'https://www.slow-manga.net/qa/pagedfail/1',
    fetchedAt: now,
  ));
  final chapter = (await chaptersDao.listForSeries(seriesId)).single;

  testWidgets('paged reader fail path: error panel + retry, not a spinner',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(const {}),
          libraryDirProvider.overrideWithValue(tmp),
          sourcesProvider.overrideWith((ref) => SourcesController([fake])),
        ],
        child: MaterialApp(home: PagedReaderScreen(chapter: chapter)),
      ),
    );

    // loadChapter goes through the ffi DB isolate + a throwing source
    // (REAL async) → drain before asserting.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }

    expect(find.text('เกิดข้อผิดพลาด'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(find.text('กำลังโหลด…'), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

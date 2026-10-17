import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/ui/detail/detail_screen.dart';

import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_detail_wt');
  await _seed(db); // series id 1

  // One widget test per file (shared font/asset caches hang a second one).
  testWidgets('detail: header, tabs, source dots, mark-read, chapter tap',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const {}),
        libraryDirProvider.overrideWithValue(tmp),
        sourcesProvider.overrideWithValue(const []),
      ],
      child: const MaterialApp(home: DetailScreen(seriesId: 1)),
    ));
    // controller.load reads through the ffi DB isolate (REAL async —
    // FakeAsync alone never completes it): drain, then pump the VM in.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }

    // Header (L5: Thai title primary, original as subtitle) + type/status.
    // The Thai title shows twice: AppBar + header.
    expect(find.text('นาโน แมชชีน'), findsNWidgets(2));
    expect(find.text('Nano Machine'), findsOneWidget);
    expect(find.text('มังงะเกาหลี'), findsOneWidget);
    expect(find.text('กำลังเข้า'), findsOneWidget);

    // Two source tabs (Plan/09 §5); slow-manga is the primary (default
    // tab). sourcesProvider is empty in this test → labels fall back to
    // the source ids; each shows twice (header badge + tab).
    expect(find.text('slow-manga'), findsNWidgets(2));
    expect(find.text('go-manga'), findsNWidgets(2));

    // Chapter rows of the primary tab, old→new default (doc 09 §6).
    expect(find.textContaining('ตอนที่ 1'), findsWidgets);

    // Long-press → sheet → mark read; the check appears WITHOUT refetch
    // (the DB write must drain through the ffi isolate first).
    await tester.longPress(find.textContaining('ตอนที่ 1').first);
    await tester.pumpAndSettle();
    expect(find.text('ทำเครื่องหมายว่าอ่านแล้ว'), findsOneWidget);
    await tester.tap(find.text('ทำเครื่องหมายว่าอ่านแล้ว'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsWidgets);

    // Tap the chapter row → the REAL webtoon reader opens (Phase 7).
    // openReader awaits seriesDao.byId through the ffi isolate → drain.
    // This chapter has no page rows and sourcesProvider is empty in the
    // unit env, so the reader lands in its error state with retry.
    await tester.tap(find.textContaining('ตอนที่ 2').first);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }
    expect(find.text('เกิดข้อผิดพลาด'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsWidgets);

    // Drain the fire-and-forget progress write (ffi isolate round-trip).
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
  }, timeout: const Timeout(Duration(minutes: 1)));
}

Future<int> _seed(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final seriesId = await SeriesDao(db).upsertByTitleNorm(Series(
    title: 'นาโน แมชชีน',
    originalTitle: 'Nano Machine',
    titleNorm: normalizeTitle('Nano Machine'),
    type: 'manhwa',
    origin: 'korea',
    status: 'ongoing',
    description: 'desc',
    createdAt: now,
    updatedAt: now,
  ));
  await SeriesDao(db).upsertSource(SeriesSource(
    seriesId: seriesId,
    sourceId: 'slow-manga',
    sourceUrl: 'https://www.slow-manga.net/nano/',
    lastChapterNumber: 3,
    fetchedAt: now,
  ));
  await SeriesDao(db).upsertSource(SeriesSource(
    seriesId: seriesId,
    sourceId: 'go-manga',
    sourceUrl: 'https://www.go-manga.com/nano/',
    lastChapterNumber: 2,
    fetchedAt: now,
  ));
  await ChaptersDao(db).upsertAll([
    for (final n in <double>[1, 2, 3])
      Chapter(
        seriesId: seriesId,
        sourceId: 'slow-manga',
        number: n,
        title: 'ตอนที่ $n',
        url: 'https://www.slow-manga.net/nano/$n',
        uploadedAt: now - 86400000,
        fetchedAt: now,
      ),
    for (final n in <double>[1, 2])
      Chapter(
        seriesId: seriesId,
        sourceId: 'go-manga',
        number: n,
        title: 'ตอนที่ $n',
        url: 'https://www.go-manga.com/nano/$n',
        uploadedAt: now - 86400000,
        fetchedAt: now,
      ),
  ]);
  return seriesId;
}

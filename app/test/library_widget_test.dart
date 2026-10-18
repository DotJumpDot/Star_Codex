import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Database;

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/ui/library/library_screen.dart';

import 'helpers.dart';

/// Library screen widget test (Plan/12 DoD: category tab filters, cards,
/// multi-select). One widget test per file (shared font cache hangs a
/// second one in the same process).
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_lib_wt');
  await _seed(db);

  testWidgets('library: cards render, novel smart-tab filters, multi-select',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const {}),
        libraryDirProvider.overrideWithValue(tmp),
        sourcesProvider.overrideWith((ref) => SourcesController(const [])),
      ],
      child: const MaterialApp(home: LibraryScreen()),
    ));
    // controller.load runs through the ffi DB isolate (REAL async): drain.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }

    // Both cards visible on the default ทั้งหมด tab.
    expect(find.text('นาโน แมชชีน'), findsOneWidget);
    expect(find.text('นิยายสายดาร์ก'), findsOneWidget);
    // New-chapter badge on the series with an unread fresh chapter.
    expect(find.text('1 ตอนใหม่'), findsOneWidget);

    // Smart tab นิยาย via the category dropdown (the sliding chip row is
    // gone — user QA 2026-10-18). pumpAndSettle is safe here: only the
    // LibraryScreen is mounted and its load already drained.
    await tester.tap(find.byIcon(Icons.category_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('นิยาย')); // sheet row
    await tester.pumpAndSettle();
    expect(find.text('นิยายสายดาร์ก'), findsOneWidget);
    expect(find.text('นาโน แมชชีน'), findsNothing);

    // Back to ทั้งหมด, then long-press → multi-select (both, then merge
    // button appears at 2+).
    await tester.tap(find.byIcon(Icons.category_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ทั้งหมด').last); // sheet row (the closed
    // dropdown button also shows ทั้งหมด — .last is the sheet's copy)
    await tester.pumpAndSettle();
    await tester.longPress(find.text('นิยายสายดาร์ก'));
    await tester.pump();
    expect(find.text('เลือกไว้ 1 เรื่อง'), findsOneWidget);
    await tester.tap(find.text('นาโน แมชชีน')); // select-mode tap toggles
    for (var i = 0; i < 2; i++) {
      await tester.pump();
    }
    expect(find.text('เลือกไว้ 2 เรื่อง'), findsOneWidget);
    expect(find.byIcon(Icons.merge), findsOneWidget);

    // Drain any pending writes.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
  }, timeout: const Timeout(Duration(minutes: 1)));
}

Future<void> _seed(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final daos = (SeriesDao(db), ChaptersDao(db), LibraryDao(db));

  final manga = await daos.$1.insert(Series(
    title: 'นาโน แมชชีน',
    originalTitle: 'Nano Machine',
    titleNorm: normalizeTitle('Nano Machine'),
    type: 'manhwa',
    createdAt: now,
    updatedAt: now,
  ));
  await daos.$2.upsertAll([
    Chapter(
      seriesId: manga,
      sourceId: 'slow-manga',
      number: 1,
      title: 'ตอนที่ 1',
      url: 'https://www.slow-manga.net/n/1',
      uploadedAt: now - 86400000,
      fetchedAt: now,
    ),
    Chapter(
      seriesId: manga,
      sourceId: 'slow-manga',
      number: 2,
      title: 'ตอนที่ 2',
      url: 'https://www.slow-manga.net/n/2',
      uploadedAt: now - 1000, // newer than last_read below → "1 ตอนใหม่"
      fetchedAt: now,
    ),
  ]);
  await daos.$2.saveProgress((await daos.$2.find(manga, 'slow-manga', 1))!.id!,
      pageIndex: 0, completed: true);
  await daos.$3.add(manga, now);
  await daos.$3.markRead(manga,
      (await daos.$2.find(manga, 'slow-manga', 1))!.id!, now - 86400000);

  final novel = await daos.$1.insert(Series(
    title: 'นิยายสายดาร์ก',
    titleNorm: normalizeTitle('นิยายสายดาร์ก'),
    type: 'novel',
    createdAt: now,
    updatedAt: now,
  ));
  await daos.$2.upsert(Chapter(
    seriesId: novel,
    sourceId: 'nekopost',
    number: 1,
    title: 'ตอนที่ 1',
    url: 'nekopost:chapter:1:1',
    uploadedAt: now - 86400000,
    fetchedAt: now,
  ));
  await daos.$3.add(novel, now - 2000);
  await db.insert(
    'categories',
    {'name': 'ทั่วไป', 'sort': 0},
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

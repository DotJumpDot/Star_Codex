import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/repo/browse_merge.dart'
    show BrowseCandidate, SearchGroup;
import 'package:star_codex/data/sources/source_api.dart';
import 'package:star_codex/ui/browse/result_card.dart';
import 'package:star_codex/ui/detail/detail_screen.dart';

import 'fake_source.dart';
import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_dfg_wt');

  final fake = FakeSource(
    // Must be a SEEDED source id — series_sources.source_id FKs the
    // seeded `sources` table (test-only constraint; real ids always are).
    'slow-manga',
    details: {
      'https://www.slow-manga.net/qa/nano/': SourceSeriesDetail(
        title: 'Nano Machine QA',
        chapters: [
          const SourceChapter(
            url: 'https://www.slow-manga.net/qa/nano/1',
            title: 'ตอนที่ 1',
            number: 1,
          ),
        ],
      ),
    },
  );

  // Regression (on-device QA 2026-10-18): opening DetailScreen.fromGroup
  // through the browse push site (nested ProviderScope overriding
  // detailGroupProvider(-1)) crashed with Riverpod's "dependencies were
  // overridden but the provider is not" — detailControllerProvider reads
  // detailGroupProvider in its build without declaring the dependency.
  // Same override shape as browse_screen.dart's push.
  testWidgets('detail from browse group: scoped override does not crash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final group = SearchGroup([
      const BrowseCandidate(
        sourceId: 'slow-manga',
        referer: 'https://www.slow-manga.net/',
        url: 'https://www.slow-manga.net/qa/nano/',
        title: 'Nano Machine QA',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(const {}),
          libraryDirProvider.overrideWithValue(tmp),
          sourcesProvider.overrideWith((ref) => SourcesController([fake])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ResultCard(
              group: group,
              allGroups: [group],
              sources: [fake],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  // EXACTLY the push site in browse_screen.dart (no
                  // nested ProviderScope — the group rides the key).
                  builder: (_) => DetailScreen.fromGroup(group),
                ),
              ),
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );

    // ResultCard's cover may try a network fetch in this environment; the
    // card itself must be tappable regardless. Find the title and tap it.
    await tester.pump();
    await tester.tap(find.text('Nano Machine QA'));
    // The scoped controller materializes the row through the ffi DB
    // isolate (REAL async) → drain before asserting.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }

    // No Riverpod dependency-crash error screen; the detail header renders.
    // No Riverpod dependency-crash error screen; the detail header +
    // primary-tab chapter list render, the row materialized once.
    expect(find.text('Nano Machine QA'), findsWidgets);
    expect(find.textContaining('ตอนที่ 1'), findsWidgets);

    // DB verification through the ffi isolate needs the FakeAsync drain.
    final rows = await tester.runAsync(
      () => SeriesDao(db).findSeriesIdBySourceLink(
        'slow-manga',
        'https://www.slow-manga.net/qa/nano/',
      ),
    );
    expect(rows, isNotNull);
    final chapters = await tester.runAsync(
      () => ChaptersDao(db).listForSeries(rows!),
    );
    expect(chapters, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 1)));
}

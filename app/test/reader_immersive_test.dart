import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/ui/reader/paged_reader_screen.dart';

import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_ri_wt');

  final now = DateTime.now().millisecondsSinceEpoch;
  final seriesId = await SeriesDao(db).insert(Series(
    title: 'Immersive QA',
    titleNorm: normalizeTitle('Immersive QA'),
    type: 'manga',
    createdAt: now,
    updatedAt: now,
  ));
  await db.insert('series_sources', {
    'series_id': seriesId,
    'source_id': 'slow-manga',
    'source_url': 'https://www.slow-manga.net/qa/immersive/',
    'fetched_at': now,
  });
  await ChaptersDao(db).upsert(Chapter(
    seriesId: seriesId,
    sourceId: 'slow-manga',
    number: 1,
    url: 'https://www.slow-manga.net/qa/immersive/1',
    fetchedAt: now,
  ));
  final chapter =
      (await ChaptersDao(db).listForSeries(seriesId)).single;

  // Regression (user report 2026-10-21): the readers restored the system
  // bars in dispose() — which runs only AFTER the pop transition, so the
  // revealed page's top inset changed while fully visible and the whole
  // layout shifted ("warpy" pull-and-retract). The restore must fire at
  // the exit transition's START (AnimationStatus.reverse) and dispose
  // must not send it a second time.
  testWidgets('reader: system bars restored at pop start, once',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final modes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        modes.add(call.arguments.toString());
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const {}),
        libraryDirProvider.overrideWithValue(tmp),
        sourcesProvider.overrideWith((ref) => SourcesController(const [])),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PagedReaderScreen(chapter: chapter),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump(); // push starts; reader initState hides the bars
    expect(modes, contains('SystemUiMode.immersiveSticky'));

    await tester.pump(const Duration(milliseconds: 350));
    final modesAfterEnter = List.of(modes);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(); // exit transition STARTS — reverse fired here
    expect(modes.length, modesAfterEnter.length + 1);
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    // Transition finished + route disposed: dispose must NOT restore again.
    await tester.pump(const Duration(milliseconds: 350));
    expect(modes.length, modesAfterEnter.length + 1);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

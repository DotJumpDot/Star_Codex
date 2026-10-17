import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:star_codex/app.dart';
import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/data/sources/source_api.dart';

import 'fake_source.dart';
import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // FakeAsync can't complete real font fetches (see test/widget_test.dart).
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_browse_wt');

  // Same series on two sources, different titles — must merge into ONE card
  // with both source badges (Plan/08 DoD: "verify ≥2 sources grouped").
  const nanoA = SourceSeries(
    url: 'https://example.com/nano-machine/',
    title: 'Nano Machine',
    chapterCountHint: 920,
    type: 'manhwa',
  );
  const nanoB = SourceSeries(
    url: 'https://example.org/nano/',
    title: 'nano machine (แปลไทย)',
    chapterCountHint: 900,
  );
  final sourceA = FakeSource('slow-manga', searchResults: {
    'nano machine': [nanoA],
  }, latestResults: [
    nanoA,
    const SourceSeries(
        url: 'https://example.com/other/',
        title: 'Other Series',
        chapterCountHint: 50),
  ]);
  final sourceB = FakeSource('go-manga', searchResults: {
    'nano machine': [nanoB],
  }, latestResults: [
    nanoB,
  ]);

  // One widget test per file (shared font/asset caches hang a second one).
  testWidgets('browse: latest feed renders, search merges two sources',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(const {}),
        libraryDirProvider.overrideWithValue(tmp),
        sourcesProvider.overrideWith((ref) => SourcesController([sourceA, sourceB])),
      ],
      child: const StarCodexApp(),
    ));
    await tester.pump(); // post-frame ensureLoaded
    await tester.pump(); // latest fetch microtasks + frame

    // Latest feed (default view) shows the fake series.
    expect(find.text('Other Series'), findsOneWidget);

    // Submit-only search (Plan/08 §1).
    await tester.enterText(find.byType(TextField), 'nano machine');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // ONE merged card (Thai-preferred display title per L5)…
    expect(find.text('nano machine (แปลไทย)'), findsOneWidget);
    expect(find.text('Other Series'), findsNothing);
    // …with BOTH sources badged (chip row + card badge = 2 occurrences;
    // FakeSource.name returns its id).
    expect(find.text('slow-manga'), findsNWidgets(2));
    expect(find.text('go-manga'), findsNWidgets(2));

    // Drain the fire-and-forget history write (ffi DB isolate round-trip
    // needs REAL async; a leftover in-flight call would trip the
    // pending-timer invariant).
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 1)));
}

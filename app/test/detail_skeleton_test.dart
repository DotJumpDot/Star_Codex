import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/ui/detail/detail_screen.dart';
import 'package:star_codex/ui/detail/detail_skeleton.dart';

import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_dsk_wt');

  // Detail load used to show a bare CircularProgressIndicator (user report
  // 2026-10-21: every other list has a skeleton). While the controller's
  // load() is pending the body must render the shape-mirroring skeleton;
  // with a nonexistent series id the load then lands in the error state.
  testWidgets('detail: skeleton while loading, error state after',
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
      child: const MaterialApp(home: DetailScreen(seriesId: 999999)),
    ));
    // load() fires in the post-frame callback; the ffi DB read it awaits
    // never completes under FakeAsync, so the skeleton stays up.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(DetailSkeleton), findsOneWidget);

    // Drain: id 999999 doesn't exist → _buildVm's null assert throws →
    // the controller lands in the error/retry state.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }
    expect(find.byType(DetailSkeleton), findsNothing);
    expect(find.text('เกิดข้อผิดพลาด'), findsOneWidget);
    expect(find.text('ลองใหม่'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

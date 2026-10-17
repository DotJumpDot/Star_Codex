import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:star_codex/app.dart';
import 'package:star_codex/core/i18n/i18n.dart';

import 'helpers.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Widget tests run in a FakeAsync zone: a real google_fonts network fetch
  // can never complete there. Tests use fallback fonts; the app keeps
  // runtime fetching enabled.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Real async (i18n assets, in-memory DB open) must complete BEFORE
  // testWidgets registers — inside a test body the FakeAsync zone can
  // starve it.
  await I18nService.load();
  final overrides = await dbOverrides();

  const tabKeys = [
    'tab.browse',
    'tab.library',
    'tab.history',
    'tab.offline',
    'tab.settings',
  ];

  // One test, no shared state between widget tests (a second test in the
  // same file hangs on font/asset caches). Timeout keeps failures fast.
  testWidgets('shell shows 5 Thai tabs and tab switching works', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const StarCodexApp()),
    );
    // The real screens (library/history) load through the ffi DB isolate —
    // REAL async that never completes under FakeAsync, and their loading
    // spinners animate forever. Drain + pump instead of pumpAndSettle.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    for (final key in tabKeys) {
      expect(
        find.descendant(of: bar, matching: find.text(I18nService.translate(key))),
        findsOneWidget,
        reason: 'missing tab label for $key',
      );
    }

    await tester.tap(find.descendant(
      of: bar,
      matching: find.text(I18nService.translate('tab.settings')),
    ));
    await tester.pump();
    // Settings placeholder repeats the tab title as its heading.
    expect(find.text(I18nService.translate('tab.settings')), findsNWidgets(2));
  }, timeout: const Timeout(Duration(minutes: 1)));
}

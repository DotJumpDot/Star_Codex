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
  testWidgets('shell: left drawer nav + hamburger, no bottom bar',
      (tester) async {
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

    // Bottom navigation is gone; every tab header carries the hamburger.
    expect(find.byType(NavigationBar), findsNothing);
    // The drawer's own subtitle proves it's not in the tree while closed.
    expect(find.text(I18nService.translate('nav.subtitle')), findsNothing);

    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pump(); // start the open animation
    await tester.pump(const Duration(milliseconds: 400));

    final drawerSubtitle =
        find.text(I18nService.translate('nav.subtitle'));
    expect(drawerSubtitle, findsOneWidget);
    for (final key in tabKeys) {
      expect(
        find.text(I18nService.translate(key)),
        findsWidgets,
        reason: 'missing drawer destination for $key',
      );
    }

    // Tap by destination KEY — the settings tab's own header inside the
    // IndexedStack also carries the same text, so text finders are
    // ambiguous here. Index 5 = Settings (Doujin 18+ moved to index 1).
    await tester.tap(find.byKey(const ValueKey('nav-dest-5')));
    await tester.pump(); // start the close animation
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    // Settings is the active tab: its Appearance section header renders.
    expect(find.text(I18nService.translate('settings.theme')), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/core/providers.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/sources/source_registry.dart';
import 'package:star_codex/ui/settings/settings_screen.dart';

import 'helpers.dart';

/// Settings screen (Plan/14 DoD): every control round-trips to the
/// settings table, and disabling a source re-emits the live registry so
/// browse/search/fallback lose it immediately. One widget test per file.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  final db = await openTestDb(); // seeded: 5 enabled sources + defaults
  // REAL registry instances built from the seeded DB (no fetcher —
  // nothing here touches the network).
  final liveSources =
      await loadSources(db, SafeHttp(rateLimiter: RateLimiter(seed: 1)));
  final overrides = [
    dbProvider.overrideWithValue(db),
    initialSettingsProvider.overrideWithValue(const {}),
    libraryDirProvider.overrideWithValue(
        await ioTemp('starcodex_settings_wt')),
    sourcesProvider.overrideWith((ref) => SourcesController(liveSources)),
  ];

  testWidgets('settings: toggle round-trips to DB; source disable re-emits',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const MaterialApp(
        home: SettingsScreen(),
      )),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }

    // Wi-Fi-only switch: default ON per doc 13; flipping writes through.
    expect(find.text('ดาวน์โหลดผ่าน Wi-Fi เท่านั้น'), findsOneWidget);
    await tester.tap(find.text('ดาวน์โหลดผ่าน Wi-Fi เท่านั้น'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    final wifiOnly = await tester
        .runAsync(() => SettingsDao(db).get('downloads_wifi_only'));
    expect(wifiOnly, '0');

    // Theme radio → appearanceProvider + settings table.
    await tester.scrollUntilVisible(
        find.text('ดำสนิท (OLED)'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('ดำสนิท (OLED)'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    final theme = await tester.runAsync(() => SettingsDao(db).get('theme'));
    expect(theme, 'black');

    // Source disable: 5 seeded sources → switch one off → the live
    // registry shrinks to 4 (DoD: removed from browse/search/fallback).
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)));
    expect(container.read(sourcesProvider).length, 5);
    final nekopostSwitch = find.descendant(
      of: find.widgetWithText(ListTile, 'Nekopost'),
      matching: find.byType(Switch),
    );
    await tester.scrollUntilVisible(nekopostSwitch, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(nekopostSwitch);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }
    expect(container.read(sourcesProvider).length, 4);
    expect(container.read(sourcesProvider).any((s) => s.id == 'nekopost'),
        isFalse);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

Future<io.Directory> ioTemp(String prefix) async =>
    io.Directory.systemTemp.createTemp(prefix);

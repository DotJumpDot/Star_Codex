import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/i18n/i18n.dart';
import 'core/net/rate_limiter.dart';
import 'core/net/safe_http.dart';
import 'core/providers.dart';
import 'data/dao/settings_dao.dart';
import 'data/db.dart';
import 'data/sources/source_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await I18nService.load();
  final db = await openDb();
  final libraryDir = await defaultLibraryDir();
  final initialSettings = await SettingsDao(db).getAll();
  // One shared limiter + http door for everything (review pass: a detached
  // RateLimiter would silently drop image-host registration).
  final rateLimiter = RateLimiter();
  final http = SafeHttp(rateLimiter: rateLimiter);
  final sources = await loadSources(db, http);
  final container = ProviderContainer(overrides: [
    dbProvider.overrideWithValue(db),
    libraryDirProvider.overrideWithValue(libraryDir),
    initialSettingsProvider.overrideWithValue(initialSettings),
    rateLimiterProvider.overrideWithValue(rateLimiter),
    safeHttpProvider.overrideWithValue(http),
    sourcesProvider.overrideWithValue(sources),
  ]);
  // Cache janitor 10 s after app start (Plan/03 §LRU): startup pass includes
  // integrity (orphan/missing-file cleanup), later runs are LRU-only.
  // Scheduled here (not in a widget) so tests never inherit a timer.
  Timer(const Duration(seconds: 10), () {
    container.read(cacheJanitorProvider).runNow(withIntegrity: true);
  });
  runApp(UncontrolledProviderScope(
    container: container,
    child: const StarCodexApp(),
  ));
}

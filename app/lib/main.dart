import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/i18n/i18n.dart';
import 'core/providers.dart';
import 'data/dao/settings_dao.dart';
import 'data/db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await I18nService.load();
  final db = await openDb();
  final libraryDir = await defaultLibraryDir();
  final initialSettings = await SettingsDao(db).getAll();
  final container = ProviderContainer(overrides: [
    dbProvider.overrideWithValue(db),
    libraryDirProvider.overrideWithValue(libraryDir),
    initialSettingsProvider.overrideWithValue(initialSettings),
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

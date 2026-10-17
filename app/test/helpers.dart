import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:star_codex/core/providers.dart';
import 'package:star_codex/data/db.dart';

bool _ffiInitialized = false;

/// Fresh in-memory database with the full v1 schema + seed.
Future<Database> openTestDb() async {
  if (!_ffiInitialized) {
    sqfliteFfiInit();
    _ffiInitialized = true;
  }
  return openDb(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      singleInstance: false);
}

/// Overrides for pumping StarCodexApp in widget tests without path_provider
/// or network: empty source registry (Browse renders an empty feed), throwaway
/// library dir (blob store construction needs a Directory).
Future<List<Override>> dbOverrides() async {
  final db = await openTestDb();
  final tmp = await io.Directory.systemTemp.createTemp('starcodex_test');
  return [
    dbProvider.overrideWithValue(db),
    initialSettingsProvider.overrideWithValue(const {}),
    libraryDirProvider.overrideWithValue(tmp),
    sourcesProvider.overrideWithValue(const []),
  ];
}

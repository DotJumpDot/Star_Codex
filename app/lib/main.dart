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
  final initialSettings = await SettingsDao(db).getAll();
  runApp(ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      initialSettingsProvider.overrideWithValue(initialSettings),
    ],
    child: const StarCodexApp(),
  ));
}

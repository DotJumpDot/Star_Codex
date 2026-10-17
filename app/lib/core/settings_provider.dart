import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dao/settings_dao.dart';
import 'providers.dart';

/// Typed view over the `settings` table rows (all stored as strings).
class AppSettings {
  const AppSettings(Map<String, String> values) : _values = values;

  final Map<String, String> _values;

  String get(String key, String fallback) => _values[key] ?? fallback;
  int getInt(String key, int fallback) =>
      int.tryParse(_values[key] ?? '') ?? fallback;
  double getDouble(String key, double fallback) =>
      double.tryParse(_values[key] ?? '') ?? fallback;
  bool getBool(String key, bool fallback) {
    final raw = _values[key];
    if (raw == null) return fallback;
    return raw == '1' || raw == 'true';
  }
}

/// Holds the current settings in memory; writes through to the DB.
class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._dao, Map<String, String> initial)
      : super(AppSettings(initial));

  final SettingsDao _dao;

  Future<void> set(String key, String value) async {
    await _dao.upsert(key, value);
    state = AppSettings({...state._values, key: value});
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController(
    ref.watch(settingsDaoProvider),
    ref.watch(initialSettingsProvider),
  );
});

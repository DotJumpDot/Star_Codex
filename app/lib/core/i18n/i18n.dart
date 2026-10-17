import 'dart:convert';

import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/settings_dao.dart';
import '../providers.dart';
import '../settings_provider.dart';

/// Tiny i18n helper (Plan/01 §5).
///
/// Loads `assets/i18n/th.json` and `assets/i18n/en.json` into memory at
/// startup. Every user-visible string MUST go through [t]. Both bundles must
/// always contain the same key set — enforced by `test/i18n_parity_test.dart`.
class I18nService {
  I18nService._();

  static final Map<String, Map<String, String>> _bundles = {};
  static String _lang = 'th';

  static const supportedLanguages = ['th', 'en'];

  static Future<void> load() async {
    for (final lang in supportedLanguages) {
      final raw = await rootBundle.loadString('assets/i18n/$lang.json');
      _bundles[lang] = (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    }
    _lang = _bundles.containsKey(_lang) ? _lang : 'th';
  }

  static void setLang(String lang) {
    if (_bundles.containsKey(lang)) _lang = lang;
  }

  static String get lang => _lang;

  /// Missing keys fall back to Thai, then to the key itself.
  static String translate(String key) =>
      _bundles[_lang]?[key] ?? _bundles['th']?[key] ?? key;
}

/// Doc signature: `t(context, 'browse.title')`.
String t(BuildContext _, String key) => I18nService.translate(key);

/// Current UI language ('th' | 'en'), persisted to the settings table.
class LanguageController extends StateNotifier<String> {
  LanguageController(String initial, this._settingsDao)
      : super(I18nService.supportedLanguages.contains(initial)
            ? initial
            : 'th') {
    // Apply the persisted language to the static bundle on startup —
    // without this the app always renders Thai until the user toggles
    // (found by the Phase 5 EN-flip device check).
    I18nService.setLang(state);
  }

  final SettingsDao _settingsDao;

  void set(String lang) {
    I18nService.setLang(lang);
    state = lang;
    _settingsDao.upsert('language', lang);
  }
}

final languageProvider =
    StateNotifierProvider<LanguageController, String>((ref) {
  return LanguageController(
    AppSettings(ref.watch(initialSettingsProvider)).get('language', 'th'),
    ref.watch(settingsDaoProvider),
  );
});

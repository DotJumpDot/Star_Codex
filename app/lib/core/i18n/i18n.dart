import 'dart:convert';

import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Current UI language ('th' | 'en'). Persisted to the settings DB in Phase 2.
class LanguageController extends StateNotifier<String> {
  LanguageController() : super(I18nService.lang);

  void set(String lang) {
    I18nService.setLang(lang);
    state = lang;
  }
}

final languageProvider =
    StateNotifierProvider<LanguageController, String>((ref) => LanguageController());

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Plan/01 §5: both i18n bundles must always contain the same key set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> load(String lang) {
    final raw = File('assets/i18n/$lang.json').readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test('th.json and en.json exist and parse', () {
    final th = load('th');
    final en = load('en');
    expect(th, isNotEmpty);
    expect(en, isNotEmpty);
  });

  test('th.json and en.json have identical key sets', () {
    final thKeys = load('th').keys.toSet();
    final enKeys = load('en').keys.toSet();
    expect(enKeys.difference(thKeys), isEmpty,
        reason: 'keys missing from th.json');
    expect(thKeys.difference(enKeys), isEmpty,
        reason: 'keys missing from en.json');
  });

  test('no empty translation values', () {
    for (final lang in ['th', 'en']) {
      load(lang).forEach((key, value) {
        expect((value as String).trim(), isNotEmpty,
            reason: '$lang key "$key" is empty');
      });
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/i18n.dart';
import 'core/providers.dart';
import 'core/settings_provider.dart';
import 'core/theme/theme.dart';
import 'data/dao/settings_dao.dart';
import 'ui/shell/shell.dart';

/// Appearance setting string ('dark' | 'black' | 'light'), persisted to the
/// settings table. Default dark (D4); pure-black variant from Plan/01 §6.
class AppearanceController extends StateNotifier<String> {
  AppearanceController(String initial, this._settingsDao)
      : super(_normalize(initial));

  final SettingsDao _settingsDao;

  static String _normalize(String v) =>
      const {'dark', 'black', 'light'}.contains(v) ? v : 'dark';

  void set(String v) {
    state = _normalize(v);
    _settingsDao.upsert('theme', state);
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, String>((ref) {
  return AppearanceController(
    AppSettings(ref.watch(initialSettingsProvider)).get('theme', 'dark'),
    ref.watch(settingsDaoProvider),
  );
});

class StarCodexApp extends ConsumerWidget {
  const StarCodexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final theme = ref.watch(appearanceProvider);
    final light = theme == 'light';
    final pureBlack = theme == 'black';
    return MaterialApp(
      title: 'Star Codex',
      theme: AppTheme.light(),
      darkTheme: pureBlack ? AppTheme.dark(pureBlack: true) : AppTheme.dark(),
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      locale: Locale(lang),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const NavigationShell(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/i18n.dart';
import 'core/providers.dart';
import 'core/settings_provider.dart';
import 'core/theme/app_fonts.dart';
import 'core/theme/app_themes.dart';
import 'data/dao/settings_dao.dart';
import 'ui/shell/shell.dart';

/// Active theme id (settings key `theme`), persisted to the settings table.
/// Legacy v1 values ('dark' | 'black' | 'light') migrate via [themeById].
class AppearanceController extends StateNotifier<StarThemeSpec> {
  AppearanceController(String initial, this._settingsDao)
      : super(themeById(initial));

  final SettingsDao _settingsDao;

  void set(String id) {
    state = themeById(id);
    _settingsDao.upsert('theme', state.id);
  }
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, StarThemeSpec>((ref) {
  return AppearanceController(
    AppSettings(ref.watch(initialSettingsProvider)).get('theme', 'stardust'),
    ref.watch(settingsDaoProvider),
  );
});

/// Global navigator key: the WAF challenge dialog (PLAN_NOTES
/// 2026-10-23) is raised from the network layer, which has no context of
/// its own — this key reaches the root navigator from anywhere.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class StarCodexApp extends ConsumerWidget {
  const StarCodexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final spec = ref.watch(appearanceProvider);
    final font =
        fontById(ref.watch(settingsProvider).get('ui_font', 'sarabun'));
    // One complete ThemeData per spec — themeMode stays dark so platform
    // brightness can never fight the selected palette.
    final theme = buildTheme(spec, fontFamily: font.family);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Star Codex',
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
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

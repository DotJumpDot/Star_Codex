import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/i18n.dart';
import 'core/theme/theme.dart';
import 'ui/shell/shell.dart';

/// In-memory appearance state for Phase 1 (dark default per D4).
/// Phase 2 moves persistence into the settings DB.
class AppearanceController extends StateNotifier<ThemeMode> {
  AppearanceController() : super(ThemeMode.dark);

  void set(ThemeMode mode) => state = mode;
}

final appearanceProvider =
    StateNotifierProvider<AppearanceController, ThemeMode>((ref) => AppearanceController());

class StarCodexApp extends ConsumerWidget {
  const StarCodexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final themeMode = ref.watch(appearanceProvider);
    return MaterialApp(
      title: 'Star Codex',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
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

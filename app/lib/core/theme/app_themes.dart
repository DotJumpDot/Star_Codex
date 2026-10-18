import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One selectable app theme (settings key `theme`). Accent + background are
/// hand-picked per theme; the Material scheme surfaces are derived from
/// [bg] so cards, sheets and app bars all belong to the same family.
///
/// Monokai / Monokai Night / Monokai Dark Soda / Sakura palettes come from
/// CometStream (`frontend/src/index.css`), the rest are popular editor
/// palettes (Nord, Dracula, Tokyo Night, …).
class StarThemeSpec {
  const StarThemeSpec(
    this.id,
    this.name, // brand-style name, identical in every language
    this.brightness,
    this.primary,
    this.bg, {
    this.secondary,
    this.surface = const Color(0xFF26262B),
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color primary;
  final Color bg;
  final Color? secondary;

  /// Reader page background (dark themes want near-black regardless of the
  /// scaffold tone).
  final Color surface;

  bool get isDark => brightness == Brightness.dark;
}

const stardust = Color(0xFF3A5BC7);

const starThemes = <StarThemeSpec>[
  // — dark —
  StarThemeSpec('stardust', 'Stardust', Brightness.dark, stardust,
      Color(0xFF121318)),
  StarThemeSpec('stardust_black', 'Stardust Black', Brightness.dark,
      stardust, Color(0xFF000000)),
  StarThemeSpec('monokai', 'Monokai', Brightness.dark, Color(0xFFA6E22E),
      Color(0xFF272822), secondary: Color(0xFFF92672)),
  StarThemeSpec('monokai_night', 'Monokai Night', Brightness.dark,
      Color(0xFFF92672), Color(0xFF1F1F1F), secondary: Color(0xFF66D9EF)),
  StarThemeSpec('monokai_soda', 'Monokai Dark Soda', Brightness.dark,
      Color(0xFFFD971F), Color(0xFF242424), secondary: Color(0xFF66D9EF)),
  StarThemeSpec('nord', 'Nord', Brightness.dark, Color(0xFF88C0D0),
      Color(0xFF2E3440), secondary: Color(0xFF81A1C1)),
  StarThemeSpec('dracula', 'Dracula', Brightness.dark, Color(0xFFBD93F9),
      Color(0xFF282A36), secondary: Color(0xFFFF79C6)),
  StarThemeSpec('tokyo_night', 'Tokyo Night', Brightness.dark,
      Color(0xFF7AA2F7), Color(0xFF1A1B26), secondary: Color(0xFFBB9AF7)),
  StarThemeSpec('mocha', 'Catppuccin Mocha', Brightness.dark,
      Color(0xFFCBA6F7), Color(0xFF1E1E2E), secondary: Color(0xFFF5C2E7)),
  StarThemeSpec('one_dark', 'One Dark', Brightness.dark, Color(0xFF61AFEF),
      Color(0xFF282C34), secondary: Color(0xFF98C379)),
  StarThemeSpec('gruvbox', 'Gruvbox Dark', Brightness.dark, Color(0xFFFE8019),
      Color(0xFF282828), secondary: Color(0xFFB8BB26)),
  StarThemeSpec('rose_pine', 'Rosé Pine', Brightness.dark, Color(0xFFEBBCBE),
      Color(0xFF191724), secondary: Color(0xFF9CCFD8)),
  StarThemeSpec('solarized_dark', 'Solarized Dark', Brightness.dark,
      Color(0xFFB58900), Color(0xFF002B36), secondary: Color(0xFF2AA198)),
  StarThemeSpec('midnight_blue', 'Midnight Blue', Brightness.dark,
      Color(0xFF4FC3F7), Color(0xFF0D1B2A), secondary: Color(0xFF1B4965)),
  // — light —
  StarThemeSpec('light', 'Light', Brightness.light, stardust,
      Color(0xFFF7F8FC), surface: Color(0xFFFFFFFF)),
  StarThemeSpec('sakura', 'Sakura', Brightness.light, Color(0xFFD4637D),
      Color(0xFFFFF7F9), secondary: Color(0xFF7FB069), surface: Color(0xFFFFFFFF)),
  StarThemeSpec('nord_light', 'Nord Light', Brightness.light,
      Color(0xFF5E81AC), Color(0xFFECEFF4), surface: Color(0xFFFFFFFF)),
  StarThemeSpec('latte', 'Catppuccin Latte', Brightness.light,
      Color(0xFF8839EF), Color(0xFFEFF1F5), surface: Color(0xFFFFFFFF)),
  StarThemeSpec('github_light', 'GitHub Light', Brightness.light,
      Color(0xFF0969DA), Color(0xFFFFFFFF), surface: Color(0xFFFFFFFF)),
  StarThemeSpec('solarized_light', 'Solarized Light', Brightness.light,
      Color(0xFFAF8300), Color(0xFFFDF6E3), secondary: Color(0xFF5B8A85),
      surface: Color(0xFFFFFFFF)),
];

/// Legacy values of the `theme` setting (v1.0) → current ids.
const _legacyThemeIds = {
  'dark': 'stardust',
  'black': 'stardust_black',
  'light': 'light',
};

StarThemeSpec themeById(String? raw) {
  final id = _legacyThemeIds[raw] ?? raw;
  for (final spec in starThemes) {
    if (spec.id == id) return spec;
  }
  return starThemes.first;
}

Color _shift(Color c, double lightnessDelta) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + lightnessDelta).clamp(0.0, 1.0))
      .toColor();
}

/// Full ThemeData for one spec: seeded scheme (component tones) with the
/// spec's accent + surface family layered on top, and the selected Google
/// font. [fontFamily] is a Google Fonts family name (see app_fonts.dart).
ThemeData buildTheme(StarThemeSpec spec, {String fontFamily = 'Sarabun'}) {
  final seeded = ColorScheme.fromSeed(
      seedColor: spec.primary, brightness: spec.brightness);
  final dark = spec.isDark;
  // Container tiers step away from the scaffold color — lighter on dark
  // themes, darker on light ones.
  final step = dark ? 0.035 : -0.025;
  final scheme = seeded.copyWith(
    primary: spec.primary,
    secondary: spec.secondary ?? seeded.secondary,
    surface: spec.bg,
    surfaceContainerLowest: _shift(spec.bg, -step * 1.4),
    surfaceContainerLow: _shift(spec.bg, step * 0.7),
    surfaceContainer: _shift(spec.bg, step),
    surfaceContainerHigh: _shift(spec.bg, step * 1.5),
    surfaceContainerHighest: _shift(spec.bg, step * 2.1),
  );
  final base = dark ? ThemeData.dark() : ThemeData.light();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: spec.bg,
    textTheme: GoogleFonts.getTextTheme(fontFamily, base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: spec.bg,
      scrolledUnderElevation: 2,
    ),
  );
}

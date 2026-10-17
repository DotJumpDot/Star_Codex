import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App themes (Plan/01 §6): Material 3, dark-first, seed #3A5BC7, Sarabun.
/// The pure-black dark variant is selectable in Settings (Phase 11 wiring).
class AppTheme {
  AppTheme._();

  static const seedColor = Color(0xFF3A5BC7);

  static ThemeData dark({bool pureBlack = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pureBlack ? Colors.black : null,
      textTheme: GoogleFonts.sarabunTextTheme(ThemeData.dark().textTheme),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: GoogleFonts.sarabunTextTheme(ThemeData.light().textTheme),
    );
  }
}

/// Optional heading font (Plan/01 §6): Prompt for big titles.
TextStyle headingStyle(BuildContext context) =>
    GoogleFonts.prompt(textStyle: Theme.of(context).textTheme.titleLarge);

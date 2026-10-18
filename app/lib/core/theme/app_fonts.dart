import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Selectable UI fonts (settings key `ui_font`). All Google Fonts families
/// — no bundled assets, no new dependencies. Prompt is the Maki Launcher
/// font (its `globals.css` ships Prompt for Thai + Latin); the rest are the
/// popular Thai/Latin picks.
class StarFontSpec {
  const StarFontSpec(this.id, this.family, this.name, {this.thai = true});

  final String id;
  final String family; // Google Fonts family
  final String name; // display name, identical in every language
  final bool thai; // family carries Thai glyphs
}

const starFonts = <StarFontSpec>[
  StarFontSpec('sarabun', 'Sarabun', 'Sarabun'),
  StarFontSpec('prompt', 'Prompt', 'Prompt'),
  StarFontSpec('kanit', 'Kanit', 'Kanit'),
  StarFontSpec('ibm_plex_thai', 'IBM Plex Sans Thai', 'IBM Plex Sans Thai'),
  StarFontSpec('noto_thai', 'Noto Sans Thai', 'Noto Sans Thai'),
  StarFontSpec('bai', 'Bai Jamjuree', 'Bai Jamjuree'),
  StarFontSpec('inter', 'Inter', 'Inter', thai: false),
  StarFontSpec('poppins', 'Poppins', 'Poppins', thai: false),
  StarFontSpec('roboto', 'Roboto', 'Roboto', thai: false),
  StarFontSpec('montserrat', 'Montserrat', 'Montserrat', thai: false),
  StarFontSpec('lato', 'Lato', 'Lato', thai: false),
  StarFontSpec('source_sans', 'Source Sans 3', 'Source Sans 3', thai: false),
];

StarFontSpec fontById(String? id) {
  for (final f in starFonts) {
    if (f.id == id) return f;
  }
  return starFonts.first;
}

/// Preview style for the font picker (each row rendered in its own font).
TextStyle fontPreviewStyle(StarFontSpec font, TextStyle base) =>
    GoogleFonts.getFont(font.family, textStyle: base);

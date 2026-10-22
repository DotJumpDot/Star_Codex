import 'package:flutter/material.dart';

/// Deterministic per-source accent colors for chips and result badges
/// (Plan/08 §2 "favicon-ish colored dot").
const _palette = <Color>[
  Color(0xFFE57373), // red
  Color(0xFF64B5F6), // blue
  Color(0xFF81C784), // green
  Color(0xFFFFB74D), // orange
  Color(0xFFBA68C8), // purple
  Color(0xFF4DD0E1), // cyan
  Color(0xFFFFD54F), // yellow
  Color(0xFFF06292), // pink
];

Color sourceDotColor(int index) => _palette[index % _palette.length];

/// Compact site label for the browse card's chips (user request
/// 2026-10-22: with 3+ merged sites the chip row wrapped to three lines
/// and pushed the series intro out of the card). "Manga" is the genre
/// word, not the brand — the brands are Slow / Go / Up / Dark / Bully /
/// Fin — so the trailing word goes: "Slow Manga" → "Slow",
/// "Go-Manga" → "Go", "Nekopost" stays.
String shortSourceName(String name) {
  final trimmed = name.trim();
  final match = RegExp(
    r'\s*[-–]?\s*Manga$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) return trimmed;
  final short = trimmed.substring(0, match.start).trim();
  return short.isEmpty ? trimmed : short;
}

/// What each site MOSTLY carries — display-only badges for the site
/// sheet's right-hand side (user QA 2026-10-19), not a filter; sources can
/// carry more than listed. Grounded 2026-10-19 by counting the sites' own
/// tile type badges (ts `.typename` spans, doujin-lc `manga-title-badges`)
/// AND the app DB's detail-page Type fields — e.g. go-manga: 33 Manhwa /
/// 5 Manhua / 2 Manga tiles + 22/5/1 in the DB ⇒ manhwa+manhua only.
const sourceContentTypes = <String, List<String>>{
  'nekopost': ['manga', 'novel'], // the only novel carrier (its API)
  'slow-manga': ['manhwa', 'manga'], // DB: 25 manhwa / 9 manga / 5 manhua
  'go-manga': ['manhwa', 'manhua'],
  'up-manga': ['manhwa', 'manhua'],
  'dark-manga': ['manhwa'],
  'fin-manga': ['manhwa'],
  'bully-manga': ['manhwa', 'manhua'], // DB: 24 / 6 / 5
  'ntr-manga': ['manga'], // JP NTR translations; no badges, untyped details
  'doujin-lc': ['manhwa'], // every archive badge reads Manhwa
  'hentaithai': ['manga'],
  'miku-doujin': ['manga'],
};

/// The little colored identity dot used on browse badges, detail source
/// rows and per-chapter source chips (doc 09 addendum).
class SourceDot extends StatelessWidget {
  const SourceDot({super.key, required this.color, this.size = 9});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

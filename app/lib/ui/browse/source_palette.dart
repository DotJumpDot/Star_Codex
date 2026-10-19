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

/// What each site MOSTLY carries — display-only badges for the site
/// sheet's right-hand side (user QA 2026-10-19), not a filter; sources can
/// carry more than listed. Nekopost is the only novel carrier.
const sourceContentTypes = <String, List<String>>{
  'nekopost': ['manga', 'novel'],
  'slow-manga': ['manga', 'manhwa', 'manhua'],
  'go-manga': ['manga', 'manhwa', 'manhua'],
  'up-manga': ['manga', 'manhwa', 'manhua'],
  'dark-manga': ['manga', 'manhwa', 'manhua'],
  'fin-manga': ['manga', 'manhwa', 'manhua'],
  'bully-manga': ['manga', 'manhwa'],
  'ntr-manga': ['manga'],
  'doujin-lc': ['manga', 'manhwa'],
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

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

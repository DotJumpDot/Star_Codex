import 'package:flutter/material.dart';

/// Age-coded date color shared by the detail chapter list AND the
/// browse/search card date labels (user request 2026-11-01: the two
/// surfaces used different palettes — the cards a fixed traffic-light
/// set, the chapter list the tuned ladder — make them ONE).
///
/// The ladder (user-tuned 2026-10-24): RAW theme accent for under a day
/// ("my theme color fully, not brighter"), then even hue steps toward
/// red with NO lightening — −30 (<1 week), −60 (<1 month),
/// −85 yellow (<3 mo), −105 orange (<6 mo), −120 deep orange (<1 y) —
/// then three distinct red variants for 1 y / 2-3 y / 3-4 y (each its
/// own red; the old end must stay colorful, not two twin greys), and
/// 4+ years greys out. Null (no date) = faded variant.
Color dateAgeColor(ColorScheme scheme, int? uploadedAtMs) {
  if (uploadedAtMs == null) {
    return scheme.onSurfaceVariant.withValues(alpha: 0.45);
  }
  final ageMs = DateTime.now().millisecondsSinceEpoch - uploadedAtMs;
  final hsl = HSLColor.fromColor(scheme.primary);
  Color drift(double degrees) =>
      hsl.withHue((hsl.hue + degrees + 360) % 360).toColor();

  final day = const Duration(days: 1).inMilliseconds;
  final week = const Duration(days: 7).inMilliseconds;
  final month = const Duration(days: 30).inMilliseconds;
  final threeMonths = const Duration(days: 91).inMilliseconds;
  final sixMonths = const Duration(days: 182).inMilliseconds;
  final year = const Duration(days: 365).inMilliseconds;
  final twoYears = const Duration(days: 730).inMilliseconds;
  final threeYears = const Duration(days: 1095).inMilliseconds;

  if (ageMs < day) return scheme.primary; // theme color, full strength
  if (ageMs < week) return drift(-30);
  if (ageMs < month) return drift(-60);
  if (ageMs < threeMonths) return drift(-85); // yellow
  if (ageMs < sixMonths) return drift(-105); // orange
  if (ageMs < year) return drift(-120); // deep orange
  if (ageMs < twoYears) return drift(-140); // red
  if (ageMs < threeYears) {
    // darker red
    final c = hsl.withHue((hsl.hue - 150 + 360) % 360);
    return c.withLightness((c.lightness - 0.06).clamp(0.0, 1.0)).toColor();
  }
  if (ageMs < const Duration(days: 1460).inMilliseconds) {
    // 3-4 years: deepest red
    final c = hsl.withHue((hsl.hue - 155 + 360) % 360);
    return c.withLightness((c.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }
  // 4+ years: greyed out
  return scheme.onSurfaceVariant.withValues(alpha: 0.45);
}

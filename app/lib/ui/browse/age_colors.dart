import 'package:flutter/material.dart';

/// Aged relative-date colors (user QA 2026-10-18): fresher reads green,
/// cooling to amber/orange over weeks, red-ish for months, grey for
/// years — shared by browse result cards and download-sheet chapter rows.
/// Keys are the i18n keys produced by `relativeParts`.
Color relativeAgeColor(ColorScheme scheme, String i18nKey) =>
    switch (i18nKey) {
      'relative.now' || 'relative.minutes' => const Color(0xFF4ADE80),
      'relative.hours' => const Color(0xFF2DD4BF),
      'relative.days' => const Color(0xFFFBBF24),
      'relative.weeks' => const Color(0xFFFB923C),
      'relative.months' => const Color(0xFFF87171),
      _ => scheme.onSurfaceVariant,
    };

/// Per-type chip colors (user QA 2026-10-18): มังงะ / มังฮวา / นิยาย must
/// be distinguishable at a glance on the result card's chip row.
Color? typeChipColor(String? type) => switch (type) {
      'manga' => const Color(0xFF38BDF8), // sky
      'manhwa' => const Color(0xFFA78BFA), // violet
      'manhua' => const Color(0xFFF59E0B), // amber
      'novel' => const Color(0xFF34D399), // emerald
      _ => null,
    };

/// The colored type pill (result cards, site-sheet rows): tinted fill +
/// border in the type's color so the type reads at a glance.
class TypeChip extends StatelessWidget {
  const TypeChip({super.key, required this.label, required this.type});

  final String label;
  final String? type;

  @override
  Widget build(BuildContext context) {
    final color = typeChipColor(type) ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

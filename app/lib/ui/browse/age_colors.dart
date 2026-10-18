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

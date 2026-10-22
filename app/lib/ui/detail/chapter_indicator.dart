import 'package:flutter/material.dart';

/// The read-state of one chapter, as shown by the little circle in front
/// of the chapter title on the detail screen.
enum ChapterReadState {
  /// Never opened — an empty ring.
  unread,

  /// Opened and read for a moment, not finished — a solid dot.
  reading,

  /// Finished — a solid dot with a check.
  read,
}

/// The circle in front of a chapter title (user request 2026-10-22:
/// it sits on the LEFT of "ตอนที่ N {name}", not on the right).
///
/// Three states, all sized the same so the column of chapters stays
/// aligned:
///
/// - [ChapterReadState.unread] — an empty ring, the theme's muted tone.
/// - [ChapterReadState.reading] — a solid dot in the theme's TERTIARY
///   color: still theme-derived (it follows the active theme like
///   everything else), but a different hue from the primary the
///   "read" state uses, so the two are never confusable.
/// - [ChapterReadState.read] — a solid dot in the theme's PRIMARY color
///   with a small check inside it (the check is smaller than the dot
///   itself — the old 18 px `Icons.check_circle` dwarfed the ring).
class ChapterStateDot extends StatelessWidget {
  const ChapterStateDot({super.key, required this.state});

  final ChapterReadState state;

  /// Sized to match the small circle the websites show next to a
  /// chapter (user feedback 2026-10-22: the first pass at 14 px read
  /// as a big blob next to the title). One constant to tune.
  static const double _size = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case ChapterReadState.unread:
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
              width: 1.2,
            ),
          ),
        );
      case ChapterReadState.reading:
        // Tertiary: theme-derived, but a different hue from the primary
        // the "read" dot uses.
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.tertiary,
          ),
        );
      case ChapterReadState.read:
        return Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
          ),
          // The check sits INSIDE the dot, so it never reads bigger
          // than the unread ring.
          child: Icon(
            Icons.check,
            size: _size - 4,
            color: scheme.onPrimary,
          ),
        );
    }
  }
}

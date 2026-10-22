import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Edge-pull "drag to continue" logic (replaces the old auto-next
/// countdown): the reader feeds overscroll deltas while the user drags
/// past an edge; progress follows a sqrt curve so it gets harder the
/// further they pull (rubber-band resistance). Committing happens on
/// release when the pull reached [threshold].
///
/// BIDIRECTIONAL (user request 2026-10-23): the extent is SIGNED —
/// positive while dragging past the end (next chapter), negative while
/// dragging past the start (previous chapter). Reversing the finger
/// shrinks the extent and the indicator follows; crossing zero into the
/// other direction retargets the pull.
class PullChapterTracker {
  PullChapterTracker({this.threshold = 260});

  /// Pull distance that arms the commit. Raised on 2026-10-23 (user:
  /// the old 170/160/120 per reader tripped too easily).
  final double threshold;

  double _extent = 0;

  /// +1 = pulling toward the NEXT chapter, -1 = toward the PREVIOUS,
  /// 0 = idle.
  double get direction => _extent.sign;

  /// The RAW signed extent (device px the finger dragged past the edge,
  /// already friction-damped by the scroll physics). Readers use it to
  /// slide the page up/sideways, opening the space the indicator sits
  /// in (Webtoon-style, user request 2026-10-23).
  double get extent => _extent;

  /// Normalized pull progress with resistance (sqrt curve, 0..1) for
  /// whichever direction is active.
  double get progress => math.sqrt((_extent.abs() / threshold).clamp(0.0, 1.0));

  /// Past the threshold — releasing now switches chapters in
  /// [direction].
  bool get armed => _extent.abs() >= threshold;

  bool get dragging => _extent != 0;

  /// Shrink toward zero by [delta] px — never crosses into the opposite
  /// direction. Used when the finger reversed back into content: the
  /// scroll position is in range again (overscroll notifications stop),
  /// so the reader feeds in-range movement here to make the indicator
  /// FALL BACK with the finger instead of vanishing (user report
  /// 2026-10-23).
  void shrink(double delta) {
    if (_extent == 0 || delta <= 0) return;
    final next = math.max(0.0, _extent.abs() - delta);
    _extent = next * _extent.sign;
  }

  void add(double overscrollPx) {
    _extent = (_extent + overscrollPx).clamp(
      -threshold * 1.35,
      threshold * 1.35,
    );
  }

  /// Fingers left the surface: +1 commit next, -1 commit previous,
  /// 0 spring back.
  int release() {
    final go = armed ? _extent.sign.toInt() : 0;
    _extent = 0;
    return go;
  }

  void cancel() => _extent = 0;
}

/// The floating indicator shown while pulling (Webtoon-style, reworked
/// 2026-10-23 after user feedback): a trail of dots growing SMALL TO
/// LARGE along the drag direction, ending in a direction arrow. The
/// progress fills the trail — each dot (then the arrow) tints from
/// faint white to the theme's PRIMARY as the pull deepens, so at 50 %
/// roughly the first half of the trail is colored. The vertical
/// readers run the trail top-to-bottom (arrow down when pulling on,
/// arrow up when pulling back); the paged reader runs the same trail
/// sideways along the reading direction (RTL-aware).
class PullNextIndicator extends StatelessWidget {
  const PullNextIndicator({
    super.key,
    required this.progress,
    required this.armed,
    this.back = false,
    this.horizontal = false,
    this.rtl = false,
    this.hasNext = true,
  });

  final double progress;
  final bool armed;

  /// Pulling toward the previous chapter — the trail flips so it always
  /// runs along the travel direction.
  final bool back;
  final bool horizontal;
  final bool rtl;

  /// False when there is no chapter on the pulled side — the trail
  /// collapses to a "the end" marker instead of teasing a switch.
  final bool hasNext;

  /// Dot sizes along the trail, small → large. The arrow comes after
  /// the last dot, clearly bigger and rendered bolder (layered
  /// same-color shadows thicken the glyph).
  static const List<double> _dotSizes = [9, 13, 17, 21];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final faint = Colors.white.withValues(alpha: 0.28);

    // Trail in TRAVEL order: dots small→large, then the arrow at the
    // end. `fill` colors that many items (fractional = one extra).
    final IconData arrow = !hasNext
        ? (back ? Icons.first_page : Icons.done_all)
        : horizontal
        ? // Next points along the reading direction: forward in LTR,
          // back in RTL; previous points against it.
          (rtl == back ? Icons.arrow_forward : Icons.arrow_back)
        : (back ? Icons.arrow_upward : Icons.arrow_downward);

    final fillUnits = hasNext
        ? progress.clamp(0.0, 1.0) * (_dotSizes.length + 1)
        : _dotSizes.length + 1;
    final label = !hasNext
        ? t(context, back ? 'reader.first' : 'reader.end')
        : armed
        ? t(context, back ? 'reader.pull_prev_release' : 'reader.pull_release')
        : t(context, back ? 'reader.prev_chapter' : 'reader.next_chapter');

    Widget trailItem(int index, {double? size, IconData? icon}) {
      final filled = fillUnits > index;
      final color = filled ? accent : faint;
      // Same-color offset shadows thicken the glyph — a faux bold, since
      // Material arrows have no weight axis.
      final boldOutline = [
        for (final o in const [
          Offset(1.2, 0),
          Offset(-1.2, 0),
          Offset(0, 1.2),
          Offset(0, -1.2),
        ])
          Shadow(color: color, offset: o),
      ];
      final iconShadow = [
        ...boldOutline,
        Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 4),
      ];
      final dotShadow = [
        BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 4),
      ];
      if (icon != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Icon(
            icon,
            size: size ?? _dotSizes.last + 10,
            color: color,
            shadows: iconShadow,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 2.5),
        child: Container(
          width: size!,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: dotShadow,
          ),
        ),
      );
    }

    final trail = <Widget>[
      for (var i = 0; i < _dotSizes.length; i++)
        trailItem(i, size: _dotSizes[i]),
      trailItem(_dotSizes.length, icon: arrow),
    ];

    return AnimatedScale(
      scale: armed && hasNext ? 1.12 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The trail runs along the TRAVEL direction: top-to-bottom for
          // a next pull, bottom-to-top (flipped) for a previous pull;
          // sideways for the paged reader, flipped for RTL/prev so the
          // arrow always sits at the far end of the drag.
          Flex(
            direction: horizontal ? Axis.horizontal : Axis.vertical,
            verticalDirection: back
                ? VerticalDirection.up
                : VerticalDirection.down,
            textDirection: horizontal && (rtl != back)
                ? TextDirection.rtl
                : TextDirection.ltr,
            mainAxisSize: MainAxisSize.min,
            children: trail,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              hasNext
                  ? armed
                        ? label
                        : '$label · ${(progress.clamp(0.0, 1.0) * 100).round()}%'
                  : label,
              style: TextStyle(
                color: armed && hasNext ? accent : Colors.white,
                fontSize: 12,
                fontWeight: armed && hasNext
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

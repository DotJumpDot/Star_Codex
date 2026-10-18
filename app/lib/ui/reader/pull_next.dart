import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Edge-pull "drag to continue" logic (replaces the old auto-next
/// countdown): the reader feeds overscroll deltas while the user drags
/// past the end; progress follows a sqrt curve so it gets harder the
/// further they pull (rubber-band resistance). Committing happens on
/// release when the pull reached [threshold].
class PullNextTracker {
  PullNextTracker({this.threshold = 130});

  final double threshold;

  double _extent = 0;

  /// Normalized pull progress with resistance (sqrt curve, 0..1).
  double get progress => math.sqrt((_extent / threshold).clamp(0.0, 1.0));

  /// Past the threshold — releasing now advances to the next chapter.
  bool get armed => _extent >= threshold;

  bool get dragging => _extent > 0;

  void add(double overscrollPx) {
    _extent = (_extent + overscrollPx).clamp(0.0, threshold * 1.35);
  }

  /// Fingers left the surface: true when the pull should commit.
  bool release() {
    final go = armed;
    _extent = 0;
    return go;
  }

  void cancel() => _extent = 0;
}

/// The floating pill shown while pulling: direction arrow + progress bar
/// that fills with the pull, flipping to an "advance" state when armed.
/// [horizontal] = paged reader (arrow points along reading direction);
/// vertical = webtoon/novel (arrow down).
class PullNextIndicator extends StatelessWidget {
  const PullNextIndicator({
    super.key,
    required this.progress,
    required this.armed,
    this.horizontal = false,
    this.rtl = false,
    this.hasNext = true,
  });

  final double progress;
  final bool armed;
  final bool horizontal;
  final bool rtl;

  /// False when there is no next chapter — the pill says "the end"
  /// instead of teasing an advance.
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final IconData arrow = !hasNext
        ? Icons.done_all
        : horizontal
            ? (rtl ? Icons.arrow_back : Icons.arrow_forward)
            : Icons.arrow_downward;
    final label = !hasNext
        ? t(context, 'reader.end')
        : armed
            ? t(context, 'reader.pull_release')
            : t(context, 'reader.pull_more');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: armed && hasNext
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.15),
          width: armed ? 1.6 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(arrow,
                  size: 20,
                  color: armed && hasNext ? scheme.primary : Colors.white70),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: armed && hasNext ? FontWeight.w700 : null,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 148,
            height: 4,
            child: LinearProgressIndicator(
              value: hasNext ? progress.clamp(0.0, 1.0) : 1,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(
                  armed && hasNext ? scheme.primary : Colors.white60),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

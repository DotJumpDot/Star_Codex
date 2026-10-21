/// Pure webtoon scroll math (doc 10 §5–6) — unit-testable without widgets.
library;

/// Prefix offsets of the slot heights: offsets[i] = top edge of slot i.
List<double> slotOffsets(List<double> heights) {
  final offsets = List<double>.filled(heights.length, 0);
  var acc = 0.0;
  for (var i = 0; i < heights.length; i++) {
    offsets[i] = acc;
    acc += heights[i];
  }
  return offsets;
}

/// Current page = first slot whose bottom edge is below the 40%-viewport
/// line (doc 10 §5). Falls back to the last slot at the very end.
int currentPageIndex(
  List<double> offsets,
  List<double> heights,
  double scrollOffset,
  double viewportHeight,
) {
  if (heights.isEmpty) return 0;
  final line = scrollOffset + viewportHeight * 0.4;
  for (var i = 0; i < heights.length; i++) {
    if (offsets[i] + heights[i] > line) return i;
  }
  return heights.length - 1;
}

/// Scroll-offset correction that keeps the viewport visually anchored
/// when slot [idx] resizes by [delta] (estimate → decoded height).
///
/// Lazy slots above the viewport correct their reserved heights while you
/// scroll BACK UP (pages below never mattered — they load after you pass
/// them). Without this, growing content above the viewport shoves the
/// visible pages down mid-drag: the feed feels stuck, then jumps (user
/// report 2026-10-19). If the slot sits entirely above the viewport top,
/// the offset must move by the same [delta] for the screen to show the
/// same pixels; a slot straddling or below the viewport needs no
/// correction (it was about to shift anyway / doesn't affect the anchor).
double heightAnchorDelta(
  List<double> offsets,
  List<double> heights,
  int idx,
  double delta,
  double scrollOffset,
) {
  if (idx < 0 || idx >= heights.length || delta == 0) return 0;
  final slotBottom = offsets[idx] + heights[idx];
  return slotBottom <= scrollOffset + 0.5 ? delta : 0;
}

/// Completed when the scroll is within one viewport of the max extent
/// (doc 10 §5 "completed" rule).
bool reachedEnd(double scrollOffset, double maxExtent, double viewportHeight) {
  if (maxExtent <= 0) return false;
  return scrollOffset >= maxExtent - viewportHeight;
}

/// Auto-next fires inside the END window (within 35% of a viewport from
/// max extent) once the LAST page's top has risen above the 65% viewport
/// line (doc 10 §6). The doc's literal "bottom passes 65%" assumed
/// over-scroll physics; Android clamping pins the bottom edge at the
/// screen bottom, making it unreachable (found on-device QA 2026-10-18).
bool shouldAutoNext(
  List<double> offsets,
  List<double> heights,
  double scrollOffset,
  double viewportHeight,
) {
  if (heights.isEmpty) return false;
  final lastTop = offsets.last;
  if (viewportHeight <= 0) return false;
  final max = offsets.last + heights.last - viewportHeight;
  if (max > 0 && scrollOffset < max - viewportHeight * 0.35) {
    return false; // not inside the end window yet
  }
  return scrollOffset + viewportHeight * 0.65 >= lastTop;
}

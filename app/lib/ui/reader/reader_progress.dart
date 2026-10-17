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

/// Completed when the scroll is within one viewport of the max extent
/// (doc 10 §5 "completed" rule).
bool reachedEnd(
    double scrollOffset, double maxExtent, double viewportHeight) {
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

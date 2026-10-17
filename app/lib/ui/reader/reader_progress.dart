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

/// Auto-next fires when the LAST page's bottom has passed 65% of the
/// viewport height above the scroll position (doc 10 §6).
bool shouldAutoNext(
  List<double> offsets,
  List<double> heights,
  double scrollOffset,
  double viewportHeight,
) {
  if (heights.isEmpty) return false;
  final lastBottom = offsets.last + heights.last;
  return scrollOffset + viewportHeight * 0.65 >= lastBottom;
}

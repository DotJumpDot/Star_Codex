import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Per-chapter screen crop for letterboxed webtoon strips (rare case:
/// some sites bake solid black bars down both sides — dark-manga
/// "Sashimi Knife" ch.96, 2026-10-21). Slots render [zoom]× wider than
/// the screen and the reader shows ONE fixed horizontal window of the
/// strip ([cropX] of the overflow) — horizontal movement is inherently
/// locked, only vertical scrolling works. Persisted per chapter via the
/// `reader_crop_ch<chapterId>` settings key (never global: normal
/// chapters must stay full-width).
class ReaderCrop {
  const ReaderCrop({this.zoom = 1.0, this.cropX = 0.5});

  /// Slot width multiplier. 1.0 = off.
  final double zoom;

  /// 0..1 — which part of the overflow sits hidden on the LEFT.
  /// 0 = left-aligned window, 0.5 = centered, 1 = right-aligned.
  final double cropX;

  bool get active => zoom > 1.01;

  /// Hidden-left px for a [screenWidth]-wide viewport.
  double offsetPx(double screenWidth) =>
      (screenWidth * zoom - screenWidth) * cropX;

  String encode() => '${zoom.toStringAsFixed(2)}|${cropX.toStringAsFixed(3)}';

  static ReaderCrop decode(String? raw) {
    if (raw == null || !raw.contains('|')) return const ReaderCrop();
    final parts = raw.split('|');
    final z = double.tryParse(parts[0]);
    final x = double.tryParse(parts[1]);
    if (z == null || x == null || z <= 1.001 || z > 4.0) {
      return const ReaderCrop();
    }
    return ReaderCrop(zoom: z.clamp(1.0, 4.0), cropX: x.clamp(0.0, 1.0));
  }

  @override
  String toString() => 'ReaderCrop(${zoom.toStringAsFixed(2)}x, '
      'cropX=${cropX.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is ReaderCrop &&
      other.zoom.toStringAsFixed(2) == zoom.toStringAsFixed(2) &&
      other.cropX.toStringAsFixed(3) == cropX.toStringAsFixed(3);

  @override
  int get hashCode =>
      Object.hash(zoom.toStringAsFixed(2), cropX.toStringAsFixed(3));
}

/// Column-mean-luminance profile → artwork window as width fractions.
/// Measured on the real letterboxed pages: bar columns average ≤5
/// luminance, artwork columns ≥138, so a threshold of 40 separates them
/// while ignoring the watermark text baked onto the bars (~2-4% bright
/// rows per bar column) and dark artwork hugging the column's inner
/// edges (each column is averaged over the FULL page height).
({double left, double width})? detectArtworkWindow(List<double> colMeans,
    {double threshold = 40}) {
  final w = colMeans.length;
  if (w < 8) return null;
  var first = 0;
  while (first < w && colMeans[first] < threshold) {
    first++;
  }
  var last = w - 1;
  while (last > first && colMeans[last] < threshold) {
    last--;
  }
  if (first > last) return null;
  final width = (last - first + 1) / w;
  // Only letterboxed pages are worth cropping: a nearly-full-width
  // window is a normal page, a tiny one is likely a false positive.
  if (width < 0.2 || width > 0.95) return null;
  return (left: first / w, width: width);
}

/// Crop that frames the detected artwork window: zoom so the artwork
/// spans the screen, window pushed to the artwork's left edge (for a
/// centered column that lands at cropX 0.5).
ReaderCrop? cropForWindow(double left, double width, {double maxZoom = 3.0}) {
  if (width <= 0.2 || width >= 0.95) return null;
  final zoom = (1 / width).clamp(1.0, maxZoom);
  final cropX = (left / (1 - width)).clamp(0.0, 1.0);
  return ReaderCrop(zoom: zoom, cropX: cropX);
}

/// Column mean luminance of a stored page file, decoded downscaled
/// (default 64px wide ≈ tens of k pixels — one-shot per chapter for
/// auto-detect). Returns null on any IO/decode failure.
Future<List<double>?> columnLuminanceMeans(String absolutePath,
    {int targetWidth = 64}) async {
  try {
    final Uint8List bytes;
    try {
      bytes = await File(absolutePath).readAsBytes();
    } catch (_) {
      return null;
    }
    final codec =
        await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null || w <= 0 || h <= 0) return null;
    final px = data.buffer.asUint8List();
    final means = List<double>.filled(w, 0);
    for (var y = 0; y < h; y++) {
      var row = y * w * 4;
      for (var x = 0; x < w; x++) {
        means[x] += (px[row] * 0.299 + px[row + 1] * 0.587 +
                px[row + 2] * 0.114) /
            h;
        row += 4;
      }
    }
    return means;
  } catch (_) {
    return null;
  }
}

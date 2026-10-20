import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/ui/reader/reader_crop.dart';

void main() {
  // Measured on the real letterboxed pages (dark-manga sashimi-knife
  // ch.96, 2026-10-21): 1000px wide, bars 206px each side, artwork
  // 588px centered. 64 sampled columns ≈ the decode target width.
  List<double> letterboxMeans({double barLum = 5, double artLum = 150}) {
    final n = 64;
    final left = (206 / 1000 * n).round(); // 13
    final right = left + (588 / 1000 * n).round(); // artwork ends ≈ col 51
    return [
      for (var x = 0; x < n; x++)
        (x < left || x >= right) ? barLum : artLum,
    ];
  }

  test('ReaderCrop encode/decode round-trip; junk → inactive default', () {
    const c = ReaderCrop(zoom: 1.68, cropX: 0.5);
    expect(ReaderCrop.decode(c.encode()), c);
    expect(ReaderCrop.decode(null).active, isFalse);
    expect(ReaderCrop.decode('').active, isFalse);
    expect(ReaderCrop.decode('garbage').active, isFalse);
    expect(ReaderCrop.decode('0.90|0.5').active, isFalse,
        reason: 'zoom <= 1 decodes to the off state');
    expect(ReaderCrop.decode('9.9|0.5').active, isFalse,
        reason: 'absurd zooms are rejected, not clamped into range');
    expect(const ReaderCrop().active, isFalse);
    expect(const ReaderCrop(zoom: 1.5, cropX: 0.2),
        const ReaderCrop(zoom: 1.5, cropX: 0.2));
    expect(const ReaderCrop(zoom: 1.5) == const ReaderCrop(zoom: 1.55),
        isFalse);
  });

  test('offsetPx: hidden-left px of the window', () {
    // Screen 400, zoom 2 → overflow 400; cropX .25 hides 100 on the left.
    expect(const ReaderCrop(zoom: 2.0, cropX: 0.25).offsetPx(400), 100);
    expect(const ReaderCrop(zoom: 1.0, cropX: 1.0).offsetPx(400), 0);
  });

  test('detectArtworkWindow: letterboxed profile → centered window', () {
    final win = detectArtworkWindow(letterboxMeans())!;
    expect(win.left, closeTo(0.2, 0.03));
    expect(win.width, closeTo(0.59, 0.05));
    // Watermark text on the bars barely raises a bar column's MEAN —
    // the threshold must not mistake it for artwork.
    final marked = letterboxMeans(barLum: 24);
    final win2 = detectArtworkWindow(marked)!;
    expect(win2.width, closeTo(win.width, 0.001));
  });

  test('detectArtworkWindow: normal and degenerate pages → null', () {
    expect(detectArtworkWindow(List.filled(64, 160)), isNull,
        reason: 'no bars — normal page');
    expect(detectArtworkWindow(List.filled(64, 3)), isNull,
        reason: 'all dark');
    expect(detectArtworkWindow([2, 2, 2, 2]), isNull, reason: 'too few cols');
    // A sliver of artwork (false positive guard).
    expect(
        detectArtworkWindow([
          for (var x = 0; x < 64; x++) x == 32 ? 200.0 : 2.0,
        ]),
        isNull);
  });

  test('cropForWindow: centered letterbox → 1.7× zoom, centered window',
      () {
    final crop = cropForWindow(0.206, 0.588)!;
    expect(crop.zoom, closeTo(1.70, 0.01));
    expect(crop.cropX, closeTo(0.5, 0.01));
    // Off-center artwork: window pushed toward its left edge, clamped.
    final off = cropForWindow(0.05, 0.6)!;
    expect(off.cropX, closeTo(0.05 / 0.4, 0.01));
    // Normal pages and slivers → null (nothing to crop).
    expect(cropForWindow(0.0, 1.0), isNull);
    expect(cropForWindow(0.4, 0.1), isNull);
  });
}

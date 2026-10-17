import 'dart:typed_data';

/// Header-only image dimension sniffing (no decode). Supports the formats
/// the pipeline accepts: JPEG, PNG, GIF, WebP (VP8/VP8L/VP8X). Returns
/// null when the header can't be parsed — callers treat it as unknown.
({int width, int height})? imageDimensions(Uint8List b) {
  if (b.length < 10) return null;
  // PNG: sig(8) + IHDR length(4)+type(4) + width(4)+height(4) big-endian.
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    if (b.length < 24) return null;
    final w = _be32(b, 16);
    final h = _be32(b, 20);
    return (w > 0 && h > 0) ? (width: w, height: h) : null;
  }
  // GIF: 'GIF8?a' + width(2)+height(2) little-endian.
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
    return (width: _le16(b, 6), height: _le16(b, 8));
  }
  // WebP: 'RIFF' + size(4) + 'WEBP' + chunk.
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    if (chunk == 'VP8X') {
      // Canvas size −1 as 24-bit little-endian at 24 and 27.
      final w = b[24] | (b[25] << 8) | (b[26] << 16);
      final h = b[27] | (b[28] << 8) | (b[29] << 16);
      return (width: w + 1, height: h + 1);
    }
    if (chunk == 'VP8 ') {
      // Frame tag(3) + sync 0x9D012A(3) then width/height le16.
      if (b.length < 30) return null;
      return (width: _le16(b, 26) & 0x3FFF, height: _le16(b, 28) & 0x3FFF);
    }
    if (chunk == 'VP8L') {
      // 0x2F sig, then 14-bit width−1 / height−1 packed into 4 bytes LE.
      if (b.length < 26 || b[20] != 0x2F) return null;
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return (width: (bits & 0x3FFF) + 1, height: ((bits >> 14) & 0x3FFF) + 1);
    }
    return null;
  }
  // JPEG: walk segment markers to an SOF frame.
  if (b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    // SOF parse reads through i+8 (width), so the segment must fit fully.
    while (i + 9 <= b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      // SOF0..SOF15 excluding C4 (DHT), C8 (JPG), CC (DAC).
      if (marker >= 0xC0 && marker <= 0xCF &&
          marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        final h = _be16(b, i + 5);
        final w = _be16(b, i + 7);
        return (w > 0 && h > 0) ? (width: w, height: h) : null;
      }
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2; // standalone marker
      } else {
        i += 2 + _be16(b, i + 2); // length-prefixed segment
      }
    }
  }
  return null;
}

int _be16(Uint8List b, int i) => (b[i] << 8) | b[i + 1];
int _le16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
int _be32(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

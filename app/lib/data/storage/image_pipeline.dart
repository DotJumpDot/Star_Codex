import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:crypto/crypto.dart';

import '../../core/net/net_exception.dart';
import '../../core/net/safe_http.dart';
import '../../core/utils/image_dimensions.dart';
import '../dao/blobs_dao.dart';
import '../sources/source_api.dart';
import 'blob_store.dart';

/// Result of the single write path used by reader cache AND downloads
/// (Plan/03 §pipeline).
class PageResult {
  const PageResult({
    required this.hash,
    required this.path,
    required this.storedBytes,
    this.width,
    this.height,
    required this.fromCache,
  });

  final String hash;
  final String path; // relative path under the library root
  final int storedBytes;
  final int? width;
  final int? height;
  final bool fromCache; // true = dedup hit, no fetch
}

/// Injectable WebP compressor (real one needs the platform plugin, which is
/// absent in unit tests). [originalW]/[originalH] express "no resize"
/// (the Android plugin REJECTS 0-sized targets — found on-device QA
/// 2026-10-18); [maxWidth] caps the width keeping aspect (S3).
typedef WebpCompressor = Future<Uint8List?> Function(Uint8List bytes,
    {int? originalW, int? originalH, int? maxWidth});

/// One GPU-safe horizontal band of an oversized page — see
/// [ImagePipeline.bandsFor].
class PageBand {
  const PageBand({required this.path, this.width, this.height});

  final String path; // relative under the library root
  final int? width;
  final int? height;
}

/// Native band slicer (Android BitmapRegionDecoder via the
/// star_codex/image_slice channel in MainActivity). Returns JPEG bytes
/// per full-width band, or null when unavailable (tests/desktop/failed).
typedef BandSlicer = Future<List<Uint8List>?> Function(
    String absolutePath, int maxBandHeight);

/// Download → validate → hash → dedup → WebP q80 → atomic write (Plan/03).
class ImagePipeline {
  ImagePipeline({
    required this.http,
    required this.blobs,
    WebpCompressor? compressor,
    BandSlicer? bandSlicer,
  })  : _compressor = compressor ?? _defaultCompressor,
        _bandSlicer = bandSlicer ?? _channelBandSlicer;

  final SafeHttp http;
  final BlobStore blobs;
  final WebpCompressor _compressor;
  final BandSlicer _bandSlicer;

  /// Pages taller than this get sliced: strips beyond ~8k-16k px exceed
  /// Android's max GPU texture size and render as a BLACK VOID (user
  /// report 2026-10-21: slow-manga 800×25049 pages — "A Villain's Will
  /// to Survive" ch.67/68, while the 14373px ch.69 passed).
  static const gpuBandThreshold = 8192;

  /// Each band decodes at ≤ this height — safe on every GPU (some old
  /// Mali parts cap at 4096).
  static const gpuBandHeight = 4096;

  static Future<Uint8List?> _defaultCompressor(Uint8List bytes,
      {int? originalW, int? originalH, int? maxWidth}) async {
    // The Android plugin rejects 0-sized targets ("width and height must
    // be > 0" — found on-device QA 2026-10-18): "no resize" passes the
    // ORIGINAL dimensions; unknown dims cannot be driven at all.
    final w = originalW ?? 0;
    final h = originalH ?? 0;
    if (w <= 0 || h <= 0) {
      if (kDebugMode) {
        debugPrint('IMGCOMP SKIP (dims unknown, ${bytes.length}B)');
      }
      return null; // → caller stores original bytes
    }
    var targetW = w;
    var targetH = h;
    if (maxWidth != null && maxWidth > 0 && maxWidth < w) {
      targetW = maxWidth;
      targetH = (h * maxWidth / w).round();
    }
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        quality: 80,
        format: CompressFormat.webp,
        inSampleSize: 1,
        minWidth: targetW,
        minHeight: targetH,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('IMGCOMP FAIL: $e');
      }
      return null; // weird format → caller stores original bytes
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<PageResult> fetchAndStore(String url, {String? referer}) async {
    final Uint8List original;
    try {
      original = await http.getBytes(Uri.parse(url), referer: referer);
    } on NetException catch (e) {
      throw SourceException('pipeline', SourceErrorKind.network,
          detail: e.toString());
    }

    if (!_isImage(original)) {
      throw StoreException('not an image (no image magic bytes): $url');
    }

    // Header-only sniff before any dedup/cache return, so every result
    // carries dimensions (chapter_pages.width/height, reader aspect ratio).
    final dims = imageDimensions(original);

    final hash = sha256.convert(original).toString();

    // Dedup: same original bytes already stored → touch + reuse (03 §3).
    if (await blobs.exists(hash)) {
      final row = (await blobs.blobRow(hash))!;
      await blobs.touch(hash, DateTime.now().millisecondsSinceEpoch);
      return PageResult(
        hash: hash,
        path: row.path,
        storedBytes: row.bytes,
        width: dims?.width,
        height: dims?.height,
        fromCache: true,
      );
    }

    // GIF (site banners/badges) → store as-is, no re-encode (03 §1).
    final isGif = _isGif(original);
    Uint8List stored;
    String ext;
    if (isGif) {
      stored = original;
      ext = 'gif';
    } else {
      final webp = await _compressor(original,
          originalW: dims?.width, originalH: dims?.height);
      if (webp != null && webp.isNotEmpty && !_sameBytes(webp, original)) {
        stored = webp;
        ext = 'webp';
      } else {
        // QA instrumentation (2026-10-18 on-device): every fetch landed here.
        if (kDebugMode) {
          debugPrint(
              'IMGCOMP FALLBACK null?${webp == null} empty?${webp != null && webp.isEmpty} same?${webp != null && _sameBytes(webp, original)}');
        }
        stored = original; // compression failed → keep original (03 §4)
        ext = _extensionFor(original);
      }
    }

    final rel = await blobs.write(hash, stored, ext: ext);
    final now = DateTime.now().millisecondsSinceEpoch;
    await blobs.insertRow(BlobRow(
      hash: hash,
      path: rel,
      bytes: stored.length,
      lastAccess: now,
    ));

    return PageResult(
      hash: hash,
      path: rel,
      storedBytes: stored.length,
      width: dims?.width,
      height: dims?.height,
      fromCache: false,
    );
  }

  /// URL-indexed variant for COVERS (db v7, 2026-10-20): [fetchAndStore]
  /// must download a URL before its content-hash dedup can hit — fine
  /// for reader pages (their URL tables answer before the network), but
  /// covers re-downloaded EVERY cover on EVERY app start. This checks
  /// the persistent blob_urls index first and answers from disk; an
  /// LRU-evicted blob makes the lookup miss and the fetch self-heals
  /// the row. Reader pages keep [fetchAndStore] (their repos own
  /// freshness via chapter_pages).
  Future<PageResult> fetchAndStoreIndexed(String url, {String? referer}) async {
    final indexed = await blobs.urlIndex(url);
    if (indexed != null && await blobs.exists(indexed.hash)) {
      final row = (await blobs.blobRow(indexed.hash))!;
      final now = DateTime.now().millisecondsSinceEpoch;
      await blobs.touch(indexed.hash, now);
      return PageResult(
        hash: indexed.hash,
        path: row.path,
        storedBytes: row.bytes,
        width: indexed.width,
        height: indexed.height,
        fromCache: true,
      );
    }
    final result = await fetchAndStore(url, referer: referer);
    await blobs.putUrlIndex(BlobUrlRow(
      url: url,
      hash: result.hash,
      width: result.width,
      height: result.height,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return result;
  }

  /// GPU-safe bands for an oversized page (see [gpuBandThreshold]).
  /// Cached in page_bands by the PARENT's content hash: as long as the
  /// band files survive, repeat reads slice nothing. Slicing failures
  /// (no native channel, decode error) return an EMPTY list — callers
  /// fall back to rendering the unsliced page.
  Future<List<PageBand>> bandsFor(PageResult parent) async {
    if ((parent.height ?? 0) <= gpuBandThreshold) return const [];
    final cached = await blobs.bandRows(parent.hash);
    if (cached.isNotEmpty) {
      var allPresent = true;
      for (final b in cached) {
        if (!await blobs.exists(b.hash)) {
          allPresent = false;
          break;
        }
      }
      if (allPresent) {
        return [
          for (final b in cached)
            PageBand(
                path: (await blobs.blobRow(b.hash))!.path,
                width: b.width,
                height: b.height),
        ];
      }
    }
    final slices = await _bandSlicer(
        blobs.absolutePath(parent.path), gpuBandHeight);
    if (slices == null || slices.isEmpty) return const [];
    final rows = <PageBandRow>[];
    final bands = <PageBand>[];
    for (var i = 0; i < slices.length; i++) {
      final bytes = slices[i];
      final hash = sha256.convert(bytes).toString();
      final dims = imageDimensions(bytes);
      if (!await blobs.exists(hash)) {
        final rel = await blobs.write(hash, bytes, ext: 'jpg');
        await blobs.insertRow(BlobRow(
          hash: hash,
          path: rel,
          bytes: bytes.length,
          lastAccess: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      final row = PageBandRow(
          idx: i, hash: hash, width: dims?.width, height: dims?.height);
      rows.add(row);
      bands.add(PageBand(
          path: (await blobs.blobRow(hash))!.path,
          width: dims?.width,
          height: dims?.height));
    }
    await blobs.putBands(parent.hash, rows);
    return bands;
  }

  static Future<List<Uint8List>?> _channelBandSlicer(
      String absolutePath, int maxBandHeight) async {
    try {
      final res = await const MethodChannel('star_codex/image_slice')
          .invokeMethod<List<Object?>>('slice', {
        'path': absolutePath,
        'maxBandHeight': maxBandHeight,
        'targetWidth': 0,
      });
      if (res == null) return null;
      return [for (final b in res) b as Uint8List];
    } catch (_) {
      return null; // tests/desktop — caller renders unsliced
    }
  }

  bool _isGif(Uint8List b) =>
      b.length > 6 &&
      (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) && // 'GIF'
      ((b[3] == 0x38 && b[4] == 0x37) || (b[3] == 0x38 && b[4] == 0x39));

  bool _isImage(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true; // PNG
    }
    if (_isGif(b)) return true;
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return true; // RIFF…WEBP
    }
    return false;
  }

  String _extensionFor(Uint8List b) {
    if (b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
    if (b[0] == 0x89 && b[1] == 0x50) return 'png';
    return 'img';
  }
}

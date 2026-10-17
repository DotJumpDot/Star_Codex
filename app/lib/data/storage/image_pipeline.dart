import 'dart:typed_data';

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
/// absent in unit tests).
typedef WebpCompressor = Future<Uint8List?> Function(Uint8List bytes,
    {int? maxWidth});

/// Download → validate → hash → dedup → WebP q80 → atomic write (Plan/03).
class ImagePipeline {
  ImagePipeline({
    required this.http,
    required this.blobs,
    WebpCompressor? compressor,
  })  : _compressor = compressor ?? _defaultCompressor;

  final SafeHttp http;
  final BlobStore blobs;
  final WebpCompressor _compressor;

  static Future<Uint8List?> _defaultCompressor(Uint8List bytes,
      {int? maxWidth}) async {
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        quality: 80,
        format: CompressFormat.webp,
        inSampleSize: 1,
        // Aspect-keeping width cap (S3: default null = no resize).
        minWidth: maxWidth ?? 0,
        minHeight: 0,
      );
    } catch (_) {
      return null; // weird format → caller stores original bytes
    }
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
      final webp = await _compressor(original);
      if (webp != null && webp.isNotEmpty) {
        stored = webp;
        ext = 'webp';
      } else {
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

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../dao/blobs_dao.dart';

/// Content-addressed blob store (Plan/03). Filename = sha256 of the ORIGINAL
/// downloaded bytes; 2-char shard dir by hash prefix. Dedup is natural:
/// identical images exist once.
class BlobStore {
  BlobStore({required Directory rootDir, required BlobsDao blobsDao})
      : _root = rootDir,
        _dao = blobsDao;

  final Directory _root;
  final BlobsDao _dao;

  Directory get blobsDir => Directory(p.join(_root.path, 'blobs'));

  Future<void> ensureDir() async {
    await blobsDir.create(recursive: true);
  }

  /// Relative path under the library root: `blobs/ab/<hash>.<ext>`.
  String relativePath(String hash, String ext) =>
      'blobs/${hash.substring(0, 2)}/$hash.$ext';

  String absolutePath(String relativePath) =>
      p.join(_root.path, relativePath);

  /// True when BOTH the DB row and the file exist (Plan/03 §Blob integrity).
  Future<bool> exists(String hash) async {
    final row = await _dao.byHash(hash);
    if (row == null) return false;
    return File(absolutePath(row.path)).exists();
  }

  Future<BlobRow?> blobRow(String hash) => _dao.byHash(hash);

  Future<BlobUrlRow?> urlIndex(String url) => _dao.urlIndex(url);

  Future<void> putUrlIndex(BlobUrlRow row) => _dao.upsertUrlIndex(row);

  Future<void> insertRow(BlobRow row) => _dao.upsert(row);

  Future<void> touch(String hash, int atMs) => _dao.touch(hash, atMs);

  Future<List<BlobRow>> listAll() => _dao.all();

  /// Atomic write: `<path>.tmp` then rename. Returns the relative path.
  Future<String> write(String hash, Uint8List bytes,
      {String ext = 'webp'}) async {
    final rel = relativePath(hash, ext);
    final f = File(absolutePath(rel));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    return rel;
  }

  Future<void> delete(String hash) async {
    final row = await _dao.byHash(hash);
    if (row != null) {
      final f = File(absolutePath(row.path));
      if (await f.exists()) await f.delete();
      await _dao.delete(hash);
    }
  }

  /// Sum of stored bytes. [pinned] true → pinned subset; false → UNPINNED
  /// subset (the LRU budget — Plan/03); null → everything.
  Future<int> totalBytes({bool? pinned}) {
    if (pinned == null) return _dao.totalBytes();
    return pinned ? _dao.pinnedBytes() : _dao.unpinnedBytes();
  }

  Future<List<BlobRow>> evictableOldestFirst({int limit = 500}) =>
      _dao.evictableOldestFirst(limit: limit);

  /// Startup integrity pass (Plan/03 §Blob integrity): rows without files
  /// lose the row (chapter_pages keeps content_hash → re-fetch later);
  /// files without rows are deleted.
  Future<({int rowsDropped, int filesDeleted})> integrityPass() async {
    var rowsDropped = 0;
    var filesDeleted = 0;
    final rows = await _dao.all();
    for (final row in rows) {
      if (!await File(absolutePath(row.path)).exists()) {
        await _dao.delete(row.hash);
        rowsDropped++;
      }
    }
    if (await blobsDir.exists()) {
      await for (final entity in blobsDir.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: _root.path);
        final name = p.basenameWithoutExtension(rel);
        final hasRow = await _dao.byHash(name) != null;
        if (!hasRow) {
          await entity.delete();
          filesDeleted++;
        }
      }
    }
    return (rowsDropped: rowsDropped, filesDeleted: filesDeleted);
  }
}

/// Storage-layer failure (Plan/01 §8 error convention).
class StoreException implements Exception {
  const StoreException(this.message);
  final String message;
  @override
  String toString() => 'StoreException: $message';
}

/// Quota refusal carries the remaining free bytes so UI can show
/// "พื้นที่ไม่พอ (เหลือ X GB)" (Plan/03 §Quota).
class QuotaException implements Exception {
  const QuotaException(this.freeBytes);
  final int freeBytes;
  @override
  String toString() => 'QuotaException: only $freeBytes bytes free';
}

import 'package:sqflite/sqflite.dart';

/// `blobs` — content-addressed store index (Plan/02, engine in Plan/03).
class BlobRow {
  const BlobRow({
    required this.hash,
    required this.path,
    required this.bytes,
    this.isPinned = false,
    required this.lastAccess,
  });

  final String hash; // sha256 of ORIGINAL downloaded bytes
  final String path; // relative path under the library dir
  final int bytes; // size of the stored .webp
  final bool isPinned;
  final int lastAccess;

  Map<String, Object?> toRow() => {
        'hash': hash,
        'path': path,
        'bytes': bytes,
        'is_pinned': isPinned ? 1 : 0,
        'last_access': lastAccess,
      };

  static BlobRow fromRow(Map<String, Object?> r) => BlobRow(
        hash: r['hash'] as String,
        path: r['path'] as String,
        bytes: r['bytes'] as int,
        isPinned: (r['is_pinned'] as int) == 1,
        lastAccess: r['last_access'] as int,
      );
}

class BlobsDao {
  BlobsDao(this.db);

  final Database db;

  Future<void> upsert(BlobRow b) =>
      db.insert('blobs', b.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<BlobUrlRow?> urlIndex(String url) async {
    final rows = await db
        .query('blob_urls', where: 'url = ?', whereArgs: [url], limit: 1);
    return rows.isEmpty ? null : BlobUrlRow.fromRow(rows.first);
  }

  Future<void> upsertUrlIndex(BlobUrlRow row) => db.insert(
      'blob_urls',
      {
        'url': row.url,
        'hash': row.hash,
        'width': row.width,
        'height': row.height,
        'fetched_at': row.fetchedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  /// Band rows of one oversized page, idx order (db v8; see
  /// ImagePipeline.bandsFor).
  Future<List<PageBandRow>> bandRows(String parentHash) async {
    final rows = await db.query('page_bands',
        where: 'parent_hash = ?',
        whereArgs: [parentHash],
        orderBy: 'idx ASC');
    return rows.map(PageBandRow.fromRow).toList(growable: false);
  }

  Future<void> putBands(String parentHash, List<PageBandRow> bands) =>
      db.transaction((txn) async {
        await txn.delete('page_bands',
            where: 'parent_hash = ?', whereArgs: [parentHash]);
        for (final b in bands) {
          await txn.insert('page_bands', b.toRow(parentHash));
        }
      });

  Future<BlobRow?> byHash(String hash) async {
    final rows = await db
        .query('blobs', where: 'hash = ?', whereArgs: [hash], limit: 1);
    return rows.isEmpty ? null : BlobRow.fromRow(rows.first);
  }

  Future<List<BlobRow>> all() async =>
      (await db.query('blobs')).map(BlobRow.fromRow).toList(growable: false);

  Future<bool> exists(String hash) async {
    final rows = await db.query('blobs',
        columns: ['hash'], where: 'hash = ?', whereArgs: [hash], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> touch(String hash, int atMs) =>
      db.update('blobs', {'last_access': atMs},
          where: 'hash = ?', whereArgs: [hash]);

  Future<void> setPinned(String hash, bool pinned) =>
      db.update('blobs', {'is_pinned': pinned ? 1 : 0},
          where: 'hash = ?', whereArgs: [hash]);

  Future<int> delete(String hash) =>
      db.delete('blobs', where: 'hash = ?', whereArgs: [hash]);

  Future<int> totalBytes() async {
    final r = await db.rawQuery('SELECT COALESCE(SUM(bytes), 0) AS n FROM blobs');
    return (r.first['n'] as num).toInt();
  }

  Future<int> pinnedBytes() async {
    final r = await db
        .rawQuery('SELECT COALESCE(SUM(bytes), 0) AS n FROM blobs WHERE is_pinned = 1');
    return (r.first['n'] as num).toInt();
  }

  Future<int> unpinnedBytes() async {
    final r = await db
        .rawQuery('SELECT COALESCE(SUM(bytes), 0) AS n FROM blobs WHERE is_pinned = 0');
    return (r.first['n'] as num).toInt();
  }

  /// Eviction candidates: unpinned, oldest-access first.
  Future<List<BlobRow>> evictableOldestFirst({int limit = 500}) async {
    final rows = await db.query('blobs',
        where: 'is_pinned = 0',
        orderBy: 'last_access ASC',
        limit: limit);
    return rows.map(BlobRow.fromRow).toList(growable: false);
  }

  /// Blobs not referenced by any chapter_pages, series cover, or
  /// blob_urls entry (orphans). Currently uncalled (the janitor's
  /// integrity pass only drops rows without files) — but any future
  /// orphan sweep MUST keep the blob_urls clause: a series row pins
  /// only the DETAIL cover, so listing-tile covers live solely in the
  /// URL index (2026-10-20).
  Future<List<String>> orphanHashes() async {
    final rows = await db.rawQuery('''
      SELECT b.hash FROM blobs b
      WHERE b.hash NOT IN (SELECT content_hash FROM chapter_pages WHERE content_hash IS NOT NULL)
        AND b.hash NOT IN (SELECT cover_hash FROM series WHERE cover_hash IS NOT NULL)
        AND b.hash NOT IN (SELECT hash FROM blob_urls)
    ''');
    return rows.map((r) => r['hash'] as String).toList(growable: false);
  }
}

/// `blob_urls` — URL → blob-hash index (db v7): lets covers load from
/// disk on warm starts. fetchAndStore must download a URL before its
/// content-hash dedup can hit, so without this index every cover
/// re-fetched on every app start (user report 2026-10-20).
class BlobUrlRow {
  const BlobUrlRow({
    required this.url,
    required this.hash,
    this.width,
    this.height,
    required this.fetchedAt,
  });

  final String url;
  final String hash;
  final int? width;
  final int? height;
  final int fetchedAt;

  static BlobUrlRow fromRow(Map<String, Object?> r) => BlobUrlRow(
        url: r['url'] as String,
        hash: r['hash'] as String,
        width: r['width'] as int?,
        height: r['height'] as int?,
        fetchedAt: r['fetched_at'] as int,
      );
}

/// `page_bands` (db v8): GPU-safe horizontal slices of one oversized
/// webtoon page, keyed by the PARENT blob's content hash — re-slicing
/// is skipped whenever the rows (and band files) survive.
class PageBandRow {
  const PageBandRow({
    required this.idx,
    required this.hash,
    this.width,
    this.height,
  });

  final int idx;
  final String hash;
  final int? width;
  final int? height;

  Map<String, Object?> toRow(String parentHash) => {
        'parent_hash': parentHash,
        'idx': idx,
        'hash': hash,
        'width': width,
        'height': height,
      };

  static PageBandRow fromRow(Map<String, Object?> r) => PageBandRow(
        idx: r['idx'] as int,
        hash: r['hash'] as String,
        width: r['width'] as int?,
        height: r['height'] as int?,
      );
}

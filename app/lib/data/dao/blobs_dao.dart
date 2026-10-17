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

  Future<BlobRow?> byHash(String hash) async {
    final rows = await db
        .query('blobs', where: 'hash = ?', whereArgs: [hash], limit: 1);
    return rows.isEmpty ? null : BlobRow.fromRow(rows.first);
  }

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

  /// Eviction candidates: unpinned, oldest-access first.
  Future<List<BlobRow>> evictableOldestFirst({int limit = 500}) async {
    final rows = await db.query('blobs',
        where: 'is_pinned = 0',
        orderBy: 'last_access ASC',
        limit: limit);
    return rows.map(BlobRow.fromRow).toList(growable: false);
  }

  /// Blobs not referenced by any chapter_pages or series cover (orphans).
  Future<List<String>> orphanHashes() async {
    final rows = await db.rawQuery('''
      SELECT b.hash FROM blobs b
      WHERE b.hash NOT IN (SELECT content_hash FROM chapter_pages WHERE content_hash IS NOT NULL)
        AND b.hash NOT IN (SELECT cover_hash FROM series WHERE cover_hash IS NOT NULL)
    ''');
    return rows.map((r) => r['hash'] as String).toList(growable: false);
  }
}

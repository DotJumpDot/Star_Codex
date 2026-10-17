import 'package:sqflite/sqflite.dart';

/// `library` + `categories` + `category_members` (Plan/02; screens in Plan/12).
class LibraryEntry {
  const LibraryEntry({
    required this.seriesId,
    required this.addedAt,
    this.lastReadAt,
    this.lastReadChapterId,
  });

  final int seriesId;
  final int addedAt;
  final int? lastReadAt;
  final int? lastReadChapterId;

  static LibraryEntry fromRow(Map<String, Object?> r) => LibraryEntry(
        seriesId: r['series_id'] as int,
        addedAt: r['added_at'] as int,
        lastReadAt: r['last_read_at'] as int?,
        lastReadChapterId: r['last_read_chapter_id'] as int?,
      );
}

class Category {
  const Category({required this.id, required this.name, required this.sort});

  final int id;
  final String name;
  final int sort;

  static Category fromRow(Map<String, Object?> r) => Category(
        id: r['id'] as int,
        name: r['name'] as String,
        sort: r['sort'] as int,
      );
}

class LibraryDao {
  LibraryDao(this.db);

  final Database db;

  Future<void> add(int seriesId, int atMs) =>
      db.insert('library', {'series_id': seriesId, 'added_at': atMs},
          conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> remove(int seriesId) =>
      db.delete('library', where: 'series_id = ?', whereArgs: [seriesId]);

  Future<bool> contains(int seriesId) async {
    final rows = await db.query('library',
        columns: ['series_id'],
        where: 'series_id = ?',
        whereArgs: [seriesId],
        limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<LibraryEntry>> all() async =>
      (await db.query('library', orderBy: 'added_at DESC'))
          .map(LibraryEntry.fromRow)
          .toList(growable: false);

  Future<void> markRead(int seriesId, int chapterId, int atMs) =>
      db.update(
        'library',
        {'last_read_at': atMs, 'last_read_chapter_id': chapterId},
        where: 'series_id = ?',
        whereArgs: [seriesId],
      );

  // --- categories ---

  Future<int> addCategory(String name, {int sort = 0}) async {
    final id = await db.insert('categories', {'name': name, 'sort': sort},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) return id;
    final rows = await db.query('categories',
        columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.first['id'] as int;
  }

  Future<List<Category>> categories() async =>
      (await db.query('categories', orderBy: 'sort, name'))
          .map(Category.fromRow)
          .toList(growable: false);

  Future<void> deleteCategory(int id) async {
    await db.delete('category_members',
        where: 'category_id = ?', whereArgs: [id]);
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToCategory(int seriesId, int categoryId) =>
      db.insert('category_members',
          {'series_id': seriesId, 'category_id': categoryId},
          conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> removeFromCategory(int seriesId, int categoryId) =>
      db.delete('category_members',
          where: 'series_id = ? AND category_id = ?',
          whereArgs: [seriesId, categoryId]);

  Future<List<Category>> categoriesOf(int seriesId) async {
    final rows = await db.rawQuery('''
      SELECT c.* FROM categories c
      JOIN category_members m ON m.category_id = c.id
      WHERE m.series_id = ?
      ORDER BY c.sort, c.name
    ''', [seriesId]);
    return rows.map(Category.fromRow).toList(growable: false);
  }
}

/// `reading_history` — History tab data; upsert on chapter completion
/// (read_at = now, times_read + 1). Grouped timeline screen is Plan/12 §5.
class HistoryDao {
  HistoryDao(this.db);

  final Database db;

  Future<void> recordCompletion(int chapterId, int seriesId, int atMs) async {
    await db.transaction((txn) async {
      final rows = await txn.query('reading_history',
          columns: ['times_read'],
          where: 'chapter_id = ?',
          whereArgs: [chapterId],
          limit: 1);
      final times = rows.isEmpty ? 0 : rows.first['times_read'] as int;
      await txn.insert(
          'reading_history',
          {
            'chapter_id': chapterId,
            'series_id': seriesId,
            'read_at': atMs,
            'times_read': times + 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<int> deleteForChapter(int chapterId) =>
      db.delete('reading_history', where: 'chapter_id = ?', whereArgs: [chapterId]);

  Future<int> clear() => db.delete('reading_history');
}

/// `downloads` — pinned downloads / queue rows (Plan/02; manager in Plan/13).
class DownloadsDao {
  DownloadsDao(this.db);

  final Database db;

  Future<void> enqueue(int chapterId,
          {int priority = 0, required int createdAt}) =>
      db.insert(
          'downloads',
          {
            'chapter_id': chapterId,
            'state': 'queued',
            'priority': priority,
            'created_at': createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> updateState(int chapterId, String state, {String? error}) =>
      db.update('downloads', {'state': state, 'error': error},
          where: 'chapter_id = ?', whereArgs: [chapterId]);

  Future<bool> isDownloaded(int chapterId) async {
    final rows = await db.query('downloads',
        columns: ['state'],
        where: 'chapter_id = ? AND state = ?',
        whereArgs: [chapterId, 'done'],
        limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> byState(String state) => db.query(
      'downloads',
      where: 'state = ?',
      whereArgs: [state],
      orderBy: 'priority DESC, created_at ASC');

  Future<int> delete(int chapterId) =>
      db.delete('downloads', where: 'chapter_id = ?', whereArgs: [chapterId]);
}

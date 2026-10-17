import 'package:sqflite/sqflite.dart';

/// `tags` + `series_tags` (Plan/02). Tag names keep original casing
/// ('Action', 'พระเอกเทพ'); uniqueness is case-sensitive per SQLite default.
class TagsDao {
  TagsDao(this.db);

  final Database db;

  Future<int> getOrCreate(String name) async {
    final id = await db.insert('tags', {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) return id;
    final rows = await db.query('tags',
        columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.first['id'] as int;
  }

  Future<List<String>> tagsOf(int seriesId) async {
    final rows = await db.rawQuery('''
      SELECT t.name FROM tags t
      JOIN series_tags st ON st.tag_id = t.id
      WHERE st.series_id = ?
      ORDER BY t.name
    ''', [seriesId]);
    return rows.map((r) => r['name'] as String).toList(growable: false);
  }

  /// Every known tag name (browse filter sheet, Plan/08 §3). Populated
  /// lazily from genres seen on detail pages — often empty early on.
  Future<List<String>> allNames() async {
    final rows = await db.query('tags', columns: ['name'], orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList(growable: false);
  }

  /// Replace the series' tag set atomically (Plan/02: series writes maintain
  /// tags in a transaction — used by series_repo in Phase 5+).
  Future<void> setForSeries(int seriesId, List<String> names) {
    return db.transaction((txn) async {
      await txn
          .delete('series_tags', where: 'series_id = ?', whereArgs: [seriesId]);
      for (final name in names) {
        final tagId = await txn.insert('tags', {'name': name},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        int resolvedId;
        if (tagId != 0) {
          resolvedId = tagId;
        } else {
          final rows = await txn.query('tags',
              columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
          resolvedId = rows.first['id'] as int;
        }
        await txn.insert('series_tags',
            {'series_id': seriesId, 'tag_id': resolvedId},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }
}

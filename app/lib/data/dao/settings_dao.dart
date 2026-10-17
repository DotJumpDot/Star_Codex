import 'package:sqflite/sqflite.dart';

/// `settings` + `search_history` (Plan/02). Values are plain strings; typed
/// accessors live in the settings provider.
class SettingsDao {
  SettingsDao(this.db);

  final Database db;

  Future<Map<String, String>> getAll() async {
    final rows = await db.query('settings');
    return {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
  }

  Future<void> upsert(String key, String value) =>
      db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  // --- search history ---

  Future<void> recordSearch(String query, int atMs) =>
      db.insert('search_history', {'query': query, 'at': atMs},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<String>> recentSearches({int limit = 20}) async {
    final rows = await db.query('search_history',
        columns: ['query'], orderBy: 'at DESC', limit: limit);
    return rows.map((r) => r['query'] as String).toList(growable: false);
  }

  Future<int> clearSearches() => db.delete('search_history');
}


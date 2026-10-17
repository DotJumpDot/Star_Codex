import 'package:sqflite/sqflite.dart';

/// `search_history` (Plan/02) — browse search box dropdown (Plan/08 §1):
/// dedupe by query, newest first, capped at 10 by the caller.
class SearchHistoryDao {
  SearchHistoryDao(this.db);

  final Database db;

  Future<void> record(String query, {required int atMs}) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await db.insert('search_history', {'query': q, 'at': atMs},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> recent({int limit = 10}) async {
    // rowid DESC breaks same-millisecond ties (INSERT OR REPLACE gives the
    // re-recorded query a fresh rowid).
    final rows = await db.query('search_history',
        columns: ['query'], orderBy: 'at DESC, rowid DESC', limit: limit);
    return rows.map((r) => r['query'] as String).toList(growable: false);
  }

  Future<int> clear() => db.delete('search_history');
}

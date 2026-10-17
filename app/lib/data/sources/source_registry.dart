import 'package:sqflite/sqflite.dart';

import '../../core/net/safe_http.dart';
import 'madara/configs.dart';
import 'madara/madara_source.dart';
import 'source_api.dart';

/// All live Source instances, ordered by the `sources` table `sort`
/// (Plan/04 §7). Nekopost joins in Phase 8.
Future<List<Source>> loadSources(Database db, SafeHttp http) async {
  final rows = await db.query('sources',
      where: 'enabled = 1 AND adapter = ?', whereArgs: ['madara'],
      orderBy: 'sort');
  final enabledIds = rows.map((r) => r['id'] as String).toSet();
  return madaraConfigs
      .where((c) => enabledIds.contains(c.id))
      .map((c) => MadaraSource(c, http))
      .toList();
}

import 'package:sqflite/sqflite.dart';

import '../../core/net/safe_http.dart';
import 'madara/configs.dart';
import 'madara/madara_source.dart';
import 'nekopost/nekopost_source.dart';
import 'source_api.dart';

/// All live Source instances, ordered by the `sources` table `sort`
/// (Plan/04 §7). Adapter column decides the class.
Future<List<Source>> loadSources(Database db, SafeHttp http) async {
  final rows = await db
      .query('sources', where: 'enabled = 1', orderBy: 'sort');
  final sources = <Source>[];
  for (final row in rows) {
    switch (row['adapter'] as String) {
      case 'madara':
        final id = row['id'] as String;
        for (final config in madaraConfigs) {
          if (config.id == id) sources.add(MadaraSource(config, http));
        }
      case 'nekopost':
        sources.add(NekopostSource(http));
    }
  }
  return sources;
}

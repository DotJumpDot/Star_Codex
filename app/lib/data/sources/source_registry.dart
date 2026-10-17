import 'package:sqflite/sqflite.dart';

import '../../core/net/safe_http.dart';
import 'madara/configs.dart';
import 'madara/madara_source.dart';
import 'nekopost/nekopost_source.dart';
import 'source_api.dart';

/// All live Source instances, ordered by the `sources` table `sort`
/// (Plan/04 §7). Adapter column decides the class.
/// [onlyEnabled] false lets the Settings screen build instances of
/// disabled sources for the "ทดสอบการเชื่อมต่อ" button (doc 14).
Future<List<Source>> loadSources(Database db, SafeHttp http,
    {bool onlyEnabled = true}) async {
  final rows = await db.query('sources',
      where: onlyEnabled ? 'enabled = 1' : null,
      orderBy: 'sort');
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

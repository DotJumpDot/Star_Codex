import 'package:sqflite/sqflite.dart';

import '../../core/net/safe_http.dart';
import 'bully/bully_source.dart';
import 'hentaithai/hentaithai_source.dart';
import 'madara/configs.dart';
import 'madara/madara_source.dart';
import 'miku/miku_source.dart';
import 'nekopost/nekopost_source.dart';
import 'source_api.dart';

/// Adult (18+) sources — shown ONLY on the dedicated Doujin page, never
/// in the main browse feed/search (user request 2026-10-19).
const adultSourceIds = <String>{
  'ntr-manga',
  'doujin-lc',
  'hentaithai',
  'miku-doujin',
};

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
      case 'bully':
        sources.add(BullyMangaSource(http));
      case 'hentaithai':
        sources.add(HentaiThaiSource(http));
      case 'miku':
        sources.add(MikuDoujinSource(http));
    }
  }
  return sources;
}

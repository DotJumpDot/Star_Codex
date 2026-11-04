import 'package:sqflite/sqflite.dart';

import '../../core/net/safe_http.dart';
import 'bully/bully_source.dart';
import 'hentaithai/hentaithai_source.dart';
import 'madara/configs.dart';
import 'madara/madara_source.dart';
import 'manghaha/manghaha_source.dart';
import 'miku/miku_source.dart';
import 'nekopost/nekopost_source.dart';
import 'niceoppai/niceoppai_source.dart';
import 'oremanga/oremanga_source.dart';
import 'source_api.dart';
import 'toonary/configs.dart';
import 'toonary/toonary_source.dart';

/// Adult (18+) sources — shown ONLY on the dedicated Doujin page, never
/// in the main browse feed/search (user request 2026-10-19; manghaha
/// joined 2026-11-03).
const adultSourceIds = <String>{
  'ntr-manga',
  'doujin-lc',
  'hentaithai',
  'miku-doujin',
  'manghaha',
};

/// MIX sources (2026-10-28): sites whose catalogs mix normal AND 18+
/// content (plus a heavy yaoi share — the Mix tab filters yaoi by
/// default). Own tab; never in the main feed or the Doujin page.
/// niceoppai joined 2026-11-03 (its category cloud includes Adult/yaoi);
/// inu-manga joined 2026-11-04 (mixed manga/manhwa/manhua catalog).
const mixSourceIds = <String>{
  'mangary',
  'whytoon',
  'niceoppai',
  'inu-manga',
};

/// Feed universes: main = everything except adult + mix; mix = mix only;
/// adult = adult only.
enum BrowseScope { main, mix, adult }

List<String> sourceIdsForScope(BrowseScope scope, Iterable<String> all) {
  switch (scope) {
    case BrowseScope.main:
      return [
        for (final id in all)
          if (!adultSourceIds.contains(id) && !mixSourceIds.contains(id)) id,
      ];
    case BrowseScope.mix:
      return [for (final id in all) if (mixSourceIds.contains(id)) id];
    case BrowseScope.adult:
      return [for (final id in all) if (adultSourceIds.contains(id)) id];
  }
}

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
      case 'toonary':
        final id = row['id'] as String;
        for (final config in toonaryConfigs) {
          if (config.id == id) sources.add(ToonarySource(config, http));
        }
      case 'manghaha':
        sources.add(ManghahaSource(http));
      case 'niceoppai':
        sources.add(NiceoppaiSource(http));
      case 'oremanga':
        sources.add(OremangaSource(http));
    }
  }
  return sources;
}

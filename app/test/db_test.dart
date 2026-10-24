import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:star_codex/data/db.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUp(() async {
    db = await openTestDb();
  });

  test('opens and creates every v1 table', () async {
    final tables = await db.query('sqlite_master',
        columns: ['name'],
        where: "type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'");
    final names = tables.map((t) => t['name'] as String).toSet();
    const expected = {
      'sources',
      'series',
      'series_sources',
      'tags',
      'series_tags',
      'chapters',
      'chapter_pages',
      'chapter_text',
      'blobs',
      'blob_urls',
      'page_bands',
      'read_progress',
      'reading_history',
      'library',
      'categories',
      'category_members',
      'downloads',
      'settings',
      'search_history',
      'feed_anchors',
    };
    expect(names.difference(expected), isEmpty,
        reason: 'unexpected extra tables');
    expect(expected.difference(names), isEmpty,
        reason: 'missing tables');
  });

  test('seeds all eleven sources', () async {
    final rows = await db.query('sources', orderBy: 'sort');
    expect(rows.length, 11);
    final byId = {for (final r in rows) r['id'] as String: r};
    expect(byId['slow-manga']!['base_url'], 'https://www.slow-manga.net');
    expect(byId['go-manga']!['adapter'], 'madara');
    expect(byId['up-manga']!['adapter'], 'madara');
    expect(byId['dark-manga']!['adapter'], 'madara');
    expect(byId['nekopost']!['adapter'], 'nekopost');
    expect(byId['nekopost']!['base_url'], 'https://www.nekopost.net');
    expect(byId['fin-manga']!['adapter'], 'madara');
    expect(byId['bully-manga']!['adapter'], 'bully');
    expect(byId['ntr-manga']!['adapter'], 'madara');
    expect(byId['doujin-lc']!['adapter'], 'madara');
    expect(byId['hentaithai']!['adapter'], 'hentaithai');
    expect(byId['miku-doujin']!['adapter'], 'miku');
    // db v9 (2026-10-23): every source seeds ON — the WAF ladder made
    // the last two Cloudflare-blocked ones reachable.
    expect(byId['doujin-lc']!['enabled'], 1,
        reason: 'v9 re-enabled the WAF-unlocked sources');
    expect(byId['miku-doujin']!['enabled'], 1,
        reason: 'v9 re-enabled the WAF-unlocked sources');
    expect(byId['ntr-manga']!['enabled'], 1);
    expect(byId['hentaithai']!['enabled'], 1);
  });

  test('v1→v5 migration adds the new sources + quota + last_seen_at', () async {
    await openTestDb(); // init sqflite ffi for direct file opens
    final dbPath =
        p.join(Directory.systemTemp.createTempSync('sc_mig').path, 'mig.db');
    // Build a pretend-v1 install: fresh current-version DB rolled back to
    // version 1, with the v1-era rows (5 sources, 100 GB quota default)
    // and the v1-era library table (no last_seen_at — the v4 ALTER must
    // be the one adding it, and SQLite refuses a duplicate column).
    final v1 = await openDb(
        path: dbPath, factory: databaseFactoryFfi, singleInstance: false);
    await v1.delete('sources',
        where: "id IN ('fin-manga','bully-manga',"
            "'ntr-manga','doujin-lc','hentaithai','miku-doujin')");
    await v1.execute(
        "UPDATE settings SET value = '107374182400' "
        "WHERE key = 'total_quota_bytes'");
    await v1.execute('DROP TABLE library');
    await v1.execute('''
      CREATE TABLE library(
        series_id           INTEGER PRIMARY KEY REFERENCES series(id) ON DELETE CASCADE,
        added_at            INTEGER NOT NULL,
        last_read_at        INTEGER,
        last_read_chapter_id INTEGER REFERENCES chapters(id) ON DELETE SET NULL
      )''');
    // Dropped so the chained v7/v8 CREATEs (blob_urls, page_bands) are the
    // ones adding them — the fabricated DB is built from the CURRENT
    // schema (see the v4 note above about duplicate columns).
    await v1.execute('DROP TABLE blob_urls');
    await v1.execute('DROP TABLE page_bands');
    await v1.execute('DROP TABLE feed_anchors');
    await v1.setVersion(1);
    await v1.close();

    // Reopen at the current version → onUpgrade chains case 1 → 2 → 3.
    final db = await openDb(
        path: dbPath, factory: databaseFactoryFfi, singleInstance: false);
    final rows = await db.query('sources');
    expect(rows.length, 11,
        reason: 'migration must (re)insert every post-v1 source row');
    // The v1→v9 chain inserts the adult rows (v5), v6 disables the two
    // Cloudflare-blocked ones, and v9 re-enables them (WAF ladder,
    // 2026-10-23) — end state matches fresh seeds.
    final byId = {for (final r in rows) r['id'] as String: r};
    expect(byId['doujin-lc']!['enabled'], 1,
        reason: 'v9 must re-enable the sources v6 disabled');
    expect(byId['miku-doujin']!['enabled'], 1);
    expect(byId['ntr-manga']!['enabled'], 1);
    final quota =
        await db.query('settings', where: "key = 'total_quota_bytes'");
    expect(quota.first['value'], '21474836480');
    final libCols = await db.rawQuery('PRAGMA table_info(library)');
    expect(
      libCols.where((c) => c['name'] == 'last_seen_at'),
      isNotEmpty,
      reason: 'v4 adds the last_seen_at visit stamp for the New chip');
    // v7 creates the cover URL→blob index (fetchAndStoreIndexed).
    await db.insert('blob_urls', {
      'url': 'https://x/c.jpg',
      'hash': 'ab',
      'fetched_at': 1,
    });
    expect(await db.query('blob_urls'), hasLength(1));
    // v10 creates the sticky feed time anchors.
    await db.insert('feed_anchors', {
      'source_id': 'fin-manga',
      'series_url': 'https://www.fin-manga.com/x/',
      'chapter_hint': 69,
      'stamp_ms': 1000,
      'updated_at': 2000,
    });
    expect(await db.query('feed_anchors'), hasLength(1));
    await db.close();
  });

  test('seeds the default settings rows', () async {
    final rows = await db.query('settings');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    expect(map['language'], 'th');
    expect(map['theme'], 'stardust');
    expect(map['cache_limit_bytes'], '5368709120'); // 5 GiB
    expect(map['total_quota_bytes'], '21474836480'); // 20 GiB
    expect(map['filter_min_chapters'], '0'); // OFF — decision L1
    expect(map['filter_hide_oneshot'], '0');
    expect(map['reader_mode_default'], 'auto');
    expect(map['reader_prefetch_ahead'], '6');
    expect(map['updates_last_run'], '0');
    expect(map['novel_font_size'], '18');
    expect(map['novel_line_height'], '1.7');
    expect(map['novel_bg_opacity'], '1.0');
  });

  test('series unique index rejects duplicate title_norm', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('series', {
      'title': 'Test',
      'title_norm': 'test norm',
      'created_at': now,
      'updated_at': now,
    });
    expect(
      () => db.insert('series', {
        'title': 'Test II',
        'title_norm': 'test norm',
        'created_at': now,
        'updated_at': now,
      }),
      throwsA(anything),
    );
  });

  test('foreign keys are enforced (PRAGMA on)', () async {
    final r = await db.rawQuery('PRAGMA foreign_keys');
    expect((r.first.values.first as int), 1);
  });
}

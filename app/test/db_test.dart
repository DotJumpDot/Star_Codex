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
      'read_progress',
      'reading_history',
      'library',
      'categories',
      'category_members',
      'downloads',
      'settings',
      'search_history',
    };
    expect(names.difference(expected), isEmpty,
        reason: 'unexpected extra tables');
    expect(expected.difference(names), isEmpty,
        reason: 'missing tables');
  });

  test('seeds the seven sources', () async {
    final rows = await db.query('sources', orderBy: 'sort');
    expect(rows.length, 7);
    final byId = {for (final r in rows) r['id'] as String: r};
    expect(byId['slow-manga']!['base_url'], 'https://www.slow-manga.net');
    expect(byId['go-manga']!['adapter'], 'madara');
    expect(byId['up-manga']!['adapter'], 'madara');
    expect(byId['dark-manga']!['adapter'], 'madara');
    expect(byId['nekopost']!['adapter'], 'nekopost');
    expect(byId['nekopost']!['base_url'], 'https://www.nekopost.net');
    expect(byId['fin-manga']!['adapter'], 'madara');
    expect(byId['bully-manga']!['adapter'], 'bully');
  });

  test('v1→v3 migration adds the new sources + quota default fix', () async {
    await openTestDb(); // init sqflite ffi for direct file opens
    final dbPath =
        p.join(Directory.systemTemp.createTempSync('sc_mig').path, 'mig.db');
    // Build a pretend-v1 install: fresh v3 DB rolled back to version 1,
    // with the v1-era rows (5 sources, 100 GB quota default).
    final v1 = await openDb(
        path: dbPath, factory: databaseFactoryFfi, singleInstance: false);
    await v1.delete('sources',
        where: "id IN ('fin-manga','bully-manga')");
    await v1.execute(
        "UPDATE settings SET value = '107374182400' "
        "WHERE key = 'total_quota_bytes'");
    await v1.setVersion(1);
    await v1.close();

    // Reopen at the current version → onUpgrade chains case 1 → case 2.
    final db = await openDb(
        path: dbPath, factory: databaseFactoryFfi, singleInstance: false);
    final rows = await db.query('sources');
    expect(rows.length, 7,
        reason: 'migration must (re)insert fin-manga + bully-manga');
    final quota =
        await db.query('settings', where: "key = 'total_quota_bytes'");
    expect(quota.first['value'], '21474836480');
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

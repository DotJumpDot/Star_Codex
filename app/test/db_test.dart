import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('seeds the five sources', () async {
    final rows = await db.query('sources', orderBy: 'sort');
    expect(rows.length, 5);
    final byId = {for (final r in rows) r['id'] as String: r};
    expect(byId['slow-manga']!['base_url'], 'https://www.slow-manga.net');
    expect(byId['go-manga']!['adapter'], 'madara');
    expect(byId['up-manga']!['adapter'], 'madara');
    expect(byId['dark-manga']!['adapter'], 'madara');
    expect(byId['nekopost']!['adapter'], 'nekopost');
    expect(byId['nekopost']!['base_url'], 'https://www.nekopost.net');
  });

  test('seeds the default settings rows', () async {
    final rows = await db.query('settings');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    expect(map['language'], 'th');
    expect(map['theme'], 'dark');
    expect(map['cache_limit_bytes'], '5368709120'); // 5 GiB
    expect(map['total_quota_bytes'], '107374182400'); // 100 GiB
    expect(map['filter_min_chapters'], '0'); // OFF — decision L1
    expect(map['filter_hide_oneshot'], '0');
    expect(map['reader_mode_default'], 'auto');
    expect(map['reader_prefetch_ahead'], '6');
    expect(map['updates_last_run'], '0');
    expect(map['novel_font_size'], '18');
    expect(map['novel_line_height'], '1.7');
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

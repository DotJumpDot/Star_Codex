import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Single SQLite database (Plan/02). All timestamps are milliseconds since
/// epoch (int). Migrations append only: bump [dbVersion], add a `case` in
/// [onUpgrade] — never edit v1 statements after shipping.
const dbVersion = 8;
const dbFileName = 'manga_reader.db';

class DbException implements Exception {
  const DbException(this.message);
  final String message;
  @override
  String toString() => 'DbException: $message';
}

Future<String> defaultDbPath() async {
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, dbFileName);
}

/// [path] and [factory] are injectable for tests (in-memory / temp file via
/// sqflite_common_ffi). Tests must pass [singleInstance] false so each
/// `:memory:` open creates an independent database.
Future<Database> openDb(
    {String? path, DatabaseFactory? factory, bool singleInstance = true}) async {
  final dbPath = path ?? await defaultDbPath();
  return (factory ?? databaseFactory).openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: dbVersion,
      singleInstance: singleInstance,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seed(db);
      },
      onUpgrade: (db, fromVersion, toVersion) async {
        switch (fromVersion) {
          // v2 (2026-10-18, UX overhaul): download quota default 100→20 GB
          // (only installs still on the old default move; an explicit user
          // value survives). Theme values migrate at runtime via
          // themeById(), no row rewrite needed.
          case 1:
            await db.execute(
                "UPDATE settings SET value = '21474836480' "
                "WHERE key = 'total_quota_bytes' AND value = '107374182400'");
            continue next; // Dart cases don't fall through — chain to v3
          // v3 (2026-10-18, new sources): fin-manga + bully-manga rows for
          // installs seeded before they existed. INSERT OR IGNORE keeps it
          // idempotent (fresh installs already seed them).
          next:
          case 2:
            for (var i = 0; i < _seededSources.length; i++) {
              final s = _seededSources[i];
              await db.insert(
                  'sources',
                  {
                    'id': s.$1,
                    'name': s.$2,
                    'base_url': s.$3,
                    'adapter': s.$4,
                    'enabled': 1,
                    'sort': i,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            continue next2; // Dart cases don't fall through — chain to v4
          // v4 (2026-10-18, library New chip): per-series last-visit stamp.
          // New = chapters with uploaded_at > max(last_read_at,
          // last_seen_at) — visiting the detail page clears the chip, a
          // later upload re-arms it. 0 = never seen (kept "new" behavior
          // comes from last_read_at, which stays NULL until first read).
          next2:
          case 3:
            await db.execute(
                'ALTER TABLE library ADD COLUMN last_seen_at INTEGER '
                'NOT NULL DEFAULT 0');
            continue next3; // Dart cases don't fall through — chain to v5
          // v5 (2026-10-19, adult doujin sites): the four 18+ source rows
          // for installs seeded before they existed. INSERT OR IGNORE is
          // idempotent (fresh installs already seed them).
          next3:
          case 4:
            for (var i = 0; i < _seededSources.length; i++) {
              final s = _seededSources[i];
              if (i < 7) continue; // rows 0-6 predate v5 and already exist
              await db.insert(
                  'sources',
                  {
                    'id': s.$1,
                    'name': s.$2,
                    'base_url': s.$3,
                    'adapter': s.$4,
                    'enabled': 1,
                    'sort': i,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            continue next4; // chain to v6
          // v6 (2026-10-19): doujin-lc + miku-doujin sit behind a
          // Cloudflare WAF that fingerprint-blocks Dart's TLS stack
          // ("Attention Required!" 403 for every app request while
          // browsers pass) — seed them OFF; users can still re-enable in
          // Settings. The adapters stay correct for if the sites lift it.
          next4:
          case 5:
            await db.execute(
                "UPDATE sources SET enabled = 0 "
                "WHERE id IN ('doujin-lc', 'miku-doujin') AND enabled = 1");
            continue next5; // chain to v7
          // v7 (2026-10-20, cover disk cache): URL → blob-hash index so
          // covers load from disk on warm starts. fetchAndStore always
          // re-downloads before its content-hash dedup can hit — fine for
          // reader pages (they keep their own URL tables), wrong for
          // covers, which re-fetched EVERY cover on every app start
          // (user report 2026-10-20). No FK to blobs on purpose: an
          // LRU-evicted blob makes the lookup miss and the next fetch
          // self-heals the row.
          next5:
          case 6:
            await db.execute('''
              CREATE TABLE blob_urls(
                url        TEXT PRIMARY KEY,
                hash       TEXT NOT NULL,
                width      INTEGER,
                height     INTEGER,
                fetched_at INTEGER NOT NULL
              )''');
            continue next6; // chain to v8
          // v8 (2026-10-21, oversized webtoon strips): GPU-safe band
          // slices of pages taller than the texture limit (slow-manga
          // serves 800x25049 strips that rendered as a black void —
          // "A Villain's Will to Survive" ch.67/68 report).
          next6:
          case 7:
            await db.execute('''
              CREATE TABLE page_bands(
                parent_hash TEXT NOT NULL,
                idx         INTEGER NOT NULL,
                hash        TEXT NOT NULL,
                width       INTEGER,
                height      INTEGER,
                PRIMARY KEY (parent_hash, idx)
              )''');
          // Future migrations append cases here: `case 1: ...; continue next;`
          default:
            break;
        }
      },
    ),
  );
}

const _schemaSql = [
  '''
  CREATE TABLE sources(
    id        TEXT PRIMARY KEY,
    name      TEXT NOT NULL,
    base_url  TEXT NOT NULL,
    adapter   TEXT NOT NULL,
    enabled   INTEGER NOT NULL DEFAULT 1,
    sort      INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE series(
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    original_title TEXT,
    title_norm  TEXT NOT NULL,
    cover_hash  TEXT,
    type        TEXT,
    origin      TEXT,
    status      TEXT,
    description TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )''',
  'CREATE UNIQUE INDEX idx_series_norm ON series(title_norm)',
  '''
  CREATE TABLE series_sources(
    series_id           INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    source_id           TEXT    NOT NULL REFERENCES sources(id),
    source_url          TEXT    NOT NULL,
    source_title        TEXT,
    alt_titles          TEXT,
    cover_url           TEXT,
    last_chapter_number REAL,
    last_updated_at     INTEGER,
    fetched_at          INTEGER NOT NULL,
    PRIMARY KEY (series_id, source_id)
  )''',
  '''
  CREATE TABLE tags(
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
  )''',
  '''
  CREATE TABLE series_tags(
    series_id INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    tag_id    INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (series_id, tag_id)
  )''',
  '''
  CREATE TABLE chapters(
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    series_id   INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    source_id   TEXT    NOT NULL,
    number      REAL    NOT NULL,
    title       TEXT,
    url         TEXT    NOT NULL,
    page_count  INTEGER,
    uploaded_at INTEGER,
    fetched_at  INTEGER NOT NULL,
    UNIQUE (series_id, source_id, number)
  )''',
  'CREATE INDEX idx_chapters_series ON chapters(series_id, number DESC)',
  '''
  CREATE TABLE chapter_pages(
    chapter_id   INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
    idx          INTEGER NOT NULL,
    url          TEXT    NOT NULL,
    content_hash TEXT,
    width        INTEGER, height INTEGER, bytes INTEGER,
    PRIMARY KEY (chapter_id, idx)
  )''',
  'CREATE INDEX idx_pages_hash ON chapter_pages(content_hash)',
  '''
  CREATE TABLE chapter_text(
    chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
    text       TEXT NOT NULL
  )''',
  '''
  CREATE TABLE blobs(
    hash        TEXT PRIMARY KEY,
    path        TEXT NOT NULL,
    bytes       INTEGER NOT NULL,
    is_pinned   INTEGER NOT NULL DEFAULT 0,
    last_access INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE blob_urls(
    url        TEXT PRIMARY KEY,
    hash       TEXT NOT NULL,
    width      INTEGER,
    height     INTEGER,
    fetched_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE page_bands(
    parent_hash TEXT NOT NULL,
    idx         INTEGER NOT NULL,
    hash        TEXT NOT NULL,
    width       INTEGER,
    height      INTEGER,
    PRIMARY KEY (parent_hash, idx)
  )''',
  '''
  CREATE TABLE read_progress(
    chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
    page_index INTEGER NOT NULL DEFAULT 0,
    completed  INTEGER NOT NULL DEFAULT 0,
    read_at    INTEGER
  )''',
  '''
  CREATE TABLE reading_history(
    chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
    series_id  INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    read_at    INTEGER NOT NULL,
    times_read INTEGER NOT NULL DEFAULT 1
  )''',
  'CREATE INDEX idx_history_time ON reading_history(read_at DESC)',
  '''
  CREATE TABLE library(
    series_id           INTEGER PRIMARY KEY REFERENCES series(id) ON DELETE CASCADE,
    added_at            INTEGER NOT NULL,
    last_read_at        INTEGER,
    last_read_chapter_id INTEGER REFERENCES chapters(id) ON DELETE SET NULL,
    last_seen_at        INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE categories(
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    sort INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE category_members(
    series_id    INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    category_id  INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (series_id, category_id)
  )''',
  '''
  CREATE TABLE downloads(
    chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
    state      TEXT NOT NULL DEFAULT 'queued',
    priority   INTEGER NOT NULL DEFAULT 0,
    error      TEXT,
    created_at INTEGER NOT NULL
  )''',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)',
  '''
  CREATE TABLE search_history(
    query TEXT PRIMARY KEY,
    at    INTEGER NOT NULL
  )''',
];

Future<void> _createSchema(Database db) async {
  for (final sql in _schemaSql) {
    await db.execute(sql);
  }
}

const _seededSources = [
  // id, name, base_url, adapter  (Plan/02 seed table)
  ('slow-manga', 'Slow Manga', 'https://www.slow-manga.net', 'madara'),
  ('go-manga', 'Go-Manga', 'https://www.go-manga.com', 'madara'),
  ('up-manga', 'Up-Manga', 'https://www.up-manga.com', 'madara'),
  ('dark-manga', 'Dark Manga', 'https://www.dark-manga.com', 'madara'),
  ('nekopost', 'Nekopost', 'https://www.nekopost.net', 'nekopost'),
  // v1.1 (2026-10-18): user-added sites. fin-manga runs the same ts
  // theme (madara adapter); bully-manga is a static custom site (bully
  // adapter — see data/sources/bully/).
  ('fin-manga', 'Fin-Manga', 'https://www.fin-manga.com', 'madara'),
  ('bully-manga', 'Bully Manga', 'https://bully-manga.com', 'bully'),
  // v5 (2026-10-19): adult doujin sites — scoped to the Doujin (18+)
  // page, never the main feed (source_registry adultSourceIds).
  ('ntr-manga', 'NTR-Manga', 'https://www.ntr-manga.net', 'madara'),
  ('doujin-lc', 'Doujin-LC', 'https://doujin-lc.net', 'madara'),
  ('hentaithai', 'HentaiThai', 'https://hentaithai.net', 'hentaithai'),
  ('miku-doujin', 'Miku-Doujin', 'https://miku-doujin.com', 'miku'),
];

const _defaultSettings = {
  'language': 'th',
  'theme': 'stardust',
  'cache_limit_bytes': '5368709120', // 5 GB reading cache
  'total_quota_bytes': '21474836480', // 20 GB downloads
  'filter_min_chapters': '0',
  'filter_hide_oneshot': '0',
  'reader_mode_default': 'auto',
  'reader_prefetch_ahead': '6',
  'downloads_wifi_only': '1',
  'updates_last_seen': '0',
  'updates_last_run': '0',
  'novel_font_size': '18',
  'novel_line_height': '1.7',
  'novel_bg_opacity': '1.0',
};

/// Sources that seed DISABLED: Cloudflare fingerprint-blocks the app's
/// TLS stack (2026-10-19 probe — adapters correct, requests 403). Users
/// can re-enable in Settings.
const _seededDisabled = {'doujin-lc', 'miku-doujin'};

Future<void> _seed(Database db) async {
  final batch = db.batch();
  for (var i = 0; i < _seededSources.length; i++) {
    final s = _seededSources[i];
    batch.insert('sources', {
      'id': s.$1,
      'name': s.$2,
      'base_url': s.$3,
      'adapter': s.$4,
      'enabled': _seededDisabled.contains(s.$1) ? 0 : 1,
      'sort': i,
    });
  }
  _defaultSettings.forEach((key, value) {
    batch.insert('settings', {'key': key, 'value': value});
  });
  await batch.commit(noResult: true);
}

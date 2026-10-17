# 02 — Database Schema (sqflite)

Single SQLite database `manga_reader.db` in `getApplicationSupportDirectory()`.
Version 1 schema below. All timestamps are **milliseconds since epoch (int)**.

## Migration policy

- `db.dart` holds `version = 1` and a `onUpgrade` switch keyed by version.
- Any later schema change bumps the version and adds a case. Never edit v1
  statements after shipping — append migrations only.

## Schema (execute in one `onCreate` batch)

```sql
CREATE TABLE sources(
  id        TEXT PRIMARY KEY,   -- 'slow-manga','go-manga','up-manga','dark-manga','nekopost'
  name      TEXT NOT NULL,      -- display name (Thai ok)
  base_url  TEXT NOT NULL,
  adapter   TEXT NOT NULL,      -- 'madara' | 'nekopost'
  enabled   INTEGER NOT NULL DEFAULT 1,
  sort      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE series(
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT NOT NULL,             -- best display title (prefer Thai — decision L5)
  original_title TEXT,                   -- original/romaji/English name (L5), nullable
  title_norm  TEXT NOT NULL,             -- normalized key (07) used for merging
  cover_hash  TEXT,                      -- blob hash of cover image (nullable until fetched)
  type        TEXT,                      -- 'manga'|'manhwa'|'manhua'|'novel'|NULL  (origin axis, L6)
  origin      TEXT,                      -- 'japan'|'korea'|'china'|'thailand'|'other'|NULL (best-effort, L6)
  status      TEXT,                      -- 'ongoing'|'completed'|NULL
  description TEXT,                      -- Introduction, merged across sources (L7)
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_series_norm ON series(title_norm);

-- one series can exist on several sources; this table IS the merge
CREATE TABLE series_sources(
  series_id           INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
  source_id           TEXT    NOT NULL REFERENCES sources(id),
  source_url          TEXT    NOT NULL,   -- canonical series URL on that source
  source_title        TEXT,               -- title as written on that site
  alt_titles          TEXT,               -- JSON array of strings
  cover_url           TEXT,
  last_chapter_number REAL,
  last_updated_at     INTEGER,            -- newest chapter upload time seen on this source
  fetched_at          INTEGER NOT NULL,
  PRIMARY KEY (series_id, source_id)
);

CREATE TABLE tags(
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE              -- keep original casing: 'Action', 'พระเอกเทพ'
);
CREATE TABLE series_tags(
  series_id INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
  tag_id    INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (series_id, tag_id)
);

CREATE TABLE chapters(
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  series_id   INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
  source_id   TEXT    NOT NULL,
  number      REAL    NOT NULL,   -- parsed numeric: 'ตอนที่ 920' -> 920.0
  title       TEXT,               -- raw display title from site
  url         TEXT    NOT NULL,   -- chapter page URL
  page_count  INTEGER,            -- filled after first fetch
  uploaded_at INTEGER,
  fetched_at  INTEGER NOT NULL,
  UNIQUE (series_id, source_id, number)
);
CREATE INDEX idx_chapters_series ON chapters(series_id, number DESC);

-- pages of a chapter; content_hash filled after first successful fetch
CREATE TABLE chapter_pages(
  chapter_id   INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
  idx          INTEGER NOT NULL,   -- 0-based display order
  url          TEXT    NOT NULL,
  content_hash TEXT,               -- sha256(original bytes); NULL = never fetched
  width        INTEGER, height INTEGER, bytes INTEGER,
  PRIMARY KEY (chapter_id, idx)
);
CREATE INDEX idx_pages_hash ON chapter_pages(content_hash);

-- novel chapters (nekopost): body text instead of pages
CREATE TABLE chapter_text(
  chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
  text       TEXT NOT NULL
);

-- content-addressed blob index (see 03)
CREATE TABLE blobs(
  hash        TEXT PRIMARY KEY,    -- sha256(original bytes)
  path        TEXT NOT NULL,       -- relative path under library dir
  bytes       INTEGER NOT NULL,    -- size of stored .webp
  is_pinned   INTEGER NOT NULL DEFAULT 0,
  last_access INTEGER NOT NULL
);

CREATE TABLE read_progress(
  chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
  page_index INTEGER NOT NULL DEFAULT 0,
  completed  INTEGER NOT NULL DEFAULT 0,
  read_at    INTEGER
);

-- History tab data (user requirement): one row per chapter ever completed;
-- upsert on completion: read_at = now, times_read + 1
CREATE TABLE reading_history(
  chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
  series_id  INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
  read_at    INTEGER NOT NULL,
  times_read INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_history_time ON reading_history(read_at DESC);

CREATE TABLE library(
  series_id           INTEGER PRIMARY KEY REFERENCES series(id) ON DELETE CASCADE,
  added_at            INTEGER NOT NULL,
  last_read_at        INTEGER,
  last_read_chapter_id INTEGER REFERENCES chapters(id) ON DELETE SET NULL
);

CREATE TABLE categories(
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  sort INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE category_members(
  series_id    INTEGER NOT NULL REFERENCES series(id) ON DELETE CASCADE,
  category_id  INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  PRIMARY KEY (series_id, category_id)
);

-- pinned downloads / download queue
CREATE TABLE downloads(
  chapter_id INTEGER PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
  state      TEXT NOT NULL DEFAULT 'queued',  -- queued|running|done|error|paused
  priority   INTEGER NOT NULL DEFAULT 0,
  error      TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE search_history(
  query TEXT PRIMARY KEY,
  at    INTEGER NOT NULL
);
```

## Seed data (insert in onCreate after schema)

The five sources:

| id | name | base_url | adapter |
|---|---|---|---|
| slow-manga | Slow Manga | https://www.slow-manga.net | madara |
| go-manga | Go-Manga | https://www.go-manga.com | madara |
| up-manga | Up-Manga | https://www.up-manga.com | madara |
| dark-manga | Dark Manga | https://www.dark-manga.com | madara |
| nekopost | Nekopost | https://www.nekopost.net | nekopost |

Default settings rows:

| key | value |
|---|---|
| language | th |
| theme | dark |
| cache_limit_bytes | 5368709120 (5 GiB) |
| total_quota_bytes | 107374182400 (100 GiB) |
| filter_min_chapters | 0 (OFF — decision L1) |
| filter_hide_oneshot | 0 (OFF — decision L1) |
| reader_mode_default | auto (auto = webtoon for manhwa/manhua/novel-strip, paged for manga) |
| reader_prefetch_ahead | 6 |
| updates_last_run | 0 |
| novel_font_size | 18 |
| novel_line_height | 1.7 |

## DAO layer rules

- One file per table group in `data/dao/`. DAOs take the `Database` via
  constructor; no UI imports DAOs directly — only `data/repo/*` do.
- Always parameterize SQL (`where('id = ?', [id])`). No string interpolation.
- `series` writes go through `series_repo` which also maintains
  `series_sources`/tags atomically (`db.transaction`).
- Cover image: `series.cover_hash` points into `blobs`; covers are stored
  through the same blob pipeline (03) so they dedupe too.
- `chapters.number` is REAL: keep as double; compare with epsilon `< 1e-6`
  when matching across sources.

## Definition of Done

- [ ] `db.dart` opens the DB, creates schema + seeds on fresh install.
- [ ] Unit test (sqflite_common_ffi in `dev_dependencies`): open, verify all
  tables exist (`sqlite_master`), seed rows present, `series` unique index
  rejects duplicate `title_norm`.
- [ ] DAO smoke test: insert series + 2 sources + chapters + pages, read back,
  cascade delete works (deleting series removes chapters/pages/downloads).

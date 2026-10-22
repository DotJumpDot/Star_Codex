# Architecture

**Star Codex** is a **single Flutter Android app** under `app/` (repo:
github.com/DotJumpDot/Star_Codex). There is no backend, no server, no cloud —
the phone talks directly to the five manga websites, exactly like a browser
would. The PC is only used to compile the APK.

> Full build plan with every detail: [`Plan/`](./Plan/) — start at
> [Plan/README.md](./Plan/README.md). Decision contract:
> [Plan/00-DECISIONS.md](./Plan/00-DECISIONS.md).

## Workspace tree

```
StarCodex/
├── Docs/                        this folder
│   └── Plan/                    16-doc build plan (00–15)
├── app/                         the Flutter project (created in Plan Phase 1)
│   ├── lib/
│   │   ├── main.dart            bootstrap: db init → settings → MaterialApp
│   │   ├── app.dart             NavigationShell (Browse/Doujin 18+/Library/History/Offline/Settings)
│   │   ├── core/
│   │   │   ├── i18n/            th.json / en.json + tiny t() helper
│   │   │   ├── theme/           M3 dark-first incl. OLED family, Sarabun
│   │   │   ├── utils/           title_norm, thai collation, chapter-number parse, jaro_winkler
│   │   │   └── net/             safe_http (host-validated) + rate_limiter  ← ONLY network door
│   │   ├── data/
│   │   │   ├── db.dart + dao/   sqflite, append-only migrations (v1→v8, Plan/02 + PLAN_NOTES)
│   │   │   ├── storage/         blob_store / image_pipeline / cache_janitor (Plan/03; big-buffer hashing
in a bg isolate; GPU band slicer via the native star_codex/image_slice
channel on a worker thread)
│   │   │   ├── sources/         source_api + madara/ (ts + classic) + nekopost/ + bully/ + miku/ + hentaithai/
│   │   │   └── repo/            browse / series / reader / library / updates repos
│   │   └── ui/                  shell/ browse/ detail/ reader/ library/ downloads/ settings/
│   ├── assets/i18n/
│   ├── tool/verify_sources.dart scraper smoke-test CLI
│   └── android/                 minSdk 23, INTERNET permission, appId com.jamej.starcodex
└── compress_test/               one-off compression experiment (2026-10-17, can be deleted)
```

## Layering

```
UI (ui/*)  →  Repos (data/repo/*)  →  { DAOs (db)  |  Storage engine  |  Source adapters }
                                        all network via core/net/safe_http
```

| Layer | Responsibility | Never does |
|---|---|---|
| UI | screens, widgets, Riverpod consumers | SQL, HTTP, file paths |
| Repos | orchestration: adapter → normalize/merge → DB → blobs | rendering |
| DAOs | parameterized SQL on one table group each | business logic |
| Storage engine | content-addressed blobs, WebP pipeline, LRU, quota | network (pipeline calls safe_http) |
| Source adapters | site ⇄ data translation (HTML/JSON → models) | DB writes, caching |

## Data flow — reading one webtoon chapter (the core path)

```
tap chapter ─▶ ReaderScreen (ui/reader)
                 │ page slot visible?
                 ├─ blob cached? ── yes ─▶ Image.file (bump last_access)
                 └─ no ─▶ reader_repo.getPage()
                            └▶ image_pipeline.fetchAndStore(url, referer)
                                  ├─ safe_http (host-validated, rate-limited)
                                  ├─ sha256(original) ──▶ dedup check (blobs)
                                  ├─ WebP q80 encode ──▶ blobs/ab/<hash>.webp
                                  └▶ chapter_pages row updated (hash, dims)
                 prefetch worker keeps N pages ahead
                 scroll ─▶ read_progress upsert (throttled)
```

## Data flow — search across sites

```
query ─▶ browse_repo.search()
           ├─ 5 × source.search() in parallel (rate-limited per host)
           ├─ normalizeTitle + match (07: exact → alt-title → Jaro-Winkler)
           └▶ grouped cards: one series, N source badges
open card ─▶ series_repo: series_sources rows (the merge), chapters upserted
```

## Data flow — the update feed (grid-head, v1.3.0)

```
browse_repo.latest()
  ├─ source.recentStamps()  → the site's own homepage "updated recently"
  │    grid: .chfiv .fivtime (go/dark/fin/up) / .epxdate (slow-manga)
  │    → live relative labels ("2 นาที", "6 ชั่วโมง") = precise stamps
  ├─ page 1 = grid entries (the site's own order) + archive tail, deduped
  └─ card date = max(listing stamp, DB stamp)  → freshest wins
background pass (6 h TTL):
  stale card ─▶ grid hit? → write the link stamp (no detail fetch)
              └▶ no hit   → series_repo.refreshDetail (chapters re-stamped)
```

## Where things live (DB)

| Concern | Table(s) |
|---|---|
| Sources registry | `sources` (5 seeded rows) |
| Merged series | `series` (+ `original_title`, `type`, `origin`) + `series_sources` (+ `tags`, `series_tags`) |
| Chapters & pages | `chapters`, `chapter_pages`, `chapter_text` (novels) |
| Blob store index | `blobs` (hash → file, pinned flag, last_access) |
| Progress & library | `read_progress`, `reading_history`, `library`, `categories`, `category_members` |
| Downloads & queue | `downloads` |
| Settings & misc | `settings`, `search_history` |

Full SQL: [Plan/02-DATABASE.md](./Plan/02-DATABASE.md).

## On-disk layout (app-private storage)

```
<appSupport>/manga_reader.db
<appSupport>/manga_library/blobs/<hash[0:2]>/<sha256-of-original>.webp
```

Hashing ORIGINAL bytes (before re-encode) is what makes cross-site dedup
work — the same scanlation file mirrored on 3 sites is stored once.

## Runtime model

- Single process, single Isolate for UI + light work; image decode native;
  WebP encode native (`flutter_image_compress`).
- Downloads run in-app while the app is open (no background service in v1 —
  surfaced honestly in the UI).
- State: Riverpod 2.x, manual providers, no codegen anywhere.

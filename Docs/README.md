# Star Codex — Docs

Local-first, Android manga/manhwa/manhua/novel reader ("Star Codex") for
nine live Thai sources plus a separate Doujin (18+) page, built with
Flutter. Personal use only.
Repo: https://github.com/DotJumpDot/Star_Codex (this folder is the repo root).

| Doc | What it is |
|---|---|
| [HANDOFF.md](./HANDOFF.md) | Session-to-session state + the release recipe — **read first** |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | How the app is put together (Maki-style overview) |
| [BUILD.md](./BUILD.md) | Setting up the toolchain on this PC and building the APK |
| [HOW_TO_RUN.md](./HOW_TO_RUN.md) | Dev workflow: run on phone, hot reload, verify sources, logs |
| [PLAN_NOTES.md](./PLAN_NOTES.md) | Post-plan invariants & gotchas (source quirks, migrations, covers) |
| [QA-ON-DEVICE.md](./QA-ON-DEVICE.md) | The v1.0.0 on-device QA log (8 bugs found + fixed) |
| [../CHANGELOG.md](../CHANGELOG.md) | One line per completed batch (repo root) |
| [Plan/](./Plan/) | The complete build plan (16 documents) — start at [Plan/README.md](./Plan/README.md) |

## Project in one paragraph

**Star Codex** is a Flutter Android app that reads from **go-manga.com,
slow-manga.net, up-manga.com, dark-manga.com, fin-manga.com** (WordPress/
Madara-ts — one shared adapter), **bully-manga.com** (custom static-engine
adapter: JSON-LD detail pages, `IMAGE_MAP` chapter arrays, relative Thai
date stamps) and **nekopost.net** (custom JSON API, also carries นิยาย
novels), plus a separate **Doujin 18+ page** with **ntr-manga.net**
(Madara/ts) and **hentaithai.net** (custom one-shot engine; two more
doujin sites seed disabled behind a Cloudflare block — see PLAN_NOTES).
Reading is streaming like a website; every viewed page is silently
cached as WebP q80, content-hash deduplicated across sites (measured
−58% size), with an LRU cache (5 GB default) that cleans itself and a
20 GB pinned-download quota. The same title on several sites merges into
one library entry (Thai title kept, original name shown as subtitle)
with per-chapter source fallback, and cards enrich themselves in the
background (dates, covers) when the listings alone don't carry them.
The update feed itself is built from each site's own recent-updates
grid, so its order and its "x minutes ago" stamps match the website
(since v1.3.0).
Navigation is a left drawer — Browse · Doujin 18+ · Library · History ·
Offline · Settings. Thai-first UI with an English toggle, 25 themes
(including a true-black OLED family), 12 fonts. SQLite schema v8.
No server, no cloud, no login.

## Key decisions

See [Plan/00-DECISIONS.md](./Plan/00-DECISIONS.md) — the locked contract
(filter defaults OFF, streaming reading, storage rules, source set).
Post-plan changes are recorded in [PLAN_NOTES.md](./PLAN_NOTES.md) and
the [CHANGELOG](../CHANGELOG.md).

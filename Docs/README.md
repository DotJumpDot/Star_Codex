# Star Codex — Docs

Local-first, Android manga/manhwa/novel reader ("Star Codex") for five Thai
sources, built with Flutter. Personal use only.
Repo: https://github.com/DotJumpDot/Star_Codex (this folder is the repo root).

| Doc | What it is |
|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | How the app is put together (Maki-style overview) |
| [BUILD.md](./BUILD.md) | Setting up the toolchain on this PC and building the APK |
| [HOW_TO_RUN.md](./HOW_TO_RUN.md) | Dev workflow: run on phone, hot reload, verify sources, logs |
| [CHANGELOG.md](./CHANGELOG.md) | One line per completed build phase |
| [Plan/](./Plan/) | The complete build plan (16 documents) — start at [Plan/README.md](./Plan/README.md) |

## Project in one paragraph

**Star Codex** is a Flutter Android app that reads from **go-manga.com,
slow-manga.net, up-manga.com, dark-manga.com** (all WordPress/Madara — one
shared adapter) and **nekopost.net** (custom API, also carries นิยาย novels).
Reading is streaming like a website; every viewed page is silently cached as
WebP q80, content-hash deduplicated across sites (measured −58% size), with
an LRU cache (5 GB default) that cleans itself and a 100 GB pinned-download
quota. The same title on several sites merges into one library entry
(Thai title kept, original name shown as subtitle) with per-chapter source
fallback. Content is grouped Manhwa (Korea) / Manga (Japan) / Manhua (China)
/ Novel. Tabs: Browse · Library · History · Offline · Settings.
Thai-first UI. No server, no cloud, no login.

## Key decisions

See [Plan/00-DECISIONS.md](./Plan/00-DECISIONS.md) — the locked contract
(filter defaults OFF, streaming reading, storage rules, five sources).

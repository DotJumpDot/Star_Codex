# Manga Reader — Plan (build instructions for the coding model)

This folder is the **complete build plan** for the Manga Reader Flutter app.
It is written to be executed by a coding model (GLM 5.3 Flash) phase by phase
without needing to re-derive any decision. Everything is already decided,
probed, and written down — including live scraping data gathered from the real
sites on 2026-10-17.

## How to use this plan

1. Read [`00-DECISIONS.md`](./00-DECISIONS.md) first — it is the contract. Never violate it.
2. Follow [`15-BUILD-ORDER.md`](./15-BUILD-ORDER.md) strictly. It sequences the
   build into phases; each phase lists the plan documents to read, the files to
   create, and a **Definition of Done** that must pass before moving on.
3. When a website behaves differently from what a source doc says, verify with
   the `curl` commands given in the doc, update the doc, then continue.

## Ground rules for the coding model

- **Read the phase's documents before writing code.** The docs contain exact
  schemas, URL patterns, and algorithms. Do not invent alternatives.
- **Definition of Done is not optional.** Run the checks at the end of each
  phase. A phase that fails its checks is not done.
- **Never skip the network security rule** in [`04-SOURCE-FRAMEWORK.md`](./04-SOURCE-FRAMEWORK.md)
  (scheme + host validation before every request). It is a hard requirement.
- **No credentials in source code.** The app has no login in v1. If a future
  feature needs a secret, it comes from environment/build config only.
- **Thai first.** Default UI language is Thai (`assets/i18n/th.json`), with an
  English toggle. All user-visible strings go through the i18n helper.
- **Keep the repo clean:** no build artifacts in git, update
  `Docs/CHANGELOG.md` at the end of every phase (one line per phase).
- **Git = progress report (user requirement):** this folder is the git repo
  `github.com/DotJumpDot/Star_Codex`. Every phase ends with a commit whose
  message body lists each completed unit as `- [x] <thing> complete` lines,
  then `git push`. Exact format in [`15-BUILD-ORDER.md`](./15-BUILD-ORDER.md) rule 6.
- **When genuinely blocked** on a user decision (e.g. a site changed and two
  fixes are possible), ask the user in chat with a concrete recommendation.
  Otherwise decide using the docs.

## Document map

| Doc | What it covers |
|---|---|
| [00-DECISIONS.md](./00-DECISIONS.md) | Locked requirements and design decisions (the contract) |
| [01-PROJECT-SETUP.md](./01-PROJECT-SETUP.md) | Flutter scaffold, packages, folder structure, theme, i18n |
| [02-DATABASE.md](./02-DATABASE.md) | Full SQLite schema + DAO specs |
| [03-STORAGE-ENGINE.md](./03-STORAGE-ENGINE.md) | Content-addressed image store, WebP pipeline, LRU cache, quota |
| [04-SOURCE-FRAMEWORK.md](./04-SOURCE-FRAMEWORK.md) | Source interface, HTTP client, security, rate limits, retries |
| [05-SOURCE-MADARA.md](./05-SOURCE-MADARA.md) | Adapter for go-manga / slow-manga / up-manga / dark-manga (with live probe data) |
| [06-SOURCE-NEKOPOST.md](./06-SOURCE-NEKOPOST.md) | Nekopost adapter (API probing + reference implementation) |
| [07-TITLE-MERGE.md](./07-TITLE-MERGE.md) | Cross-site title normalization + duplicate merging algorithm |
| [08-UI-BROWSE.md](./08-UI-BROWSE.md) | Browse/search screen, filters |
| [09-UI-SERIES-DETAIL.md](./09-UI-SERIES-DETAIL.md) | Series detail screen, source switcher, chapter list |
| [10-UI-READER-WEBTOON.md](./10-UI-READER-WEBTOON.md) | Vertical streaming reader (the heart of the app) |
| [11-UI-READER-PAGED-NOVEL.md](./11-UI-READER-PAGED-NOVEL.md) | Horizontal paged reader + novel text reader |
| [12-UI-LIBRARY.md](./12-UI-LIBRARY.md) | Library screen, categories, sorting (Thai collation) |
| [13-DOWNLOADS-UPDATES.md](./13-DOWNLOADS-UPDATES.md) | Download manager, pinning, chapter-update checker |
| [14-SETTINGS.md](./14-SETTINGS.md) | Settings screen |
| [15-BUILD-ORDER.md](./15-BUILD-ORDER.md) | Master build sequence with per-phase Definition of Done |

General (non-plan) docs live one level up in [`../`](../): `ARCHITECTURE.md`,
`BUILD.md`, `HOW_TO_RUN.md`.

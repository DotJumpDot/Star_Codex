# HANDOFF — read this first in a new conversation

> Last updated 2026-10-19 (v1.1.0 release). Written originally 2026-10-17
> when the folder was renamed `C:\Code\Manga_Reader` → `C:\Code\StarCodex`.

## Where things stand

- **The app is built, QA'd, and released.** All 11 plan phases completed
  (2026-10-17), three user-driven UX overhaul rounds + two new sources
  landed (2026-10-18/19), and **v1.0.0 + v1.1.0 are live on GitHub
  Releases** (release-signed `StarCodex-<version>.apk`).
- 7 sources: go-manga, slow-manga, up-manga, dark-manga, fin-manga
  (Madara/ts), bully-manga (custom engine), nekopost (API + novels).
  SQLite is at schema v4. 193 tests green, analyze clean.
- **Remaining work = whatever the user asks for in chat.** There is no
  open phase. The user drives batches; land them with the checklist
  commit + push discipline (AGENTS.md → Git discipline), one CHANGELOG
  line per batch, and a big-model review pass after each batch.
- The original build plan (Docs/Plan/, 16 documents) is now historical
  reference; [`Plan/00-DECISIONS.md`](./Plan/00-DECISIONS.md) still wins
  as the contract, and [`Docs/PLAN_NOTES.md`](./PLAN_NOTES.md) carries
  everything learned after the plan (source quirks, migrations, cover
  fallbacks, probe matching) — read its newest sections first.

## Project in 3 lines

**Star Codex** = Flutter Android app (Thai-first UI) reading from 7 Thai
manga/novel sources (5× WordPress-Madara/ts + bully-manga custom engine +
nekopost API incl. novels). Reading is streaming like a website; viewed
pages silently cache as WebP q80, content-hash deduplicated. Navigation:
left drawer — Browse / Library / History / Offline / Settings. Personal
local use only — no server, no cloud, no login.

## What to tell the new conversation

Use a prompt like this (GLM 5.3 Flash or any model):

```
Read C:\Code\StarCodex\AGENTS.md, then Docs\HANDOFF.md and
Docs\PLAN_NOTES.md. Check git log + CHANGELOG.md for where things stand,
then do what I ask in chat. Land every batch with the checklist commit +
push, and keep the full test suite green.
```

## Release recipe (short)

1. Version: `app/pubspec.yaml` (`x.y.z+N`), About string in
   `settings_storage_sources.dart`, CHANGELOG line.
2. `flutter build apk --release` → verify with `build-tools/36.0.0/
   apksigner.bat verify --print-certs`.
3. Copy to `StarCodex-<version>.apk`, SHA-256 it, write English notes
   (`.git-msg-release-<version>.md` stays untracked).
4. Commit, `git tag -a v<version> -m "Star Codex v<version>"`, push both.
5. `GH_TOKEN=$(git credential fill …)` → `gh release create v<version>
   <apk> --title … --notes-file …`.

Debug installs must be uninstalled before a release build installs
(signature mismatch) — the release notes carry that warning.

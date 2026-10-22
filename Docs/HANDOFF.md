# HANDOFF — read this first in a new conversation

> Last updated 2026-10-22 (v1.3.0 release). Written originally 2026-10-17
> when the folder was renamed `C:\Code\Manga_Reader` → `C:\Code\StarCodex`.

## Where things stand

- **The app is built, QA'd, and released.** All 11 plan phases completed
  (2026-10-17), four user-driven UX rounds + the Doujin (18+) page
  landed (2026-10-18/19), and **v1.0.0 → v1.3.0 are live on GitHub
  Releases** (release-signed `StarCodex-<version>.apk`).
- 11 sources seeded, 9 live: main feed = go-manga, slow-manga, up-manga,
  dark-manga, fin-manga (Madara/ts), bully-manga (custom engine),
  nekopost (API + novels); Doujin 18+ page = ntr-manga, hentaithai
  (one-shot engine) — plus doujin-lc and miku-doujin, which seed
  DISABLED because their Cloudflare WAF blocks non-browser TLS stacks
  (see PLAN_NOTES 2026-10-19: not fixable in-app; adapters correct).
  SQLite is at schema v8. 243 tests green, analyze clean.
- **v1.2.x focus was reading smoothness** (decode caps, fling-safe
  height anchors, GPU band slicing for oversized strips, pipeline work
  moved off the UI threads) plus offline browse fallback, the popular
  feed, and detail skeletons — see PLAN_NOTES' 2026-10-20/21 sections
  for the invariants. v1.2.7 confirmed smooth on the user's real phone
  (2026-10-21) — the reading-smoothness work is closed.
- **v1.3.0 focus is the BROWSE FEED matching the websites** (2026-10-22):
  page 1 of the feed = the site's own recent-updates grid (order + live
  relative labels), card dates re-checked every 6 h instead of freezing,
  card intros in the leftover space, compact site chips. Invariants:
  PLAN_NOTES 2026-10-22 (three sections). Reader gestures shipped in
  v1.2.10 (real crop lock, website-style pinch, paged freeze).
- **Remaining work = whatever the user asks for in chat.** There is no
  open phase. The user drives batches; land them with the checklist
  commit + push discipline (AGENTS.md → Git discipline), one CHANGELOG
  line per batch, and a big-model review pass after each batch.
- The original build plan (Docs/Plan/, 16 documents) is now historical
  reference; [`Plan/00-DECISIONS.md`](./Plan/00-DECISIONS.md) still wins
  as the contract, and [`Docs/PLAN_NOTES.md`](./PLAN_NOTES.md) carries
  everything learned after the plan (source quirks, migrations, cover
  fallbacks, probe matching, the Cloudflare fingerprint blocks) — read
  its newest sections first.

## Project in 3 lines

**Star Codex** = Flutter Android app (Thai-first UI) reading from 9 live
Thai manga/novel sources (5× WordPress-Madara/ts + bully-manga custom
engine + nekopost API incl. novels) plus a separate Doujin 18+ page
(ntr-manga, hentaithai). Reading is streaming like a website; viewed
pages silently cache as WebP q80, content-hash deduplicated. Navigation:
left drawer — Browse / Doujin 18+ / Library / History / Offline /
Settings. Personal local use only — no server, no cloud, no login.

## What to tell the new conversation

Use a prompt like this (GLM 5.3 Flash or any model):

```
Read C:\Code\StarCodex\AGENTS.md, then Docs\HANDOFF.md and
Docs\PLAN_NOTES.md. Check git log + CHANGELOG.md for where things stand,
then do what I ask in chat. Land every batch with the checklist commit +
push, and keep the full test suite green.
```

## Release recipe (short)

1. Version: `app/pubspec.yaml` (`x.y.z+N`) AND the About string in
   `settings_storage_sources.dart` (`AboutSection.appVersion`), CHANGELOG
   line.
2. `flutter build apk --release` → verify with `build-tools/*/apksigner.bat
   verify --print-certs` (expect CN=Star Codex, O=DotJumpDot).
3. Copy to `StarCodex-<version>.apk`, SHA-256 it, write English notes to
   a TEMP file via the Write tool (heredocs mangle; the mimosa hook
   blocks shell-written files).
4. Commit + push (the release commit is what the tag points at).
5. `GH_TOKEN=$(printf "protocol=https\nhost=github.com\n\n" |
   git credential fill | grep ^password= | cut -d= -f2)` →
   `gh release create v<version> <apk> --title … --notes-file …` —
   this CREATES the tag on the current HEAD, so no manual `git tag`,
   then DELETE the staged APK copy at the repo root (never commit it).

Debug installs must be uninstalled before a release build installs
(signature mismatch) — the release notes carry that warning.

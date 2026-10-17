# 15 — Master Build Order (follow strictly)

Phases build on each other; each has a Definition of Done (DoD) that must
pass before starting the next. After every phase: `flutter analyze` clean,
`flutter test` green, update [`../CHANGELOG.md`](../CHANGELOG.md) at the repo
root (one line), then **commit
and push** with a checklist message (rule 6 below).

If a DoD fails and the fix is not obvious within ~3 attempts, write the
failing details into `Docs/PLAN_NOTES.md` and ask the user with a concrete
recommendation — do not silently skip.

## Phase 0 — Environment (human-assisted)

- [ ] Flutter SDK stable installed, `flutter doctor` green (Android toolchain).
  See [`../BUILD.md`](../BUILD.md). Phone connected with USB debugging on.
- DoD: `flutter doctor` shows no blockers; `flutter devices` lists the phone.

## Phase 1 — Scaffold (doc: 01)

- Create project, deps, folder tree, i18n, theme, shell with 4 tabs, error
  conventions, empty screens.
- DoD: 01 §Definition of Done.

## Phase 2 — Database + settings (doc: 02)

- `db.dart` + all DAOs + seed. Settings provider. Add `sqflite_common_ffi`
  to dev_dependencies for tests.
- DoD: 02 §Definition of Done (schema test, seed test, cascade test).

## Phase 3 — Network + Madara adapter (docs: 04, 05)

- `safe_http` + rate limiter + retries FIRST (04 is a hard security rule).
- Then `madara_source.dart` with the four configs; run all §7 verification
  curls per site and record drift in 05 before coding each parser piece.
- `tool/verify_sources.dart` CLI (uses the same adapter code, not a copy).
- DoD: 04 §DoD + 05 §DoD (verify_sources for all 4 Madara sites).

## Phase 4 — Storage engine (doc: 03)

- BlobStore, ImagePipeline, CacheJanitor; unit tests with mocked http.
- DoD: 03 §Definition of Done (dedup test, LRU test, on-device manual blob check).

## Phase 5 — Browse UI + title merge (docs: 07, 08)

- Normalization + Jaro-Winkler + merge logic with unit tests FIRST, then
  browse screen (search, latest feed, filters default OFF per L1).
- DoD: 07 §6 tests + 08 §DoD.

## Phase 6 — Series detail (doc: 09)

- Detail screen, source tabs, chapter list, progress marks, continue button.
- DoD: 09 §DoD (minus reader navigation — open stub screens for now).

## Phase 7 — Webtoon reader (doc: 10) — the big one

- ReaderScreen, PageSlot, prefetch queue, chrome, progress tracking,
  auto-next, source fallback. Add `wakelock_plus`.
- DoD: 10 §DoD in full (cold-open < 3 s, airplane-mode re-read, RAM budget).

## Phase 8 — Paged + Novel readers (doc: 11) + Nekopost adapter (doc: 06)

- Do 11's shared plumbing; then reverse-engineer nekopost per 06 (§2 probe,
  fill §4 table, port keiyoushi logic); novel end-to-end.
- DoD: 11 §DoD + 06 §DoD.

## Phase 9 — Library + History (doc: 12)

- Library screen, categories (user + smart), sorting incl. Thai collation,
  quick filters, manual merge/split. **History tab (12 §5): reading_history
  upsert from reader completion + the grouped timeline screen.**
- DoD: 12 §DoD in full (incl. History checks).

## Phase 10 — Downloads + Offline tab + updates (doc: 13)

- Download sheet, **Offline tab (truthful ready-offline list + queue)**,
  pinning, quota, updates checker + Library bell feed. Add `connectivity_plus`.
- DoD: 13 §DoD (incl. offline-truthfulness checks).

## Phase 11 — Settings + polish + release (docs: 14 + this)

- Settings screen complete; app icon + label; final QA pass:
  - [ ] Full journey: search → open → read 3 chapters (webtoon, paged, novel)
    → library badge → download range → airplane re-read → updates refresh.
  - [ ] `flutter analyze` 0 issues; `flutter test` green.
  - [ ] `flutter build apk --release` succeeds; install on phone; repeat the
    full journey on the release build.
  - [ ] Update root README + CHANGELOG; mark v1 in CHANGELOG.

## Rules that apply to every phase

1. Read the linked docs fully before writing that phase's code.
2. Never weaken a DoD to make it pass — fix the code or escalate.
3. All network through `safe_http`; all images through the pipeline; all
   strings through `t()`.
4. Keep files under ~400 lines; split rather than grow monsters.
5. No new dependencies beyond: the 01 table + `url_launcher`, `wakelock_plus`,
   `connectivity_plus`, `cookie_jar`, `dio_cookie_manager`, `sqflite_common_ffi`
   (dev). Anything else needs a note in PLAN_NOTES.md justifying it.
6. **Git discipline (user requirement — D7).** At the end of every phase:

   ```powershell
   git add -A
   git commit -m @'
   Phase N: <short title>

   - [x] navbar complete
   - [x] browse search complete
   - [x] webtoon reader complete
   - [ ] paged reader (next phase)
   '@
   git push
   ```

   The body MUST enumerate every completed unit with `- [x] <thing> complete`
   lines (and `- [ ]` for what's knowingly left for later phases) — the user
   reads the commit list as a progress report. Never amend pushed commits;
   a fix after push is its own small commit (`Fix: <what>`). Verify the
   remote first with `git remote -v` (expected:
   https://github.com/DotJumpDot/Star_Codex.git).

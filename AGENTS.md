# AGENTS.md — operating instructions for AI coding agents

Read this before touching anything. It exists so any fresh agent session can
pick the build up correctly without re-deriving rules.

**All replies, commits, and docs are English only** (user requirement —
never mirror hook/system text language).

## Project

**Star Codex** — Flutter Android app (Thai-first UI) reading from 7 live
Thai manga/novel sources in the main feed (5× WordPress-Madara/ts +
bully-manga custom engine + nekopost API incl. novels) plus a separate
**Doujin 18+ page** with 2 more (ntr-manga, hentaithai) and doujin-lc +
miku-doujin — since db v9 (2026-10-23) ALL 11 sources ship enabled: the
WAF ladder (dio → cronet → webview, PLAN_NOTES 2026-10-23) gets through
every Cloudflare block. Streaming
reading, silent WebP q80 caching, content-hash dedup. Personal local use
only — no server, no cloud, no login. **v1.4.5 released** (GitHub
Releases, release-signed APK); the repo is public. The browse feed is
built from each site's own recent-updates grid — the site's order and
its live "x minutes ago" labels, anchored at the page's cache-generation
time so cached copies can't freeze them (PLAN_NOTES 2026-10-22/23).

## Startup sequence (every session)

1. Read [`Docs/HANDOFF.md`](Docs/HANDOFF.md).
2. Read [`Docs/Plan/README.md`](Docs/Plan/README.md), then
   [`Docs/Plan/15-BUILD-ORDER.md`](Docs/Plan/15-BUILD-ORDER.md).
3. Check `git log --oneline -10` and [`CHANGELOG.md`](CHANGELOG.md) (repo
   root) for progress. All 11 build phases are complete and **v1.0.0 →
   v1.4.5 are shipped**; remaining work is whatever the user asks for in
   chat, landing as `Phase`/`Fix`/feature commits per the discipline
   below.
4. [`Docs/Plan/00-DECISIONS.md`](Docs/Plan/00-DECISIONS.md) is the contract —
   it wins over any phase doc. Never violate it silently.
5. [`Docs/PLAN_NOTES.md`](Docs/PLAN_NOTES.md) carries the post-plan
   invariants (source quirks, db migrations v2–v9, cover fallbacks,
   probe matching, Cloudflare blocks, reader smoothness + UI-thread
   rules). Read its newest sections before touching sources, merge
   logic, the reader, or the DB.
6. [`Docs/SOURCES.md`](Docs/SOURCES.md) is the per-site reference (which
   adapter talks to which site, its markup quirks, which sites support
   the grid feed, which are Cloudflare-blocked). Read it before touching
   any adapter.

## Hard rules

- **Definition of Done is not optional.** Run each phase's checks. A phase
  that fails its checks is not done. Never weaken a DoD to make it pass.
- **All network through `safe_http`** (scheme + host validation before every
  request — Plan/04 §2). All images through the pipeline. All user-visible
  strings through `t()`.
- **No new dependencies** beyond the Plan/01 table + the additions listed in
  15-BUILD-ORDER rule 5 (+ `connectivity_plus` 7.3.2, see PLAN_NOTES).
  Anything else needs a note in [`Docs/PLAN_NOTES.md`](Docs/PLAN_NOTES.md)
  justifying it.
- **No codegen** (drift/freezed/build_runner). Plain classes, manual
  Riverpod providers.
- Files under ~400 lines; split rather than grow.
- Keep the repo clean: no build artifacts, logs, or QA screenshots in git
  (they are gitignored — never `git add` them).
- If genuinely blocked on a user decision, ask in chat with a concrete
  recommendation. Otherwise decide from the docs.
- **Cadence: after each user-request batch, a big-model review pass**
  re-reads the new code, fixes bugs, and lands one
  `Fix: post-<batch> review pass (big model)` commit (see git history for
  the pattern). Keep it. Visual QA runs in a vision-capable (Flash)
  session when the user asks; the big model defers emulator screenshots.
- **Releases**: tag `v<version>` + GitHub Release with
  `StarCodex-<version>.apk` (release-signed via the out-of-repo keystore).
  Also bump `AboutSection.appVersion` in
  `app/lib/ui/settings/settings_storage_sources.dart` — it is a hardcoded
  const, NOT read from pubspec. `gh` auth in this environment: extract
  the PAT with
  `printf "protocol=https\nhost=github.com\n\n" | git credential fill`
  → export as `GH_TOKEN`. Notes are English with install steps + SHA-256.
  **Full runbook: [`Docs/RELEASING.md`](Docs/RELEASING.md).**

## Git discipline (user requirement D7)

Every phase/batch ends with:

```
git add -A
git commit -m "Phase N: <short title>

- [x] <thing> complete
- [ ] <left for later>
"
git push
```

The body MUST enumerate completed units as `- [x]` lines — the user reads
commits as a progress report. Never amend pushed commits; post-push fixes
are their own `Fix: <what>` commit. Remote:
`https://github.com/DotJumpDot/Star_Codex.git`.
Also append lines to [`CHANGELOG.md`](CHANGELOG.md) per batch.

## Environment (this machine)

- Flutter 3.47.7 stable at `C:\tools\flutter\bin` (on user PATH; in Git Bash
  `export PATH="/c/tools/flutter/bin:$PATH"`).
- Android SDK at `%LOCALAPPDATA%\Android\Sdk` (platform 36, platform-tools,
  licenses accepted). JAVA_HOME → Temurin 17. Release keystore descriptor:
  `%USERPROFILE%\.android\star-codex-key.properties`.
- Emulator AVD `StarCodex` (Pixel 7, API 36). Headless boot:
  `emulator -avd StarCodex -no-window -no-snapshot -gpu swiftshader_indirect
  -no-boot-anim -memory 3072`. Drive UI via adb (`input tap/swipe`,
  `uiautomator dump`, `screencap`) — screenshot + inspect before declaring
  UI work done. For the USER to look at the app themselves, drop
  `-no-window` (app installs persist across reboots; a GUI exit code of
  2816 usually just means the user closed the window) — or just run
  `scripts\boot-emu.bat [ramMB]`, which does exactly that (windowed
  boot, no CPU/RAM caps, ALWAYS a cold boot — a quick-boot snapshot
  restored under a different host GPU state corrupts the guest GL stack
  and Flutter/Impeller renders BLACK while system UI is fine,
  2026-10-24). A leftover HEADLESS qemu holds the AVD lock
  and a second launch dies with "Running multiple emulators" — kill it
  first (`taskkill //PID <qemu> //F`).
- When the host is busy (user gaming etc.), boot via
  `scripts\boot-emu-low.bat [ramMB]` instead: guest RAM default 2048,
  QEMU pinned to the top 2 threads + BelowNormal priority, GPU untouched.
  Boot takes 10–20 min in that mode — that is expected, not a hang.
- Phone-in-hand remains the judge for performance DoDs (timing, RAM).

## Patch-tooling gotchas (learned the hard way)

- **Large `python - <<'PYEOF'` heredocs corrupt** ("unterminated
  triple-quoted string") — the shell mangles big multi-line UTF-8 bodies.
  For multi-line patches use the **Edit tool**, not heredoc python.
- The mimosa security hook **blocks writing `.py` patch scripts that contain
  repo-relative paths** (path-traversal false positive). Same conclusion:
  Edit tool.
- Run repo-root python one-liners with an explicit `cd /c/Code/StarCodex`
  first — the Bash cwd silently resets between calls.
- `adb` is not on the Git Bash PATH — use the full SDK paths
  (`/c/Users/jamej/AppData/Local/Android/Sdk/platform-tools/adb.exe`).
- `adb shell <path>` mangles device paths through MSYS conversion — prefix
  `export MSYS_NO_PATHCONV=1` for on-device paths like `/sdcard/ui.xml`.
- `adb shell cat <file>` corrupts BINARY output (CRLF translation) — pull
  binaries (DB, screenshots) with `adb exec-out cat`/`adb exec-out
  screencap` instead. Copy the app DB only after `am force-stop` (WAL
  mid-write otherwise).
- PowerShell from Git Bash eats `$_` unless the whole `-Command` string is
  single-quoted; `wmic` returns nothing on this Windows build.

## Testing gotchas (learned the hard way)

- **Never pipe `flutter.bat` output** through `tr/grep/tail` in Git Bash —
  dart.exe children hold the pipe and the shell hangs. Redirect to a file:
  `flutter.bat test > out.log 2>&1; echo $?`, then read the file.
- Widget tests must set `GoogleFonts.config.allowRuntimeFetching = false`
  (FakeAsync can't complete real font fetches; the shared font cache makes a
  *second* widget test in the same file hang for 10 minutes). Prefer one
  widget test per file.
- Real async (I18nService.load, DB open) must complete in `main()` BEFORE
  `testWidgets` registers. Inside a test body, everything that hits the
  sqflite ffi isolate needs `await tester.runAsync(...)` drains — including
  plain `SettingsDao.get()` reads, not just fire-and-forget writes.
- **`pumpAndSettle` times out once real screens are mounted** (Library/
  History/Offline show indeterminate spinners while ffi loads pend under
  FakeAsync). Use the drain-loop pattern instead:
  `for (...) { await tester.runAsync(() => Future.delayed(150ms)); await tester.pump(); }`.
  Exception: it is safe when a test mounts exactly ONE screen with no
  other tabs and its load already drained (library_widget_test does this
  for bottom-sheet interaction).
- A single `pump(const Duration(milliseconds: 300))` may NOT complete a
  modal-bottom-sheet entrance for tap targeting — use `pumpAndSettle` in
  the single-screen case above, or tap after two pumps.
- `helpers.openTestDb` disables sqflite_common's 10 s transaction-lock
  watchdog — with several controllers reading the DB it leaves a pending
  FakeTimer at teardown and the test dies on "A Timer is still pending".
  (sqflite_common is a dev_dependency for that import.)
- **Android's `insertWithOnConflict(IGNORE)` returns −1 when the row
  exists; the sqflite ffi test shim returns 0** — never treat "non-zero"
  as a rowid (`id > 0`, then by-name lookup — the TagsDao −1 sentinel FK
  crash, on-device QA 2026-10-18).
- **Migration tests must recreate the old-era tables**: a "pretend vN" DB
  built by rolling a FRESH database back runs the new ALTERs against
  columns that already exist → "duplicate column" (db_test drops and
  rebuilds the v1-era `library` for the v4 test).
- Dart's `List.sort` is NOT stable — never assert tail order of
  tie-broken sorts; assert the parts the comparator actually orders.
- `FakeSource`'s result maps and `.error` are MUTABLE — seed/flip them
  mid-test (e.g. take a source offline between ticks).
- Broadcast streams (downloads snapshots): **subscribe BEFORE driving the
  emitter** — broadcast streams don't replay.
- "newer than X" fixtures need explicit timestamps (`seenAt + 1000`), never
  `DateTime.now()` twice — same-millisecond collisions make assertions
  flaky. Whole doubles interpolate as `1.0`, not `1` (`'c$number'` →
  `c1.0`) — format them.
- Warm full suite ≈ 11 s. If a run takes minutes, something is
  hanging — investigate, don't retry blindly.
- Screencap PNGs render to the agent DOWNSCALED — pixel coords estimated
  from a screenshot miss `input tap` targets by ~15% (a chip read at
  y≈928 off the image was really at y≈1114 on the device, 2026-10-20).
  Always take tap targets from `uiautomator dump` bounds (`adb exec-out
  cat` the dump; text nodes can come back empty right after an
  animation — settle a couple of seconds and re-dump). Screenshots are
  for how things LOOK; bounds are for where things ARE.

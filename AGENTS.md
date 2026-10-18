# AGENTS.md — operating instructions for AI coding agents

Read this before touching anything. It exists so any fresh agent session can
pick the build up correctly without re-deriving rules.

## Project

**Star Codex** — Flutter Android app (Thai-first UI) reading from 5 Thai
manga sites (4× WordPress-Madara + nekopost API incl. novels). Streaming
reading, silent WebP q80 caching, content-hash dedup. Personal local use
only — no server, no cloud, no login.

## Startup sequence (every session)

1. Read [`Docs/HANDOFF.md`](Docs/HANDOFF.md).
2. Read [`Docs/Plan/README.md`](Docs/Plan/README.md), then
   [`Docs/Plan/15-BUILD-ORDER.md`](Docs/Plan/15-BUILD-ORDER.md).
3. Check `git log --oneline -10` and [`CHANGELOG.md`](CHANGELOG.md) (repo
   root) for progress. All 11 build phases are complete (v1, 2026-10-17);
   remaining work is the deferred on-device DoD pass plus anything the
   user asks for in chat.
4. [`Docs/Plan/00-DECISIONS.md`](Docs/Plan/00-DECISIONS.md) is the contract —
   it wins over any phase doc. Never violate it silently.

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
- Keep the repo clean: no build artifacts in git.
- If genuinely blocked on a user decision, ask in chat with a concrete
  recommendation. Otherwise decide from the docs.
- **Cadence: after each phase batch, a big-model review pass** re-reads the
  new code, fixes bugs, and lands one `Fix: post-Phase-N review pass (big
  model)` commit (see git history for the pattern). Keep it.

## Git discipline (user requirement D7)

Every phase ends with:

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
Also append one line to [`CHANGELOG.md`](CHANGELOG.md) per phase.

## Environment (this machine)

- Flutter 3.47.7 stable at `C:\tools\flutter\bin` (on user PATH; in Git Bash
  `export PATH="/c/tools/flutter/bin:$PATH"`).
- Android SDK at `%LOCALAPPDATA%\Android\Sdk` (platform 36, platform-tools,
  licenses accepted). JAVA_HOME → Temurin 17.
- Emulator AVD `StarCodex` (Pixel 7, API 36). Headless boot:
  `emulator -avd StarCodex -no-window -no-snapshot -gpu swiftshader_indirect
  -no-boot-anim -memory 3072`. Drive UI via adb (`input tap/swipe`,
  `uiautomator dump`, `screencap`) — this is the project's "Playwright":
  screenshot + inspect before declaring UI work done.
- When the host is busy (user gaming etc.), boot via
  `scripts\boot-emu-low.bat [ramMB]` instead: guest RAM default 2048,
  QEMU pinned to the top 2 threads + BelowNormal priority, GPU untouched.
  Boot takes 10–20 min in that mode — that is expected, not a hang.
- Phone-in-hand remains the judge for performance DoDs (timing, RAM).

## Patch-tooling gotchas (learned the hard way — Phases 5-11)

- **Large `python - <<'PYEOF'` heredocs corrupt** ("unterminated
  triple-quoted string") — the shell mangles big multi-line UTF-8 bodies.
  For multi-line patches use the **Edit tool**, not heredoc python.
- The mimosa security hook **blocks writing `.py` patch scripts that contain
  repo-relative paths** (path-traversal false positive). Same conclusion:
  Edit tool.
- Run repo-root python one-liners with an explicit `cd /c/Code/StarCodex`
  first — the Bash cwd silently resets between calls.

## Testing gotchas (learned the hard way — Phases 1-11)

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
- `helpers.openTestDb` disables sqflite_common's 10 s transaction-lock
  watchdog — with several controllers reading the DB it leaves a pending
  FakeTimer at teardown and the test dies on "A Timer is still pending".
  (sqflite_common is a dev_dependency for that import.)
- **Android's `insertWithOnConflict(IGNORE)` returns −1 when the row
  exists; the sqflite ffi test shim returns 0** — never treat "non-zero"
  as a rowid (`id > 0`, then by-name lookup — the TagsDao −1 sentinel FK
  crash, on-device QA 2026-10-18).
- `FakeSource`'s result maps and `.error` are MUTABLE — seed/flip them
  mid-test (e.g. take a source offline between ticks).
- Broadcast streams (downloads snapshots): **subscribe BEFORE driving the
  emitter** — broadcast streams don't replay.
- "newer than X" fixtures need explicit timestamps (`seenAt + 1000`), never
  `DateTime.now()` twice — same-millisecond collisions make assertions
  flaky. Whole doubles interpolate as `1.0`, not `1` (`'c$number'` →
  `c1.0`) — format them.
- Warm full suite ≈ 10 s (168 tests). If a run takes minutes, something is
  hanging — investigate, don't retry blindly.

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
   root) for progress. Continue at the first unfinished phase.
4. [`Docs/Plan/00-DECISIONS.md`](Docs/Plan/00-DECISIONS.md) is the contract —
   it wins over any phase doc. Never violate it silently.

## Hard rules

- **Definition of Done is not optional.** Run each phase's checks. A phase
  that fails its checks is not done. Never weaken a DoD to make it pass.
- **All network through `safe_http`** (scheme + host validation before every
  request — Plan/04 §2). All images through the pipeline. All user-visible
  strings through `t()`.
- **No new dependencies** beyond the Plan/01 table + the additions listed in
  15-BUILD-ORDER rule 5. Anything else needs a note in
  [`Docs/PLAN_NOTES.md`](Docs/PLAN_NOTES.md) justifying it.
- **No codegen** (drift/freezed/build_runner). Plain classes, manual
  Riverpod providers.
- Files under ~400 lines; split rather than grow.
- Keep the repo clean: no build artifacts in git.
- If genuinely blocked on a user decision, ask in chat with a concrete
  recommendation. Otherwise decide from the docs.

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
- Phone-in-hand remains the judge for performance DoDs (timing, RAM).

## Testing gotchas (learned the hard way — Phase 1)

- **Never pipe `flutter.bat` output** through `tr/grep/tail` in Git Bash —
  dart.exe children hold the pipe and the shell hangs. Redirect to a file:
  `flutter.bat test > out.log 2>&1; echo $?`, then read the file.
- Widget tests must set `GoogleFonts.config.allowRuntimeFetching = false`
  (FakeAsync can't complete real font fetches; the shared font cache makes a
  *second* widget test in the same file hang for 10 minutes). Prefer one
  widget test per file.
- Warm full suite ≈ 4 s. If a test run takes minutes, something is hanging —
  investigate, don't retry blindly.

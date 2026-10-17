# HANDOFF — read this first in a new conversation

> Written 2026-10-17 for restarting work in a fresh ZCode session after the
> folder was renamed `C:\Code\Manga_Reader` → `C:\Code\StarCodex`.

## Where things stand

- **Nothing has been built yet.** The app (`app/`) does not exist — the
  project is at the end of the *planning* stage.
- The complete build plan lives in **[`Plan/`](./Plan/)** — 16 documents,
  start at [`Plan/README.md`](./Plan/README.md). The decision contract is
  [`Plan/00-DECISIONS.md`](./Plan/00-DECISIONS.md); the master build sequence
  is [`Plan/15-BUILD-ORDER.md`](./Plan/15-BUILD-ORDER.md).
- Git is linked to **https://github.com/DotJumpDot/Star_Codex** and pushed.
  `git pull` to confirm you're current. Every build phase MUST end with a
  checklist-style commit + push (rule 6 in 15-BUILD-ORDER).
- Flutter SDK / Android toolchain are **not installed yet** — that is Phase 0,
  see [`BUILD.md`](./BUILD.md).

## Project in 3 lines

**Star Codex** = Flutter Android app (Thai-first UI) reading from 5 Thai
manga sites (4× WordPress-Madara + nekopost API incl. novels). Reading is
streaming like a website; viewed pages silently cache as WebP q80,
content-hash deduplicated. Tabs: Browse / Library / History / Offline /
Settings. Personal local use only — no server, no cloud, no login.

## What to tell the new conversation

Use a prompt like this (GLM 5.3 Flash or any model):

```
Read C:\Code\StarCodex\AGENTS.md, then Docs\Plan\README.md and
Docs\Plan\15-BUILD-ORDER.md. Continue the Star Codex build from where it
stands (check git log + CHANGELOG.md at the repo root for progress). Follow
the plan docs exactly; end every phase with the checklist commit + push.
```

## Notes about the rename

- The GitHub remote is unaffected (it points at GitHub, not the local path).
- The old conversation (planning session) is archived by ZCode under
  `C:\Users\jamej\.zcode\cli\rollout\` as `model-io-sess_*.jsonl` — it is
  not needed to continue; this Docs folder is the source of truth.
- `compress_test/` (one-off WebP benchmark, git-ignored) may or may not have
  survived the rename — it's disposable either way.

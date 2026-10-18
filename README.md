# Star Codex

Local-first Android manga / manhwa / manhua / novel reader for five Thai
sources. One app instead of five websites. **Personal use only — no cloud,
no server, no login.**

```
Load once - read anywhere - stored light. Star Codex
```

## Download & install

Grab `app-release.apk` from the latest
[GitHub Release](https://github.com/DotJumpDot/Star_Codex/releases/latest)
and install it (allow "install from unknown sources" when prompted).
Requires Android 7.0+ (API 24). If an older debug/test build is installed,
uninstall it first — release builds are signed with a different key.

## Sources

| Site | Type | Adapter |
|---|---|---|
| go-manga.com | Manga / Manhwa / Manhua | Madara |
| slow-manga.net | Manga / Manhwa / Manhua | Madara |
| up-manga.com | Manga / Manhwa / Manhua | Madara |
| dark-manga.com | Manga / Manhwa / Manhua (incl. Mature) | Madara |
| nekopost.net | Comics + novels | custom API |

The same title on several sites merges into one library entry (Thai title
kept, original name shown as subtitle) with automatic chapter fallback
between sources.

## Highlights

- **Read like a website, cache like an app** — tap a chapter and pages
  stream in; everything you view is silently stored compressed (WebP q80,
  −58% measured) and content-hash deduplicated across sites.
- **Self-cleaning cache** (5 GB default LRU) — nothing to manage. Optional
  pinned downloads for offline, capped by a 100 GB quota setting.
- **Webtoon vertical reader + paged manga reader (LTR/RTL) + novel reader**
  with font/background controls. Reading position resumes automatically,
  auto-next on chapter end.
- **Library** — categories, cross-source merge, new-chapter badges.
  **History** tab (what you read, when) and **Offline** tab (what's really
  on disk — always truthful).
- Browse/search all sites at once, per-site filters, genre browsing,
  categories, tags. UI is Thai-first with an English toggle.

## Repository layout

```
Star_Codex/
├── Docs/          architecture, build & run guides
│   └── Plan/      the complete 16-document build plan (start: Plan/README.md)
└── app/           Flutter project
```

## Build (short version)

```powershell
cd app
flutter pub get
flutter build apk --release
flutter install
```

Release signing uses a keystore kept outside the repo
(`%USERPROFILE%\.android\star-codex-key.properties`); without it the
release build falls back to debug signing — see
[Docs/PLAN_NOTES.md](./Docs/PLAN_NOTES.md) for the signing baseline.

Full toolchain setup: [Docs/BUILD.md](./Docs/BUILD.md). Dev loop:
[Docs/HOW_TO_RUN.md](./Docs/HOW_TO_RUN.md). How it works:
[Docs/ARCHITECTURE.md](./Docs/ARCHITECTURE.md).

## Status

**v1.0.0 (2026-10-18)** — all 11 build phases complete, on-device QA
verification complete (8 bugs found and fixed along the way — see
[Docs/QA-ON-DEVICE.md](./Docs/QA-ON-DEVICE.md)), `flutter test` green
(168 tests), `flutter analyze` clean. APKs are published via GitHub
Releases. Build progress: [CHANGELOG.md](./CHANGELOG.md) and the commit
history — every phase lands as a commit with a `- [x] item complete`
checklist.

On-phone performance checks (cold-open timing, RAM budget on a real
device) remain the only open v1 item — everything emulator-verifiable has
been verified.

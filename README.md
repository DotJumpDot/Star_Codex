# Star Codex

Local-first Android manga / manhwa / manhua / novel reader for five Thai
sources. One app instead of five websites. **Personal use only — no cloud,
no server, no login.**

```
โหลดครั้งเดียว  อ่านทุกที่  เก็บให้เบา  ⭐ Star Codex
```

## Sources

| Site | Type | Adapter |
|---|---|---|
| go-manga.com | Manga / Manhwa / Manhua | Madara |
| slow-manga.net | Manga / Manhwa / Manhua | Madara |
| up-manga.com | Manga / Manhwa / Manhua | Madara |
| dark-manga.com | Manga / Manhwa / Manhua (incl. Mature) | Madara |
| nekopost.net | Comics + **นิยาย (novels)** | custom API |

The same title on several sites merges into one library entry (Thai title
kept, original name shown as subtitle) with automatic chapter fallback
between sources.

## Highlights

- **Read like a website, cache like an app** — tap a chapter and pages
  stream in; everything you view is silently stored compressed (WebP q80,
  −58% measured) and content-hash deduplicated across sites.
- **Self-cleaning cache** (5 GB default LRU) — nothing to manage. Optional
  pinned downloads for offline, capped by a 100 GB quota setting.
- **Webtoon vertical reader + paged manga reader + Thai novel reader.**
- **History tab** (what you read, when) and **Offline tab** (what's really
  on disk — always truthful).
- Browse/search all sites at once, per-site filters, genre browsing,
  categories, tags, Thai-first UI (EN toggle).

## Repository layout

```
Star_Codex/
├── Docs/          architecture, build & run guides
│   └── Plan/      the complete 16-document build plan (start: Plan/README.md)
└── app/           Flutter project (created by Plan Phase 1)
```

## Build (short version)

```powershell
cd app
flutter pub get
flutter build apk --release
flutter install
```

Full toolchain setup: [Docs/BUILD.md](./Docs/BUILD.md). Dev loop:
[Docs/HOW_TO_RUN.md](./Docs/HOW_TO_RUN.md). How it works:
[Docs/ARCHITECTURE.md](./Docs/ARCHITECTURE.md).

## Status

**v1 shipped (2026-10-17)** — all 11 build phases complete, `flutter test`
green (161 tests), release APK builds clean
(`app/build/app/outputs/flutter-apk/app-release.apk`). Build progress: see
[CHANGELOG.md](./CHANGELOG.md) and the commit history — every build phase
lands as a commit with a `- [x] item complete` checklist.

On-phone performance DoDs (cold-open timing, RAM budget, airplane-mode
re-reads) remain to be verified in hand — they are tracked as unchecked
items in the phase commits and Docs/PLAN_NOTES.md.

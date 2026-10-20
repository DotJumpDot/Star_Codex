<div align="center">

<img src="Picture/star_codex_logo.png" width="150" alt="Star Codex logo" />

# Star Codex

**Local-first manga · manhwa · manhua · novel reader for Thai sources**

One app instead of seven websites — read like a site, cache like an app.

[![Latest Release](https://img.shields.io/github/v/release/DotJumpDot/Star_Codex?label=release&logo=github)](https://github.com/DotJumpDot/Star_Codex/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](https://github.com/DotJumpDot/Star_Codex/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![API](https://img.shields.io/badge/Android-7.0%2B-38BDF8?logo=android&logoColor=white)](https://github.com/DotJumpDot/Star_Codex/releases/latest)

*Personal use only — no cloud, no server, no login, no ads. Everything stays on your device.*

</div>

---

## ✨ Features

### Reading
- **3 reader modes** — vertical webtoon, paged manga with LTR/RTL tap zones,
  and a dedicated novel reader (font size, line height, background themes
  and opacity). Switching modes in the reader drawer applies **instantly**
  and resumes at the same spot
- **Reading position resumes automatically** — reopen any chapter exactly
  where you left it
- **Pull-to-continue** — drag past the end of a chapter with resistance +
  progress bar to flow into the next one (no auto-advance timers)
- **Prefetch in every mode** — pages ahead of you download in the
  background (configurable 3–12), so page turns and going back never
  flash a loading spinner
- **Smooth webtoon scrolling** — decoded pages stay in a large memory
  cache and rebuild instantly in both directions, page heights converge
  to the chapter's real shape (no jump-then-settle), and height fixes
  never shift what's under your finger
- **Cross-source chapter fallback** — when one site's page fails, another
  site's copy of the same chapter loads instead, badged with its origin

### Browsing & discovery
- **All 9 live sources in one feed** — search everything at once, filter
  by site, browse per-site genres, and sort the results (latest/oldest
  update, most/fewest chapters — latest update by default); the same
  title on several sites merges into a single card (Thai title kept,
  original as subtitle)
- **Doujin (18+) page** — a separate drawer destination with its own
  feed, site filter and scoped search, so adult sources never mix into
  the main browse
- **One-row site selector** — every site on its own line: selection
  circle, colored identity dot, and pills for what the site mostly
  carries (grounded in the sites' own listings)
- **Smart cards** — type chips in per-type colors (มังงะ / มังฮวา /
  นิยาย), chapter counts, and last-update stamps colored by freshness
  (green = hours → grey = years)
- **Background enrichment** — cards missing dates or covers get them
  filled in automatically from a budgeted detail fetch, no tapping needed
- **Robust covers** — dead or undecodable (AVIF) covers fall back to
  another site's copy of the same series

### Library & history
- **Library** — categories, grid/list views, cross-source merge (and
  unmerge), unread progress bars, per-series covers
- **"N ตอนใหม่" badges** — green, float to the top of every sort, and
  clear when you visit the series; re-arm when newer chapters land
- **History** — grouped into one row per series with the read-chapter
  range; tap resumes your latest chapter (toggleable in Settings)

### Offline & storage
- **Streaming with silent caching** — every viewed page is stored
  compressed (WebP q80, −58% measured) and content-hash deduplicated
  across sites
- **Self-cleaning cache** — 5 GB LRU by default, configurable, nothing to
  manage
- **Pinned downloads** — pick chapter ranges (even from a specific site)
  with size estimates; capped by a configurable 20 GB quota; the Offline
  tab only lists files that are really on disk

### App
- **Thai-first UI** with a full English toggle
- **25 themes** — Stardust, the Monokai family, Nord, Dracula, Tokyo
  Night, Gruvbox, Rosé Pine, Sakura, Solarized and more, plus a
  **true-black OLED family** (white / red / orange / pink / green
  accents on #000000)
- **12 fonts** — Thai (Sarabun, Prompt, Kanit, IBM Plex Sans Thai, …) and
  Latin picks, live-previewed in Settings
- **Safe by construction** — every network request goes through URL
  scheme/host validation; nothing is ever sent off-device

## 📖 Sources

Main feed (9 live):

| Site | Content | Adapter |
|---|---|---|
| go-manga.com | Manhwa / Manhua / Manga | WordPress-Madara |
| slow-manga.net | Manhwa / Manga | WordPress-Madara |
| up-manga.com | Manhwa / Manhua | WordPress-Madara |
| dark-manga.com | Manhwa | WordPress-Madara |
| fin-manga.com | Manhwa | WordPress-Madara (ts theme) |
| bully-manga.com | Manhwa / Manhua | custom static-site engine |
| nekopost.net | Comics + Thai novels (นิยาย) | custom JSON API |

Doujin 18+ page (separate destination):

| Site | Content | Adapter |
|---|---|---|
| ntr-manga.net | Manga (18+) | WordPress-Madara |
| hentaithai.net | Manga (18+) | custom one-shot engine |
| doujin-lc.net | Manhwa (18+) | WordPress-Madara (classic) — *seeded off: Cloudflare blocks non-browser apps* |
| miku-doujin.com | Manga (18+) | custom one-shot engine — *seeded off: Cloudflare blocks non-browser apps* |

## 📥 Download & install

Grab `StarCodex-<version>.apk` from the
[latest release](https://github.com/DotJumpDot/Star_Codex/releases/latest)
and install it (allow "install from unknown sources" when prompted).
Requires Android 6.0+ (API 23).

> **Upgrading from a debug/test build?** Uninstall it first — release
> builds are signed with a different key.

See [what changed in v1.2.0](https://github.com/DotJumpDot/Star_Codex/releases/tag/v1.2.0).

## 🛠️ Tech stack

- **Flutter 3.47 / Dart** — Material 3, no codegen (plain classes, manual
  Riverpod providers)
- **SQLite** (sqflite) — append-only migrations, currently v6
- **Image pipeline** — download → magic-byte validation → SHA-256 dedup →
  WebP q80 recompress (flutter_image_compress) → atomic write
- **Scraping** — `html` parser for the Madara/ts/classic themes and the
  custom engines; JSON POST API for nekopost
- **205 tests**, `flutter analyze` clean

## 🔨 Build from source

```powershell
git clone https://github.com/DotJumpDot/Star_Codex.git
cd Star_Codex\app
flutter pub get
flutter build apk --release
```

Release signing uses a keystore kept **outside the repo**
(`%USERPROFILE%\.android\star-codex-key.properties`); without it the
release build falls back to debug signing — see
[Docs/PLAN_NOTES.md](./Docs/PLAN_NOTES.md) for the signing baseline.

Full toolchain setup: [Docs/BUILD.md](./Docs/BUILD.md) ·
Dev loop: [Docs/HOW_TO_RUN.md](./Docs/HOW_TO_RUN.md) ·
Architecture: [Docs/ARCHITECTURE.md](./Docs/ARCHITECTURE.md)

## 📁 Repository layout

```
Star_Codex/
├── app/               Flutter project (lib/, test/, android/)
│   └── test/fixtures/ HTML fixtures trimmed from the live sites
├── Docs/
│   ├── Plan/          the complete 16-document build plan
│   ├── ARCHITECTURE.md / BUILD.md / HOW_TO_RUN.md / PLAN_NOTES.md
│   └── HANDOFF.md     session-to-session state
├── Picture/           the Star Codex logo (banner + icon sources)
├── scripts/           emulator boot helpers for low-load situations
├── AGENTS.md          operating instructions for AI coding agents
└── CHANGELOG.md       one line per completed batch, newest last
```

## 📜 Status

**v1.2.0 (2026-10-19)** — all 11 build phases complete, four user-driven
UX rounds shipped, the Doujin (18+) page live, on-device QA verified
(see [CHANGELOG.md](./CHANGELOG.md) for the full history). Every batch
landed as a commit with a `- [x] item complete` checklist.

## ⚠️ Disclaimer

Personal, local-use project. All content belongs to the source sites —
please support the translators and authors by visiting the original
websites.

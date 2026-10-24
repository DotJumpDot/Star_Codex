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
  to the chapter's real shape (no jump-then-settle), height fixes
  never shift what's under your finger, and loading work (hashing,
  slicing, compression) runs off the UI threads so first-time reads
  scroll without stutter
- **Oversized pages just work** — strips taller than the GPU texture
  limit (8k+ px, the "black page" chapters on some sites) are silently
  sliced into GPU-safe bands and cached that way
- **Cross-source chapter fallback** — when one site's page fails, another
  site's copy of the same chapter loads instead, badged with its origin

### Browsing & discovery
- **All 7 live sources in the main feed** — search everything at once,
  filter by site, browse per-site genres, sort the results (latest/oldest
  update, most/fewest chapters — latest update by default), and flip
  the feed between ล่าสุด and ยอดนิยม (server-side popularity on the
  sites that support it); the same title on several sites merges into a
  single card (Thai title kept, original as subtitle). The Doujin page
  adds 2 more live sites of its own
- **Works offline** — airplane mode shows your visited series from the
  on-device catalog instead of a blank page, downloaded chapters read
  anywhere, and covers/last-update dates persist to disk
- **Doujin (18+) page** — a separate drawer destination with its own
  feed, site filter and scoped search, so adult sources never mix into
  the main browse
- **One-row site selector** — every site on its own line: selection
  circle, colored identity dot, and pills for what the site mostly
  carries (grounded in the sites' own listings)
- **Smart cards** — type chips in per-type colors (มังงะ / มังฮวา /
  นิยาย), chapter counts, and last-update stamps colored by freshness
  (green = hours → grey = years); the leftover space under the chips
  shows the series intro, as many lines as fit
- **The feed is the site's own grid** — page 1 of the feed is built from
  each site's "updated recently" homepage grid, so the card order and
  the "x minutes ago" stamps match the website instead of a local guess
- **Background enrichment** — cards missing dates or covers get them
  filled in automatically from a budgeted detail fetch, no tapping needed;
  dated cards are re-checked every 6 h, and a card the site's grid lists
  is refreshed from that label (no extra request)
- **Skeleton loading** — browse cards and series detail pages show
  shape-matching placeholders while they load, never bare spinners
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

Main feed (7 live):

| Site | Content | Adapter |
|---|---|---|
| go-manga.com | Manhwa / Manhua / Manga | WordPress-Madara |
| slow-manga.net | Manhwa / Manga | WordPress-Madara |
| up-manga.com | Manhwa / Manhua | WordPress-Madara |
| dark-manga.com | Manhwa | WordPress-Madara |
| fin-manga.com | Manhwa | WordPress-Madara (ts theme) |
| bully-manga.com | Manhwa / Manhua | custom static-site engine |
| nekopost.net | Comics + Thai novels (นิยาย) | custom JSON API |

Doujin 18+ page (separate destination — all 4 enabled):

| Site | Content | Adapter |
|---|---|---|
| ntr-manga.net | Manga (18+) | WordPress-Madara |
| hentaithai.net | Manga (18+) | custom one-shot engine |
| doujin-lc.net | Manhwa (18+) | WordPress-Madara (classic) |
| miku-doujin.com | Manga (18+) | custom one-shot engine |

Cloudflare-blocked sites (dark-manga's whole-site challenge,
doujin-lc/miku's TLS fingerprinting) are handled by the app's **WAF
ladder**: the normal stack first, an embedded Chromium network stack
(cronet) for fingerprint blocks, and an in-app WebView that clears
"Just a moment..." challenges automatically.

## 📥 Download & install

Grab `StarCodex-<version>.apk` from the
[latest release](https://github.com/DotJumpDot/Star_Codex/releases/latest)
and install it (allow "install from unknown sources" when prompted).
Requires Android 7.0+ (API 24).

> **Upgrading from a debug/test build?** Uninstall it first — release
> builds are signed with a different key.

See [what changed in v1.4.4](https://github.com/DotJumpDot/Star_Codex/releases/tag/v1.4.4).

## 🛠️ Tech stack

- **Flutter 3.47 / Dart** — Material 3, no codegen (plain classes, manual
  Riverpod providers)
- **SQLite** (sqflite) — append-only migrations, currently v9
- **Image pipeline** — download → magic-byte validation → SHA-256 dedup →
  WebP q80 recompress (flutter_image_compress) → atomic write; hashing
  and oversized-strip slicing run on background threads/isolates so
  loading never stutters scrolling
- **Scraping** — `html` parser for the Madara/ts/classic themes and the
  custom engines; JSON POST API for nekopost; WAF ladder (dio → cronet →
  webview) for Cloudflare-blocked sites
- **276 tests**, `flutter analyze` clean

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
Release runbook: [Docs/RELEASING.md](./Docs/RELEASING.md) ·
Per-site reference: [Docs/SOURCES.md](./Docs/SOURCES.md) ·
Architecture: [Docs/ARCHITECTURE.md](./Docs/ARCHITECTURE.md)

## 📁 Repository layout

```
Star_Codex/
├── app/               Flutter project (lib/, test/, android/)
│   └── test/fixtures/ HTML fixtures trimmed from the live sites
├── Docs/
│   ├── Plan/          the complete 16-document build plan
│   ├── ARCHITECTURE.md / BUILD.md / HOW_TO_RUN.md / PLAN_NOTES.md
│   ├── SOURCES.md     per-site reference (adapter, quirks, grid support)
│   ├── RELEASING.md   the release runbook
│   └── HANDOFF.md     session-to-session state
├── Picture/           the Star Codex logo (banner + icon sources)
├── scripts/           emulator boot helpers (boot-emu.bat = windowed,
│                      boot-emu-low.bat = low-load headless)
├── AGENTS.md          operating instructions for AI coding agents
└── CHANGELOG.md       one entry per completed batch
```

## 📜 Status

**v1.4.4 (2026-10-24)** — chapter-list polish: dateless chapters show
"ไม่ระบุวันที่" at full row height, and update dates are color-coded by
age on a theme-derived ladder (accent for fresh, drifting warm through
yellow/orange to red variants across the years). All 11 build phases
are complete; every batch landed as a commit with a `- [x] item
complete` checklist (see [CHANGELOG.md](./CHANGELOG.md) for the full
history).

**v1.4.3 (2026-10-24)** — fix round from on-phone reports: system bars
no longer return after chapter switches on MIUI (re-assert at entrance
settle), feed update times keep aging truthfully on sites that serve
stale cached copies (sticky anchors, db v10), search cards show the
intro text (borrowing a sibling site's synopsis when the primary has
none), Up-Manga/Dark-Manga search works again (rides the request
ladder), search results got a clear button, the reader top bar shows
the chapter ("ตอนที่ 628 · จาก dark-manga"), and recycled list rows can
no longer show another series' cover. All 11 build phases are complete;
every batch landed as a commit with a `- [x] item complete` checklist
(see [CHANGELOG.md](./CHANGELOG.md) for the full history).

**v1.4.2 (2026-10-23)** — reader pull polish. The drag-to-switch-chapter
indicator now sits in the space the page slide opens (the side the
next/previous chapter comes from) instead of over the artwork, and the
swipe distance to trigger the switch is tuned down — 160 px in the
paged (side-slide) reader, 200 px in webtoon and novel (was
420/400/300). All 11 build phases are complete; every batch landed
as a commit with a `- [x] item complete` checklist (see
[CHANGELOG.md](./CHANGELOG.md) for the full history).

**v1.4.1 (2026-10-23)** — patch: real update dates. The sites' homepages
are served from long-lived caches, so their relative labels ("4 วินาที")
were true only at page-generation time — cards sat "just updated" for
days and skewed the update-date filter. Labels are now anchored at the
page's real generation time (response `Last-Modified` / `Age`), so card
dates tick truthfully and genuinely fresh drops rank on top.

**v1.4.0 (2026-10-23)** — every source loads again. Cloudflare blocks
are answered by a per-site ladder: the normal stack, an embedded
Chromium network stack for TLS-fingerprint blocks (doujin-lc,
miku-doujin — blocked since v1, now live), and an in-app WebView that
clears "Just a moment..." challenges automatically (dark-manga). All 11
sources are enabled by default. The reader's pull-to-switch got a
Webtoon-style rework (page slides with the finger, dot-trail + arrow
indicator, bidirectional, smooth fall-back), the Android bars stay
hidden across chapter switches, hentaithai's feed pages properly, and
fin-manga covers are fixed. All 11 build phases are complete; every
batch landed as a commit with a `- [x] item complete` checklist (see
[CHANGELOG.md](./CHANGELOG.md) for the full history).

**v1.3.1 (2026-10-22)** — bug-fix release: per-chapter read-state
indicators, reader chrome carry-over, hentaithai /image/ detail pages.

## ⚠️ Disclaimer

Personal, local-use project. All content belongs to the source sites —
please support the translators and authors by visiting the original
websites.

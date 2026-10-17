# 00 — Locked Decisions (the contract)

These decisions were made with the user on 2026-10-17 and are **final** for v1.
If a phase seems to conflict with this file, this file wins. Changing anything
here requires asking the user in chat.

## Product

| # | Decision |
|---|---|
| D1 | **Flutter app, Android-only in v1.** Compiled APK, installed manually (sideload). No Play Store. A Windows build is allowed later from the same codebase but is NOT in scope for v1. |
| D2 | **Five sources:** go-manga.com, slow-manga.net, up-manga.com, dark-manga.com (all WordPress/Madara → one shared adapter) and nekopost.net (custom API). |
| D3 | **Novels are supported** via nekopost (it hosts นิยาย). Novels get a text reader, not an image reader. |
| D4 | **Thai-first UI**, English toggle. Dark theme default, Material 3. |
| D5 | **No backend, no server, no cloud, no login, no telemetry.** The app talks directly from the phone to the websites. The PC is only used to compile the APK. |
| D6 | **Personal local use only.** No sharing/export of content, no public deployment. (User's legal stance: private offline reading.) |
| D7 | **App name: Star Codex.** Repo: https://github.com/DotJumpDot/Star_Codex — `C:\Code\Manga_Reader\` IS the repo root (Docs/, app/, .gitignore). Every plan phase ends with a detailed checklist-style commit + push (see 15 §rules). Android applicationId: `com.jamej.starcodex`. |

## Navigation & tabs (user-confirmed)

Bottom nav has exactly **5 tabs**:

| Tab | Label (TH) | Content |
|---|---|---|
| Browse | ค้นหา | search all sites + latest feed + per-site filtering (08) |
| Library | คลัง | saved series, categories, sorting (12). Bell icon with badge → updates feed sheet (13) |
| **History** | **ประวัติ** | chronological "what I read": title + chapter + time (12 §5) |
| **Offline** | **ออฟไลน์** | downloaded/pinned content that exists on disk; always truthful — cache clears clean this tab (13) |
| Settings | ตั้งค่า | 14 |

## Reading model (the most important UX decision)

| # | Decision |
|---|---|
| R1 | **Reading is streaming, like a website.** Tap a chapter → pages load and display immediately with prefetch. The user never presses "download" to read. |
| R2 | **Every viewed page is auto-cached** to disk as WebP q80. Re-reading is instant + offline. |
| R3 | **Cache is self-cleaning (LRU)**, default budget 5 GB. The user never has to delete anything manually. |
| R4 | **Reading progress/history is kept forever** in SQLite (tiny rows), even after images are evicted. |
| R5 | An explicit **Download button** exists per series/chapter for permanent pinning (e.g. trips). Pinned blobs are never auto-evicted. |

## Storage

| # | Decision |
|---|---|
| S1 | **Content-addressed store:** filename = SHA-256 of the ORIGINAL downloaded bytes. Identical images (same scanlation mirrored across sites) are stored exactly once. |
| S2 | **Always recompress to WebP q80** at write time (measured on a real chapter: 15.14 MB → 6.42 MB = −58%, visually lossless). No "original quality" profile in v1. |
| S3 | **No image resizing in v1** — the five sites serve 720–1000 px wide images, narrower than phone screens, so there is nothing to gain. The pipeline keeps a `maxWidth` hook (default null) for future sites. |
| S4 | **Total storage quota setting, default 100 GB**, checked before pinned downloads. Cache (5 GB default) is a separate, smaller budget. |

## Library / filters

| # | Decision |
|---|---|
| L1 | **Browse filter "min 10 chapters + hide oneshot" exists but is DEFAULT OFF** (user changed their mind — streaming reading means junk results cost nothing). Toggle in the browse filter panel. |
| L2 | **Cross-site title merging is ON**: same title on multiple sites = one merged entry with source badges, defaulting to the source with most chapters / newest update, with per-chapter fallback to other sources. |
| L3 | User-created **categories** + smart categories; sort options incl. proper Thai ordering; tag filtering from site genres. |
| L4 | Chapter numbers like "ตอนที่ 920" must parse to a numeric `920` for sorting, filtering, and dedup. |
| L5 | **Dual titles:** Thai display title is primary (translators' Thai names are kept — user requirement); the original name (English/romaji) is stored as `series.original_title` and shown as a secondary subtitle wherever the title appears big (detail header, reader top bar). |
| L6 | **Origin grouping:** `type` = manhwa (Korea) / manga (Japan) / manhua (China) / novel. Novels additionally get best-effort `origin` (thailand/japan/korea/china) from source metadata only — never guessed from title text. |
| L7 | **Metadata completeness:** Introduction (description), genres/tags, and category/type are captured from ALL sources and merged (07 §4) — missing metadata on one site gets filled by another. |

## Measured facts (from live probes, 2026-10-17)

- slow-manga chapter images: 720 px wide strips, up to 7000 px tall, 23 pages = 15.14 MB original.
- go-manga chapter images: ~1000×1347 px pages, ~60 pages/chapter, ~100–200 KB/page.
- WebP q80 recompress: 42% of original size (58% saved). WebP q75: 35%.
- Image CDNs redirect (301) and require a browser User-Agent **and Referer** — see 04/05.

## Non-goals v1 (do not build)

- Anime streaming, tracking services (MAL/AniList sync), Cloud sync, Windows/desktop UI, reader plugins marketplace, EPUB/PDF export, account systems.

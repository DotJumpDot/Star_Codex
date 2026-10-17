# 06 — Nekopost Adapter (API-based, includes novels)

Nekopost is NOT WordPress. It is a custom app whose web frontend talks to a
backend API at `backend.nekopost.net` **[PROBED: separate backend subdomain,
Google sign-in, categories Manga / Comic / Novel / Original Novel, search
supports "ค้นหาเรื่อง ผู้แต่ง หรือกุ่มแปล"]**.

Unlike the Madara sites, this one needs **reverse-engineering work during the
build**. This document gives the method and the known reference so the work is
small and safe. Budget: one phase, most of it probing not coding.

## 1. Primary reference (port the logic, don't guess)

The Tachiyomi/Mihon ecosystem already has a maintained Nekopost scraper in
Kotlin, Apache-2.0 licensed:

- Repo: https://github.com/keiyoushi/extensions — Thai sources live under
  `lib/th/nekopost/` (package id `th.nekopost`; the built apk is
  `tachiyomi-th.nekopost-v1.6.16.apk` per the SourceForge mirror).
- Read `Nekopost.kt` there: it contains the exact endpoint paths, request
  headers, and JSON field names that worked most recently.
- Apache-2.0 allows porting the logic into our Dart adapter with attribution:
  keep a comment header in `nekopost_source.dart`:
  `// Logic ported from keiyoushi/extensions th.nekopost (Apache-2.0)`.

If the repo path moved (404), find it via GitHub code search
(`nekopost keiyoushi`) — the package name `th.nekopost` is stable.

## 2. Probe the API yourself (30 minutes, browser only)

1. Open https://www.nekopost.net in Chrome → F12 → Network tab → filter XHR.
2. Browse: home → a manga series → a chapter reader → a novel series → a
   novel chapter → type in the search box.
3. Record for each action: method, URL, headers, query/body, and save one
   example JSON response per endpoint (they're big — save to
   `Docs/Plan/notes/nekopost-*.json`, add folder to git).
4. Expected shape (from the keiyoushi extension's history): REST-ish JSON
   under `https://backend.nekopost.net/v1/...` (or similar version segment),
   no auth for public content, novel chapter content delivered as either
   structured paragraphs or an HTML/text blob — handle whichever appears.

Document every confirmed endpoint in this file's §4 table as you go.

## 3. Adapter contract

Implements the same `Source` interface (04). Specifics:

- `referer` = `https://www.nekopost.net/` (API may not need it; images might).
- `supportsNovels = true`.
- Series URLs are API ids (e.g. `nekopost:series:{id}`) — store an opaque id,
  NOT a guessable path. The series row's `source_url` must round-trip into
  `detail()` unchanged.
- `pages()` returns image URLs for comics; `novelText()` returns the chapter
  body for novels. `ChapterPages.imageUrls.isEmpty && novelText == null` is a
  bug — throw `SourceException(parse)`.
- Map nekopost categories → `type`: manga/comic → `manga`(comic style =
  paged reader), novel/original novel → `novel`.
- Novel text: normalize to plain text paragraphs separated by `\n\n`; strip
  site chrome/scripts; keep Thai text as-is (no transliteration, no trimming
  inside paragraphs).

## 4. Confirmed endpoints (FILL DURING PROBE — keep as table)

| purpose | method+path | notes |
|---|---|---|
| search | _(fill)_ | |
| latest | _(fill)_ | |
| series detail + chapter list | _(fill)_ | |
| chapter pages | _(fill)_ | |
| novel chapter text | _(fill)_ | |

## 5. Risks

- API may add a required header (e.g. `X-Requested-With` or a token from the
  page) — copy exactly what the browser sends; if a token is per-session,
  implement the token fetch step first and cache it.
- Cloudflare on the API: handled by the shared 04 policy.
- If some content requires Google login — **skip it** (decision D5: no login).
  Public catalog only. Note gaps in `Docs/CHANGELOG.md`.

## Definition of Done

- [ ] §4 table filled with confirmed endpoints + saved example responses in
  `Docs/Plan/notes/`.
- [ ] `tool/verify_sources.dart --source nekopost` prints: 10 latest, search
  "one piece", one series' chapter list with parsed numbers, one comic
  chapter's image URLs, and one **novel** chapter's first 200 characters.
- [ ] Novel chapter stored via `chapter_text` and rendered by the novel
  reader (11) end-to-end.

# 05 — Madara Adapter (go-manga, slow-manga, up-manga, dark-manga)

All four sites run WordPress + the **Madara** theme. One adapter, four config
entries. Everything below marked **[PROBED]** was verified live on 2026-10-17;
anything else must be verified with the given curl command before coding that
part (sites drift).

## 1. Per-site config

| id | base_url | series URL shape | chapter URL shape | notes |
|---|---|---|---|---|
| slow-manga | https://www.slow-manga.net | `/manga/{slug}/` **[PROBED]** | `/{slug}-{N}/` (english slug, e.g. `/eternally-regressing-knight-108/`) **[PROBED]** | images 720px strips |
| go-manga | https://www.go-manga.com | `/{slug}/` (SITE ROOT, not /manga/!) **[PROBED]** | `/{slug}-ตอนที่-{N}/` percent-encoded Thai **[PROBED]** | images ~1000px pages, ~60/ch |
| up-manga | https://www.up-manga.com | `/manga/{slug}/` (verify §7.1) | `/{slug}-ตอนที่-{N}/` (verify) | user's entry point was `/author/upmanga/` (ignore, it's just an uploader page) |
| dark-manga | https://www.dark-manga.com | `/{slug}/` **[PROBED]** | `/{slug}-ตอนที่-{N}/` **[PROBED]** | Adult/Mature/Smut tags present — keep them, they're just tags |

Because series URLs differ (`/manga/{slug}/` vs `/{slug}/`), never construct
series URLs — always take them from listing/search links. Only chapter URLs
are constructed (from series page hrefs anyway — see §4).

## 2. Listing (latest updates)

- **[PROBED]** Madara listing pages: `{base}/manga/?order=update` (grid) and
  `{base}/manga/list-mode/` (compact list). Pagination: `/manga/page/{n}/`
  (go-manga also exposes `?order=update&page={n}`).
- Parse (verify selectors per site with §7.2 — Madara markup is stable but
  class names occasionally differ):
  - items: `.page-item-detail` (grid) or `.c-tabs-item__content` (list-mode)
  - link: `.post-title h3 a` or `h5 a` → series URL + title
  - cover: `img` attr `src` or `data-src`
  - latest chapter hint: `.chapter-item a` first text → parse number (§6)
  - trust only the URL + title; everything else is best-effort

## 3. Search

- Standard Madara search **[PROBED exists on these themes]**:
  `GET {base}/?s={urlencoded}&post_type=wp-manga`
  → same `.page-item-detail` items as listing.
- Verify per site with §7.3. If a site returns a different layout, fall back
  to Google-style `site:` scraping is FORBIDDEN — instead use
  `/manga/list-mode/?s=`... if neither works for a site, mark search as
  unsupported in config (browse still works via listings + genres).
- Genre archive browse: `{base}/genres/{term}/` — parse like listing. The
  full genre list is linked from the homepage/footer `.genres-content` or
  the genres cloud — scrape once, cache in tags table.

## 4. Series detail + chapter list

GET series URL → parse:

| Field | Selector (verify §7.2) | Notes |
|---|---|---|
| title | `.post-title h1` (or `h3`) | strip whitespace |
| alt titles | `.mg_alternative, .summary_image ~ .post-content_item:has(.alternative)` — commonly `.post-status .summary-content` sibling blocks; Madara renders "Alternative" row in `.post-content_item` | best-effort; empty ok |
| description | `.description-summary .summary__content` (`p` text) | may contain links — text only |
| genres/tags | `.genres-content a` | each text = tag |
| type | `.post-kind`/"Type" row value: Manga/Manhwa/Manhua | map to enum |
| status | `.post-status .summary-content` ("OnGoing"/"Completed") | normalize lowercase |
| cover | `.summary_image img` (`src` or `data-src`) | |
| chapter list | `li.wp-manga-chapter` → `a` (URL + text), time in `span.chapter-release-date i` (attr `title` or text, parse relative) | see AJAX variant below |

**Long-series AJAX variant (go-manga has 900+ chapter series):** Madara
often ships the chapter list empty and loads via
`POST {base}/wp-admin/admin-ajax.php` with form
`action=mangabooth_get_manga_chapters&manga={postId}` (postId from
`.rating-post-id` / `#manga-chapters-holder[data-id]`).
Detect: if chapter list HTML has < 1 `li.wp-manga-chapter` but the page
contains `manga-chapters-holder`, do the AJAX POST. **Verify with §7.4.**

Chapter list is given newest-first on the site → reverse for ascending.

## 5. Chapter pages (the important one — PROBED)

GET chapter URL → the images are **NOT** in `<img>` tags (those are ads/
banners). They are in a JS init blob **[PROBED on slow-manga; same theme
everywhere — verify per site §7.5]**:

```html
<script>ts_reader.run({... "images":["https:\/\/img3.flash-manga.com\/2026\/05\/24\/xxx.jpg", ...] ...})</script>
```

Parse (Dart):
```dart
final m = RegExp(r'"images"\s*:\s*\[([^\]]*)\]').firstMatch(html);
final urls = m!.group(1)!.split(',').map((s) =>
    s.trim().replaceAll('"', '').replaceAll('\\', '')).toList();
```
Keep page order as given. Fallback if `ts_reader` missing: parse
`.reading-content img` `data-src`/`src` attributes.

**Image fetch requirements [PROBED]:**
- Image hosts (e.g. `img3.flash-manga.com`, `image.cdend.com`) answer with a
  **301 redirect** — follow redirects (safe_http does, re-validated).
- Must send desktop **User-Agent** and **Referer: {base}/** — without Referer
  some CDNs refuse/return error pages.
- Observed hosts are per-site CDN domains read from the JSON — never hardcode
  host names; use whatever URLs the blob contains (safe_http validates them).

## 6. Chapter-number parsing (decision L4)

Titles look like: `ตอนที่ 922`, `Chapter 45`, `920`, `ตอนที่ 155.5`, `- ตอนที่ 9 [จบ]`.

```
parseChapterNumber(String raw) -> double?:
  prefer first match of regex  (?:ตอนที่|chapter|ch\.?|ตอน)\s*[:#]?\s*(\d+(?:\.\d+)?)
  else first standalone number in string
  else null (adapter then uses list index as fallback number, flagged low-confidence)
```
`[จบ]`/`end`/`final` in the title → mark `title` display only, do NOT treat as oneshot.

## 7. Verification commands (run before coding each part, from PowerShell)

Save UA once: `$UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"`

1. Series shape (up-manga): `curl.exe -sL -A $UA "https://www.up-manga.com/manga/?order=update" | Select-String -Pattern "href=""https://www.up-manga.com/[^""]*/""" | Select -First 10`
2. Detail selectors: fetch a series page, confirm `.post-title`, `.genres-content`, `li.wp-manga-chapter` exist: `curl.exe -sL -A $UA "<series-url>" > t.html` then grep the classes.
3. Search: `curl.exe -sL -A $UA "https://www.slow-manga.net/?s=nano+machine&post_type=wp-manga" | Select-String "page-item-detail" | Select -First 3`
4. AJAX chapters (go-manga big series): check series page for `manga-chapters-holder`, then
   `curl.exe -s -A $UA -X POST "https://www.go-manga.com/wp-admin/admin-ajax.php" -d "action=mangabooth_get_manga_chapters&manga=<id>"` (also try action `madara_load_chapters`).
5. ts_reader (per site): fetch one chapter page, `Select-String "ts_reader.run"` must hit.
6. Novel check: Madara sites have NO novels — if a config's `supportsNovels` is true anywhere in this adapter it's a bug.

Record any drift you find by editing THIS file (date + what changed), then code it.

## 8. Config struct

```dart
class MadaraSiteConfig {
  final String id, name, baseUrl;
  final bool seriesUnderMangaPrefix;  // slow-manga,up-manga: true; go-manga,dark-manga: false
  final bool searchSupported;         // default true, flip if §7.3 fails
  final bool chaptersViaAjax;         // auto-detect per series anyway; this is a hint
}
```

## Definition of Done

- [ ] `tool/verify_sources.dart --source slow-manga` prints 10 latest series,
  searches "nano machine", prints 5 chapters of the first result with parsed
  numbers, prints 23 image URLs for one chapter (PROBED count for
  eternally-regressing-knight-108).
- [ ] Same for the other three sites (image count will differ).
- [ ] Fetching one image through the full pipeline (03) produces a WebP blob
  ~40% of original size.

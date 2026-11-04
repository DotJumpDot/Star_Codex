# Sources — per-site reference

One row per seeded source: which adapter talks to it, what its markup
looks like, and what breaks on it. Everything here was probed against the
live sites; when a site changes, update this file **and**
[PLAN_NOTES.md](./PLAN_NOTES.md) in the same batch.

20 sources are seeded and since db v9 (2026-10-23) **all 20 ship
enabled** — the WAF ladder made the last two Cloudflare-blocked ones
reachable. The Doujin (18+) page holds 5 of them, the Search Mix tab 4,
and the main feed the other 11. Adult/mix sources never appear in the
main feed and vice versa (`adultSourceIds` / `mixSourceIds` in
`app/lib/data/sources/source_registry.dart`).

## At a glance

| Site | Scope | Adapter | Live | Grid feed | Search | Notes |
|---|---|---|---|---|---|---|
| go-manga.com | main | Madara (ts) | ✅ | ✅ family A | ✅ | |
| slow-manga.net | main | Madara (ts) | ✅ | ✅ family B | ✅ | grid is chapter-linked |
| up-manga.com | main | Madara (ts) | ✅ | ✅ family A | ✅ | 2026-10-24: search rides the WAF ladder (was 403 pre-ladder) |
| dark-manga.com | main | Madara (ts) | ✅ | ✅ family A | ✅ | 2026-10-23: whole site behind the challenge — the WAF ladder's webview tier auto-solves it; 2026-10-24: search re-enabled on the same clearance |
| fin-manga.com | main | Madara (ts) | ✅ | ✅ family A | ✅ | archive order drifts A–Z; 2026-10-23: WPFC lazy covers (data-wpfc-original-src) |
| bully-manga.com | main | custom static | ✅ | ❌ **open** | ✅ | needs its own grid port |
| nekopost.net | main | JSON API | ✅ | n/a (API) | ✅ | the only novel carrier |
| nano-manga.com | main | Madara (classic) | ✅ | ✅ | ✅ | added 2026-10-28 |
| oremanga.net | main | custom WP | ✅ | ✅ (tile stamps) | ✅ | added 2026-11-03; explicit type badge on tiles + detail |
| madoo-manga.com | main | Madara (ts) | ✅ | ❌ (no time labels) | ✅ | added 2026-11-03; archive-order feed |
| 1668manga.com | main | Madara (ts) | ✅ | ✅ family B | ✅ | added 2026-11-03; reader data hides in base64 CF scripts |
| mangary.com | MIX | Toonary (Next.js) | ❌ | ✅ | ✅ | normal+18+ mixed; yaoi filtered by default |
| whytoon.com | MIX | Toonary (Next.js) | ❌ | ❌ (no genre pages) | ✅ | BL-heavy; same adapter as mangary |
| niceoppai.net | MIX | custom WP | ✅ | ✅ (unix-sec data-ago) | ✅ POST-only | added 2026-11-03; Adult category in catalog → Mix scope |
| inu-manga.net | MIX | Madara (ts) | ✅ | ✅ family B | ✅ | added 2026-11-04; plain ts config — manga+manhwa+manhua mix |
| ntr-manga.net | Doujin | Madara (ts) | ✅ | ❌ custom grid | ✅ | its own grid markup — not parsed |
| hentaithai.net | Doujin | custom one-shot | ✅ | n/a | ❌ | one-shot; thread page = reader |
| doujin-lc.net | Doujin | Madara (classic) | ✅ | n/a | ✅ | cronet lane unlocks it (2026-10-23); enabled since db v9 |
| miku-doujin.com | Doujin | custom one-shot | ✅ | n/a | ❌ | cronet lane unlocks it (2026-10-23); enabled since db v9 |
| manghaha.com | Doujin | custom WP | ✅ | ✅ (relative stamps) | ✅ | added 2026-11-03; manhwa-heavy |

"Grid feed" = whether the site renders a server-side recent-updates grid
that the v1.3.0 grid-head feed can read for exact order + live relative
stamps. See [ARCHITECTURE.md](./ARCHITECTURE.md) → "the update feed".

The grid column was verified by live probe on 2026-10-22 (counting the
`.bsx` tiles, `.fivtime` pills and `.epxdate` stamps each homepage
actually renders).

## The ts theme (go / slow / up / dark / fin, ntr)

One shared adapter (`app/lib/data/sources/madara/`), configured per site in
`configs.dart`. Two grid-label families are parsed today:

- **Family A** — `.chfiv` tiles with a `.fivchap` / `.fivtime` pill. The
  bare label ("6 ชั่วโมง", "2 นาที") is the precise age. The series link
  is `.tt a[title]` (the anchor is INSIDE `.tt`, not wrapping it — this
  trips up fixtures). go / up / dark / fin use this.
- **Family B** (slow-manga) — `.epxdate` on a chapter-linked tile. The
  stamp belongs to the CHAPTER, so it is borrowed onto the matching
  archive tile by normalized title.

Both are parsed by `Source.recentStamps()` and `parseRelativeStamp()`
(`app/lib/core/utils/thai.dart`). A third variant (ntr-manga) exists but
is not parsed — see the per-site quirks below.

The labels are relative to the page's **cache-generation time**, not the
fetch time: the ts homepages ride WP Fastest Cache behind the Cloudflare
edge (`max-age=16070400`), so the served copy can be ~a day old and a
"24 วินาที" in it is 24 s before generation (2026-10-23 user report —
fin/up cards stuck at "24 วินาที" for days). `recentStamps()` anchors
the labels at the response's `Last-Modified` (probed equal to the
plugin's own "file was created" comment), falling back to `Date − Age`
and then to fetch-now — see `core/utils/page_time.dart` and PLAN_NOTES
2026-10-23.

### Per-site quirks

- **slow-manga** — series URLs live under `/manga/{slug}/`; the grid is
  chapter-linked, so stamps are borrowed by title.
- **go-manga** — series URLs are `/<slug>/` (no prefix).
- **up-manga / dark-manga** — `?s=` (search) sits behind a Cloudflare
  challenge (plain 403 pre-ladder, 2026-10-17). Since the WAF ladder
  escalates the HOST on the CF-signed 403, search rides cronet/webview
  like every other page — `searchSupported` is `true` again (2026-10-24).
- **fin-manga** — `/manga/?order=update` intermittently serves A–Z
  instead of newest-first. The homepage grid is the reliable order
  source, which is exactly why v1.3.0 leads with it.
- **ntr-manga** — ts theme, but its tiles carry no type badges and its
  details are untyped (shown as plain Manga). Its homepage DOES render a
  recent-updates grid, but in its **own** markup — `div.ntr-upd-grid` with
  `ntr-upd-card` tiles and an `ntr-upd-eptime` stamp ("8 นาทีที่แล้ว"),
  not the ts `.bsx` / `.fivtime` shape. The Madara parser finds nothing
  there, so the Doujin feed on ntr-manga still uses the archive order.
  Supporting it is a small, self-contained follow-up (a third grid
  family) — the stamps are already in a parseable form.

### The date-only anchor rule (why no fixed time works)

ts chapter rows carry **date-only** timestamps (no time-of-day) rendered in
a **lagging site timezone**. Verified live on 2026-10-22: go-manga's
`solo-leveling` chapter list has 206 `.chapterdate` cells, every one of
them "November 18, 2025" — no time component anywhere. go-manga's
chapter from 6 hours ago reads "Oct 21"; dark-manga's chapter from 2
minutes ago reads "today". No
single anchor is correct on all sites, so date-only strings are anchored
at **local 20:00** (`_dateOnlyMs`) as the best compromise for the evening
drop cluster — and the grid stamps are what the user actually sees, so
the feed shows the grid's time, not ours.

`parseSiteDate` (needs a "ที่แล้ว/ago" marker for relative text) is for
absolute/relative dates; `parseRelativeStamp` (bare labels allowed) is
for grid pills only. Mixing them up is how a date ends up a phantom day
old.

## Custom engines

### bully-manga.com — `app/lib/data/sources/bully/`

Not WordPress. A static server-rendered site:

- listing: `/genres/all[/<page>]` — `div.mc-card` tiles (`a.mc-img-wrap`
  href = series `/slug`, `img.mc-img` alt = title, `data-src` = the real
  cover behind a placeholder `src`, `.mc-badge img` = the type icon,
  first `.mc-ep-num` = the latest-chapter hint). 39 pages of real
  content.
- search: `/search?keyword=<q>&page=<n>` — same cards, but the index
  also returns chapter pages (`<slug>-epNNNN`), which are filtered out.
- detail: JSON-LD `ComicSeries` (name/description/image), `a.sh-genre`
  Thai tags, `span.sh-badge-status` ("On Going"), and the full chapter
  list as `a.sh-ep` rows (`data-title` = number, `.sh-ep-label` = title,
  `.sh-ep-date` = relative Thai stamp). The absolute last update is in
  the `อัปเดต` meta pill.
- pages: the chapter page embeds `const IMAGE_MAP = [...]`.

**Open:** the feed order still differs from the site's, because this
engine has no ts-style grid to read. It needs its own grid port — that
would ride a v1.3.1.

### nekopost.net — `app/lib/data/sources/nekopost/`

A JSON API, not HTML. Two live payload shapes matter:

- `POST /api/handler/cinfo` with `{p, c}` → decrypted via the app's own
  `nekopost_crypto.dart`. The decrypted payload has keys
  `[projectId, chapterId, chapterNo, pageItem, pageCount]`.
  **Path moved 2026-10-28**: the site rebuilt onto a SvelteKit frontend
  whose bundle calls `www.nekopost.net/api/handler/cinfo` — the bare
  `/handler/cinfo` answers 404 and every chapter open failed. Crypto
  unchanged (CryptoJS passphrase `AeyTest`, OpenSSL salted format).
- In a page item, **`pageNo` is an int** (not a String) and **`fileName`
  is the real key** (`pageName` does not exist). `width`/`height` ride
  along as extra metadata. The old `as String?` casts threw and the
  reader spun forever — see PLAN_NOTES 2026-10-18. **2026-10-28:**
  `pageName` may now be a FULL image URL (`fs?…/collectManga/…`) — the
  adapter prefers a non-empty `pageName` (mirrors the site's own reader)
  and only prepends the collectManga base to bare names.

Novels use `novelContent` when `pageText` is absent. Listings already
carry stamps, so `recentStamps()` is a no-op here.

### nano-manga.com — Madara config (main feed)

Classic Madara layout (same family as doujin-lc): `.c-tabs-item` rows,
`/manga/page/N/` archive, series under `/manga/<slug>/`, working `?s=`
search (probed 2026-10-28). Added as a `madaraConfigs` entry with
`classicLayout: true` — no dedicated adapter.

Theme is Madara 6.8 (2026-11-01 probes): the detail page ships an EMPTY
`#manga-chapters-holder` and the chapter list arrives via POST
`{seriesUrl}ajax/chapters/` (same `li.wp-manga-chapter` rows; the date
rides in the sibling `.chapter-release-date a` title attribute,
"9 ชั่วโมง ago"). The synopsis is a plain `post-content_item` whose
heading reads "Summary" — NOT `.description-summary`. `detail()`
auto-falls back to the ajax POST when the page has no chapter rows and
the holder is present. Dates: newest ~2 rows carry the relative
`c-new-tag` title attribute ("9 ชั่วโมง ago"), older rows the span text
`17/10/2026` (d/m/Y). The `/manga/` archive tiles themselves list each
series' newest 1-2 chapters with ages (`.chapter` + `.post-on`) —
`parseClassicRows` stamps chapterCountHint + lastUpdatedMs from the
tile, so the feed shows dates without a detail fetch.

### mangary.com / whytoon.com — `app/lib/data/sources/toonary/`

One adapter, per-site configs (`configs.dart`). Both are Next.js
App-Router sites on the "Toonary" platform:

- listing: mangary `/latest?page=N` (cards carry genre chips — the Mix
  tab's yaoi filter reads them); whytoon `/browse/page/N`.
- detail `/content/<slug>`: title/description/cover from the HTML;
  chapters + genres ONLY in the flight payload
  (`self.__next_f.push([1,"…"])` chunks) — first non-empty
  `"episodes":[…]` array = main series, first non-dictionary
  `"genres":[…]` = series tags. `premium:true` episodes are EXCLUDED
  (coin-locked, no bypass).
- reader: mangary `/content/<slug>/episode/<no>`, whytoon
  `/content/<slug>/<no>`; images from the flight `"images":[…]` array
  (whytoon relative → `https://gd.whytoon.com/`).
- search: server-rendered `?q=` on the listing route (probed 2026-11-01;
  /search itself 404s) — mangary `/latest?q=…&page=N`, whytoon
  `/browse(/page/N)?q=…`; same card parser as the feed, yaoi filter
  applies. Genre pages: mangary `/latest/<term>`, whytoon none.
- type: ALWAYS 'manhwa' (platform truth — vertical webtoons only). Do
  not re-introduce a genre-derived type: mangary files Korean webtoons
  under its "Manga - มังงะญี่ปุ่น" category.
- toondee.com runs the same platform but ships NO server-side chapter
  or image data (client-only, RSC-header request empty) — not addable
  without a session API; excluded 2026-10-28.

### oremanga.net — `app/lib/data/sources/oremanga/` (main feed)

Custom WP theme (added 2026-11-03, probed live). The ONLY custom-engine
main-feed site whose tiles carry an explicit type badge (`span.type`
under the thumb → `/genre/manga|manhwa|manhua/`), so feed cards type
themselves without a detail fetch.

- feed: homepage `//page/N/` — several "มาใหม่" sections of
  `.flexbox4-item` tiles (thumb link = series URL, `.title a`, first
  `ul.chapter li` = chapter hint + relative `.date` stamp); union
  deduped by URL. Series URLs keep MIXED CASE (`/series/Momiji-to-Kouyou/`)
  — never lowercase them.
- search: GET `/?s=<q>` → `.flexbox2-item` cards (big cover link with
  `title` attr, `.type <Name>` div, `.genres` chips). Same tile family
  on `/genre/<term>/page/N/` (browseGenre + genres() from homepage
  `/genre/` links).
- detail `/series/<slug>/`: `.series-thumb img` cover, `.series-titlex
  h2` title, `span.type` / `span.status` (class-suffixed English
  values), `.series-genres a`, `.series-synops`; chapters
  `ul.series-chapterlist .flexch-infoz a` — the date span nests INSIDE
  the label span (strip before number parsing), Thai month dates
  ("2 พฤศจิกายน 2026").
- reader: `/<series-slug>/<n>-<series-slug>/` — plain `img` tags inside
  `div.reader-area-main` (host `img.oremanga.net`), server-rendered in
  order.

### madoo-manga.com / 1668manga.com — Madara configs (main feed)

Same ts family as slow/up/dark/fin end to end (added 2026-11-03,
probed live): `/manga/` `.listupd .bsx` archive + `/manga/page/N/`,
`?s=&post_type=wp-manga` search, `h1.entry-title` / `.tsinfo .imptdt` /
`.mgen` / `.eph-num .chapternum|.chapterdate` detail. Plain `madaraConfigs`
entries — no dedicated adapter.

- madoo labels its imptdt rows in ENGLISH ("Status/Type"); 1668
  LOCALIZES them ("สถานะ/ประเภท") — the ts detail parser accepts both.
- 1668's chapter page hides the reader payload in Cloudflare data-URI
  scripts (`<script src="data:text/javascript;base64,…">` containing
  `ts_reader.run(… "images":[…])`); `pages()` decodes every base64
  blob on the page and scans the decoded text too. Images live on
  `img.168toon.com`.
- **`img.168toon.com` hotlink-bans its own origin** (2026-11-04,
  user report: every page of Murim's Debt King chapters 1-3 showed
  "can't load this page" while ch25 worked): the CDN answers 403
  "error code: 1011" to ANY request whose headers include a Referer on
  the legacy `/Manga/…/N.jpg` paths (older chapters); the dated
  `2026/MM/DD/<hash>.webp` paths tolerate one. No-Referer fetches work
  for both, so the 1668manga config sets `noImageReferer` —
  `MadaraSource.imageReferer` returns null and page images are fetched
  referer-less. The cover CDN (`cdn.1668manga.com`) accepts a Referer,
  so covers are unaffected.
- 1668's homepage grid renders `.epxdate` stamps (family B); madoo's
  grid carries no time labels → archive-order feed for it.

### inu-manga.net — Madara config (Search Mix)

Same ts family as madoo/1668 end to end (added 2026-11-04, probed live):
`/manga/` `.listupd .bsx` archive + `/page/N/`, `?s=` search
(`.bsx` results), `h1.entry-title` / `.tsinfo .imptdt` (THAI labels —
สถานะ/ประเภท, already supported) / `.eph-num .chapternum|.chapterdate`
detail, plain inline `ts_reader.run(… "images":[…])` pages on
`img.inu-manga.net`. Plain `madaraConfigs` entry — no dedicated adapter.
Carries a manga+manhwa+manhua mix (homepage tile badges: 42 Manhwa /
38 Manga / 7 Manhua → pills `manhwa, manga, manhua`); no `/genre/`
links on the archive, so the genre picker is empty for it (detail tags
still parse where `.mgen` renders). MIX scope per user request.

### niceoppai.net — `app/lib/data/sources/niceoppai/` (MIX scope)

NOPOrange theme (added 2026-11-03, probed live). Mix scope because the
category cloud includes Adult/yaoi — the yaoi filter applies to its
searches like every Mix source (tiles carry no genres, so the filter
only matches after detail data lands).

- feed: `/manga_list/all/any/last-updated/<page>/` — `.fcard.panel`
  tiles; the newest `.fcard__ch` row's `.ago` carries an ABSOLUTE
  unix-seconds stamp in `data-ago` (parse × 1000). Cover paths contain
  literal spaces → encode as %20.
- search: POST `/manga_list/search/` with
  `cmd_wpm_wgt_mng_sch_sbm=Search` + `txt_wpm_wgt_mng_sch_nme=<q>` —
  the theme reads `$_POST` only (GET variants render "Search result of
  ''"). Cloudflare now challenges POSTs from EVERY non-browser client —
  curl, Dart, and even a real Chrome `fetch()`/form navigation get
  "Just a moment…" (re-probed 2026-11-04 after the user reported the
  search dead) — so the POST rides the full ladder: direct → cronet
  (Chrome TLS) → the WebView tier, where a challenged relay POST falls
  back to a real WebView form post (`WebviewGate.postForm`, the only
  client shape the zone trusts). Single page.
- detail `/<Title-Slug>/`: `h1`, itemprop cover img, `.chip--genre`
  genres (exact Manhwa/Manhua/Manga chip = type), `p.series__syn`,
  `.series__facts .fact` rows (สถานะ/ตอนทั้งหมด), `.chrow` chapter rows
  (`data-ch` = number, `.chrow__d` "Sep 20, 2026"). NOTE: the page
  server-renders only the newest ~70 rows; a longer series' older
  chapters arrive via the site's own JS and are NOT fetched (v1
  limitation).
- reader `/<Title-Slug>/<n>/`: `#image-container img[src]` on
  `image7.niceoppai.net`, server-rendered.
- genres: `/manga_list/` sidebar `a[href*="/manga_list/category/"]`;
  browseGenre `/manga_list/category/<Term>/` (single page).

### manghaha.com — `app/lib/data/sources/manghaha/` (Doujin 18+)

"obito" bootstrap theme (added 2026-11-03, probed live). Manhwa-heavy
adult site.

- feed: homepage grid `/?page=N` — `.latest-item-contain` tiles (thumb
  link, `.title a`, newest `.last .d-flex` row = chapter label + Thai
  relative `<small>` stamp). The SAME tile family serves
  `/search/?s=<q>` and `/tag/<name>/` pages — one parser for all three.
- detail `/<slug>/`: `h1.manga-title` reads "อ่านมังงะ <title> แปลไทย"
  (strip prefix/suffix), `img.manga-thumb` cover,
  `.manga-content-heading/.manga-content-value` label rows (สถานะ),
  `.description` (text OUTSIDE the embedded `.tag-list`; "No Story" =
  empty), chapters `.ep-list .ep-item` (`.ep-heading` label,
  `.ep-time` relative stamp).
- reader `/<series>/<chapter>/`: `.manga-image-contain img.page-img`,
  server-rendered, in order.
- genres: homepage `/tag/` links; browseGenre `/tag/<name>/` (single
  page).

### hentaithai.net — `app/lib/data/sources/hentaithai/`

A forum-style community site, not WordPress:

- listing: the homepage is a LANDING page (30 `a.number-even`/`odd`
  cards + a "see all" button). The real feed is the `/page-<N>` chain
  that button points at (2026-10-23): `/page-1814` = newest 24 threads,
  `/page-1813` the next-older 24 — descending page numbers. `latest()`
  learns N from the homepage link once per session and walks down;
  feed cards are `a.col-6.col-md-3` (title attr, style-block cover) —
  a different family from the landing grid. The `/prev-<id>` /
  `/next-<id>` links are per-thread JS navigation that 404 on direct
  GET, not pagination.
- search: not supported (the site uses a Google CSE form) — `search()`
  returns an EMPTY result, never a throw (2026-11-04: a throw rendered
  the source's search row with a red "failed" dot on every Doujin-page
  search, which read as a bug).
- the thread page IS detail + reader in one: every page image is inline
  (`img[src*="hentaithai.net/"]` on the s1 CDN). One-shot → one chapter.
- tag browse (`/tag-<id>`) shares the col-6 card family but exposes no
  server-side pagination — page 1 only.

### miku-doujin.com — `app/lib/data/sources/miku/`

WordPress with a fully custom "inz" theme:

- listing: homepage + `?page=N` — cards are `a.inz-a`, the title in
  `.inz-title`/`.inz-title-sm`, the cover in `img.inz-img-thumbnail`
  (lazy `data-src`). **Pagination param is `?page=` (2026-10-28):** the
  theme's own "older" link is `?page=2`; the old `?paged=N` still
  answers 200 but renders a COPY of page 1, which stalled the feed
  after the first screen (dedup ate the duplicates).
- search: not supported — `?s=` is ignored and renders the homepage
  verbatim (re-probed 2026-11-04), and `wp-json/wp/v2/search` is 404
  (REST disabled). `search()` returns an EMPTY result, never a throw
  (2026-11-04: a throw rendered the source's search row with a red
  "failed" dot on every Doujin-page search).
- genres: `/genre/<term>/` paged the same `?page=N` way (2026-10-28 —
  was `/category/`; old paths answer 200 EMPTY). Genre terms in
  `pathSegments` arrive already percent-decoded — a second
  `Uri.decodeComponent` on decoded Thai throws.
- the series page IS the reader (one-shot doujin): all pages are
  `#manga-content img.lazy[data-src]` inline, so the detail reports
  exactly one chapter whose URL is the series URL. Tags come from
  `a[href*="/genre/"]`.

## Cloudflare blocks → the WAF ladder (2026-10-23)

Cloudflare blocks sites in two ways, and the app now answers both
(`app/lib/core/net/waf_gate.dart`, per-host ladder; full write-up in
PLAN_NOTES 2026-10-23):

- **TLS fingerprint block** (doujin-lc, miku-doujin): the site serves
  200 to Chrome and 403 to dart:io's handshake. The **cronet tier**
  (embedded Chromium network stack) handshakes like Chrome and passes —
  verified on-device 2026-10-23 (doujin-lc OK 2699 ms, miku OK 1166 ms).
  Both re-enabled everywhere in db v9 (2026-10-23): with the ladder in
  place there is no reason to keep them off.
- **Interactive challenge** (dark-manga, whole site since 2026-10-23):
  "Just a moment..." JS challenge on every request. The **webview tier**
  loads the site in a headless WebView, the managed challenge
  auto-solves (verified: dark-manga OK 1008 ms, no user interaction),
  and follow-up byte traffic rides cronet with the relayed clearance
  cookies. If a site ever demands a human tap, a lock icon appears on
  the source row in Settings → one tap opens the visible verification
  page; after that the headless WebView takes over again.

`up-manga`'s `?s=` search 403 is a CF challenge too — since v1.4.0 it
escalates the host up the ladder like any other page, so search is on
(`searchSupported: true` since 2026-10-24).

## When a site breaks

1. Probe it: `dart run tool/verify_sources.dart --source <id>` (ts sites
   and nekopost), or fetch the page and read the markup.
2. Compare against the table above and the adapter's doc comment —
   both record the expected selectors.
3. Fix the adapter, then update this file + PLAN_NOTES in the same
   batch (the comment in the adapter file is the third copy — keep all
   three in sync).

# Sources — per-site reference

One row per seeded source: which adapter talks to it, what its markup
looks like, and what breaks on it. Everything here was probed against the
live sites; when a site changes, update this file **and**
[PLAN_NOTES.md](./PLAN_NOTES.md) in the same batch.

11 sources are seeded and since db v9 (2026-10-23) **all 11 ship
enabled** — the WAF ladder made the last two Cloudflare-blocked ones
reachable. The Doujin (18+) page holds 4 of them; the main feed holds
the other 7. Adult sources never appear in the main feed and vice versa
(`adultSourceIds` in `app/lib/data/sources/source_registry.dart`).

## At a glance

| Site | Scope | Adapter | Live | Grid feed | Search | Notes |
|---|---|---|---|---|---|---|
| go-manga.com | main | Madara (ts) | ✅ | ✅ family A | ✅ | |
| slow-manga.net | main | Madara (ts) | ✅ | ✅ family B | ✅ | grid is chapter-linked |
| up-manga.com | main | Madara (ts) | ✅ | ✅ family A | ⚠️ Cloudflare | search endpoint 403s |
| dark-manga.com | main | Madara (ts) | ✅ | ✅ family A | 🚫 Cloudflare | 2026-10-23: whole site behind the challenge — the WAF ladder's webview tier auto-solves it (verified on-device) |
| fin-manga.com | main | Madara (ts) | ✅ | ✅ family A | ✅ | archive order drifts A–Z; 2026-10-23: WPFC lazy covers (data-wpfc-original-src) |
| bully-manga.com | main | custom static | ✅ | ❌ **open** | ✅ | needs its own grid port |
| nekopost.net | main | JSON API | ✅ | n/a (API) | ✅ | the only novel carrier |
| ntr-manga.net | Doujin | Madara (ts) | ✅ | ❌ custom grid | ✅ | its own grid markup — not parsed |
| hentaithai.net | Doujin | custom one-shot | ✅ | n/a | ❌ | one-shot; thread page = reader |
| doujin-lc.net | Doujin | Madara (classic) | ✅ | n/a | ✅ | cronet lane unlocks it (2026-10-23); enabled since db v9 |
| miku-doujin.com | Doujin | custom one-shot | ✅ | n/a | ❌ | cronet lane unlocks it (2026-10-23); enabled since db v9 |

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

### Per-site quirks

- **slow-manga** — series URLs live under `/manga/{slug}/`; the grid is
  chapter-linked, so stamps are borrowed by title.
- **go-manga** — series URLs are `/<slug>/` (no prefix).
- **up-manga / dark-manga** — `?s=` (search) sits behind a Cloudflare
  challenge: the app gets a 403, browsing still works. `searchSupported`
  is `false` in the config.
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

- `POST /handler/cinfo` with `{p, c}` → decrypted via the app's own
  `nekopost_crypto.dart`. The decrypted payload has keys
  `[projectId, chapterId, chapterNo, pageItem, pageCount]`.
- In a page item, **`pageNo` is an int** (not a String) and **`fileName`
  is the real key** (`pageName` does not exist). `width`/`height` ride
  along as extra metadata. The old `as String?` casts threw and the
  reader spun forever — see PLAN_NOTES 2026-10-18.

Novels use `novelContent` when `pageText` is absent. Listings already
carry stamps, so `recentStamps()` is a no-op here.

### hentaithai.net — `app/lib/data/sources/hentaithai/`

A forum-style community site, not WordPress:

- listing: the homepage grid only (`a.number-even` / `a.number-odd` cards;
  the full title rides in the `title` attribute, the thread link is
  `/t<id>`). `/page/N` 404s, so `latest()` is a single page and paging
  honestly returns empty.
- search: not supported (the site uses a Google CSE form).
- the thread page IS detail + reader in one: every page image is inline
  (`img[src*="hentaithai.net/"]` on the s1 CDN). One-shot → one chapter.

### miku-doujin.com — `app/lib/data/sources/miku/`

WordPress with a fully custom "inz" theme:

- listing: homepage + `?paged=N` — cards are `a.inz-a`, the title in
  `.inz-title`/`.inz-title-sm`, the cover in `img.inz-img-thumbnail`
  (lazy `data-src`).
- search: not supported — `?s=` is ignored and renders the homepage.
- the series page IS the reader (one-shot doujin): all pages are
  `#manga-content img.lazy[data-src]` inline, so the detail reports
  exactly one chapter whose URL is the series URL. Tags come from
  `a[href*="/category/"]`.

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

`up-manga`'s `?s=` search 403 is a CF challenge too, but search there
stays off (`searchSupported: false`) — the ladder is for whole-site
reachability, not per-endpoint toggling.

## When a site breaks

1. Probe it: `dart run tool/verify_sources.dart --source <id>` (ts sites
   and nekopost), or fetch the page and read the markup.
2. Compare against the table above and the adapter's doc comment —
   both record the expected selectors.
3. Fix the adapter, then update this file + PLAN_NOTES in the same
   batch (the comment in the adapter file is the third copy — keep all
   three in sync).

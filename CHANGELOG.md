# Changelog

One line per completed build phase (Plan/15). Format: `YYYY-MM-DD — Phase N: what`.

- 2026-10-17 — Planning complete: Docs + Docs/Plan (16 documents), live site
  probes (4× Madara + nekopost), WebP compression benchmark (−58% measured).
- 2026-10-17 — Requirements update: app named **Star Codex**, GitHub repo
  linked (DotJumpDot/Star_Codex), History tab + Offline (truthful downloads)
  tab added, dual Thai/original titles, Manhwa/Manga/Manhua/Novel origin
  grouping, Introduction/genre/category merged from all sites, per-site
  browse filters, per-phase checklist commits + push policy.
- 2026-10-17 — Phase 0: toolchain installed — Flutter 3.47.7 stable at
  C:\tools\flutter (user PATH), Android SDK platform 36 + platform-tools,
  licenses accepted, `flutter doctor` fully green. Headless emulator AVD
  `StarCodex` (Pixel 7 / API 36) for automated UI verification.
- 2026-10-17 — Phase 1: scaffold — Flutter project `app/` (applicationId
  com.jamej.starcodex, minSdk 23, INTERNET permission, label "Star Codex"),
  all planned deps (see PLAN_NOTES for version pins), folder tree, Thai-first
  i18n helper + th/en bundles with key-parity test, M3 dark theme (Sarabun),
  5-tab shell (Browse/Library/History/Offline/Settings) with placeholder
  screens. `flutter analyze` clean, `flutter test` green (4 tests), shell
  verified on emulator.
- 2026-10-17 — Phase 2: database + settings — full v1 SQLite schema (17
  tables, FK cascade on, append-only migrations), 5-source seed + 11 default
  settings rows, 6 DAO files, Riverpod settings/language/theme persistence,
  main() opens DB before runApp. `flutter test` green (13 tests: schema,
  seed, unique-index, DAO round-trip, cascade delete), analyze clean,
  on-device launch verified (manga_reader.db created, no crashes).
- 2026-10-17 — Phase 3: network + sources — safe_http (scheme/host
  validation, per-hop redirect re-validation, 50 MB cap, retries w/
  Retry-After), per-host rate limiter (2/700 ms strict, 4/200 ms image
  CDNs), Cloudflare detection, Source interface + ts-theme adapter for all
  4 sites (theme drift discovered & recorded in Plan/05), chapter-number +
  Thai-date parsing, tool/verify_sources.dart — live-verified latest/search/
  detail/chapters/images on all 4 sites. 29 tests green, analyze clean,
  Dio only in safe_http (grep).
- 2026-10-17 — Phase 4: storage engine — BlobStore (content-addressed
  sha256 store, 2-char shards, tmp+rename atomic writes, integrity pass),
  ImagePipeline (magic-byte validation, dedup, WebP q80 via
  flutter_image_compress, GIF passthrough, maxWidth hook per S3),
  CacheJanitor (LRU 5 GiB default, never evicts pinned, pin recompute from
  done downloads, 100 GiB quota guard, 10 s-after-start + every-50-writes
  schedule). 36 tests green (dedup, LRU, pins, quota, integrity), analyze
  clean.

- 2026-10-17 — Phase 5: title merge + Browse UI — title_norm (bracket/noise
  stripping, Thai kept), Jaro-Winkler + Plan/07 matcher (exact/alt/fuzzy
  merge, 0.88–0.95 similar hint), BrowseRepo grouping (search + latest +
  genre, per-source failures never blank results), add-to-library with
  §3.2 cross-source probe, Browse screen (submit-only search + history,
  per-site chips with error dots, long-press genre browser via
  /manga/?genres=, filter sheet defaults OFF per L1, merged cards with
  source badges, covers via the pipeline, infinite scroll). 87 tests
  green, analyze clean. On-device: multi-source merges live (2- and
  3-source cards), filters + genre browsing verified via adb; fixed
  genre-href ArgumentError, unbounded DNS lookup, persisted language not
  applied at startup.
- 2026-10-17 — Phase 6: Series detail (Plan/09 + per-chapter chips
  addendum) — SeriesRepo (stale-tab 12h refresh, incremental L7 metadata
  union, §3.2 re-probe, shared upsertFromDetail now powering add-to-
  library AND browse-card open), detail screen (L5 dual titles, type/
  origin/status chips, source badges, collapsible description with source
  caption, tag chips → browse pre-filter), source tabs (07 §4 primary,
  green "N ตอน" banner on bigger tabs), chapter list (old→new default
  persisted per series, search-in-chapters, relative Thai dates,
  read/unread + downloaded marks), per-chapter colored source dots +
  "อ่านจากเว็บไหน" picker, long-press sheet (mark read/unread instant,
  download queue row), continue button (last read → first unread → ch 1),
  reader router + mode stubs. 105 tests green, analyze clean.
- 2026-10-17 — Phase 7: Webtoon reader (Plan/10) — ReaderRepo (page lists
  from DB, source fetch + persist, whole-chapter 07 §5 fallback chain,
  shared 2-slot TaskQueue), PageSlot (cached→instant, known-dims exact
  height / estimate 1.9×, retry slot), ReaderScreen (immersive + wakelock,
  scroll progress tracking via slot offsets at the 40% line, 500 ms
  throttled read_progress writes, completion at end-viewport, 3 s
  auto-next countdown with cancel, middle-60% chrome toggle, draggable
  progress bar, chapter picker sheet with per-number source dots, reader
  settings sheet: prefetch/keep-awake/auto-next), per-page source fallback
  with "จาก X" toast, adjacent-chapter resolution (same-source preferred).
  wakelock_plus added (rule 5 table). 116 tests green, analyze clean.
- 2026-10-17 — Phase 8 (part 1): Paged + Novel readers (Plan/11) —
  PagedReaderScreen (horizontal PageView, double-tap zoom/pan via
  ExtendedImage gesture with tap-gating on scale, left/right/middle tap
  zones with RTL swap, overscroll→next chapter), NovelReaderScreen
  (Sarabun paragraphs from chapter_text with indent, adjustable font
  14–30 / leading 1.4–2.2 / light-sepia-dark themes, scroll-fraction
  progress at ≥97% completes, end button + 1.5s dwell auto-next), shared
  reader settings sheet (per-series mode override persisted via
  reader_mode_<id>, RTL switch, novel extras), resolveReaderMode
  (override > type default), ReaderRepo.resolvePage shared page fallback
  + loadNovelText (chapter_text → source fetch → persist).
- 2026-10-17 — Phase 8 (part 2): Nekopost adapter (Plan/06) — live-probed
  all endpoints (detail2 serves novels too; chapter payloads are
  AES-256-CBC "Salted__" with passphrase AeyTest via /handler/cinfo),
  pure-Dart decryptor (EVP_BytesToKey + AES, no new deps), adapter with
  opaque project/chapter URLs, manga+novel latest merge, search surfacing
  novels (projectType f/n), HTML→paragraphs novel text with inline-media
  placeholder resolution, safe_http.postJson through the same
  validation/retry door, source registry now dispatches by adapter
  column. Fixture tests run the whole adapter offline; live
  verify_sources --source nekopost ALL OK (26 latest, Thai detail,
  26 decrypted pages, 5.9k-char novel chapter).
- 2026-10-17 — Phase 9: Library tab (category chips + smart tabs, Thai A–Z sort, quick filters, grid/list, multi-select with merge/split/delete) + History tab (day-grouped timeline from reading_history, tap-to-resume, clear-all) with a single reader-completion write path.
- 2026-10-17 — Phase 10: download sheet (unread/next10/all/range + estimates + quota), foreground queue worker (pause/resume/retry/backoff, Wi-Fi-only via connectivity_plus), truthful Offline tab (ready list = files on disk, queue section, storage header), updates checker + Library bell feed with mark-seen badge.
- 2026-10-17 — Phase 11: full Settings screen (language/theme, reader defaults, novel typography, storage with live readout + clear-unpinned, source switches/connection-test/reorder — all hot-applying), launcher icon + label, release APK builds clean. **v1.**
- 2026-10-18 — On-device QA session + review pass: 4 QA fixes (riverpod
  DetailKey scope crash browse→detail, WebP pipeline no-op on 0-sized
  targets, webtoon auto-next unreachable end-window + parked-at-end
  poller, paged per-slot gesture keys), then review-pass fixes — tags FK
  (Android insertIgnore returns −1), nekopost live int pageNo/fileName
  payload casts, paged-reader fail-path error panel (Bug #7) + regression
  test. 167 tests green.
- 2026-10-18 - On-device QA completion: Bug #7 confirmed live (paged
  reader error panel + retry, both directions), library tab staleness
  after detail add/remove found + fixed (onLibraryChanged hook, test
  168), release journey + RAM 109 MB (indicative), low-impact emulator
  boot tooling. All phase 4-11 DoDs verified on emulator; verdicts in
  Docs/QA-ON-DEVICE.md.
- 2026-10-18 - v1.0.0 released: proper release-signing keystore baseline
  (cert CN=Star Codex, stored outside repo) + first GitHub Release APK.
- 2026-10-18 — v1.1.0 UX overhaul (user feedback batch): left navigation
  drawer replaces the bottom bar (hamburger on every tab header, edge-swipe
  opt-in setting, default off); global search overlay slides from the top
  right on every tab; 20 app themes (Monokai / Monokai Night / Monokai Dark
  Soda from CometStream + Nord/Dracula/Tokyo Night/Catppuccin/Gruvbox/Rosé
  Pine/Solarized/Sakura/…), 12 UI fonts (Prompt from Maki Launcher + Thai
  & Latin picks); detail page compacted (smaller hero, tags/status/sites in
  one chip row, collapsible เรื่องย่อ, heart=add-to-library, site switcher
  replaces chapter tabs, newest-first chapter default); download sheet gets
  a site picker + per-chapter upload stamps; browse cards redesigned (big
  cover + overlay chips + last-update stamps, DB-enriched status/tag
  filters); readers: all controls move to a right-hand drawer, 3 s
  auto-next countdown replaced by drag-past-the-end pull-to-continue with
  resistance + progress pill; novel background opacity setting; history now
  records the moment a chapter opens (not only on completion); Madara
  covers prefer data-src over lazy placeholders (fixes blank/mismatched
  covers); browse detail opens link ALL merged listing members; settings
  split Language/Appearance/Navigation/Library + numeric GB quota inputs
  (defaults 5 GB cache / 20 GB downloads, db v2 migration); About: date
  localized, plan note removed, GitHub button added; Library toolbar
  collapsible search + denser cards. 168 tests green, on-device QA pass.
- 2026-10-18 — Sources: fin-manga.com (same ts theme → Madara config,
  search live) + bully-manga.com (custom static engine → new dedicated
  adapter: /genres/all listings, /search?keyword=, JSON-LD detail,
  a.sh-ep chapter rows with relative-Thai stamps, IMAGE_MAP page arrays);
  db v3 seeds/migrates 7 sources. Fixture tests from live pages; 175 green.
- 2026-10-18 — Detail compaction round 2: เรื่องย่อ toggle moved into the
  hero under the genre chips (2-line truncated snippet, expands with a
  slide on tap); ค้นหาตอน + sort arrow now occupy the row it vacated, so
  the chapter list starts one full row higher.
- 2026-10-18 — Cover robustness: slow-manga AVIF uploads ("Poison Master
  of Sacheon Tang Clan") and 404 WP thumbnails ("I'll Resign…") can never
  render — parsers now skip .avif, CoverThumb walks a fallback chain
  (un-suffixed full-size original, then sibling sites' covers for merged
  cards/hero); Thai status string กำลังเข้า → กำลังแปล. 183 tests green.
- 2026-10-21 — Release: v1.2.7 — version 1.2.7+11. Ships everything since
  v1.2.6 for real-phone testing: the paged reader (หน้าต่อหน้า) swipe
  decode cap (min(source, 2× screen) — full-res decodes raced every
  swipe), the back-from-reader "warpy" layout shift fix (system bars
  restore at pop start, not after the transition), the series-detail
  skeleton loading state, and the first-read scroll-freeze fixes (page
  hashing off the UI isolate, band slicing off Android's main thread).
  223 tests green.
- 2026-10-21 — Release: v1.2.10 — version 1.2.10+14. Ships the gesture
  rework: the webtoon crop is a real lock (no drag — sliders/auto-detect
  only), webtoon pinch is a website-style transient view zoom anchored
  to your fingers (no shaking, one-finger pan while zoomed, pinch back
  to reset), and the paged reader never slides while zoomed or during a
  two-finger pinch. 233 tests green.
- 2026-10-21 — Crop lock + website-style pinch zoom (user feedback
  round on v1.2.9): (1) the crop is now a REAL lock — the horizontal
  drag/pan gestures were removed (they let the window wander into the
  black bars during reading); selection = drawer sliders + auto-detect.
  Emulator-verified: a hard 650px horizontal swipe changed ZERO pixels
  of the cropped page. (2) Webtoon pinch zoom is completely reworked —
  the old pinch re-laid-out the whole strip (vertical shaking, anchored
  top-left); it is now a transient website-style VIEW zoom: a paint
  transform over the list, anchored to your fingers (content under the
  pinch start focal stays under it), clamped so the screen is always
  covered, one finger pans while zoomed, pinch back in to reset. No
  persistence — the per-chapter crop keeps its own saved zoom.
  (3) Paged reader (หน้าต่อหน้า): the page no longer slides while the
  image is zoomed (PageView freezes; the zoomed image pans in its
  slot), and a two-finger hold never flips the page. ViewZoom math unit
  tested (focal anchoring, clamping, reset); 233 tests green.
- 2026-10-21 — Release: v1.2.9 — version 1.2.9+13. Fixes v1.2.8's
  broken screen crop (all-black screen whenever the crop applied):
  the crop window's OverflowBox sized itself infinite under the
  scroll list's unbounded constraints and painted nothing — now uses
  OverflowBoxFit.deferToChild. Emulator-verified: crop, pinch zoom,
  drawer zoom, and drag-to-select all render correctly on the
  letterboxed dark-manga ch.96. 228 tests green.
- 2026-10-21 — Release: v1.2.8 — version 1.2.8+12. Ships the webtoon
  per-chapter screen crop: pinch to zoom, drag horizontally (one or two
  fingers) to select where to crop, locked to vertical scrolling while
  reading; auto-detect one-tap for letterboxed chapters; drawer sliders
  for fine control; persisted per chapter (normal chapters unaffected).
  228 tests green.
- 2026-10-21 — Manual crop selection (user feedback: auto-detect alone
  was "weird" — they want to pick the crop themselves): with a crop
  active, a clearly-horizontal ONE-finger drag slides the window left/
  right (the vertical ListView rejects exactly those gestures, so
  scrolling is untouched), and two-finger focal drift pans the window
  alongside the pinch zoom — content follows the fingers. Intent guard:
  the one-finger path only engages past 18px with 1.5× horizontal
  dominance. Drawer hint rewritten to teach the gestures; auto-detect
  stays as a one-tap convenience. Persist still lands once per gesture.
  228 tests green.
- 2026-10-21 — Webtoon screen crop + pinch zoom (user request, the
  letterboxed dark-manga ch.96 case): the webtoon reader now supports a
  per-CHAPTER crop — slots render zoom× wider than the screen and the
  reader shows one fixed horizontal window, so horizontal movement is
  inherently locked (scroll up/down only). Two-finger pinch zooms the
  strip (raw-pointer Listener — never enters the gesture arena, so
  single-finger scrolling is untouched; scrolling freezes for the pinch
  duration). The right drawer gains a "ครอปหน้าจอ (ตอนนี้เท่านั้น)"
  section: zoom + horizontal-position sliders, reset, and AUTO-DETECT —
  a column-luminance profile of the first page finds the artwork window
  between the black bars (measured: bar columns ≤5 luminance, artwork
  ≥138, threshold 40 ignores watermarks) and snaps the crop to it
  (≈1.7× centered for the sashimi-knife pages). Persisted per chapter
  via reader_crop_ch<id> — normal chapters stay full-width. Zoom
  changes rescale slot heights and re-anchor the scroll offset so the
  artwork under you stays put. 228 tests green.
- 2026-10-21 — v1.2.7 real-phone verdict: scrolling is smooth (webtoon
  first-read included) — the reading-smoothness line of work is closed;
  the deferred blur-up/two-stage decode lever stays documented in
  PLAN_NOTES but is not needed.
- 2026-10-21 — Docs refresh after v1.2.7: AGENTS.md (v1.2.7, migrations
  v2–v8 pointer incl. reader/UI-thread rules), HANDOFF.md (status block,
  release recipe now matches practice — gh release create makes the tag),
  README.md (v1.2.7 links/status, band-slicing + skeleton + threading
  features, 223 tests), ARCHITECTURE.md + Docs/README.md (schema v8,
  pipeline threading notes).
- 2026-10-21 — First-read scroll freezes fixed (user report: "first
  time reading a new chapter, scrolling stutters; fully loaded pages
  scroll smooth"): the load pipeline was stealing UI-thread time while
  pages resolved. Two causes, both off the hot threads now — (1) every
  downloaded page was SHA-256-hashed in pure Dart on the main isolate
  (tens of ms per multi-MB strip, several in flight with prefetch);
  buffers ≥256 KB now hash in a background isolate (band slices
  included); (2) the native band slicer ran decode+JPEG-compress of
  giant strips on Android's platform MAIN thread inside the
  MethodChannel handler (hundreds of ms hard freeze); it now runs on a
  worker thread and posts the reply back on the main looper. WebP
  compression was already on the plugin's native 8-thread pool. 223
  tests green.
- 2026-10-21 — Detail skeleton + back-navigation warp fix (user reports):
  the series detail page shows a shape-mirroring skeleton (hero row, action
  row, search row, chapter rows — same surfaceContainerHighest convention
  as the browse skeleton) instead of a bare spinner while loading; and the
  "warpy" pull-and-retract seen when returning from the reader was the
  system bars restoring in dispose() — AFTER the pop transition, so the
  revealed page's top inset shifted its whole layout. Both readers now
  restore at the exit transition's start (AnimationStatus.reverse hook;
  dispose only covers un-popped replacement exits), and the platform call
  is sent exactly once per exit. 222 tests green.
- 2026-10-21 — Release: v1.2.6 — version 1.2.6+10. Ships everything
  since v1.2.5: the merged เรียงลำดับ filter section (ยอดนิยม as a sort
  chip, server order shown through), fling-preserving scroll anchors
  (forcePixels instead of jumpTo), decode width capped at the source
  image width, exact band heights at build time, and per-frame batched
  height fix-ups. Cut for real-phone smoothness testing — the emulator
  shares the host's CPU/GPU and exaggerates jank. 220 tests green.
- 2026-10-21 — Paged reader (หน้าต่อหน้า) swipe lag (user report after
  v1.2.6's webtoon fixes landed: "manga mode on side slide a little
  laggy"): its slots never set cacheWidth, so every page decoded at
  FULL source resolution while PageView keeps ±1 neighbors built —
  three big decodes racing the swipe. Decode is now capped at 2×
  screen width (portrait pages are width-limited under BoxFit.contain
  and typically ≤1080 wide sources anyway; wide double-spreads are
  height-limited and zoomed, hence the 2× headroom) and never above
  the source's own width. Band-slice stacks in the paged reader get
  the same cap. 220 tests green.
- 2026-10-21 — Two more free webtoon-scroll wins (user: "still a bit
  laggy" on the emulator): (1) band slices of oversized pages now
  reserve their EXACT height from the stored dims — each band used to
  size itself only after decoding, so tall-strip chapters relayouted
  the whole stack below per band, repeatedly, mid-scroll; (2) height
  fix-ups are batched into one relayout + one anchor shift per frame —
  a first-read fling resolving several pages in the same frame used to
  trigger back-to-back full ListView relayouts. Decode-ahead via
  precacheImage was evaluated and REJECTED: ExtendedImage routes
  cacheWidth through its own ExtendedResizeImageProvider key class, so
  a framework-provider precache would double-decode instead of sharing
  the entry. 220 tests green.
- 2026-10-21 — Filter-sheet merge + webtoon fling smoothness (user
  round). The separate ลำดับฟีด section is GONE — ยอดนิยม now lives in
  the เรียงลำดับ chips (one ordering section; picking it re-fetches
  with the servers' popularity param and shows that order through with
  no client re-sort; persisted). Reader fling jank on manhwa chapters:
  height-correction anchors used jumpTo, which KILLS the ballistic
  fling — every late correction mid-scroll stopped the scroll dead;
  anchors now shift pixels via forcePixels and the fling continues.
  Also: decode cacheWidth is capped at the SOURCE image width (800px
  strips were being upscaled ~1.7× at decode for zero sharpness).
  220 tests green.
- 2026-10-21 — Release: v1.2.5 — version 1.2.5+9. Ships everything
  since v1.2.4: the black-void chapter fix (oversized webtoon strips
  now slice into GPU-safe bands — "A Villain's Will to Survive"
  ch.67/68), covers loading instantly from disk on every app start
  (blob_urls index, db v7), the ล่าสุด/ยอดนิยม feed ordering in the
  filter sheet, the offline browse fallback with recovery, hentaithai
  card dates, the slider-jump progress fix, and the offline-fallback
  race fix. 219 tests green.
- 2026-10-21 — Offline-fallback race fix (caught during on-device QA):
  the browse screen fires TWO overlapping feed fetches on mount, and the
  superseded one's failed fallback attempt fell through to a stale
  empty-state emission that clobbered the winner's offline catalog. The
  non-fallback emission now re-checks the fetch sequence after the
  fallback attempt.
- 2026-10-21 — Feature batch (user picks) + black-void chapter fix.
  READER BUG (user report: "A Villain's Will to Survive" slow-manga
  ch.67/68 blank dark, ch.69 fine): those pages are 800×25049 strips —
  beyond Android's max GPU texture size, so every decode rendered as a
  black void (ch.69's 14373px squeaked under the limit). New native
  band slicer (BitmapRegionDecoder via a star_codex/image_slice channel
  in MainActivity, no new dependency) cuts oversized pages into
  4096-px-tall JPEG bands; they persist in page_bands (db v8) keyed by
  the parent blob hash — sliced once, re-served from cache — and both
  the webtoon and paged readers render the bands stacked. SLIDER-JUMP:
  every chapter navigation now awaits its progress write first (the
  webtoon reader swapped routes before the completed row landed, so the
  chapter reopened from the top). POPULAR FEED: ล่าสุด/ยอดนิยม toggle on
  the latest feed (server-side order=popular on the madara family,
  persisted setting; the ล่าสุด/ยอดนิยม pair lives in the FILTER SHEET's
  ลำดับฟีด section, not as always-visible chips — user request
  2026-10-21; search ignores it — sites reject ordering there).
  HENTAITHAI DATES: the site exposes no <time> stamps anywhere; the
  upload date is embedded in the CDN image path (/thai/2026/2026-10-10/)
  and now lands on listing cards and the chapter stamp. OFFLINE
  BROWSE: when no source answers (airplane mode), the feed shows the
  visited-series catalog from the DB with an ออฟไลน์ banner instead of
  a blank page; recovery clears it. Per-series reader mode was verified
  ALREADY shipped (drawer writes reader_mode_<seriesId>). Batch
  download UI already shipped (download sheet: unread/next-10/all/
  range); OS-level background downloading (foreground service) is
  deferred pending on-device testing of a new dependency. 219 tests
  green.
- 2026-10-20 — Covers load from disk on warm starts (user report:
  "title pictures reload every time I open the app"). Root cause:
  fetchAndStore downloads a URL BEFORE its content-hash dedup can hit —
  reader pages are unaffected (their URL tables answer first), but
  covers had only a session memo, so every app start re-downloaded
  every cover just to discover the blob already existed. db v7 adds a
  blob_urls index (url → hash, dims, fetched_at); the pipeline's new
  fetchAndStoreIndexed answers from it with zero network, touches LRU,
  and self-heals when a blob was size-evicted (lookup misses →
  re-fetch → row updated). CoverCache and the detail-path series cover
  both use it; reader pages keep the plain path. orphanHashes (dead
  code, but kept consistent) now also preserves blob_urls-referenced
  blobs. 215 tests green.
- 2026-10-20 — Release: v1.2.4 — version 1.2.4+8. Ships everything since
  v1.2.3: webtoon scroll smoothness (500 MiB decoded-page cache, instant
  rebuilds both directions, pre-frame height anchoring, adaptive aspect
  estimates) and the fast parallel search-date backfill (all results
  dated, not just the first 30–40). 213 tests green.
- 2026-10-20 — Post-reader-smoothness review pass (big model): re-read
  the whole batch (reader memory cache, pre-frame anchor, adaptive
  aspect, parallel backfill). One real bug fixed — the observed-aspect
  running average double-counted pages (slot rebuilds re-fire
  onDimensions off the memoized resolve, so a page scrolled past N
  times weighed N×); now deduped per page index. Verified safe: the
  worker pool's next/budget counters are synchronous (no interleaving),
  initialData renders correctly for already-complete futures, jumpTo
  semantics during drags are unchanged from the old post-frame path.
  213 tests green.
- 2026-10-20 — Webtoon scroll smoothness + fast search dates (user
  reports: jerky shake while scrolling down — worst on fin-manga "I
  Will Protect My Tyrant Dad!" ch.1; scrolling UP re-loaded
  already-seen pages with a spinner; only the first 30–40 search
  results ever got dates). Reader: image cache raised 100→300 MiB (the
  default held only ~10 decoded webtoon pages, so scroll-up evicted and
  re-decoded them), the screen memoizes resolved pages per chapter and
  hands them to slots as initialData (a rebuilt slot renders its image
  on the first frame — no spinner), height corrections that shift
  content above the viewport now jump the offset BEFORE the relayout
  frame (no intermediate shifted frame while flinging), and
  unknown-height slots estimate from the chapter's observed average
  aspect instead of the flat 1.9× (fin-manga strips run much taller).
  Search: the date backfill runs 6 concurrent workers instead of one
  fetch per second. On-device: fling down/up render clean on the
  reported chapter; DB audit 210/215 series dated (hentaithai's 5
  stayed undated — its pages expose no parseable chapter stamps; to
  probe). 213 tests green.
- 2026-10-20 — Release: v1.2.3 — version 1.2.3+7. Ships everything since
  v1.2.2: the browse sort orders (latest/oldest update, most/fewest
  chapters — latest update by default) and the search-card date fix
  (newest-chapter stamps now reach every card, including the ts sources
  whose tiles carry no dates). 213 tests green.
- 2026-10-20 — Search cards show the newest-chapter date (user report:
  "Overgeared from up/go-manga shows no last update but every chapter
  has a date"). Three stacked causes: the date-backfill pass was capped
  (12 detail fetches per refresh, first 40 groups only) so most
  ts-source cards never got one; enrichment could attach a date only by
  TITLE-NORM lookup, which misses when the tile's Thai subtitle differs
  from the detail row's ("จ้าวนักสู้กระทันที" vs "จ้าวแห่งยุทธภัณฑ์",
  "(Remake)" stripped from the row norm); and merging the next
  infinite-scroll page rebuilt every group, WIPING whatever was
  attached. The backfill now covers every undated card (one persisted
  detail fetch each, paced by the per-host limiter; the cross-source
  probe keeps its 12 budget) and writes the row it already knows
  straight onto the card; merges carry the enrichment fields.
  On-device: both Overgeared cards now show เมื่อสักครู่ / 3 ปีที่แล้ว.
  213 tests green.
- 2026-10-20 — Release: v1.2.2 — version 1.2.2+6. Ships everything
  since v1.2.1: the site-sheet clipping fix (Bully Manga row visible
  and tappable again), the user-made Star Codex logo as the app icon +
  README header, and the browse sort orders (latest/oldest update,
  most/fewest chapters — latest update by default). 211 tests green.
- 2026-10-20 — Browse sort orders (user request): the filter sheet gains
  a เรียงลำดับ section — อัปเดตล่าสุด (default), อัปเดตเก่าสุด,
  ตอนมากสุด, ตอนน้อยสุด. The sort is stable (Dart's List.sort isn't)
  and groups with an unknown date/chapter count sink to the bottom in
  BOTH directions instead of faking a position; the merged feed re-sorts
  live, so later pages interleave by key rather than appending. Popular
  order was probed and left out honestly: the ts themes ignore ordering
  params on search (identical tile order with/without them) and no
  source exposes view counts. On-device: tapping ตอนมากสุด reorders the
  feed 1254→1196→1000→924→364 ตอน. 211 tests green.
- 2026-10-20 — App icon + README use the user-made Star Codex logo:
  README header shows the banner lockup; the launcher ships a
  rounded-square tile (no circle, no sharp corners) built by radially
  extending the emblem disc's own edge colors into the padding — no
  background-color seam (a flat sampled color had mismatched the logo's
  gradient, user caught it). Adaptive icon (API 26+) with the emblem at
  60% of the canvas — inside every launcher's safe zone, so no mask
  shape ever crops the wordmark (verified on the emulator's circle-mask
  launcher). Picture/ holds the banner, tile and emblem sources.
- 2026-10-20 — Site-sheet bottom clipping fixed (user report + visual
  QA on emulator): my 12 px list padding pushed the sheet's Column past
  the default bottom-sheet height budget — Flutter painted a
  "BOTTOM OVERFLOWED BY 12 PIXELS" band with the last row (Bully Manga)
  inside it, invisible and untappable. The sheet now opens
  isScrollControlled with a 0.75-screen max-height contract (same as the
  filter sheet), so headers + scrollable row list always fit; verified
  on the emulator that Bully renders fully, toggles (globe badge), and
  the filter resets cleanly. 206 tests green.
- 2026-10-19 — Release: v1.2.1 — version 1.2.1+5. Reader polish over
  v1.2.0: harder pull-to-continue with a live percentage that tracks
  sliding back, no black frame on page-by-page turns, and the webtoon
  scroll-up stuck/jump fix (anchored height corrections). Release-signed
  APK (StarCodex-1.2.1.apk) on GitHub Releases with English notes +
  SHA-256.
- 2026-10-19 — Webtoon scroll-up jank fixed (user report): scrolling up
  got stuck/jumpy because never-displayed pages above the viewport still
  held 1.9× height estimates; when scrolling back rebuilt them, their
  real decoded heights (often much taller) shifted all content below —
  worst after resuming mid-chapter. Height corrections are now
  ANCHORED: when a slot above the viewport resizes, the scroll offset
  shifts by the same delta (heightAnchorDelta, unit-tested) so the
  visible pages stay under the finger; decoded webtoon pages also stay
  in the memory cache (no placeholder re-decode flash on scroll-back).
  206 tests green.
- 2026-10-19 — Reader pull + paged flash + sheet padding (user QA
  round 5): drag-to-continue needs noticeably more force (thresholds
  170 px vertical / 160 px horizontal) and the pill now shows a live
  percentage that DROPS when you slide back (all three readers feed
  negative overscroll into the tracker); the paged reader's brief black
  frame on every page turn is gone (neighboring page stays built via
  allowImplicitScrolling + decoded pages stay in the memory cache
  instead of being dropped when their slot disposes); the site sheet's
  last row gets trailing padding so it no longer sits flush against the
  sheet edge. 205 tests green.
- 2026-10-19 — Docs: v1.2.0 refresh — README (doujin page, site
  selector rows, OLED family, 9-live-source tables, correct minSdk
  badge, v1.2.0 status), AGENTS/HANDOFF/Docs-README/ARCHITECTURE
  brought current (sources, drawer order, schema v6, 205 tests,
  release recipe with the About-string step), and the About dialog's
  hardcoded version bumped to 1.2.0 (release APK re-uploaded with it).
- 2026-10-19 — Release: v1.2.0 — version 1.2.0+4. Ships everything since
  v1.1.0: the Doujin (18+) page (NTR-Manga + HentaiThai live; doujin-lc
  and miku-doujin seed disabled behind their Cloudflare WAF), the
  site-filter race fix, the one-row-per-site selector with grounded
  type pills, the OLED theme family (white/red/orange/pink/green),
  instant reading-mode switching in the reader drawer, and paged-reader
  prefetch (no spinner on page turns). Release-signed APK
  (StarCodex-1.2.0.apk) published to GitHub Releases with English
  notes + SHA-256.
- 2026-10-19 — Post-doujin-QA review pass (big model): the live
  mode-switch raced SettingsController.set — the in-memory settings state
  publishes only AFTER its awaited DB write, so re-reading
  reader_mode_<id> right after the drawer tap could still see the old
  value and the swap silently no-ops; the three readers now pass the
  freshly chosen mode directly into the re-route instead of re-reading.
  Also verified: empty-page chapters throw before the paged reader's
  clamp (novel flipped to paged shows the error panel, no crash), db
  v6 migration end-state matches fresh seeds, and the CF marker strings
  can't false-positive on normal pages. 205 tests green.
- 2026-10-19 — Site-sheet + OLED themes (user feedback round 4): the
  "เว็บที่จะค้นหา" site selector is now one full-width row per site —
  selection circle on the left, colored identity dot + name, small
  mostly-carries type pills on the right (grounded in each site's own
  tile badges + the DB's detail types: nekopost มังงะ+นิยาย,
  go/up มังฮวา+มังฮวาจีน, slow มังฮวา+มังงะ, dark/fin/bully-lc-family
  มังฮวา(-จีน), one-shots มังงะ) — toggling only
  flips the circle so rows never resize (the old wrapped chips jumped
  around on select); list scrolls, capped at half the screen; long-press
  → genre browser kept. Theme picker gained an OLED family: Stardust
  Black's true-#000 background with white/red/orange/pink/green accents
  (reader surface stays black too). The type pill moved to a shared
  TypeChip (result cards + sheet rows). 205 tests green.
- 2026-10-19 — Doujin QA fix round (user emulator report): hentaithai
  never rendered because its REAL pages embed Cloudflare's benign
  challenge-platform JS-detect snippet and the challenge sniff
  false-positived on it — the sniff now lives in one shared helper
  (source_api.looksLikeCloudflarePage, all 5 adapters) that only reacts
  to actual challenge/block pages; miku-doujin + doujin-lc are
  confirmed Cloudflare fingerprint-blocked at the TLS layer (403 block
  page for Dart while every browser/curl probe passes — not fixable
  in-app), so they seed disabled via db v6 (migration re-disables,
  users can re-enable in Settings); miku's URL builder no longer emits
  a trailing "?" (empty queryParameters). Reader: flipping the reading
  mode in the drawer now swaps the open reader immediately (progress
  saved first, resumes at the same page) instead of only affecting the
  next chapter; the paged reader memoizes page futures + prefetches
  ahead like webtoon mode, so page turns and going back no longer
  flash a spinner. Doujin 18+ moved to second in the drawer (under
  ค้นหา; settings tab is now index 5). Materialization budget 8→12 so
  NTR's date-less tiles fill faster (their listing carries no dates at
  all — dates only exist on detail pages). 205 tests green.
- 2026-10-19 — Doujin (18+) page + 4 adult sources + site-filter race fix:
  ntr-manga.net (ts Madara config), doujin-lc.net (classic-Madara layout
  support: .page-item-detail / c-tabs-item__content rows, post-title
  detail, /doujin/ archive), miku-doujin.com + hentaithai.net (one-shot
  custom adapters — series page IS the reader); db v5 seeds all four;
  adult sources live ONLY on the new Doujin 18+ drawer destination
  (scoped controller, search from that page stays scoped); main
  browse/search/site-sheet exclude them entirely. Site-filter race: a
  stale in-flight fetch could overwrite a newer filter's results
  (select Bully → Done → feed flips back) — fetches now carry a
  sequence number and stale completions are dropped; the site sheet
  debounces rapid toggles into one refetch and flushes on
  Done/outside-tap. Fixture tests for every new parser (203 green).
- 2026-10-19 — Post-v1.2 review pass (big model): enrichment now also
  looks up the series row by the tile's Latin-only norm (solo bully
  cards with Thai-suffixed titles were missing their DB dates/covers);
  materialization re-enriches just the finished card instead of the whole
  list; history screen drops a dead computation in grouped mode. 193
  tests green.
- 2026-10-19 — Release: v1.1.0 — version 1.1.0+3, About string cleaned,
  release-signed APK (StarCodex-1.1.0.apk) published to GitHub Releases
  with English notes + SHA-256.
- 2026-10-19 — Feed completeness pass (on-device QA round with the user):
  background materialization — browse cards the listing alone left
  incomplete (no date or no renderable cover) get the open-card path run
  budgeted in the background (detail fetch → chapters/dates → cross-probe
  → persist), re-emitting progressively; enrichment now also surfaces a
  DB cover for cards whose every listing tile is dead/AVIF; probe
  matching gained a Latin-only retry so "English title + Thai subtitle"
  listings (bully/go) link to the same series; never-read library series
  now count every dated chapter as new (chip clears on first visit);
  library category dropdown fixed (flex 3:1 vs Spacer — "ทั้งหมด" was
  truncated to "ทั้…"); filter sheet 70% cap moved over the drag handle;
  duplicate site badges on merged cards deduped. Poison Master cover +
  date recovered live via bully/go links; "I'll Resign…" stays a
  placeholder (slow-manga's file is gone and no other source carries the
  title). 193 tests green.
- 2026-10-18 — v1.2 UX batch (user feedback round 3): site-select sheet
  stays open while toggling (Done button / outside tap closes it); filter
  sheet capped at 70% height + scrollable; browse refresh button; library
  category dropdown replaces the sliding chip row; library "New" chip is
  green, sorts to top, resets on detail-page visit (db v4
  library.last_seen_at); history collapses to one row per series with the
  read-chapter range (setting, default on); result card loses the globe +
  status chips, type chip leads the row with per-type colors; aged
  relative-date colors (green→grey) on cards + download rows (single-line
  "ตอน | อัปเดต"); nekopost latest/search now carry chapter counts and
  update stamps (SourceSeries.lastUpdatedMs); detail hero tag chips moved
  into the intro expansion, which always opens with the full title; font
  label "Prompt (Maki)" → "Prompt". 186 tests green.
- 2026-10-22 — Browse card date freshness (user report: site tiles said
  "16 ชั่วโมงที่แล้ว" while app cards showed 3–6 days, slow-manga feed).
  Two root causes fixed: (1) the card stamp let the DB-enriched date win
  unconditionally, shadowing a fresh nekopost listing stamp — now the
  FRESHEST of DB + listing stamps wins; (2) the persisted date froze at
  the first materialization forever, and nothing ever re-checked the site
  (ensureSeries skips the detail fetch once the (source,url) link
  exists). The background materialize pass now also re-checks cards whose
  date is older than 6 h (attempt memoized per URL with a timestamp, so
  pagination re-presents stay free) via a new SeriesRepo.refreshDetail
  that always fetches and re-stamps chapters/link/metadata through the
  existing identity rules; cross-probe stays an incomplete-card-only
  extra. Also: scripts/boot-emu.bat (windowed emulator starter). 235
  tests green.
- 2026-10-22 — Card date precision (follow-up to the freshness fix; emu
  verified: slow-manga cards now read "16 ชั่วโมงที่แล้ว" exactly where
  the site's grid says 16 hours, order included). ts chapterdates are
  DATE-ONLY ("ตุลาคม 21, 2026" — probed live: all 364 rows carry no clock
  time), and the old parser anchored them at UTC midnight = 07:00 Thai,
  overstating every fresh chapter by ~13 h ("1 วันที่แล้ว" for a 16 h-old
  chapter). parseSiteDate now (a) parses RELATIVE stamps
  ("16 ชั่วโมงที่แล้ว" / "3 days ago" — previously → null stamp) and
  (b) anchors date-only strings at local 20:00 (Thai scanlation drops
  cluster in the evening; the site's own 16 h grid label back-solves to
  ≈19:16 posting). Known bound: morning drops may understate by up to
  ~12 h — they stay in the hours bucket. 236 tests green.
- 2026-10-22 — Feed leads with the homepage recent grid (user reports:
  wrong ORDER on up/dark/fin/bully + wrong dates on go/dark/up —
  order+dates the user cross-checks against the site's own grid). Root
  discovery: ts chapterdates are date-only AND rendered in a lagging site
  timezone, so NO fixed anchor can be right on all sites (go-manga's
  6-hour chapter reads Oct 21, dark-manga's 2-minute chapter reads
  today). But every ts homepage renders the recent-updates grid
  SERVER-SIDE with live relative labels (.chfiv .fivtime pills on
  go/dark/fin/up, .epxdate on slow-manga). New Source.recentStamps()
  harvests them; MadaraSource.latest() page 1 now injects grid entries
  first (the site's own update order), appends the archive tail deduped,
  and chapter-linked grids (slow-manga) borrow the precise stamps onto
  their archive tiles by title. parseRelativeStamp parses bare labels
  ("6 ชั่วโมง", "2 นาที", "38 วินาที ที่แล้ว" — seconds included). The
  stale re-check prefers a grid hit (writes the link stamp, skips the
  detail fetch). Emu verified: go-manga feed = the site's grid order with
  matching hour stamps; dark-manga Reincarnator's Stream reads
  "2 นาทีที่แล้ว" — identical to the site. Bully (custom engine) grid
  support deferred. 241 tests green.
- 2026-10-22 — Browse card intro fills the empty space under the chip row
  (user request: short-title cards showed a dead gap next to the cover).
  The card now renders the series description below the chips, truncated
  to two lines with an ellipsis. New SearchGroup.dbDescription field,
  filled from the materialized series row in the browse enrichment pass
  (and the offline catalog), carried across group rebuilds like the other
  DB-enriched fields. Listing-only series have no description yet — it
  appears once the row is materialized (detail fetch). 242 tests green.
- 2026-10-22 — Browse card polish (user feedback on the intro cards):
  (1) COMPACT site chips — the generic "Manga" word is dropped from the
  chip label ("Slow Manga" → "Slow", "Go-Manga" → "Go", "Bully Manga" →
  "Bully"; brands without it keep their name) and the chip padding
  tightened, so 3 merged sites fit on ONE chip line and 5 on two, instead
  of three chip lines pushing the intro out of the card; the full site
  name still shows in the site sheet and on the detail screen. (2) The
  intro now takes AS MANY LINES AS FIT beside the 128 px cover — the
  budget is measured (title's real line count via TextPainter + the rows
  the chip labels wrap into), never fewer than 2 and never more than 4,
  then truncated with an ellipsis. 243 tests green.
- 2026-10-22 — Release: v1.3.0 — version 1.3.0+15. The browse feed finally
  matches the websites: page 1 is built from each site's own
  recent-updates grid (the site's own order + its live "x minutes ago"
  labels), card dates are re-checked every 6 h instead of freezing at the
  first read (a grid-listed card refreshes without any extra request),
  and the cards fill their leftover space with the series intro (2–4
  measured lines, ellipsized) under compact site chips. Ships the v1.2.10
  reader gestures too (real per-chapter crop lock, website-style pinch
  zoom, paged-slide freeze). 243 tests green.
- 2026-10-22 — Docs: full audit against the code (not just a version bump).
  Fixed the facts the docs got wrong: the main feed has 7 live sources (not
  9 — the other 2 live on the Doujin page), the app requires Android 7.0
  / API 24 (not 6.0 / API 23), ARCHITECTURE no longer says "five manga
  websites" and its DB table now lists blob_urls + page_bands, BUILD.md is
  retitled "Star Codex" and gained the release-signing + two-place version
  bump rules, HOW_TO_RUN gained the emulator boot scripts and fin-manga in
  the smoke test, QA-ON-DEVICE no longer links a non-existent shots folder
  (and is marked as the historical v1.0.0-era log), and 2 broken
  ../CHANGELOG.md links in the Plan folder now resolve. Added two new
  docs: Docs/SOURCES.md (per-site reference — adapter, markup quirks,
  which sites support the grid feed, which are Cloudflare-blocked) and
  Docs/RELEASING.md (the release runbook: bump → build → verify the
  signature → publish → clean up). Live-probed every homepage while
  auditing: the grid has a THIRD family (ntr-manga's own ntr-upd-grid
  markup, which the Madara parser does not read yet — recorded as a
  follow-up). Repaired 3 stray cp1252 bytes that made PLAN_NOTES.md
  invalid UTF-8 (sequence-aware replacement — a blind byte replace
  corrupts the Thai sections). 243 tests green, analyze clean.
- 2026-10-22 — Fix: three user-reported bugs (chapter state, reader chrome,
  hentaithai detail). (1) The chapter-state circle now sits in FRONT of
  "ตอนที่ N" and shows three states — unread (hollow ring), on reading
  (solid dot), read (solid dot + check). Opening a chapter and reading it
  for 2–3 s marks it "on reading"; finishing it (or pulling to the next
  chapter, which also marks the previous one read) marks it "read". Both
  colors are theme-derived, and the "on reading" color is always distinct
  from the "read" color (probed against all 25 themes). The dot is 10 px —
  the size of the websites' own indicator — and the check sits inside it.
  (2) The reader header now STAYS hidden when you pull to the next
  chapter: a chapter switch builds a fresh reader screen, so the hidden
  state is passed along instead of resetting. (3) hentaithai.com serves
  its pages under two CDN layouts (/thai/… and /image/…); the parser
  only accepted the first, so threads served under /image/ failed with
  "can't load the detail page". Both layouts are parsed now, and the
  non-content images are still filtered out. 253 tests green.
- 2026-10-22 — Release: v1.3.1 — version 1.3.1+16. Ships the three bug
  fixes above (chapter read-state indicator, reader chrome carry-over,
  hentaithai /image/ detail pages) plus the smaller indicator size the
  user asked for. 253 tests green.
- 2026-10-23 — Fix/UX: reader pull rework + two site-side breakages.
  (1) The Android status/navigation bars stayed hidden across chapter
  switches and webtoon↔paged mode flips (the outgoing reader's cleanup
  fired after the new reader's setup and un-hid them — all reader
  replacements now route through one handover path). (2) The
  pull-to-switch gesture is rebuilt to Webtoon style: the page slides
  with the finger past an edge, opening space for a growing-dot trail
  (small→large dots + faux-bold arrow) whose fill sweeps with the
  pull; dragging BACK at the top pulls the previous chapter with the
  same indicator; reversing the finger falls the progress back
  smoothly instead of vanishing; thresholds raised (420/400/300).
  (3) fin-manga covers: the site enabled WP Fastest Cache lazy-loading
  (covers moved to data-wpfc-original-src) — the parser reads it now.
  (4) dark-manga.com is behind the Cloudflare challenge as of today
  (same WAF family as the disabled doujin sources); it stays enabled —
  the feed degrades gracefully and auto-recovers if the site relents.
  254 tests green, analyze clean.
- 2026-10-23 — WAF ladder: blocked sites now load. Cloudflare blocks come
  in two shapes and each gets its tier: (1) TLS-fingerprint blocks
  (doujin-lc, miku-doujin — 403 for dart:io since v1) pass through a new
  **cronet tier** (embedded Chromium network stack — real Chrome TLS
  handshake at native speed; verified on-device: doujin-lc OK 2699 ms,
  miku OK 1166 ms; both stay seed-disabled). (2) Interactive challenges
  (dark-manga, whole site) are executed by a **webview tier**: a
  headless WebView auto-solves the managed challenge (verified: OK
  1008 ms, zero interaction) and byte traffic rides cronet with the
  relayed clearance cookies; if a site ever demands a human tap, a lock
  icon appears on the source row in Settings → visible verification
  dialog. Lanes are learned per host at runtime (direct → cronet →
  webview, fail-fast 10 min after exhaustion); all requests still go
  through SafeHttp's scheme/host validation, POSTs stay on the direct
  lane. Two new dependencies (justified in PLAN_NOTES): cronet_http
  1.10.0 + cronet-embedded 143.7445.0 (~8 MB/ABI), flutter_inappwebview
  6.2.0-beta.3 (pinned — 6.1.5 breaks Flutter 3.47's AGP). Default UA
  bumped Chrome/126 (2024) → Chrome/140. **db v9 re-enables every
  source** (user request: all sites open by default — the ladder made
  the two seed-disabled doujin sites reachable). 265 tests green (11
  new ladder tests), analyze clean.
- 2026-10-23 — Fix: hentaithai feed paging. The homepage is only a
  landing page — the real feed is the /page-<N> chain its "see all"
  button points at (descending page numbers, 24 threads each, probed
  live: /page-1814 = t51966..t51943). latest() now learns N once per
  session and walks down for page 2, 3, … (live-verified: four
  contiguous pages t51966→t51871); feed cards are a different markup
  family (a.col-6.col-md-3 + style-block cover) parsed alongside the
  old landing grid. The user-seen /prev-/next- links are per-thread JS
  navigation, not pagination. 266 tests green.
- 2026-10-23 — Release: v1.4.0 — version 1.4.0+17. Ships everything
  since v1.3.1: the WAF ladder (every Cloudflare-blocked source now
  loads; all 11 sources enabled by default, db v9), the Webtoon-style
  pull-to-switch rework + system-bars carry-over fix, fin-manga lazy
  covers, hentaithai feed paging (+ genre-browse union fix from the
  review pass), and the review-pass hardening of the WebView tier.
  267 tests green.
- 2026-10-23 — Fix: browse card dates frozen at the site's cache time.
  fin/up-manga cards stayed at "24 วินาที" for days (WP Fastest Cache +
  the Cloudflare edge serve the homepage ~a day old, and its relative
  grid labels were re-anchored at fetch time on every refresh, which
  also dodged the 6 h stale re-check and skewed the update-date search
  filter). Grid labels now anchor at the page's real generation time
  (`Last-Modified`, else `Date − Age`) via `SafeHttp.getHtmlPage` —
  true update times, homepage order untouched. Live-verified on
  fin-manga (frozen + freshly-regenerated copies). 276 tests green.
- 2026-10-23 — Release: v1.4.1 — version 1.4.1+18. The frozen-date fix
  as a patch release: browse/search card dates now anchor each site's
  relative grid labels at the page's real cache-generation time instead
  of fetch time, so fin/up-manga cards no longer sit at "4 วินาที" for
  days, the update-date filter is accurate again, and genuinely fresh
  drops (nekopost) rank on top as they should. Emulator-verified: card
  ages tick in real time across two screenshots and the newest chapter
  holds the top slot. 276 tests green.
- 2026-10-23 — UX: paged-reader (หน้าต่อหน้า) pull polish. The dot-trail
  indicator was pinned to the opposite side from where the page slide
  opens space (it drew over the artwork instead of the black gap) — it
  now sits on the side the next/prev chapter comes from, in both LTR
  and RTL. The paged arm threshold was tuned against the shipped build
  (400 → 200 → 160 px): overscroll deltas are friction-damped, so the
  old values needed far too much finger travel, and with the slide +
  visible trail a shallow arm is safe. Same-session follow-up: the
  webtoon (420 → 200) and novel (300 → 200) readers also lowered, and
  the v1.4.2 asset was REPLACED in place (same tag, same versionCode
  19 — users who installed an earlier v1.4.2 build must
  uninstall/reinstall; nobody outside the author had it yet). 276
  tests green.
- 2026-10-23 — Release: v1.4.2 — version 1.4.2+19. The paged-reader
  pull polish as a patch release: the drag-to-switch dot-trail
  indicator now sits in the space the page slide opens (the side the
  next/prev chapter comes from) instead of drawing over the artwork,
  and the arm threshold tuned down against the shipped build — 160 px
  in the paged (side-slide) reader, 200 px in webtoon and novel — so
  a normal-length swipe is enough. Asset replaced in place after the
  follow-ups. 276
  tests green.
- 2026-10-24 — Polish: the reader top bar's "จาก <source>" tail got a
  12 px gap before the book-icon button (user: sat too close), and the
  subtitle now flows as one line — "ตอนที่ 628 · จาก dark-manga" — with
  the source hugging the chapter text instead of pinning to the bar's
  right edge (loose Flexible: short label = adjacent, long label still
  ellipsizes the chapter first). Same day, user-approved.
- 2026-10-24 — Fixes: five-report round from the phone + emulator. (1)
  The system bars coming back after most chapter switches (MIUI only):
  the readers now re-assert immersive when their entrance animation
  settles and once more ~900 ms later, and the outgoing reader's wakelock
  disable is handover-guarded — the window-flag churn at dispose was the
  likely re-show trigger; needs on-phone confirmation (MIUI does not
  reproduce on the emulator). (2) Sticky feed time anchors (db v10):
  fin/dark serve WP-cache copies whose "2 นาที" labels stayed frozen for
  10+ hours; the feed now remembers each series' latest-chapter + stamp,
  keeps aging an unchanged chapter from the first-seen moment, and only
  re-anchors when the chapter actually changes or the site corrects.
  (3) History rows could show manga A's art under manga B's title —
  recycled cover widgets kept the previous row's cached blob future;
  the hash guard now covers history, offline catalog, updates sheet,
  and the detail hero. (4) up-manga / dark-manga search re-enabled —
  the WAF ladder carries the challenged `?s=` endpoint, so search no
  longer shows those two as dead. (5) The reader top bar now leads its
  subtitle with the chapter number + name before "จาก <source>"
  (truncation keeps the source visible), and the browse search results
  got an X button to return to the latest feed. Also: boot-emu.bat now
  always cold-boots — a quick-boot snapshot corrupted guest GL and
  black-screened the app on the emulator. 287 tests green.- 2026-10-24 — Search cards show the intro text (เรื่องย่อ) now: the
  background backfill covers dated+covered cards that never got opened
  (bounded at 20 per pass), and when a series' primary site writes no
  synopsis the card borrows a sibling member's (go-manga-empty /
  bully-or-up-has-it, user ask). Emulator-verified on a fresh search.- 2026-10-24 — Release: v1.4.3 — version 1.4.3+20. The five-fix round
  as a patch release: MIUI bars re-assert after chapter switches,
  sticky feed time anchors (db v10), search-card intro text with
  sibling-synopsis fallback, Up/Dark-Manga search via the ladder, the
  search ✕ button, the "ตอนที่ N · จาก <source>" reader subtitle, and
  the cover-recycling guard — plus the review-pass catch (novel-reader
  wakelock leak) landed in the release commit itself. 290 tests green.

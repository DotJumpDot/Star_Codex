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

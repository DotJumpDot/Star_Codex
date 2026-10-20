# Plan Notes — deviations & environment facts

Deviations from Plan/01 tables, per rule 5 of 15-BUILD-ORDER (documented, not silent).

## Dependency versions (Phase 1, 2026-10-17)

Flutter stable resolved to **3.47.7 / Dart 3.13.5**. On this SDK:

| Package | Plan expected | Actual | Reason |
|---|---|---|---|
| google_fonts | 6.x | **8.2.1** | 6.2.1 does not compile on Flutter 3.47 (const `FontWeight` map evaluation error in google_fonts 6.x against new dart:ui). 9.0.0 compiles but pulls `material_ui` fork whose `TextTheme` type clashes with flutter's. 8.2.1 is the newest version that compiles clean. API used (`sarabunTextTheme`, `prompt`) is unchanged. |
| intl | 0.19.x | 0.20.3 | Pinned by flutter_localizations on this SDK; not independently choosable. |
| flutter_riverpod | 2.x | 2.6.1 | Matches plan (pinned down from pub's 3.x resolution). |
| everything else | — | as planned | dio 5.11, sqflite 2.4, path 1.9, path_provider 2.1, crypto 3.0, html 0.15.7, flutter_image_compress 2.5, extended_image 10.1, shared_preferences 2.5. |

## Testing environment notes (Phase 1)

- Widget tests must set `GoogleFonts.config.allowRuntimeFetching = false`
  (FakeAsync zone can't complete real network font fetches; the shared
  google_fonts cache poisons any *second* widget test in the same file →
  10-minute hang). Keep widget tests one-per-file or reset state carefully.
- `flutter.bat` output must be redirected to a file, never piped through
  `tr/grep/tail` in Git Bash — child dart.exe processes hold the pipe open
  and the calling shell hangs even after the tool exits.
- Test suite wall time ≈ 4s warm (execution itself is sub-second).

## Emulator (Phase 0)

- AVD `StarCodex`: Pixel 7, android-36 google_apis x86_64, headless
  (`-no-window -gpu swiftshader_indirect`), driven via adb
  (input/screencap/uiautomator) for per-phase UI verification.
- Phone-in-hand remains the judge for performance DoDs (cold-open timing,
  RAM) — emulator numbers are approximate.

## Source framework notes (Phase 3, 2026-10-17)

- **All 4 sites are MangaStream-family ("ts") themes, NOT Madara.** Full
  drift record + verified selector table lives at the top of
  [`Plan/05-SOURCE-MADARA.md`](Plan/05-SOURCE-MADARA.md). The file is named
  "madara" for history; the adapter (`MadaraSource`) speaks ts-theme markup.
- up-manga & dark-manga: `?s=` search endpoint returns Cloudflare 403;
  `searchSupported: false` in configs, browse still works via `latest()`.
- Chapter rows are `div.eph-num` (sometimes li) → parser matches `.eph-num a`;
  fragment-only template links (`#/chapter-{{number}}`) are filtered by
  same-host + non-empty-path checks (safe_http caught the first attempt).
- Status `<i>` is often empty on these sites → `status` stays null
  (best-effort per spec); type falls back to the listing tile badge at merge
  time (Phase 5).
- CLI console shows mojibake for Thai on Windows (codepage only — data is
  correct UTF-8; the app renders it properly).
- 05 DoD bullet "fetch one image through pipeline 03 → WebP ~40%" is
  exercised in Phase 4 when the BlobStore/ImagePipeline exist.
- Retry tests use an injected fetcher (loopback servers are forbidden by the
  security rule itself); redirect-to-private rejection is enforced by
  re-validating every hop through the same `_validate` covered by unit tests.

## Storage engine notes (Phase 4, 2026-10-17)

- `PageResult.width/height` are null in v1 — decoding dimensions needs the
  dart:ui codec which is not reachable from plain unit tests; the schema
  columns are nullable and the reader can fill them in Phase 7 if needed.
- `fetchAndStore` always performs the network fetch (it must, to hash the
  original bytes). The zero-network dedup path is the repo read path
  (`getPage`: content_hash + file-exists → serve directly).
- Widget tests must not construct `main()`'s 10 s janitor Timer — it lives
  in `main()` (UncontrolledProviderScope), not in any widget, or the
  test binding's pending-timer invariant fails.
- Test gotcha: `sqflite_common_ffi` re-exports `package:file`, whose
  `File.deleteSync()` returns void — use `dart:io as io` in tests that mix
  real filesystem work with the ffi import.
- The Phase 4 DoD "manual on-device check" (blobs ~40% size, airplane
  re-read) needs the reader UI — it is exercised in Phase 7's on-device
  verification and again in the Phase 11 release journey.

## Post-Phase-4 review pass (big model, 2026-10-17)

Bugs found & fixed (commit "Fix: post-Phase-4 review"):

1. **`getHtml` Latin-1 mojibake (serious).** `String.fromCharCodes(bytes)`
   decoded UTF-8 sites as Latin-1 — every Thai string was garbled, which
   silently broke Thai month parsing (uploadedAt always null), the
   `ตอนที่ N` chapter-number regex (silent fallback to positional
   numbering), and status normalization. Now `utf8.decode`. Live-verified:
   Thai tags/labels parse, dates non-null, status=ongoing.
2. **SSRF guard didn't resolve DNS.** Only literal IPs were checked; a
   hostname resolving into private/loopback space passed. `_validate` now
   does `InternetAddress.lookup` and rejects unless every resolved address
   is public (per Plan/04 §2 "resolve the host").
3. **Dio options binding.** The injected-fetcher refactor tore off
   `_dio.getUri` as a positional 2-arg closure — real requests crashed
   (`Closure call with mismatched arguments`) even though fake-fetcher
   tests passed. Reminder: injected-transport tests do NOT cover the
   default transport; run `tool/verify_sources.dart` live after touching
   safe_http.
4. **Detached rate limiter.** `safeHttpProvider` built its own RateLimiter;
   `registerImageHost` would have gone to an unused instance. Now shared.

Improvements:

- Janitor split: integrity pass (full dir walk) at startup only; periodic
  runs are LRU-only (matches Plan/03 and avoids walks every 50 writes).
- Header-only image dimension sniffing (`image_dimensions.dart`): PNG/GIF/
  JPEG/WebP(VP8/VP8L/VP8X) parsed before dedup so PageResult always carries
  width/height for chapter_pages + reader aspect ratios.
- `.gitignore`: `.git-msg-*.txt` scratch files no longer enter commits
  (messages live in git history proper).

## Phase 5 (2026-10-17) — merge + browse findings

- **Live tile-title reality vs Plan/07 §6:** go-manga/up-manga append Thai
  subtitles to English titles on search/listing tiles ("Infinite Mage
  จอมเวทไร้ขีดจำกัด"). Such pairs land at jw ≈ 0.89–0.90 → the 0.88–0.95
  "similar" band → hinted ("คล้ายกับเรื่องอื่น?"), never auto-merged — per
  spec. Auto-merge fires on identical titles; verified live on device with
  2-source (My Exclusive Tower Guide slow+up, Star-Embracing Swordmaster
  slow+dark) and 3-source (Magic Emperor up+dark+go, Disastrous Necromancer
  dark+go+up) merged cards. The Thai↔English bridge comes from alt titles
  at detail level (Plan/07 §2 note; lands with Phase 6 DB merge).
- **`String.normalize` is web-only Dart** (compiles to JS
  `String.prototype.normalize`; absent on the VM). NFC step of Plan/07 §1
  is skipped — WordPress content is NFC in practice; NFKC-compat would
  destroy Thai vowel marks anyway (doc's actual concern). Noted in
  title_norm.dart.
- **Genre browsing drift** (also in Plan/05 drift addendum): `/genres/{term}/`
  archive pages are EMPTY shells on ts themes; the working filter is
  `/manga/?genres={term}` (server-side, paginates, same `.bsx` tiles).
  Genre list scraped from homepage `a[href*="/genres/"]`. Sites emit some
  malformed hrefs → `Uri.resolve` throws ArgumentError ("Illegal percent
  encoding") — `_genreTermFrom` skips unparseable links (was a live bug
  found by the emulator genre-browser check).
- **Listing tiles carry `.epxs`** (latest-chapter label) → chapterCountHint;
  **no timestamps** in listings → latest feed interleaves sources in their
  own newest-first order (Plan/08's "sort by newest chapter time" is
  approximated; recorded in Plan/05).
- **Unbounded DNS lookup hung the whole feed** on a just-booted emulator
  (resolver not ready → `InternetAddress.lookup` blocked for minutes).
  `safe_http._validate` now bounds lookup at 10 s → NetException → source
  marked failed, others still load.
- **Persisted language was never applied at startup** (Phase 1 bug surfaced
  by the EN-flip device check): `LanguageController` constructor now calls
  `I18nService.setLang(state)`. Verified live: settings row language=en
  renders every Phase-5 label in English.
- **Search history write is fire-and-forget** (`unawaited`) — results must
  never wait on a DB round-trip (and a sqflite-ffi call can't complete
  inside a widget-test FakeAsync zone; the test drains it with
  `tester.runAsync`).
- **`search_history.recent`** orders by `at DESC, rowid DESC` — same-
  millisecond re-records otherwise tie arbitrarily.
- **Search on submit only** (Plan/08 §1, no per-keystroke network). Browse
  filters are session-only; restart ⇒ defaults OFF (verified live, L1).
- Status/tag filter controls exist but are honest no-ops on browse listings
  (no status/tags until a detail fetch — they engage with Phase 6 data).
- **New dep:** `url_launcher 6.3.3` (allowed by 15 rule 5; long-press card
  → open source site in browser).
- **New tool:** `tool/genre_probe.dart` — host-side smoke for
  `Source.genres()` (also keeps proving the "live-verify after touching
  safe_http" rule: safe_http must stay free of Flutter imports so
  `dart run` keeps working).
- Shimmer skeletons from Plan/08 are static (non-animated) placeholder
  cards — no animation package, and looping controllers hang
  pumpAndSettle-based widget tests. Profile-mode ≥50 fps scroll check for
  the latest feed is a phone-in-hand task (swiftshader emulator numbers
  are meaningless), consistent with prior performance DoDs.
- adb driving notes: screen coordinate factor 1.2 (screencap renders
  900×2000, device is 1080×2400); `input text` uses `%s` for spaces;
  ChoiceChip has no long-press (wrapped in GestureDetector); EN-flip via
  `run-as com.jamej.starcodex sqlite3 files/manga_reader.db "UPDATE
  settings SET value='en' WHERE key='language';"` + app restart.

## Post-Phase-5 review pass (big model, 2026-10-17)

Findings & fixes (commit "Fix: post-Phase-5 review pass"):

1. **Duplicate-series hole in addToLibrary (serious).** Identity was
   title-norm only: re-adding the same source page under a drifted tile
   title would create a SECOND `series` row. A (source_id, source_url)
   link is a stronger identity than any title match — `addToLibrary` now
   resolves an existing link first and reuses that series
   (`SeriesDao.findSeriesIdBySourceLink`). Cross-probe likewise never
   re-links a URL owned by another series. Verified live on device:
   adding the same card twice → still 1 series, 1 library row.
2. **Empty-norm fusion risk.** A pure-noise title ('มังงะ') normalizes to
   '' — the UNIQUE(title_norm) index would fuse unrelated series onto one
   row. Fallback chain: detail-page title norm → per-page escape key
   `raw:<primary.url>` (URL-unique; same-URL re-adds are caught by the
   link check before norm matters). Unit-tested with two same-noise-title
   pages → two distinct rows, no '' norm ever stored.
3. **Chapter writes not atomic.** 175-chapter detail fetch did 175
   sequential inserts outside a transaction → `ChaptersDao.upsertAll`
   (single transaction). Live-verified: 175 chapters land whole.
4. **Genre-mode + source-chip inconsistency.** Toggling a chip while in
   genre mode silently kept genre results; now it leaves genre view and
   filters the latest feed (genre is bound to one source by definition).
   Controller unit tests added (genre toggle, clear, retry, loadMore).
5. **Empty state had no retry** when ALL sources fail — added retry
   button (Plan/08 "never a blank error page").
6. **Status-filter honesty.** Status chips were selectable no-ops on
   browse listings (no status until a detail fetch); the sheet now says
   when they engage. Tags likewise (populated lazily from details).
7. **browse_repo.dart was 500 lines** (rule: ~400) — pure grouping/
   filter logic split into `data/repo/browse_merge.dart`; browse_repo
   re-exports it so callers keep one import path.
8. `_genreTermFrom` catch narrowed `on Object` → `on Exception`.

Also this pass:
- **Per-chapter source chips (user decision 2026-10-17, extends L2):**
  every chapter row will show which sites carry it + a "read from which
  site" picker. Data primitive shipped now
  (`ChaptersDao.sourcesForNumber`, epsilon match); UI lands in Phase 6 —
  spec recorded as a dated addendum at the top of Plan/09.
- Hard-rule greps re-verified: Dio only in safe_http; no hardcoded user
  strings; deps exactly plan + url_launcher.
- adb gotcha for DB checks: `input tap` coords from a uiautomator dump
  of a PREVIOUS sheet/layout are stale — dump and tap in the same
  session (cost one false-negative live check this pass).

## Phase 6 (2026-10-17) — series detail

- **แชร์ลิงก์ → คัดลอกลิงก์.** Doc 09's ⋯ menu lists "share link"; the
  allowed dependency table has no share plugin (`share_plus` would need a
  rule-5 note for a 2-line feature). Clipboard copy ships instead — revisit
  if a share dep ever gets approved.
- **ผสานเรื่อง (manual merge) deferred to Phase 9** per its own doc (12 §4);
  the menu item is not shown yet.
- **Series-row creation is now shared.** BrowseRepo.addToLibrary and the
  browse-card → detail open both go through `SeriesRepo.upsertFromDetail`
  (identity order: (source,url) link → title-norm → `raw:` escape). Semantics
  unchanged; existing browse_repo tests still pass.
- **Widget-test ffi drains:** any detail action that writes through
  sqflite_common_ffi (mark read, openReader's byId) needs
  `tester.runAsync(() => Future.delayed(...))` before asserting — same rule
  as the Phase 5 history write.
- **Tab index moved to `tabIndexProvider`** so detail tag chips can pop to
  the root and switch to Browse (doc 09 §4). Browse filters remain
  session-only; tag enforcement on listings is still an honest no-op until
  listing data carries tags.

## Phase 7 (2026-10-17) — webtoon reader

- **Widget tests: wrap platform-channel calls.** wakelock_plus has no
  handler in unit tests (invokeMethod returns null → parse error →
  unhandled async exception). WakelockPlus/SystemChrome calls in
  ReaderScreen go through try/catch helpers (`_setAwake`, `_setImmersive`).
- **safe_http DNS validation runs BEFORE the injectable fetcher** — test
  URLs must use resolvable hosts (`www.example.com` works,
  `img.example.com` does not).
- **Scroll math is pure** (`reader_progress.dart`): slot offsets = prefix
  sums of slot heights; current page = first slot bottom past the 40%
  viewport line; heights come from chapter_pages dims when known, else
  the 1.9× estimate (doc 10), corrected in place as images load.
- Chapter switching is `pushReplacement` — the new ReaderScreen reloads
  everything (scroll reset per doc 10 §6).
- reading_history upsert stays in Phase 9 (15-BUILD-ORDER); completion
  currently writes read_progress + library.last_read_*.

## Phase 8 part 1 (2026-10-17) — paged + novel readers

- extended_image 10.1: zoom state is read via `extendedImageGestureKey` →
  `ExtendedImageGestureState.gestureDetails.totalScale` (there is no
  `.scale` on GestureDetails; 0/1 means unzoomed → tap zones active).
- Flutter 3.47: `RadioListTile` groupValue/onChanged deprecated in favor
  of the `RadioGroup<T>` ancestor widget; ListView's `cacheExtent` →
  `scrollCacheExtent: ScrollCacheExtent.pixels(...)` (rendering import).
- Novel novels have no cross-source fallback (single-source by nature);
  loadNovelText rejects empty text as a parse bug per doc 06 §3.

## Phase 8 part 2 (2026-10-17) — Nekopost probing findings

- **Novels are NOT a separate API.** detail2 + cinfo serve them with the
  manga shapes; projectType m/c/d = comics, f/n = novels. The keiyoushi
  extension dropped novels entirely — our novel support is original work
  (doc 06 addendum §4 records it).
- `/handler/cinfo` is OUTSIDE /api (the web bundle calls
  `{www}/api/handler/cinfo` → 404; keiyoushi's `{www}/handler/cinfo`
  works).
- Latest feed: type "m" only returns comics; novels need type "f"
  (translated) / "n" (original) — adapter merges m+f per page.
- detail2 dead ids answer HTTP 200 with the string
  `"sql: no rows in result set"` — always type-check the decoded body.
- dio `Options` has no data field: SafeHttp.postJson carries the body in
  `Options.extra['safe_http_body']` and the default transport switches to
  `dio.post` on method=POST. Fetcher fakes read the extra map.
- Nekopost genres: categories exist but no server-side genre filter —
  browse-by-genre is unsupported for this source (picker shows nothing).
- keiyoushi reference moved to `keiyoushi/extensions-source`
  (`src/th/nekopost/`, not `lib/src/...` as doc 06 guessed).

## Post-Phase-8 review pass (big model, 2026-10-17)

Bugs found + fixed (all regression-tested):

1. **Dead action buttons on browse→detail.** The detail controller is a
   family keyed -1 for browse entry, but the action row / sort toggle /
   chapter sheet read `detailControllerProvider(vm.series.id)` — a
   different, empty controller. Library toggle, sort, mark-read, download
   actions all silently no-op'd on that path. The screen's family key is
   now threaded through every child (`controllerKey`).
2. **Reader never resumed** (doc 10/11 DoD). Webtoon now jump-restores the
   saved page after layout; paged creates its PageController with
   `initialPage` from progress; novel restores scroll by percent AND
   evaluates end-of-chapter state once for chapters that fit one screen
   (no scroll events ever fired there — the end button and completion
   never triggered).
3. **Double download of the first screens.** Seed-prefetch and the slot's
   own build both resolved the same pages, and the pipeline dedups only
   AFTER downloading → 2× network per early page. Per-screen inflight memo
   (successes cached for the chapter, failures evicted so retry works).
4. **Fallback re-downloaded forever.** resolvePage's sibling fallback
   never checked the sibling's cached page and never wrote the hash back
   to the ORIGINAL chapter row — every reopen re-triggered the failing
   fetch + a fresh download. Now: sibling disk-first, resolved hash
   persisted onto the requested chapter (next open = plain cache hit).
5. **upsertFromDetail clobbered existing series metadata.** Same title on
   a new URL went through upsertByTitleNorm's wholesale row UPDATE — a new
   source with null description/status erased the union'd values, and tags
   were REPLACED instead of unioned. Identity chain now: (source,url) link
   → title-norm lookup (no overwrite; merge-only) → insert. Tags union.
6. **continueTarget replayed a finished chapter.** A completed
   last_read_chapter_id reopened its last page; Continue now falls through
   to the first unread number.
7. **Nekopost cold-open violated by the rate limiter.** osemocphoto hosts
   were strict-class (700 ms/page ≈ 18 s per chapter); now image-class
   (4 concurrent / 200 ms), same as the other sites' CDNs.
8. **AES decrypt was ~86M iterations per chapter** (inverse S-box was a
   256-iteration linear search per byte) — replaced with a 256-entry table
   built once.

Improvements: stale-source refresh on detail open now parallel (was
serial ×source-count); alt titles deduped across mirrors; latest-feed
dedupe by URL string (not hashCode); `_Cover` blob-row future cached in
state (was a DB read per setState); webtoon prefetch-ahead is now actually
driven by the `reader_prefetch_ahead` setting (page-change kicks N pages
through the memo) — previously only the fixed 2500 px cacheExtent did any
prefetching and the settings slider did nothing.

## Phase 9 (2026-10-17) — Library + History

- **Doc-12 collation erratum.** The spec's parenthetical "Latin titles sort
  after Thai automatically (higher codepoints)" is inverted: Thai block
  (U+0E00–U+0E7F) codepoints are HIGHER than Latin's, so under the spec's
  own algorithm (strip marks → collapse → lowercase → codepoint compare)
  lowercase Latin sorts BEFORE Thai. The exact spec algorithm is implemented
  as written; only the parenthetical was wrong. Thai A–Z reads correctly
  (tone marks ่ ้ ๊ ๋ and ็ ์ ํ never reorder consonants — covered by
  test/thai_collation_test.dart).
- New-chapter badge follows the doc-13 rule exactly: count of chapters with
  `uploaded_at > library.last_read_at` (regardless of completion).
- Merge/split transactions live in `LibraryRepo` (series_repo.dart was
  already over the 400-line budget). Merge conflict rule: an absorbed
  chapter whose (source, number) already exists on the target is DROPPED —
  its progress/history cascade away, which is the right semantics for a
  duplicate. Split keeps progress/history because they key off chapter ids;
  the standalone row gets an escape `title_norm` when its display title
  equals the parent's (same pattern as upsertFromDetail).
- History write path centralized: `ui/reader/reader_actions.dart
  persistReaderProgress` is the ONE place readers touch read_progress +
  library + reading_history (doc 12 §5: history upserts at the same moment
  completed=1 is set). Detail long-press mark-read uses the same moment.
- History tab refreshes on shell tab re-entry (IndexedStack keeps it alive);
  covers render cache-only (never refetch over network).
- Widget-test gotcha added to the pile: the shell test's pumpAndSettle now
  times out because the real Library/History screens show indeterminate
  progress spinners while their ffi-isolate loads pend under FakeAsync —
  drain-loop + pump instead.

## Phase 10 (2026-10-17) — Downloads + Offline + updates

- **connectivity_plus resolved to 7.3.2**, not the doc-era 6.x: wakelock_plus
  1.8.1 pins dbus ^0.8.0, and connectivity_plus <7.3.2 needs dbus ^0.7.0 —
  pub itself suggested ^7.3.2. API used is unchanged (checkConnectivity).
- The queue engine REUSES the reader's fetch path (ReaderRepo.fetchPage /
  loadNovelText) instead of a second pipeline caller: downloads share the
  2-slot politeness pool, the dedup pipeline, and hash/dims persistence for
  free. `chapter_pages.bytes` is now persisted there too (was write-only
  schema) — the download sheet's size estimate uses real sizes once pages
  exist, 8 MB/chapter default before that.
- Offline-tab truthfulness is enforced twice: `CacheJanitor
  .demoteBrokenDownloads` (startup integrity pass deletes `done` rows with
  neither intact page blobs nor chapter_text) AND `DownloadsRepo
  .readyOffline()` joining through `blobs` so a half-broken row can never
  render between runs.
- Updates feed treats `updates_last_seen = 0` (never opened) as an EMPTY
  feed — otherwise a fresh install lights the bell with every chapter the
  sites ever published. checkAll gates: 6 h run-gate + per-link fetched_at
  gate; force bypasses both (pull-to-refresh).
- Retry bookkeeping (3 strikes + doubling backoff) is in-memory in the
  worker — the v1 worker dies with the app, matching the doc's
  "no background service" note shown in the Offline tab.
- **Test infra:** sqflite_common arms a 10 s transaction-lock watchdog per
  transaction. The shell's newer DB readers (library/offline/updates) can
  leave one queued under FakeAsync at teardown → "A Timer is still
  pending". helpers.openTestDb now sets `sqflite_utils.lockWarningDuration
  = null` (dev-logging only; sqflite_common added to dev_dependencies for
  the import).

## Phase 11 (2026-10-17) — Settings + polish + release

- `sourcesProvider` is now a `StateNotifierProvider` over a
  `SourcesController` so the Settings switches / reorder / connection-test
  re-emit the live registry (doc 14 DoD: a disabled source leaves browse,
  search and the reader fallback chain immediately). Tests override it
  with `overrideWith((ref) => SourcesController(fakes))` — the old
  `overrideWithValue` no longer type-checks by design.
- `loadSources(db, http, {onlyEnabled})` gained a flag so the Settings
  screen can build instances of DISABLED sources for the
  "ทดสอบการเชื่อมต่อ" button.
- The global reader-mode default (`reader_mode_default`, doc 14) now
  actually participates: `effectiveModeOverride(perSeries, globalDefault)`
  resolves per-series override → global default → type default. Previously
  the setting existed but nothing read it.
- `CacheJanitor.clearUnpinned()` for the settings button; the readout adds
  the SQLite file size (`File(db.path).stat()`).
- Launcher icon: hand-rolled star-on-dark PNGs generated into every
  `mipmap-*` (pure-python zlib writer, no new dependency —
  flutter_launcher_icons deliberately NOT added, rule 5). Label was
  already "Star Codex" from the scaffold.
- Release: `flutter build apk --release` green (58.9 MB); icon tree-shaken.
  On-phone DoD items (cold-open, RAM, airplane re-read, quota round-trip
  on device) stay deliberately unchecked until the user's emulator/phone
  session.

## Post-Phase-11 review pass (big model, 2026-10-18)

Bugs found and fixed (Phases 9-11):

1. **Downloads of un-opened chapters were silently useless.** The worker
   fetched `source.pages()` directly and wrote hashes via setPageHash —
   which targets `chapter_pages` rows that DON'T EXIST until a chapter is
   opened in the reader. Blobs landed unlinked; the done row demoted at
   the next integrity pass. (Tests had masked it by pre-seeding page
   rows.) The worker is now DB-first like the reader and persists the
   page list (+ page_count) before fetching.
2. **times_read inflated ~10x.** The readers persist completed=1 every
   500 ms while the user sits at the chapter end; every save bumped
   times_read. Guard: recordCompletion compares against the PREVIOUS
   HISTORY row's read_at (< 60 s = same session, no bump; none yet or
   older = bump). Comparing against read_progress instead eats the FIRST
   completion too — the reader stamps it milliseconds earlier.
3. **Merge could die on the chapters FK.** Step 4 copied the absorbed
   library row's last_read_chapter_id verbatim; when that chapter was a
   dropped duplicate the UPDATE violated the FK and rolled the whole
   merge back. The id is now verified to have survived ON the primary.
4. **Offline tab re-queried ready-offline every second.** Every worker
   tick emitted a fresh snapshot (new list identity) and the tab's
   listener re-ran its grouped query. Idle ticks no longer refresh at
   all, and identical snapshots are suppressed by an equality gate
   (wifiPaused/pinnedBytes/rows by chapterId+state+pagesDone+error).
5. **Library card cover referer could come from the wrong source** (the
   first link donated its referer even when a later link supplied the
   cover URL). Now paired with the supplying link.
6. **"N ตอนใหม่" badge double-counted mirror copies** of the same new
   chapter; now distinct chapter numbers.
7. **Download sheet was empty when the primary link has no chapters
   yet** (lazy probed link) — falls back to the first non-empty source.
8. **Novel downloads estimated at 8 MB/chapter** (quota over-refusal
   ~100x); novels now estimate 64 KB and the estimate is one query.
9. updates reload ran feed() twice; delete-sheet button reused the
   "ดาวน์โหลด N ตอน" label; dead updateAge helper removed.

Improvements: queued download rows are now pauseable; error-row resume
gets a fresh retry budget (queued-row resume keeps the strikes so the
backoff skip can't reset them); Settings source tile restructured
(switch on the row, icons below) to avoid narrow-screen overflow;
readers now stamp read_progress.read_at on completion.

Regression tests added: un-opened-chapter download, times_read spam
guard, merge-with-dropped-last-read, badge dedupe across mirrors, cover
referer pairing, novel estimate. 165 tests green.

## On-device QA (2026-10-18) � running findings

- **Riverpod scope crash, browse  detail (fixed, a3a1c75).** Opening any
  detail screen from a browse card red-screened with "dependencies were
  overridden but the provider is not": the push site overrode
  detailGroupProvider(-1) in a nested ProviderScope while
  detailControllerProvider (family, no dependencies declared) watched it �
  riverpod 2.6 asserts exactly this shape. Fixed by keying the controller
  family on a DetailKey (id / group identity) and dropping the nested
  scope entirely. dependencies: alone did NOT satisfy the assert.
  Test-env corollary: series_sources.source_id FKs the seeded sources
  table � fake sources in tests must use a seeded id (slow-manga etc.).
- **flutter_image_compress rejects 0-sized targets (fixed).** The
  pipeline's "no resize" passed minWidth: 0, minHeight: 0  the plugin
  threw CompressError(unknown): width and height must be > 0 for EVERY
  image  every blob silently stored as ORIGINAL bytes (.jpg), so no WebP
  q80 rewrite ever happened on-device. "No resize" now passes the parsed
  original dimensions; unknown dims skip compression. On-device re-verify
  after fix: fresh fetches land .webp (RIFF/WEBP magic), debug-gated
  IMGCOMP logs instrument the fallback. Per-page shrink remains the
  compress_test measurement (?58%, Docs/README).
- Left as-is: racing a fast programmatic slider jump to the very end can fire auto-next before the ~500ms completed-save tick lands, so the completed chapter restarts at the top on a later manual reopen (read row was page/0). Slow-scroll path saves completed=1 correctly; the DB truth never regressed, only the pill-vs-save ordering.
- **Android insertWithOnConflict(IGNORE) returns -1, the ffi test shim returns 0 (fixed, Bug #5).** TagsDao.getOrCreate / setForSeries treated any non-zero insert result as a rowid; on Android an ignored-conflict insert answers -1, so the first genuinely NEW tag name produced series_tags(tag_id=-1) -> FOREIGN KEY constraint failed -> every novel/manga detail with novel tags died with the generic error panel. Fix: only id > 0 is a rowid, otherwise fall back to the by-name lookup. Tests could not catch this: the sqflite ffi shim answers 0 on ignored conflicts (decision: no brittle -1 mock; on-device QA is the guard).
- **Live nekopost cinfo page items use INT pageNo + fileName key (fixed, Bug #6).** Real decrypted payload shape: {"pageNo":1,"fileName":"84749_..._1.jpg","width":2281,"height":1616} - pageNo is an int (fixture had it as string), pageName does not exist. The old `page['pageNo'] as String?` sort and `pageName ?? fileName` map cast threw TypeError on every image chapter, killing the candidate. Fix: _pageNo via double.tryParse('${page['pageNo']}'), _fileName prefers non-empty fileName then legacy pageName; empty file names keep the parse-throw path. width/height are free extra metadata (future polish).
- **Paged reader had NO fail-path UI (fixed, Bug #7).** manga-type chapters (incl. all nekopost image projects) route to PagedReaderScreen; its _open() catch swallowed errors into an eternal spinner + "1/0" chrome while webtoon/novel readers failed gracefully. Root cause of the "reader fail path never surfaces error panel" hunt: QA had analyzed the webtoon screen, but the mounted screen was the paged one. Fix mirrors the webtoon reader: _failed flag + error title + retry; regression test paged_reader_fail_test.dart (suite 167). Lesson recorded: confirm WHICH screen a route actually mounts before reading its code for a UI bug.

## On-device QA (2026-10-18, completion session) - findings + environment facts

- **Library tab went stale after a detail add/remove (fixed, Bug #8).** The
  bottom shell keeps all tabs mounted, so LibraryScreen.initState's one-shot
  load() never re-ran; DetailController.toggleLibrary wrote the DB but the
  card only appeared after an app restart. Fix: onLibraryChanged hook on
  DetailController, wired from the provider to
  libraryControllerProvider.load() - matching the controller's own
  "write through to the DB and reload" contract. Regression test
  library_refresh_test.dart (suite 168). Live-verified both directions.
- **Browse catalog has no offline fallback.** Under airplane mode the
  home catalog grid shows "no results" even though series rows exist in
  the DB - the grid renders only live-fetched latest lists. Acceptable
  for v1; a cached-catalog mode would be the polish.
- **reading_history rows appear only after a progress tick.** Opening a
  chapter and viewing page 1 without paging writes no history row (the
  completed/progress save path is the single write point). Do not use
  history presence as a "was this chapter opened" probe.
- **img-to-device coordinate rule misses.** The x1.2 rule (900x2000
  screenshots -> 1080x2400 device) is necessary but not sufficient:
  IconButton hit targets are smaller than they look (the search-field X
  swallowed a tap that "looked" centered), and one tap during a
  keyboard-dismiss relayout landed on the pre-relayout geometry. Rule
  that now works: screencap AFTER every layout-changing event, re-derive
  coordinates from the LATEST shot, and verify destructive/one-shot taps
  with an immediate screencap or DB read.
- **uiautomator dump on Flutter: bounds yes, text no.** Dumps list nodes
  with correct bounds but Flutter semantics expose almost no text
  content; use it for geometry only (the PNG-size trick or a screencap
  still judges content).
- **PNG size is a binary signal.** Byte-identical sizes between two
  screencaps = the frame did not change (caught a wedged ANR dialog and
  a not-yet-loaded screen without burning vision reads on every step).
- **Nekopost file host is osemocphoto.** Chapter image URLs serve from
  the osemocphoto host (not www.nekopost.net); the cinfo API host is
  what airplane-mode DNS-failured on in the Bug #7 log chain.
- **Nekopost novels get origin=''** (originForType covers manga kinds
  only) - carried from the known-issues register; tab filters unaffected.
- **adb push target paths under Git Bash need MSYS_NO_PATHCONV=1**, or
  /data/local/tmp/... gets rewritten to C:/Program Files/Git/data/...
  and the push fails with secure_mkdirs.
- **Emulator under a busy host (games running).** scripts/boot-emu-low.bat
  boots headless with a thread-affinity pin + BelowNormal priority and
  2048 MB guest. 2 pinned threads: boots, but SystemUI ANR-loops under
  UI driving (its own dialog becomes untappable). 4 pinned threads +
  BelowNormal: stable working floor; still strictly leftover CPU. The
  qemu process can be killed outright by host memory pressure (it
  happened once) - userdata-qemu.img survives, so just re-run the
  script. While an ANR dialog is wedged, `adb shell am broadcast -a
  android.intent.action.CLOSE_SYSTEM_DIALOGS` dismisses it without
  needing SystemUI's input pipeline.

## Release signing (v1.0.0 baseline, 2026-10-18)

- Release APKs are now signed with a dedicated keystore: certificate
  "CN=Star Codex, OU=Personal, O=DotJumpDot, C=TH", cert SHA-256
  c2e2b7ac4eff2f82f06731654e9af04ad9bd1f2329f3bd548637f9d552a0228b.
  Keystore + password live OUTSIDE the repo at
  %USERPROFILE%\.android\star-codex-release.jks and
  star-codex-key.properties (never committed; build.gradle.kts reads the
  properties via USERPROFILE and falls back to debug signing when the
  file is absent, so clean checkouts still build). .properties files:
  use FORWARD slashes in storeFile - java.util.Properties eats single
  backslashes as escapes (gradle then resolves a mangled relative path).
- BACK UP the keystore + key.properties (password manager + a copy off
  this machine). Losing it = every future release can no longer update
  over installed v1.0.0+ devices.
- Devices that had debug-signed test builds must uninstall first
  (signature mismatch).
- Releases go to GitHub Releases via gh (GH_TOKEN from git credential
  manager). Old releases are never auto-deleted; the "Latest" label just
  moves.
- Release asset naming: attach as StarCodex-<version>.apk (copy/rename
- the build output before gh release upload), not app-release.apk.

## v1.1.0 UX overhaul decisions (2026-10-18, user-requested batch)

- **Theme registry** (`core/theme/app_themes.dart`): 20 `StarThemeSpec`s,
  hand-picked primary/background per theme; component scheme derived via
  `ColorScheme.fromSeed` + explicit surface-container steps (lighter on
  dark, darker on light). Setting `theme` stores the spec id; legacy
  v1 values `dark`/`black`/`light` migrate in `themeById()` at runtime
  (no DB rewrite). `themeMode` is pinned to dark with a complete
  `ThemeData` per spec so the platform brightness can never fight the
  palette. Monokai/Monokai Night/Monokai Dark Soda/Sakura palettes come
  from CometStream `frontend/src/index.css`.
- **Fonts** (`core/theme/app_fonts.dart`): Google Fonts runtime only (no
  new deps, no assets). Setting `ui_font`; latin-only families are labeled
  in the picker (Thai renders with the fallback font per-glyph).
- **Shell**: bottom NavigationBar GONE. Left `NavigationDrawer` + per-tab
  `starAppBar` (hamburger opens the SHELL's Scaffold via
  `shellScaffoldKeyProvider` — inner tab Scaffolds shadow it otherwise).
  Edge-swipe gated by `nav_edge_swipe` (default OFF, user request).
  Search = `searchOpenProvider` overlay sliding from the top right over
  every tab; submit jumps to Browse + runs the merged search.
- **Browse enrichment**: listing payloads carry no status/tags/timestamps,
  so `BrowseRepo.enrichGroups` joins materialized series rows (by
  primary-title norm) AFTER the page renders — fire-and-forget from
  `BrowseController._enrichInBackground`, then a `copyWith()` re-emit
  mutates the same `SearchGroup` instances in place. Never await it in
  the fetch path: widget tests (FakeAsync) hang on the DB round-trips.
  `filterGroups` now enforces status/tags/type off the enriched fields —
  honest for any visited/added series.
- **Detail**: chapter tab bar replaced by a site-switch `PopupMenuButton`
  in the action row (more list height, user request); the selected source
  id lives in `_DetailBodyState`. `SeriesRepo.ensureSeries` now links ALL
  group members up-front (skip links owned by another series) — fixes
  "second site disappears after opening a merged card". Chapter sort
  default flipped to newest-first: `chapter_sort_<id>` now means
  `'asc'` = oldest (legacy rows were only ever `'desc'`, which now reads
  as the new default — no migration needed).
- **Readers**: one `ReaderControlDrawer` (endDrawer, drag-open disabled)
  holds slider/prev/next/picker + the full settings panel
  (`reader_settings_body.dart` replaces the old bottom sheet). The chrome
  menu button MUST open the drawer via a `GlobalKey<ScaffoldState>` —
  `Scaffold.of(context)` from the screen's own build context cannot find
  the Scaffold (it's below that context) and silently dead-ends.
- **Pull-to-continue** (`pull_next.dart`): replaces the 3 s countdown
  everywhere. Overscroll notifications accumulate into `PullNextTracker`
  (sqrt resistance, 130 px threshold webtoon/novel, 100 px paged); commit
  happens on `ScrollEndNotification` when armed. The next chapter is
  resolved lazily ONCE at the end (`_ensureNext`, re-entrancy guarded) so
  the pill knows "no next chapter" vs "keep pulling".
- **History-on-open**: `persistReaderProgress` upserts reading_history on
  EVERY throttled save (500 ms), not only completions;
  HistoryDao's ±60 s same-session guard keeps times_read sane.
- **Madara covers**: `_bestCoverUrl` prefers `data-src`/`data-lazy-src`
  over `src` and skips `data:`/svg placeholders — lazy tiles otherwise
  yield blank or WRONG-site covers (dark-manga/slow-manga QA).
- **DB v2**: one-time UPDATE moving untouched `total_quota_bytes`
  100 GB → 20 GB default (explicit user values survive). Defaults now
  5 GB cache / 20 GB downloads with numeric ±/input GB fields.
- **Merge/split hidden**: setting `hide_merge_split` (default ON) removes
  ผสานเรื่อง/แยกเรื่อง from the detail ⋯ menu (user finds them
  unnecessary but "nice to have").
- Reader pages/streaming behavior (doc 10/11 semantics: prefetch, resume,
  fallback) are untouched — only the chrome moved.

## New sources + detail compaction 2 (2026-10-18, second user batch)

- **bully-manga.com is NOT Madara** — custom static site. Dedicated
  `BullyMangaSource` (data/sources/bully/): listing `/genres/all[/<page>]`
  (`div.mc-card`, cover in `img.mc-img[data-src]`, type from
  `/static/images/<type>.svg`, chapter hint from first `.mc-ep-num`),
  search `/search?keyword=<q>` (filter out `-ep\d+$` chapter slugs the
  site's index also returns), detail via JSON-LD `ComicSeries` +
  `a.sh-genre` tags + `sh-badge-type`/`sh-badge-status` text badges +
  full `a.sh-ep` chapter rows (`data-title` = number; note the CTA
  anchors `sh-btn-read/latest` share ep hrefs but carry NO data-title —
  that's why the parser keys on data-title), pages from the chapter
  page's `IMAGE_MAP = [...]` JS array, relative Thai chapter stamps
  ("N สัปดาห์") parsed to epoch ms. Fixtures under test/fixtures/
  trimmed from the live pages.
- **fin-manga.com IS the ts theme** → plain MadaraSiteConfig
  (seriesUnderMangaPrefix false, search works — verified live; a
  zero-hit query renders CSS-only hits, don't be fooled when probing).
- **db v3**: `case 2:` inserts the two new source rows (INSERT OR
  IGNORE). Dart switch cases do NOT fall through — `case 1:` ends with
  `continue next;` chained into `next: case 2:` so v1→v3 upgrades run
  BOTH migrations (round-trip tested in db_test).
- **Detail compaction 2**: เรื่องย่อ toggle lives in the hero under the
  chips (IntroductionToggle, 2-line truncated snippet so the hero stays
  within cover height); the full text slides open below the action row
  (IntroductionExpansion + AnimatedSize). The chapter search field +
  sort arrow moved onto the vacated row — ChapterList is a bare list
  receiving `query` from the detail body.
- On-device visual QA of the new sources + this layout is DELIBERATELY
  deferred to the next (vision-capable) session per the user.

## v1.1.0 era invariants (2026-10-18/19, UX rounds + release)

- **Covers**: slow-manga serves AVIF uploads (Flutter has no decoder, no
  server negotiation) and 404 WP thumbnails (sized AND full-size gone).
  `_bestCoverUrl` (madara) + `_cleanUrl` (bully) skip `.avif`;
  `CoverThumb(url, referer, fallbacks)` walks sized → un-suffixed
  full-size → sibling sites' covers and never fetches avif/svg/data:.
  `SearchGroup.dbCoverUrl` (from enrichGroups) is the card's last resort
  after cross-probe links a site whose listing wasn't in the feed.
- **Background materialization** (`BrowseRepo.materializeIncompleteGroups`):
  cards with `needsMaterialization` (no date or no renderable cover) get
  the open-card path run budgeted (8/call, session-memoized by primary
  URL), re-enriching just the finished card. Enrichment looks up the
  series row by the tile norm THEN its `latinOnlyNorm` (solo bully cards
  with Thai-suffixed titles materialize under the Latin norm).
- **Probe Latin retry** (`SeriesRepo._probeMatches` +
  `latinOnlyNorm(raw)`, < 12 chars → null): "English title + Thai
  subtitle" listings link to the series after full-title bands fail.
  Linking-only — browse card merging keeps the strict bands (sequels
  like "Solo Leveling Ragnarok" stay in the similar band and refuse).
- **db v4**: `library.last_seen_at` (visit stamp, 0 = pre-v4 "never
  visited" treated as NULL). New chip = chapters with uploaded_at >
  max(last_read_at, last_seen_at); never-read/visited ⇒ ALL dated
  chapters are new; stamped in `_buildVm` AFTER the stale-link refresh.
  New-chipped cards partition to the top of every library sort.
- **Nekopost list rows**: `listChapter` carries `chapterNo` (STRING) +
  `releaseDate`; `listProject` carries `noChapter` + `updateDate.String`
  (sql-null struct) → `SourceSeries.lastUpdatedMs`
  (SearchGroup prefers the DB stamp, falls back to listing stamps).
- **History grouping** (`history_group_series`, default on):
  `collapseBySeries` → one row per series, min–max range, tap resumes
  latest read, long-press deletes the series' whole history.
- **Thai status wording**: UI shows กำลังแปล; the raw site value
  กำลังเข้า remains mapped in bully `_normalizeStatus` (it is a site
  string, not UI text).
- **Release v1.1.0** (tag on 3989c44): 1.1.0+3, release-signed APK
  `StarCodex-1.1.0.apk`, English notes with SHA-256; gh authenticated
  via the PAT from `git credential fill` (no interactive login here).

## Doujin (18+) scope + site-filter race (2026-10-19, third user batch)

- **Adult sources are scoped, not merged**: `adultSourceIds` in
  source_registry = {ntr-manga, doujin-lc, hentaithai, miku-doujin}.
  The MAIN `browseControllerProvider` is constructed with
  `allowedSourceIds` = non-adult ids, and `adultBrowseControllerProvider`
  with the adult set — "all" in either scope means only that scope
  (`_effectiveSourceIds`; an out-of-scope-only selection resolves to the
  `__no_source__` sentinel, NEVER to "all sources" because the repo
  treats an empty set as no filter). BrowseScreen takes `adult: true`,
  filters its site sheet + filter sheet through the scoped provider, and
  the search overlay routes by current tab (tab 5 = adult). Never add an
  adult source to the main feed — the user explicitly wants them on a
  separate page.
- **Site-filter race**: every chip toggle fired an UNGUARDED `_replace`;
  an older fetch finishing last overwrote the newer filter's results
  ("select bully → Done → feed flips back to slow-manga"). Fix:
  `_fetchSeq` monotonic sequence — `_replace`/`loadMore` capture it and
  DROP superseded completions (regression test with a first-call-delayed
  FakeSource). The sheet queues toggles on a 300 ms debounce and flushes
  on Done AND on dispose (outside-tap close must not drop changes).
- **doujin-lc = CLASSIC Madara**, not ts: config `classicLayout: true` +
  `archivePath: 'doujin'`. Archive rows are `.page-item-detail` (a stray
  `.c-tabs-item` wrapper spans the WHOLE listing panel — never select
  it); search rows are `.row.c-tabs-item__content`; union selector +
  URL-dedupe covers both. Detail: `.post-title h1`,
  `.post-content_item` label/value (Status/Type), `.genres-content a`,
  `li.wp-manga-chapter a` (date span often INSIDE the anchor — stripped
  from the label). Pages: `.reading-content img` with data-src (base64
  svg placeholders in src are filtered).
- **miku-doujin / hentaithai are one-shot engines**: series page IS the
  reader → detail() returns exactly ONE chapter whose URL is the series
  URL; pages() scrapes inline imgs (miku `#manga-content img[data-src]`,
  hentaithai `img` filtered to host *.hentaithai.net + path /thai/).
  hentaithai URLs come protocol-relative with mixed case
  (`//HentaiThai.net/t51996`) — normalized through Uri (host
  lowercasing). Neither has native search (miku ignores ?s=;
  hentaithai uses a Google CSE form) — search() throws notFound, browse
  via latest()/genres. hentaithai homepage feed is single-page
  (latest(page>1) = []).

## 2026-10-19 — Doujin QA round: Cloudflare fingerprint block + reader invariants

- **Cloudflare TLS-fingerprint blocking is REAL and unfixable in-app**
  (miku-doujin + doujin-lc): their WAF returns an "Attention Required!"
  403 for Dart's TLS stack while EVERY browser/curl request passes —
  probed UA variants (mobile/desktop/no-header), Accept on/off,
  HTTP/1.1, `www.` and apex hosts, plain `http://` (301s back). Windows
  curl passes because it links Schannel (browser-like fingerprint);
  dart:io cannot shape its ClientHello. If a future session is tempted
  to "fix the 403": it is not headers, not UA, not the URL. Both
  adapters are correct (fixture-tested) and seed DISABLED (db v6,
  `_seededDisabled`); users can re-enable in Settings. hentaithai, by
  contrast, works fine — it merely EMBEDS Cloudflare's benign
  `challenge-platform/scripts/jsd/main.js` snippet on normal pages,
  which the old challenge sniff false-positived on. The sniff now lives
  in `source_api.looksLikeCloudflarePage` (shared by all 5 adapters) and
  only reacts to actual challenge/block bodies (`Just a moment`,
  `Attention Required`, `_cf_chl_opt`, `cf-browser-verification`) — do
  NOT re-add bare `challenge-platform` to it.
- **db v6** (append-only): `UPDATE sources SET enabled = 0 WHERE id IN
  ('doujin-lc','miku-doujin') AND enabled = 1`. Fresh seeds insert them
  with enabled 0. Settings live-registry count is now 9 (was 11).
- **Reader mode flips apply LIVE**: `replaceWithResolvedReader`
  (reader_router.dart) re-resolves `reader_mode_<id>` after a drawer
  change and pushReplaces the route when the resolved screen differs;
  each reader saves progress first (webtoon `_atEnd`/paged last-page/
  novel ≥97% completion preserved) so the swap resumes in place. A
  no-op when the resolution lands on the same screen (e.g. manga +
  'paged' while already paged).
- **Paged reader memoizes page futures** (`_inflight`, webtoon parity):
  PageView disposes off-screen slot State, so without the memo every
  turn — including going BACK — re-resolved and flashed a spinner.
  `_prefetchFrom(page)` queues `reader_prefetch_ahead` pages ahead on
  every page change; failures are evicted so Retry still works.
- **Doujin 18+ is drawer index 1** (under ค้นหา), Settings index 5 —
  `shell._pages`, `app_drawer`, and `search_overlay.adultTab` must move
  together. NTR-manga listing tiles carry NO date markup at all (only
  chapter + rating); card dates come exclusively from background
  materialization (budget raised 8→12), so they fill a few per refresh.

## 2026-10-19 — Site-sheet rows + OLED theme family

- **Site sheet = one row per site** (source_filter.dart): leading
  `_SelectDot` (the ONLY thing that changes on toggle — rows are
  full-width and never resize), `SourceDot` identity color, name, then
  display-only type pills from `sourceContentTypes` (source_palette.dart
  — a hint map, NOT a filter; sources can carry more). Labels use
  `browse.type_short.*` (the compact มังงะ/นิยาย family — `browse.type.*`
  is the long "มังงะญี่ปุ่น" set used by the filter sheet). List capped
  at 50% screen height with its own scroll; long-press → genre browser
  unchanged; debounce/Done/drop-on-dispose unchanged.
- **OLED themes** (`oled_white|red|orange|pink|green` in starThemes):
  accent + true #000 bg AND `surface: #000000` — the StarThemeSpec
  default surface (0xFF26262B) is the READER background and would glow
  grey against an OLED scaffold; always override it for black themes.

## 2026-10-19 — Webtoon scroll-anchor invariant

- **Height corrections above the viewport MUST re-anchor the scroll
  offset.** Lazy slots hold a 1.9× width estimate until decoded; slots
  ABOVE the viewport only decode when you scroll BACK UP into them
  (below-viewport pages load after you pass them, which is why
  scrolling down was always smooth). When such a slot's real height
  replaces the estimate, everything below shifts — mid-drag that reads
  as "stuck then jumps" (worst after resuming mid-chapter: everything
  above the resume point is unmeasured). Fix: `heightAnchorDelta`
  (reader_progress.dart) returns the resize delta only when the slot is
  ENTIRELY above the viewport top; the reader shifts the offset by it
  post-frame (after the extent updates, so the clamp is against the new
  max). Straddling slots take the one-time small shift.
- `PageSlot` no longer clears the memory cache on dispose (same fix as
  the paged reader): scroll-back re-decodes caused placeholder flashes;
  `cacheWidth` keeps entries small and the framework LRU evicts.

## 2026-10-20 — Browse sort orders (filter sheet)

- `BrowseSortOrder` (browse_merge.dart): latestUpdate (DEFAULT — the one
  deliberate exception to L1 "defaults OFF"; the list opens
  newest-update first per user request 2026-10-20), oldestUpdate,
  chaptersDesc, chaptersAsc. Session-only like every other filter.
- `sortGroups` is STABLE by original position (never trust List.sort
  with ties — enrichment re-emits would shuffle undated cards) and puts
  unknown-key groups (no date yet / no chapter hint) LAST in BOTH
  directions — an unknown must never claim newest/oldest/most/fewest.
  It runs on the filtered view in browse_screen, never re-fetches;
  infinite-scroll pages interleave by key, they don't append.
- "Popular" is intentionally absent: probed 2026-10-20 — slow-manga
  search returns identical tile order with `m_orderby=views` and
  `order=popular` (the ts theme ignores ordering params on `/?s=`;
  archive byte-diffs were nonces), and no source (nekopost included)
  exposes view counts. Nothing honest to sort by.

## 2026-10-20 — Search-card dates: direct row→card write; merges carry enrichment

- A ts search tile carries NO date; the only source of a browse card's
  last-update stamp is the materialize pass (detail → chapters'
  uploaded_at → series_sources.last_updated_at). That pass was
  budget-capped (12 fetches/refresh over the first 40 groups): fine for
  scoped feeds, hopeless for big searches (user report: Overgeared
  cards dateless while the detail page showed every chapter stamp).
  The DETAIL fetch is now unbudgeted — one sequential fetch per
  incomplete card, persisted, session-memoized (once ever); `budget`
  (still 12) caps only the cross-source probe.
- NEVER attach enrichment by title-norm lookup when the row id is
  already known: materialize calls `_applyRowToGroup(g, row)` directly.
  Tile norms and row norms legitimately diverge — each site's Thai
  subtitle differs ("จ้าวนักสู้กระทันที" vs "จ้าวแห่งยุทธภัณฑ์"),
  "(Remake)" is stripped from the row norm, and latinOnlyNorm needs
  ≥12 chars so short Latin titles have no fallback. enrichGroups' norm
  path stays only for cards whose rows predate the session.
- mergeIntoGroups/mergeGroupLists rebuild every existing group as a
  fresh SearchGroup; `_carryEnrichment` copies the db* fields across,
  or the next infinite-scroll page erased all earlier cards' dates.

## 2026-10-20 — Reader smoothness invariants + backfill concurrency

- Image cache: `PaintingBinding.instance.imageCache.maximumSizeBytes =
  300 MiB` in main(). Framework default 100 MiB holds only ~8–12
  decoded webtoon pages, so scrolling back up evicted and re-decoded
  pages the user had JUST seen (spinner flash). OS memory-pressure
  still clears the whole cache, so the larger cap is safe.
- The reader screen keeps a per-chapter `_pageFiles` memo and passes
  each slot `initial:` — a slot REBUILT after dispose must render its
  image on frame one. FutureBuilder without initialData flashes the
  placeholder even when the file is already on disk.
- Height fix-ups: when the anchor correction's target offset fits the
  CURRENT extent, jump the offset BEFORE `setState` of the new height —
  the relayout frame then sees height+offset together (zero shifted
  frames). Post-frame jump remains only for the grow-the-extent case.
  Unknown-dim slots estimate from the chapter's OBSERVED average aspect
  after 3 resolved pages (`observedAspect`), not the flat 1.9 constant
  — fin-manga strips run far taller and the constant compounded every
  correction into visible shake (user report, ch.1 first read).
- `materializeIncompleteGroups` runs 6 concurrent workers. The
  pending/memo registration happens UP FRONT (before workers start), so
  overlapping callers can't double-fetch. Sequential dating was ~1
  card/second — big searches only ever filled their first 30–40 cards
  (user report). safe_http's per-host limiter stays the politeness gate.
- hentaithai series stayed undated after a full pass (0/5 links) —
  either its detail fetches fail or its pages expose no parseable
  chapter stamps. Probe before assuming either.

## 2026-10-20 — Cover disk cache: blob_urls index (db v7)

- `ImagePipeline.fetchAndStore` MUST download before its content-hash
  dedup fires (hash is of the original bytes). Reader pages never
  notice — chapter_pages answers by URL first — but covers went through
  the SESSION-only CoverCache, so every app start re-downloaded every
  cover to dedupe against itself (user report 2026-10-20).
- `fetchAndStoreIndexed(url)` (covers only; CoverCache + the
  series.cover_hash detail path): checks blob_urls → disk hit with
  LRU touch; miss (first fetch OR LRU-evicted blob — store.exists
  checks row AND file) → fetchAndStore + upsert the index row. Reader
  pages stay on plain fetchAndStore.
- Staleness tradeoff accepted: a site replacing a cover AT THE SAME URL
  serves the indexed copy forever. WP uploads change filename on
  change, so this is near-zero risk; revisit only if a source is
  observed reusing URLs for new content.
- `orphanHashes` is DEAD CODE (nothing calls it — the janitor's
  integrity pass only drops rows-without-files) but its query now keeps
  blob_urls-referenced blobs; any future orphan sweep must too:
  series.cover_hash pins only the DETAIL cover, listing-tile covers
  live solely in the URL index.

## 2026-10-21 — Oversized-page slicing + popular feed + offline catalog

- **GPU band slicing**: pages taller than `ImagePipeline.gpuBandThreshold`
  (8192) CANNOT render as one image — Android's max texture size is
  commonly 16384 (slow-manga serves 800×25049 strips → black void; the
  14373px ones passed, which is why only some chapters broke). The
  native slicer (`star_codex/image_slice` channel in MainActivity,
  BitmapRegionDecoder) returns ≤4096-px JPEG bands; they persist in
  `page_bands` (db v8) keyed by the PARENT blob hash → sliced once
  forever (unless size-evicted: band-file check per row, re-slice
  self-heals). Both readers render bands stacked; the slot's layout
  height still comes from the PARENT dims, so anchoring math is
  unchanged. Cached pages fetched before dims were stored (null
  height) skip slicing until their next refetch. The WebP compressor
  returning EMPTY for these images is the same size limit — the
  pipeline already falls back to storing the original.
- **Popular feed**: `Source.latest(popular:)` — honored only by the
  madara archive (`order=popular`, probed: genuinely different list);
  every other engine accepts-and-ignores. Persisted setting
  `browse_feed_popular`; search/genre never reorder (probed: the ts
  theme ignores ordering params on `/?s=`).
- **Offline catalog**: `_replace` falls back to `repo.cachedCatalog()`
  (series rows + links → SearchGroups, DB-only) ONLY in latest mode
  when every source failed; banner + `state.offline`, endReached (no
  pagination offline). Recovery on next refresh clears it.
- **Slider-jump**: `_goTo`/`_goPrev` in all three readers AWAIT the
  progress write before the route swap.
- **Deferred**: OS-level background downloading needs a foreground
  service (new dep: workmanager/flutter_foreground_task + POST_
  NOTIFICATIONS runtime permission) — must be verified on-device
  before shipping; batch enqueue itself already existed (download
  sheet: unread / next 10 / all / range).

## 2026-10-21 — On-device QA round (feature batch)

- Offline fallback raced: mount fires TWO overlapping `_replace`s; the
  superseded one's fallback attempt returns false (`seq != _fetchSeq`)
  and FELL THROUGH to its stale empty-state emission, clobbering the
  winner's offline catalog (intermittent — order-dependent). Fix: the
  non-fallback emission re-checks `seq != _fetchSeq` after the fallback
  attempt. Verified stable across 3 offline cold starts + recovery.
- ล่าสุด/ยอดนิยม moved into the filter sheet (ลำดับฟีด section) per
  user request — the feed stays clean; the choice persists via
  `browse_feed_popular`.
- Band slicer verified live: slow-manga 800×25049 ch.67 now renders
  (was a solid black void); content flows continuously across band
  boundaries. hentaithai cards show CDN-path dates on-device.

## 2026-10-21 — Sort-section merge + fling-preserving anchors

- ONE ordering section: BrowseSortOrder.popular joins the sort chips;
  `feedPopular` is now derived (filters.sort == popular). setFilters
  special-cases crossing into/out of popular with a full refetch (it is
  a server fetch param, not a view sort); sortGroups returns popular
  groups UNTOUCHED — any client re-sort would erase the servers'
  popularity order. The old ลำดับฟีด section + setFeedPopular are gone;
  `browse_feed_popular` still seeds/persists the choice.
- **jumpTo during ballistic scrolling KILLS the fling** — anchor
  corrections landing mid-fling (late resolvers above the viewport)
  stopped the scroll dead and read as "laggy scrolling". Use
  `ScrollPosition.forcePixels` (protected; framework uses it for
  pointerScroll/nested scrolling — value pre-clamped, lint ignored at
  the one call site) to shift pixels while the activity continues.
- Decode `cacheWidth` must cap at the SOURCE width: decoding an 800px
  strip up to screen width (~1080px on 2.6-2.8dpr phones) costs ~1.7×
  the pixels for zero sharpness — visible fling jank on manhwa.

## 2026-10-21 — Webtoon scroll: band heights + batched fix-ups

- Band slices MUST reserve height from page_bands dims at BUILD time.
  Without an explicit height each ExtendedImage band sizes itself after
  its decode lands — a 7-band page relayouts the Column (and everything
  below it) up to 7 times, all while the user flings. Exact-height
  reserve kills that entirely.
- Height fix-ups batch per frame (_pendingDims + post-frame flush): ONE
  relayout + ONE anchor shift (summed heightAnchorDelta) instead of N
  setStates when several pages resolve in the same frame. The anchor
  shift keeps the forcePixels semantics (pre-clamped, fling continues).
- precacheImage-based decode-ahead is NOT viable with extended_image:
  cacheWidth routes to ExtendedResizeImageProvider (its own obtainKey),
  so a standard ResizeImage precache would double-decode.

## 2026-10-21 — Paged reader decode cap

- _PageSlotPaged had NO cacheWidth: every page decoded at full source
  resolution while PageView (allowImplicitScrolling) keeps ±1 neighbors
  built — three full-res decodes raced every swipe = the "manga mode
  side slide" lag. Cap = min(sourceWidth, 2× screen px): portrait
  pages are width-limited under BoxFit.contain (≤1080 sources decode
  native), wide double-spreads are height-limited AND zoomed — the 2×
  headroom preserves their zoom detail. GestureConfig.inPageView is
  for the package's OWN ExtendedImageGesturePageView — meaningless
  with a standard PageView (checked, not applicable).

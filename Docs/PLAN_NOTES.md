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

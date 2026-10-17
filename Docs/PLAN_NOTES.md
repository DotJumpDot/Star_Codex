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

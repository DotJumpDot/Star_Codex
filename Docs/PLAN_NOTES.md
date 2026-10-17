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

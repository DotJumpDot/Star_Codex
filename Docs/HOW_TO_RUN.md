# How To Run (dev loop)

## Run on the phone with hot reload

```powershell
cd C:\Code\Manga_Reader\app
flutter pub get
flutter run              # picks the connected phone; r = hot reload, R = restart
```

Emulator works too (`flutter emulators`), but real phone is the target —
image scrolling feel and storage behave differently on emulators.

## Scraper smoke-test (no app UI)

After Phase 3 of the build order, sources can be tested from the CLI:

```powershell
cd C:\Code\Manga_Reader\app
dart run tool/verify_sources.dart --source slow-manga
dart run tool/verify_sources.dart --source go-manga
dart run tool/verify_sources.dart --source up-manga
dart run tool/verify_sources.dart --source dark-manga
dart run tool/verify_sources.dart --source nekopost
dart run tool/verify_sources.dart --all
```

It prints: 10 latest series → a search → chapters with parsed numbers →
image URLs (and for nekopost, a novel excerpt). If a site changed, this is
the fastest way to see it.

## Inspecting the app's data on the phone

```powershell
adb shell run-as com.jamej.starcodex ls files/  # db + manga_library (debug builds)
adb shell run-as com.jamej.starcodex du -h files/manga_library
```

Release builds are not run-as-able; rely on the Settings → storage readout.

## Logs

```powershell
flutter logs                     # app logs (print/debugPrint) + crashes
adb logcat -s flutter            # same via adb, survives hot restart
```

## Wiping app data for a fresh start

```powershell
adb shell pm clear com.jamej.starcodex
```

## Analyze / test before committing

```powershell
flutter analyze
flutter test
```

Both must be clean at the end of every plan phase (Plan/15 rules).

## The old compression experiment

`compress_test/` holds the 2026-10-17 one-off WebP benchmark (real chapter
from slow-manga, report.html side-by-side). Safe to delete anytime; the
numbers live in Plan/00-DECISIONS.md.

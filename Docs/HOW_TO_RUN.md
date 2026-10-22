# How To Run (dev loop)

## Run on the phone with hot reload

```powershell
cd C:\Code\StarCodex\app
flutter pub get
flutter run              # picks the connected phone; r = hot reload, R = restart
```

Emulator works too (`flutter emulators`), but real phone is the target —
image scrolling feel and storage behave differently on emulators.

### Booting the emulator

```powershell
scripts\boot-emu.bat          # windowed, full speed — for looking at it yourself
scripts\boot-emu-low.bat      # headless, 2 QEMU threads + BelowNormal priority
```

`boot-emu-low.bat` takes 10–20 minutes to boot (expected, not a hang) —
use it when the host is busy. Both scripts wait for `sys.boot_completed`
and print `BOOTED`.

**A leftover headless qemu holds the AVD lock** — a second launch dies with
"Running multiple emulators". Kill it first:
`taskkill //PID <qemu-pid> //F`.

## Scraper smoke-test (no app UI)

Sources can be tested from the CLI:

```powershell
cd C:\Code\StarCodex\app
dart run tool/verify_sources.dart --source slow-manga
dart run tool/verify_sources.dart --source go-manga
dart run tool/verify_sources.dart --source up-manga
dart run tool/verify_sources.dart --source dark-manga
dart run tool/verify_sources.dart --source fin-manga
dart run tool/verify_sources.dart --source nekopost
dart run tool/verify_sources.dart --all
```

`--all` covers every Madara-family site plus nekopost. The custom
engines (bully, hentaithai, miku) are not in this tool — probe them
through the app.

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

**In Git Bash, never pipe `flutter` output** through `tr`/`grep`/`tail` —
the dart children hold the pipe and the shell hangs. Redirect to a file
instead and read the file:

```bash
flutter.bat test > out.log 2>&1; echo $?
```

The suite is ~11 s warm. If a run takes minutes, something is hanging —
investigate, don't retry blindly. Widget-test gotchas (FakeAsync drains,
one widget test per file, `pumpAndSettle` timeouts) are listed in
[../AGENTS.md](../AGENTS.md).

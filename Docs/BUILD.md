# Manga Reader — Build Guide (Windows PC → Android APK)

One-time setup on this machine, then two commands per build. For the dev
loop see [HOW_TO_RUN.md](./HOW_TO_RUN.md). For what to build, see
[Plan/15-BUILD-ORDER.md](./Plan/15-BUILD-ORDER.md).

## 1. One-time toolchain setup

### Flutter SDK

```powershell
# Option A (recommended): git clone, stays updatable
cd C:\tools   # create if missing: mkdir C:\tools
git clone https://github.com/flutter/flutter.git -b stable
setx PATH "$env:PATH;C:\tools\flutter\bin"   # then RESTART the terminal
flutter doctor
```

(Option B: download the stable zip from flutter.dev and extract to
`C:\tools\flutter`.)

### Android toolchain

Easiest path (installs SDK + platform-tools + a JDK):

1. Install **Android Studio** (default options).
2. Open it once → More Actions → SDK Manager → install the latest
   **Android SDK Platform** + **SDK Platform-Tools** + **SDK Command-line Tools** (if prompted).
3. Accept licenses:

```powershell
flutter doctor --android-licenses   # accept all
```

4. `flutter doctor -v` must show Android toolchain ✓ (NVIDIA/Java issues are
   usually fixed by letting Studio install its bundled JDK).

### Phone setup

Settings → About phone → tap Build number 7× → Developer options → enable
**USB debugging** → plug in via USB → allow the computer when prompted.
Check: `flutter devices` must list the phone.

## 2. Build the release APK

```powershell
cd C:\Code\StarCodex\app
flutter pub get
flutter build apk --release
```

Output: `build\app\outputs\flutter-apk\app-release.apk` (a single fat APK,
arm32+arm64 — fine for personal use; `--split-per-abi` if you want smaller).

## 3. Install on the phone

```powershell
flutter install            # with the phone connected
# or manually:
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

First install: Android will warn "unknown sources" — allow it (personal
sideload, decision D5/D6).

## 4. Version bump policy

Bump `pubspec.yaml` `version: X.Y.Z+NN` before every release build that
leaves your phone's old data in place. SQLite schema migrations key off the
db `version`, not the app version (see Plan/02).

## 5. Gotchas

- **Java version flapping**: if `flutter doctor` complains about JDK, set
  `JAVA_HOME` to Android Studio's bundled jbr (e.g.
  `C:\Program Files\Android\Android Studio\jbr`).
- **Long paths on Windows**: keep the project at `C:\Code\StarCodex`
  (short path) — already the case.
- **Gradle first build is slow** (5–15 min, downloads). Later builds ~1 min.
- **Antivirus can lock `build\`**: if a build fails weirdly, delete
  `app\build` and retry.
- **Do not ship `compress_test/`** — it's the one-off experiment folder; it
  can be deleted at any time.

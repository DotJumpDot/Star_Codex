# Releasing Star Codex

The runbook for cutting a version: bump → build → verify → publish.
Every release follows it exactly — a missed version bump or a
wrong-signed APK is not recoverable once users have installed.

Releases are published on GitHub: https://github.com/DotJumpDot/Star_Codex/releases

## Before you start

- Working tree clean, `main` up to date with origin.
- `flutter analyze` clean and `flutter test` green.
- The release keystore exists at `%USERPROFILE%\.android\star-codex-release.jks`
  with its descriptor `star-codex-key.properties`. **Back this up** — losing
  it means no future release can update over an installed v1.0.0+ device.

## 1. Bump the version — in TWO places

```yaml
# app/pubspec.yaml
version: 1.3.0+15
```

```dart
// app/lib/ui/settings/settings_storage_sources.dart
static const appVersion = '1.3.0';
```

The About screen shows the **hardcoded const**, not the pubspec value.
Bump only the pubspec and the app keeps advertising the old version.

Also add the release line to `CHANGELOG.md` (repo root).

## 2. Build

```bash
cd /c/Code/StarCodex/app
flutter.bat build apk --release > /c/Users/jamej/AppData/Local/Temp/build.log 2>&1
```

> Never pipe `flutter` output through `tr`/`grep`/`tail` in Git Bash — the
> dart children hold the pipe and the shell hangs. Redirect to a file.

Output: `app/build/app/outputs/flutter-apk/app-release.apk`.

## 3. Verify the signature

```bash
"$LOCALAPPDATA/Android/Sdk/build-tools"/36.0.0/apksigner.bat \
  verify --print-certs app/build/app/outputs/flutter-apk/app-release.apk
```

Expect: `CN=Star Codex, OU=Personal, O=DotJumpDot, C=TH`. A debug
signature means the keystore descriptor was not found — the build is
not publishable.

## 4. Stage, hash, and write the notes

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk StarCodex-1.3.0.apk
sha256sum StarCodex-1.3.0.apk
```

Write the release notes to a file **in TEMP** using the Write tool (a
heredoc mangles UTF-8, and the security hook blocks shell-written files).
The notes are English, and must contain:

- What changed (a couple of sentences, user-facing).
- Install steps.
- The warning that a debug-signed build must be uninstalled first.
- The SHA-256 of the APK.

## 5. Commit and push

The release commit is what the tag points at, so commit BEFORE creating
the release.

```bash
git add -A
git commit -m "Release: v1.3.0 — <short title>

- [x] <unit> complete
- [x] <unit> complete
"
git push
```

Never amend a pushed commit — a post-push fix is its own `Fix:` commit.

## 6. Publish

```bash
export GH_TOKEN=$(printf "protocol=https\nhost=github.com\n\n" \
  | git credential fill | grep ^password= | cut -d= -f2)

gh release create v1.3.0 StarCodex-1.3.0.apk \
  --title "Star Codex v1.3.0 — <short title>" \
  --notes-file /c/Users/jamej/AppData/Local/Temp/starcodex-1.3.0-notes.md
```

`gh release create` **creates the tag on the current HEAD** — do not
`git tag` by hand.

The asset MUST be named `StarCodex-<version>.apk` (not
`app-release.apk`); the download link in the README points at that name.

## 7. Clean up

```bash
rm StarCodex-1.3.0.apk
git status
```

The staged APK lives at the repo root and is gitignored (`*.apk`) — but
delete it anyway so it never gets picked up by a stray `git add -A`.
The tree must be clean when you finish.

## 8. Sync the docs

- `README.md` — status line, download link, feature bullets.
- `AGENTS.md` — the released version, the roadmap.
- `Docs/HANDOFF.md` — where things stand, the open items.
- `CHANGELOG.md` — the release entry.
- `Docs/PLAN_NOTES.md` — the invariants this release established.

## Release checklist

- [ ] `pubspec.yaml` version bumped
- [ ] `AboutSection.appVersion` const bumped
- [ ] `flutter analyze` clean, `flutter test` green
- [ ] release APK built
- [ ] `apksigner verify` shows CN=Star Codex
- [ ] SHA-256 recorded
- [ ] English notes written to a temp file
- [ ] release commit pushed
- [ ] `gh release create` succeeded, tag points at the release commit
- [ ] staged APK deleted, tree clean
- [ ] docs synced

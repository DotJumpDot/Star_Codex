# 01 — Project Setup

Create the Flutter project and all foundation code. Target: `C:\Code\StarCodex\app\`
(the repo root stays `C:\Code\StarCodex\` with `Docs/` beside `app/` — the
repo is github.com/DotJumpDot/Star_Codex, decision D7).

## 1. Create project

```powershell
cd C:\Code\StarCodex
flutter create --org com.jamej --project-name star_codex --platforms android app
cd app
```

- Flutter stable channel (≥ 3.24). Run `flutter doctor -v` first; Android
  toolchain must be green before continuing (see [`../BUILD.md`](../BUILD.md)).
- `--platforms android` only: v1 is Android-only (decision D1). Do NOT delete
  the `windows/` capability permanently — a later phase may add it, but do not
  create it now.

## 2. Dependencies

Run these (they resolve to latest compatible versions; majors must match):

```powershell
flutter pub add dio sqflite path path_provider crypto
flutter pub add html flutter_image_compress extended_image
flutter pub add flutter_riverpod shared_preferences google_fonts intl
flutter pub add flutter_localizations --sdk=flutter
```

Expected major versions (if pub resolves something wildly different, stop and note it):

| Package | Major | Used for |
|---|---|---|
| dio | 5.x | HTTP with interceptors |
| sqflite | 2.x | SQLite |
| path / path_provider | 2.x | file paths |
| crypto | 3.x | SHA-256 for content addressing |
| html | 0.15.x | DOM parsing of Madara pages |
| flutter_image_compress | 2.x | native WebP encode (fast, unlike pure-Dart `image`) |
| extended_image | 9–10.x | zoom/crop/large-image image widget |
| flutter_riverpod | 2.x | state management (NO codegen, manual providers only) |
| shared_preferences | 2.x | lightweight settings mirror |
| google_fonts | 6.x | Sarabun (Thai) |
| intl | 0.19.x | date formatting |

**Forbidden:** `drift`, `freezed`, `json_serializable`, `build_runner`,
anything needing code generation. A weaker build pipeline must stay simple.

## 3. Folder structure (create empty dirs now, fill per phase)

```
app/
├── lib/
│   ├── main.dart                    bootstrap: db init, settings load, MaterialApp
│   ├── app.dart                     root widget, NavigationShell, theme
│   ├── core/
│   │   ├── i18n/                    i18n.dart, th.json, en.json (assets)
│   │   ├── theme/                   theme.dart (M3 dark-first), fonts.dart
│   │   ├── utils/                   thai.dart (collation, chapter-number parse),
│   │   │                            title_norm.dart (see 07), misc.dart
│   │   └── net/
│   │       ├── safe_http.dart       host-validated client (04 §2) — ALL requests go through this
│   │       └── rate_limiter.dart    per-host queue (04 §4)
│   ├── data/
│   │   ├── db.dart                  sqflite open + migrations
│   │   ├── dao/                     series_dao.dart, chapters_dao.dart, blobs_dao.dart,
│   │   │                            library_dao.dart, settings_dao.dart, tags_dao.dart
│   │   ├── storage/
│   │   │   ├── blob_store.dart      content-addressed store (03)
│   │   │   ├── image_pipeline.dart  download → hash → WebP (03)
│   │   │   └── cache_janitor.dart   LRU eviction + quota (03)
│   │   ├── sources/
│   │   │   ├── source_api.dart      Source interface + models (04)
│   │   │   ├── madara/              madara_source.dart + per-site configs (05)
│   │   │   └── nekopost/            nekopost_source.dart (06)
│   │   └── repo/                    browse_repo.dart, series_repo.dart, reader_repo.dart,
│   │                                library_repo.dart, updates_repo.dart
│   └── ui/
│       ├── shell/                   bottom-nav shell (Browse / Library / Updates / Settings)
│       ├── browse/                  screens + widgets (08)
│       ├── detail/                  (09)
│       ├── reader/                  webtoon (10), paged + novel (11)
│       ├── library/                 (12)
│       ├── downloads/               (13)
│       └── settings/                (14)
├── assets/i18n/th.json, en.json
├── tool/
│   └── verify_sources.dart          runnable scraper smoke-test (see 15 Phase 3)
├── android/                         default; set app label + icon in Phase 2
└── test/                            one widget/unit test per phase (see 15)
```

## 4. Android manifest & basics (Phase 2 fills icon)

`android/app/src/main/AndroidManifest.xml`:
- Add `<uses-permission android:name="android.permission.INTERNET"/>`.
- `android:label="Star Codex"` on application.
- In `android/app/build.gradle.kts` set `applicationId = "com.jamej.starcodex"`
  (do not keep the generated `com.jamej.star_codex`).
- Keep minSdk as generated **but raise to 23** (flutter_image_compress WebP +
  modern TLS): `defaultConfig { minSdk = 23 }`.
- Target SDK: whatever Flutter generates (do not pin manually).

## 5. i18n

`core/i18n/i18n.dart`: tiny helper — loads `th.json`/`en.json` from assets into
maps; `t(context, 'browse.title')`; language stored in settings (default `th`).
No `gen-l10n`, no ARB — keep it dead simple. Keys are English-ish slugs.
Every user-visible string MUST go through `t()`. Both json files must always
contain the same key set (add a unit test that asserts key parity).

## 6. Theme

- Material 3, `darkTheme` = default with seed `#3A5BC7` (indigo-blue), pure
  black variant (`scaffoldBackground #000000`) selectable in settings later.
- Thai font: `GoogleFonts.sarabun()` applied via `textTheme` (google_fonts
  fetches/caches at runtime; also bundles license note). Titles may use
  `GoogleFonts.prompt()` for headings — optional.
- One `AppTheme` static class; no runtime theme logic in v1 beyond dark/black/light.

## 7. State management convention (Riverpod, manual)

- Providers are plain `StateNotifierProvider` / `FutureProvider` / `StreamProvider`.
- Repositories are provided via `Provider` in `core/providers.dart`.
- Screens consume via `ConsumerWidget` / `ref.watch`.
- **No codegen**, no `@riverpod` annotations, no freezed models — plain classes
  with `const` constructors + `copyWith`.

## 8. Error handling convention

- Every layer throws typed exceptions defined next to the layer:
  `NetException` (core/net), `SourceException` (data/sources),
  `StoreException` (data/storage). UI catches and maps to friendly Thai
  messages + retry buttons. Never swallow silently; never crash a screen —
  use an `AsyncError` state with retry.

## Definition of Done

- [ ] `flutter create` succeeded; `flutter analyze` clean.
- [ ] `flutter pub add` list installed; pubspec matches table above.
- [ ] Folder tree exists as specified (empty dirs with `.gitkeep` or filled files).
- [ ] `flutter run` on device shows the shell with 4 empty tabs and Thai labels.
- [ ] i18n key-parity test passes (`flutter test`).

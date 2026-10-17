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


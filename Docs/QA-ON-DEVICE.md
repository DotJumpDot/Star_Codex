# QA — On-device DoD verification (phases 4-11)

Date: 2026-10-18 · Emulator: Pixel 7 AVD `StarCodex`, API 36, headless
(swiftshader GPU) · Build: release + debug, both rebuilt AFTER the
post-Phase-11 review commit. Emulator numbers are INDICATIVE — the
phone-in-hand session remains the judge for performance DoDs
(AGENTS.md). Screenshots live in [`qa/shots/`](qa/shots/).

## Found & fixed during this pass (chronological)

| # | Symptom on device | Root cause | Fix commit |
|---|---|---|---|
| 1 | Opening ANY series detail from the Browse search/listing flow = red Riverpod error screen ("dependencies were overridden but the provider is not"). Library → detail opens still worked. | `detailControllerProvider` (family, no `dependencies`) watched `detailGroupProvider(-1)`, which the push site overrode in a nested ProviderScope. Riverpod 2.6's dependency verify asserts on exactly this shape. | `a3a1c75` — replaced the nested-override trick with a `DetailKey` (id / group-identity) family key; nested ProviderScope removed; regression test `detail_from_group_widget_test.dart` drives the browse push-site shape end-to-end. |

## Baseline gates (re-run this session)

- `flutter analyze`: **0 issues**.
- `flutter test`: **166 passed** (165 + 1 new regression).
- Emulator first boot + install: OK, no logs errors (only the normal
  "Not starting debugger since process cannot load the jdwp agent").

## Phase 11/15-quick checks

- [x] Cold app start (release, `am start -W`, COLD): **TotalTime 1464 ms**
  (`LaunchState COLD`, WaitTime 1469 ms). Indicative only.
- Browse feed renders merged cards from live sources with per-source
  chips + "คล้ายกับเรื่องอื่น?" similarity hint (shots 01, 02).
- [ ] Full journey on release build (search → 3 readers → badge → download
  → airplane → updates) — below via phase sections.

## Phase 4 — storage engine (deferred on-device items)

- [ ] Viewed pages land as .webp blobs (extension + size vs original).
- [ ] Airplane re-read of a viewed chapter.

## Phase 6 — series detail

- [ ] Source tabs/dots, per-tab chapter swap (≥2 sources).
- [ ] Mark-read instant (no refetch); Continue target correctness.
- [ ] Per-chapter source chips + "อ่านจากเว็บไหน" picker; search-in-chapters.
- [ ] Description collapse + tag chips → browse pre-filtered.

## Phase 7 — webtoon reader

- [ ] Cold-open < 3 s (measured, emulator-indicative).
- [ ] Resume at saved position after reopen.
- [ ] Middle-60% tap toggles chrome; back exits.
- [ ] Auto-next countdown; source fallback under airplane.

## Phase 8 — paged + novel readers

- [ ] Manga series opens paged; tap zones; double-tap zoom; RTL toggle.
- [ ] Novel: Thai text renders; sepia + font-size settings apply; ≥97%
  completes; dwell auto-next.

## Phase 9 — Library + History

- [ ] Category "ทั่วไป" create + assign 2 + filter; นิยาย smart tab; Thai
  A–Z sort; quick filters AND with tab.
- [ ] Merge two duplicates → single entry; split restores.
- [ ] History: 3 chapters across 2 series → newest-first, day groups;
  tap reopens at position; long-press delete; clear-all preserves
  library progress.

## Phase 10 — Downloads / Offline / updates

- [ ] 10-chapter range: sheet estimate, live "n/m หน้า" queue rows, done →
  is_pinned=1, airplane re-read after force-clearing unpinned cache;
  Offline tab truthfulness.
- [ ] Pause/resume/pause-all; airplane mid-download → retry/backoff.
- [ ] Updates: bell badge = card badge, mark-seen.

## Phase 11 — settings + release journey

- [ ] Every setting round-trips (change → force-stop → relaunch).
- [ ] Language flips all strings incl. reader chrome; themes.
- [ ] Source disable → gone from chips/search/fallback instantly.
- [ ] Cache-limit 2 GB janitor + readout ≈ disk.
- [ ] RAM < 150 MB after reading 2+ chapters (dumpsys, indicative).

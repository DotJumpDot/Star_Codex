# QA — On-device DoD verification (phases 4–11) — COMPLETE

> **Historical log (2026-10-18).** It records the v1.0.0-era QA pass and
> its 168-test baseline; the suite has grown a lot since (243 at v1.3.0 —
> see [../CHANGELOG.md](../CHANGELOG.md)). Later QA rounds live in
> [PLAN_NOTES.md](./PLAN_NOTES.md); the current state of the project is in
> [HANDOFF.md](./HANDOFF.md).

Date: 2026-10-18 · Emulator: Pixel 7 AVD `StarCodex`, API 36, headless
(swiftshader GPU) · Builds: debug **and** release, both rebuilt AFTER the
review pass (`4204e9e`) and after this session's Fix commit. Emulator
numbers are INDICATIVE — the phone-in-hand session remains the judge for
performance DoDs (AGENTS.md). Screenshots live under the gitignored
`qa_f/` and `qa_v2/` folders (emulator driving byproducts — deliberately
not in git); the shot numbers in the tables below refer to them
(78–113 are this session's; 01–76 belong to the earlier run recorded in
[`QA-SESSION-PROGRESS.md`](QA-SESSION-PROGRESS.md)).

## Baseline gates (re-run this session)

- `flutter analyze`: **0 issues**.
- `flutter test`: **168 passed** (167 + the new `library_refresh_test`).
- Debug APK rebuilt + installed; release APK rebuilt + installed.

## Verdict table

| Phase | DoD area | Verdict | Evidence |
|---|---|---|---|
| 4 | Viewed pages land as WebP q80 blobs + hash dedup | **PASS** | earlier session: 122 webp vs 48 legacy jpg; per-page shrink `compress_test` |
| 4 | Storage readout / clear-unpinned honesty | **PASS** | quota moved 0.0→0.1 GB in step with bytes (earlier session) |
| 5 | Sources: browse chips, catalogs, search (ASCII reliable) | **PASS** | shots 50–54, 95; offline search degrades gracefully (shot 79) |
| 6 | Series detail: tabs, tags, chapters, mark-read | **PASS** | shots 57, 69, 96; Bug #5 fixed (tags FK) |
| 7 | Readers: paged chrome/tap zones/resume | **PASS** | shots 44–46 + ZONE/PAGED logs; per-slot gesture keys |
| 7 | Readers: webtoon auto-next + edge poller | **PASS** | earlier session strips (`pill*`, `tabs_probe`) |
| 8 | Nekopost adapter live: manga pages + novel text | **PASS** | shot 75 (`LOADCH ok n=43`), shots 70/71 (novel render + 42%) |
| 8 | Reader fail paths surface the error panel | **PASS (confirmed on-device this session)** | shots 97/98 + logcat `PAGED open FAIL` → retry → `LOADCH ok n=29` (Bug #7) |
| 9 | Library: add/remove round-trip without restart | **PASS (fixed + confirmed this session)** | shots 104 (remove), 110 (add); Bug #8 below |
| 9 | History: day groups, tap-to-resume, clear-all | **PASS** | earlier session shots; rows only appear after a progress tick (see env notes) |
| 10 | Downloads: batch, quota, pause/resume, Wi-Fi gate | **PASS** | shots 29–36, DB `state='done'` + `chapter_pages` |
| 10 | Offline tab truthfulness (files on disk) | **PASS** | earlier session; ready group "8 ตอน · 73 MB" |
| 10 | Updates checker + bell feed | **PASS** | bell visible shots 101/110; checker gated 6 h |
| 11 | Settings round-trips (mode/RTL/switches/prefetch) | **PASS** | shots 47–49 incl. cold-restart persistence |
| 11 | Release build + full journey | **PASS (this session)** | shots 111–113 (home → search → detail → reader 1/43 → settings) |
| 11 | Release RAM < 150 MB (indicative) | **PASS** | `dumpsys meminfo`: TOTAL PSS **109 MB** (native 34, java 19.7) after the full journey |
| — | Cold start (release, `am start -W`) | 1464 ms (earlier session, indicative) | — |
| — | Phone-in-hand performance DoDs | **DEFERRED by user** | not an emulator verdict |

## Bugs found & fixed across the QA pass

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | Browse → detail red Riverpod error screen | nested ProviderScope overrode a watched family dependency | `a3a1c75` DetailKey family key |
| 2 | Every blob stored as original jpg (no WebP) | compressor rejected 0-sized "no resize" targets | `7d27343` original dims + identity guard |
| 3 | Webtoon auto-next unreachable / silent skip | end-window + parked-at-end poller missing | `ed89e92` |
| 4 | Paged tap zones intermittently dead | shared GlobalKey across page slots | `92e5221` per-slot gesture keys |
| 5 | New tag names → detail FK crash (`tag_id=-1`) | Android insertWithOnConflict(IGNORE) returns −1, ffi shim returns 0 | `4204e9e` `id > 0` guards |
| 6 | Every nekopost image chapter eternal-spinner | live cinfo payload has int `pageNo` + `fileName` (old casts threw) | `4204e9e` `_pageNo`/`_fileName` |
| 7 | Paged reader: failed open = eternal spinner, no error UI | manga-type chapters route to PagedReaderScreen whose catch had no `_failed` state | `4204e9e` error panel + retry + `paged_reader_fail_test.dart` |
| 8 | **Library tab went stale after detail add/remove** — the card appeared only after an app restart | the shell keeps tabs mounted, so `LibraryScreen.initState`'s one-shot `load()` never re-ran; `DetailController.toggleLibrary` wrote the DB only | `5706d37` — `onLibraryChanged` hook (provider wires it to `libraryControllerProvider.load()`); regression test `library_refresh_test.dart`; verified live (shots 104/110) |

Bug #7 on-device confirmation protocol (this session): airplane ON →
open ตอนที่ 2 (uncached) → DNS-fail chain in logcat (`LOADCH enter
ch=484` → `candidate FAIL … DNS lookup failed` → `all failed` → `PAGED
open FAIL`) and the error panel renders in ~1 s (shot 97, vs shot 76's
eternal spinner pre-fix). Airplane OFF → ลองใหม่ → `NEKO cinfo BYTES
3224` → `pages mapped n=29` → `LOADCH ok src=nekopost n=29` → pages
render (shot 98). Both directions PASS.

## Airplane / offline verdicts

- Search offline: graceful "ไม่พบผลลัพธ์" + per-source fail badges +
  banner; no crash (shot 79).
- Reader offline, uncached chapter: error panel + retry (Bug #7 fix,
  shot 97).
- Reader offline, cached chapter: loads from the DB/blob cache
  (ตอนที่ 1 opens with airplane ON — `chapter_pages` + blobs).
- Browse catalog offline: "ไม่พบผลลัพธ์" — the catalog grid renders only
  live-fetched results; there is no cached-catalog fallback (by design
  for v1; recorded in PLAN_NOTES).

## Session environment record (host busy — user gaming)

The QA ran under a deliberately throttled emulator so the host's game
keeps priority (see `scripts/boot-emu-low.bat`, added this session):

- First boot at 2048 MB guest / 2 pinned threads + BelowNormal: booted
  fine; the qemu process itself died once under host memory pressure
  (userdata survived — the data image persists across `-no-snapshot`).
- At 2 threads the guest SystemUI ANR-looped ("System UI isn't
  responding" would not accept taps). Re-capped to the top 4 threads,
  still BelowNormal → stable. Escape hatch that worked while the dialog
  was wedged: `adb shell am broadcast -a
  android.intent.action.CLOSE_SYSTEM_DIALOGS`.
- Verdict: 2 threads is too starved for UI-driving sessions; 4 slow
  threads + low priority is the working floor on a busy 16-thread host.
  Both caps remain strictly "leftover CPU only".

## Left open

- Phone-in-hand performance DoDs (user-deferred; the only remaining v1
  item).
- Known-issues register (QA-SESSION-PROGRESS §12) carries forward:
  slider-jump vs completed-save ordering, novel `origin=''`,
  slow-slider auto-next edge — none regress DB truth.

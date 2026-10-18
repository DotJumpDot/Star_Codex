# QA Session Progress — On-Device DoD Verification (Phases 4–11)

_Detailed working log, written 2026-10-18 (mid-session, after an interrupted
tool call). This file is the accreted detective story + runbook; the formal
deliverable remains `Docs/QA-ON-DEVICE.md`. **No commit has been pushed** —
user rule: commits allowed locally, push never._

---

## 0. TL;DR status

| Item | Status | Evidence |
|---|---|---|
| Phase 10 downloads (batch, quota, disclaimer, pause/resume) | **PASS** | shots 29–36, DB rows |
| WebP pipeline at real scale | **PASS** | 122 webp vs 48 jpg blobs, DB |
| Phase 11 settings round-trips (mode/RTL/switches/prefetch) | **PASS** | shots 47–49 + cold restarts |
| Paged reader (chrome, tap zones, turns, resume, ring) | **PASS** | shots 44–46, ZONE/PAGED logs |
| Novel reader render + progress + persistence (Phase 8) | **PASS** | shots 69–71, logcat, DB |
| Nekopost image-chapter loads (webtoon, n=43 pages) | **PASS** | shot 75, `LOADCH ok` log |
| Bug #5 tags FK (-1 sentinel) | **FIXED on-device** (committed, review-verified) | tag list renders, §5 |
| Bug #6 nekopost int-payload casts | **FIXED on-device** (committed, review-verified) | n=43 pages, §6 |
| Bug #7 reader fail-path UI (spinner instead of error panel) | **FIXED + regression test** (root cause found in review pass §7; on-device confirm pending) | §7 |
| Release build + RAM < 150 MB | **NOT STARTED this session** | §9 step 4 |
| Phase 9 stragglers (library remove round-trip) | optional | §9 step 5 |
| QA-ON-DEVICE.md + PLAN_NOTES + CHANGELOG + final QA commit | PENDING | §9 steps 6–7 |

**⚠️ Environment right now: the emulator/adbs device is GONE
(`adb` reports no devices). The interrupted command chain may have left the
AVD image with airplane-mode ON. Restart the AVD before anything else.**

## 1. Mission and ground rules

- On-device DoD verification of Phases 4–11 on headless emulator `StarCodex`
  (Pixel 7, API 36), driving UI via adb (the project's "Playwright").
- Preceded by three earlier fixed bugs (#1 riverpod DetailKey, #2 WebP
  pipeline no-op, #3 webtoon auto-next) — all committed locally.
- DoD is not optional; never weaken a check; ~3 failed attempts on one DoD →
  document in `Docs/PLAN_NOTES.md` and move on.
- Commits with `Fix:`/`QA:` style + `- [x]` bodies; **never push**.

## 2. QA driving runbook (what actually worked)

### 2.1 Infrastructure
- Every shell call must re-source `. C:\Code\StarCodex\Docs\qa\qa-env.ps1`
  (adb PATH/session), and shell cwd silently resets between calls — prefix
  file-relative commands with an explicit `cd`.
- Screenshot pipeline: `adb shell screencap -p /sdcard/qa.png` →
  `adb pull … Docs\qa\shots\NN_name.png` → `read` the PNG (vision).
- PNG **size is a usable binary signal** for some screens: reader chrome state
  alternates ~40 K (bars visible) vs ~21 K (bars hidden) on the same page —
  this is how tap-zone bisecting was measured (see §8).
- `flutter.bat test/analyze` output must be redirected to a file, never piped
  (dart children hang the shell) — `> ana_pg.log 2>&1; echo $?`.
- Debug builds numbered: debug9 → debug16 this session side-track; each cycle
  = `flutter build apk --debug` → `adb install -r` → `force-stop` → `logcat -c`
  → `am start -n com.jamej.starcodex/.MainActivity`.

### 2.2 Coordinates (device px; SCREENSHOTS stream at 900×2000 → **device = img × 1.2**)
Several tap misses this session came from mixing the img/device axes —always
multiply. Working recipes:

- Tabs at y=2232: ค้นหา 108 · คลัง 324 · ประวัติ 540 · ออฟไลน์ 756 · ตั้งค่า 972.
- History rows: Nano ตอนที่ 1 (540,634), ตอนที่ 2 (540,823).
- Detail: row 5 ≈ (540,2252); อ่านต่อ button (408–414, 938); chapter detail
  rows ตอนที่ 1 (400,1620), ตอนที่ 2 (400,1793).
- Search: field (546,366) → `input text "<ascii>"` → keyevent 66 (Enter).
  **ASCII queries are the reliable way to reach a specific catalog item**
  ("Nihonkoku" → 2 result cards).
- Browse (ค้นหา tab): source-chip rail at y≈499; one `swipe 700 499 → 150 499`
  reveals the Nekopost chip ≈ (900,499). List scroll drifts between runs —
  **always screencap before tapping a card**, card pixel-heights in the list:
  each card ≈ device 550 px tall.
- Reader settings sheet: ปิด (540,1035); mode rows y ≈ 1245/1371/1497/1623;
  toggles ห้ามปิดหน้าจอ ≈1801, อัตโนมัติถัดไป ≈1948, RTL ≈2095; prefetch slider
  (299–425, 2253–2379).
- Paged reader chrome: กลับ [0,136–126,262], เลือกตอน [954,136], progress ring
  [477,2148], ตอนก่อนหน้า (63,2337), ตอนถัดไป (892,2337), ตั้งค่าตัวอ่าน
  (1017,2337).
- Reader tap zones (paged): left/right ×3-flex outer thirds, middle ×4
  (chrome toggle) — boundaries ≈324/756 confirmed by bisect (§8).

### 2.3 DB inspection (app-owned, no root needed)
```
adb push Docs\qa\q.sql /data/local/tmp/qa.sql
adb shell "run-as com.jamej.starcodex sqlite3 files/manga_reader.db < /data/local/tmp/qa.sql"
```
Schema facts learned (live `.schema` + queries):
- `chapters(series_id, source_id, number, page_count, …)` — `page_count`
  stays NULL until a reader fetch writes rows; great truth-probe for
  "did `pages()` ever complete".
- `chapter_pages(chapter_id, idx, url, content_hash, width, height)` —
  only written via `replacePages` inside `reader_repo._pageList`.
- `chapter_text(chapter_id, text)`; `read_progress(chapter_id, page_index,
  completed, read_at)` — for novels `page_index` stores **scroll percent**
  (doc 11 B), e.g. 36 after ~42% display.
- `blobs(... bytes ... is_pinned ...)` — pin counts and webp-vs-jpg mix are
  how the pipeline DoD was judged.
- `series_sources(series_id, source_id, source_url)` — `nekopost:project:<pid>`
  mapping is the ground truth for "which series did that tap actually open".

### 2.4 Standalone-server probing trick (no rebuild)
To inspect an encrypted upstream payload *without* a rebuild: `curl.exe -s
-X POST -H "Content-Type: application/json" -d '{\"p\":8393,\"c\":84749}'
https://www.nekopost.net/handler/cinfo`, then a throwaway `app/tool/nek_probe.dart`
(`dart run`) importing the real `nekopost_crypto.dart` to decrypt + print raw
items; **delete the tool after** (kept repo clean — it is not in git status).

## 3. Verified DoDs — the detailed record

### 3.1 Phase 10 downloads (shots 29–36)
- Selected 5 chapters in the detail download sheet → started → queue UI shows
  per-chapter progress ("6/8 หน้า", "75%"), pause button → paused row gets ▶ →
  resume finishes. Ready group reads **8 ตอน · 73 MB**.
- Quota readout moved 0.0 → 0.1 GB in step with actual bytes (honesty check).
- Disclaimer line "ดาวน์โหลดทำงานเมื่อแอปเปิดอยู่เท่านั้น" present.
- DB truth: chapters 176/177/178 `state='done'` + full `chapter_pages`
  (25/61/42 rows), then ตอนที่ 4–8; `blobs.is_pinned` 0→128.

### 3.2 WebP pipeline at scale
- After mass fetch: **122 webp** blobs (~104 KB avg) vs **48 legacy jpg**
  (~780 KB avg). Confirms encode/insert/dedup path under load.

### 3.3 Phase 11 reader-settings round-trips (shots 47–49)
- Per-series override (`reader_mode_<seriesId>=paged`) persisted across
  force-stops; reopening ตอนที่ 5 opens the TRUE paged reader, resumes at the
  saved page; 50% ring on chrome.
- RTL ON → cold restart → still ON (shot 49); restored afterward. Mode row
  still หน้าต่อหน้า in the same shot ⇒ multiple keys persisted by one restart.
- ห้ามปิดหน้าจอ/เปิดตอนถัดไปอัตโนมัติ correctly ON; prefetch slider = 6.

### 3.4 Paged reader (shots 44–46, commit `92e5221`)
- Chrome: กลับ / เลือกตอน / ตอนก่อนหน้า / ตอนถัดไป / ตั้งค่าตัวอ่าน / back.
- Middle zone toggles chrome; side zones turn pages — proven by logcat:
  tap (900,1400) → `ZONE RIGHT` + `PAGED tapZone forward=true page=1`, and a
  5-tap alternating stress test all fired with page counters 1↔2.
- Bisect established the live middle span ≈ [320..760] device px = flex 3/4/3
  design. Two ตอนที่-5-wide black pages gave byte-identical frames — a useful
  tool for hidden-UI testing.
- Per-slot gesture keys fixed the shared-GlobalKey defect (see commit).

### 3.5 Novel reader — Phase 8 (shots 69–71)
Journey: search `Nihonkoku` → opened the TRUE novel card (shot 69: badges
**นิยาย · กำลังฉาย**, Nekopost chip, description, tag chips Action … Yuri,
chapter rows "3 บรรทัด" with unread dots) → อ่านต่อ → novel reader:
- Router picked the novel mode from `series.type='novel'` (series 7).
- Logcat: `NEKO cinfo START p=13276 c=142288` → 7832 bytes → DEL/decrypt OK →
  `NEKO novelText keys=[… novelContent] pageTextLen=null novelLen=2082`
  ⇒ the adapter's `pageText ?? novelContent` fallback is CORRECT against live
  data.
- Thai paragraphs render beautifully (shot 70); scroll → **42%** label + ring
  (shot 71); prev/next chapter buttons + slider + gear present.
- Persistence: `chapter_text` 1894 chars for chapter id 524 (—url includes
  142288); `read_progress` `(page_index=36, completed=0)`.

### 3.6 Nekopost image chapters (shot 75)
Post-Bug-#6: search → ตอนที่ 1 of the 'Nihonkoku' mangá (p=8393) → `LOADCH ok
src=nekopost n=43` → cover art renders at หน้า 1/43 in webtoon mode.

## 4. Phase numbering/timeline (logcat anchor points)

| Time (10-18) | Event |
|---|---|
| 05:35 | ZONE prints prove side taps work on fresh build (tap-zone saga closes) |
| 05:44–05:47 | settings round-trips; Browse/neka-post exploration begins |
| 05:47:38 | first novel detail attempt → `DETAIL LOAD FAIL … FK … args [5, -1]` (Bug #5 caught) |
| 05:51–05:59 | tags fix verified (novel detail loads, shot 57); reader endlessly spins on manga chapters (shots 59–67) — later root-caused as Bug #6 |
| 06:09:34 | TRUE novel end-to-end render (shot 70) + heedful persistence |
| 06:15 | LOADCH prints catch the manga failure: `type 'int' is not a subtype of 'String?'` (Bug #6 confirmed) + يدshot 74 |
| 06:18 | live-payload probe via dart script → real cinfo shape |
| 06:19 | Bug #6 fix on-device → n=43 pages render (shot 75) |
| 06:21 | airplane-ON fail-path test (shot 76) → **Bug #7** surfaces |
| ~06:2x | big diagnostic build interrupted; emulator lost |

## 5. Bug #5 — series_tags FK via tag_id = −1 (FIXED, uncommitted)

**Symptom.** Opening ANY detail that carries *new* tag names (first real novel)
showed "เกิดข้อผิดพลาด / ลองใหม่"; retry repeated it. Zero user-visible trace
beyond the panel.

**Discovery.** Added a kDebug print in `detail_controller.load()` catch →
```
DETAIL LOAD FAIL: DatabaseException(FOREIGN KEY constraint failed (code 787
SQLITE_CONSTRAINT_FOREIGNKEY)) sql 'INSERT OR IGNORE INTO series_tags
(series_id, tag_id) VALUES (?, ?)' args [5, -1]
```
Stack pinned `TagsDao.setForSeries` (tags_dao.dart:53).

**Root cause.** Android's `SQLiteDatabase.insertWithOnConflict(IGNORE)`
returns **-1** when the insert is ignored (row exists), not 0. Both
`getOrCreate` and `setForSeries` used `if (id != 0) return id;` → treated −1
as a real rowid → `series_tags(tag_id=-1)` → FK violation. Madara-era series
dodged it only because their second merge produced `union == existing` → no
`setForSeries` call; any genuinely new tag name would die.

**Why 166 tests missed it:** the sqflite ffi test shim answers **0** on
ignored conflicts. A brittle mock of −1 was deemed low-value (same code path
already covered by the 0-branch test); decision: on-device verification +
PLAN_NOTES note instead.

**Fix (both spots):** accept **only `id > 0`** as a rowid; otherwise fall back
to the by-name lookup. Comments added with the QA date.

**On-device verification:** the TRUE novel detail now loads with all 11
category tags (Action/Comedy/Drama/Fantasy/Gender Bender/Isekai/Reincarnate/
Romance/Sci-fi/Second Life/Yuri) → series row 7 + `series_tags` cleaned up.

## 6. Bug #6 — nekopost live cinfo payload kills image chapters (FIXED, uncommitted)

**Symptom.** Every non-novel nekopost chapter opened into "กำลังโหลด…" +
หน้า 1/0 forever (shots 59, 60, 61, 66, 67) — no error panel, no crash.

**Trail.** Instrumented `_cinfo` (START/BYTES/DECODED prints) → decoded OK,
then silence. Everything after in `pages()` was believed synchronous →
contradiction. Standalone dart probe (curl + app's own `decryptCryptoJs`)
on a real 4716-byte payload revealed:
```
keys: [projectId, chapterId, chapterNo, pageItem, pageCount]
items total: 43
item: {"pageNo":1,"fileName":"84749_202009061031_1.jpg","width":2281,"height":1616}
```
→ `pageNo` is an **int**, `pageName` doesn't exist, `fileName` is the real key
(and `width/height` are free extra metadata — polish opportunity).

**Broken code.** Sort comparator `page['pageNo'] as String?` and the URL map
`(page['pageName'] as String?) ?? page['fileName']` → both threw
`TypeError: type 'int' is not a subtype of type 'String?'` (logcat
06:15:19.992 `LOADCH candidate FAIL src=nekopost: …`), the candidate failed,
all-candidates failed, Bug #7 hid the error from the user.

**Fix.** `_pageNo` → `double.tryParse('${page['pageNo']}')`; new `_fileName`
prefers non-empty `fileName`, then legacy `pageName`, else '' → existing
"pageItem missing file names" parse-throw path preserved. Existing fixture
test (`fileName` asserted first, sort by numeric pageNo) still green —
analyze=0, **166/166 tests pass** after the fix.

**On-device verification:** `NEKO pages mapped n=43` → `LOADCH ok n=43` →
cover art renders (shot 75).

## 7. RESOLVED — Bug #7: reader fail path never surfaces the error panel

**Root cause (found statically in the review pass — no extra build needed).**
The failing screens were the **PAGED reader, not the webtoon screen** this
section originally analyzed. Chain: nekopost image projects carry
`type='manga'` (`_typeFor('m')`) → `resolveReaderMode` routes manga →
`PagedReaderScreen` → its `_open()` catch did only
`setState(() => _loaded = null)` with **no `_failed` flag and no error UI**
— its `loaded == null` branch rendered an unconditional
`CircularProgressIndicator` + "กำลังโหลด…". So a failed open (airplane DNS
fail, or the Bug #6 TypeErrors) showed the eternal spinner + หน้า 1/0 that
shots 59–67/74/76 captured. The webtoon (`_failed` + retry) and novel
(`_error` + retry) readers were always correct; hypothesis 2 below
("route/state mismatch — the catch belongs to a different screen") was
exactly right.

**Fix (review-pass commit).** `PagedReaderScreen` now mirrors the webtoon
reader: `_failed` flag, error title + ลองใหม่ retry button in the loading
branch, `kDebug 'PAGED open FAIL'` print in the catch. Regression test
`app/test/paged_reader_fail_test.dart` (FakeSource with a pages()-throws
chapter → expects เกิดข้อผิดพลาด + ลองใหม่, no กำลังโหลด…). 167/167 tests
green, analyze 0. The LOADCH/READER fence prints from §7's hunt are
retained as kDebug diagnostics.

**Remaining for on-device (this session's step 4):** CONFIRM only — the
airplane fail-path protocol should now show the error panel + retry within
~15 s in the paged reader.

Historical hunt notes (why it was missed): `reader_screen._open()`'s catch
was proven correct and its build (lines 307–340) renders the panel — but
that screen was never the one mounted for manga-type chapters. Fence
prints (`LOADCH enter/ok/candidate FAIL/all failed`, `READER open FAIL`)
were added to discriminate; the static read made them confirmation tools
instead.

## 8. The paged tap-zone saga (documented, closed)

- Symptom originally "side taps dead, middle toggles only" — repeatedly
  non-reproducible after cold restarts. Static code was perfectly symmetric
  (Same 3×Expanded + translucent GestureDetector). Empirical bisect proved
  the live middle span = design bounds; fresh-session stress test: 5/5 taps
  fire both sides with correct page turns.
- Conclusion recorded in commit `92e5221`: intermittent stale-session
  artifact, likely arena/history corruption in that old process; per-slot
  `GlobalKey<ExtendedImageGestureState>` fix stands; kDebug ZONE/PAGED prints
  retained as diagnostics. Routing mystery resolved earlier: manhua type
  auto-routes to webtoon — several "dead paged taps" runs were actually the
  webtoon reader where side taps are by design inert.

## 9. Resume checklist (ordered)

0. **Boot the AVD** headless: `emulator -avd StarCodex -no-window
   -no-snapshot -gpu swiftshader_indirect -no-boot-anim -memory 3072`;
   wait boot; `adb devices` sanity. If the host is busy (user gaming),
   use `scripts\boot-emu-low.bat` instead (2-thread cap + BelowNormal,
   guest RAM 2048 — boots in 10–20 min, that is expected).
1. `adb shell cmd connectivity airplane-mode` → expect **Off** (disable if
   ON) — the interrupted airplane test may have left it enabled in userdata.
2. `flutter analyze` → expect 0 (kDebugMode import fixed); re-run tests if
   anything feels off (166 green as of the nekopost fix).
3. Build/install debug16 run (log `build_debug16.log` shows the APK already
   built: `√ Built … app-debug.apk` — install step did NOT reach the device,
   a fresh install is needed after AVD boot).
4. Bug #7 on-device CONFIRM only (root cause + fix + regression test
   landed by the review pass, §7): airplane ON → search `Nihonkoku` →
   ตอนที่ 1 (400,1620) → expect the error panel + ลองใหม่ within ~15 s
   (tap ลองใหม่ with airplane OFF → chapter loads). Do NOT push.
5. Phase 9 straggler (cheap): library add/remove round-trip (add โลกในฝัน →
   คลัง row appears → remove → row gone) + history clear-button if quick.
6. **Release drain**: check `C:\Code\StarCodex\build_rel2.log` finished;
   `flutter build apk --release` if stale; install release; run a full
   journey (home → search → detail → reader → settings → back) + RAM check
   `adb shell dumpsys meminfo com.jamej.starcodex` (phone-in-hand judge →
   label "indicative"); threshold <150 MB.
7. Documentation pass:
   - `Docs/QA-ON-DEVICE.md` — full report, clean out stale TODOs, link shots
     01–76 groups, note Bug #5/#6 with root causes and onward tests, Bug #7
     outcome, RAM verdict, airplane offline verdicts.
   - `Docs/PLAN_NOTES.md` — the on-device QA section: Android-vs-ffi
     insertIgnore return values, live cinfo shapes (int pageNo, fileName
     key, width/height available), osemocphoto file host facts, the ×1.2
     coordinate rule and its misses, Flutter uiautomator text-empty dumps,
     novel origin='' note, don't-mock-−1 decision.
   - `CHANGELOG.md` — one line for the QA session.
8. Final `QA: on-device DoD verification (phases 4-11)` commit (commit only —
   NEVER push), include this progress file and the shots 47–76 in the commit.

## 10. Current repo state (git)

> **Superseded by §13** — the review pass landed Bug #5/#6/#7 (one Fix
> commit, pushed) and this file + shots 47–76 are committed. Snapshot
> below is the historical mid-session record.

Local commit chain (newest first):
```
92e5221 Fix: paged reader per-slot gesture keys + tap-zone diagnostics
ed89e92 Fix: webtoon auto-next unreachable + silent skip when parked at end (doc 10 S6)
7d27343 Fix: webp pipeline no-op (compressor rejected zero-sized targets)
a3a1c75 Fix: riverpod scope crash opening detail from browse (DetailKey refactor)
```
(pushed upstream: `1a91495`)

Uncommitted (verified via `git status --porcelain`):
- `M` Docs/qa/q.sql
- `M` app/lib/data/dao/tags_dao.dart ← Bug #5 fix
- `M` app/lib/data/repo/reader_repo.dart ← LOADCH fence prints
- `M` app/lib/data/sources/nekopost/nekopost_source.dart ← Bug #6 fix + prints
- `M` app/lib/ui/detail/detail_controller.dart ← DETAIL LOAD FAIL print
- `M` app/lib/ui/reader/reader_screen.dart ← READER open FAIL print (+import)
- `??` Docs/QA-SESSION-PROGRESS.md (this file)
- `??` Docs/qa/shots/47…76 (16 new evidence shots; note `77_offline_fail2.png`
  was never captured — the command aborted before the screencap)

## 11. Evidence shot index (this session's additions)

| Shot | Content |
|---|---|
| 44/45/46 | paged chrome on/off + tap-zone bisect (byte-size states) |
| 47/48/49 | settings sheet; RTL ON; RTL still ON after cold restart |
| 50–54 | browse nekopost chip + catalog scroll + novel card layout |
| 55/56 | Bug #5 symptom (detail error + failed retry) |
| 57 | Bug #5 fixed — novel detail with tags/chapters |
| 58–61 | novel-reader open attempts mid-debug (spinner states) |
| 62–68 | browse navigation + wrong-card taps (coordinate lessons) |
| 69 | TRUE novel detail (นิยาย badge, tags, "3 บรรทัด" rows) |
| 70/71 | novel reader text render + 42% scroll |
| 72/73 | search `Nihonkoku` results + series 5 detail rows |
| 74 | Bug #6 fail state (spinner + `LOADCH candidate FAIL` TypeError) |
| 75 | Bug #6 fixed — 43 pages render (cover art) |
| 76 | Bug #7 evidence (airplane-ON spinner persists) |
| pill*/ST_*/tabs_probe | earlier-session auto-next/edge-poller evidence strips |

_build logs: `build_debug9…15.log`, `build_rel2.log` (release background),
`ana_pg.log`, `test_pg.log` at repo root/app dir._

## 12. Known-issues register (carried into PLAN_NOTES)

1. Bug #7 fail-path (open, one build from root cause).
2. Silent-detail on nekopost rate/parse oddities — the app shows the graceful
   error panel (a Phase-4 style win) once Bug #7 is fixed.
3. 50% page-progress ring label is "indicative" only (phone-in-hand judge).
4. Slow slider jump may trigger auto-next before the completed-save tick —
   DB truth never regresses (recorded earlier, re-confirmed).
5. Nekopost novels get `origin=''` (originForType covers manga kinds only) —
   acceptable; tab filters unaffected.
6. Local-only footprint: new series 4–7 are emulator test data (personal-app
   philosophy — fine).

## 13. Big-model review pass over the QA session (2026-10-18)

The interrupted session's work was rechecked end to end; everything below
is committed and **pushed** (user authorized push for the review pass).

Verified sound, no changes needed:
- `a3a1c75` DetailKey refactor — identity-equality group key, ==/hashCode
  consistent, nested scope fully gone, regression test drives the real
  push site.
- `7d27343` WebP no-op fix — original-dims "no resize", `_sameBytes`
  identity guard (a compressor echoing input can no longer store jpg
  bytes under a .webp name), unknown dims skip cleanly.
- `ed89e92` auto-next rule + edge poller — `_maybeAutoNext`'s
  `_countdown != null` guard and 500 ms throttle make the 300 ms poller
  spam-safe; short-content arm-at-0 covered by tests.
- `92e5221` per-slot gesture keys — stale-key reads are safe (disposed
  slots answer currentState null → not zoomed).
- Bug #5 tags `-1` fix and Bug #6 nekopost int-payload fix exactly match
  their root causes; parse-throw path preserved.

Fixed by this pass:
- **Bug #7** (§7): paged reader had NO fail-path UI at all — `_failed`
  flag + error panel + ลองใหม่ retry added, mirroring the webtoon reader;
  `app/test/paged_reader_fail_test.dart` regression test (suite now 167).
- Import hygiene: data-layer `debugPrint` now comes from
  `flutter/foundation.dart`, not `material.dart` (reader_repo,
  nekopost_source, detail_controller).
- PLAN_NOTES/CHANGELOG updated with the three bug root causes.

Suite: analyze 0 issues, 167/167 tests green.

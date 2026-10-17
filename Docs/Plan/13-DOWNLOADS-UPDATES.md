# 13 — Downloads & Chapter Updates

## A. Download manager (pinned downloads — decision R5)

Optional permanence: "download this so it survives cache eviction / works
offline for a trip". NOT required for reading.

### UI

- **Series detail → ดาวน์โหลด button** → bottom sheet:
  - ตอนที่ยังไม่ได้อ่าน (N) / 10 ตอนถัดไป / ทั้งหมด (N) / เลือกเอง (range picker
    from–to + multi-select list)
  - shows estimate: "ประมาณ 62 MB (ประเมินจากค่าเฉลี่ย)" — estimate =
    unfetched chapters × 8 MB default, fetched ones × their real size.
  - Quota check (03) before enqueue; refusal message with remaining GB.
- **Chapter long-press → ดาวน์โหลดตอนนี้** (single).
- **Bottom-nav tab 4 "ออฟไลน์" (Offline)** — two sections:
  1. **พร้อมอ่านออฟไลน์ (Ready offline)** — grouped by series: cover, title +
     original subtitle (L5), "12 ตอน · 148 MB", per-series actions (เลือกลบ
     บางตอน / ลบทั้งหมด). Rows show ONLY chapters with `downloads.state='done'`
     AND blobs still present on disk.
  2. **คิว / กำลังดาวน์โหลด / ล้มเหลว** — queue rows: series cover thumb,
     title, "ตอนที่ 920 · 12/23 หน้า", progress bar, pause/resume per row +
     pause-all. Storage summary header: "ใช้ไป 42.1 GB / 100 GB".

### Truthfulness rule (user requirement: "when cache is cleared this tab should be clean")

- The Offline tab NEVER lists cache — only pinned downloads with existing
  files. The 03 startup integrity pass (blob row missing file → delete row)
  is extended: any `downloads` row in `done` whose chapter has pages with NO
  existing blob → delete the `downloads` row (demote to not-downloaded).
- "ล้างแคช" in settings clears UNPINNED blobs only → Offline tab unaffected
  (downloads are pinned by definition). Explicit delete flows (per series /
  per chapter / ลบไฟล์ทั้งหมดของเรื่องนี้) remove downloads rows + unpin —
  and the tab updates immediately.
- Result: the tab always equals reality on disk, with no refresh tricks.

### Engine

- `downloads` table is the queue. A single foreground `Isolate`-free worker:
  `downloads_repo.tick()` loop driven by a `Timer.periodic(1 s)` while the
  app runs (v1 has NO background service — document this clearly in UI:
  "ดาวน์โหลดทำงานเมื่อแอปเปิดอยู่เท่านั้น").
- Per tick: pick oldest `queued` (respect priority: manual single > range >
  whole-series), set `running`, fetch its pages serially through pipeline
  (03), updating `chapter_pages` rows; on all-pages-done → `state=done`,
  recompute pins (03). Errors → 3 retries with backoff then `state=error`
  + message.
- Pause = move `running`→`paused`; resume re-enqueues.
- **Novels**: download = fetch + store `chapter_text` (instant, no queue UI noise).
- Wi-Fi-only switch in settings (default ON): before starting downloads,
  check connectivity (`connectivity_plus` package); on mobile data → keep
  queue paused with explanatory chip.

## B. Chapter updates checker

"Did any of my series get new chapters?" — replaces site-hopping.

- **Trigger**: app open (if `updates_last_run` > 6 h ago) + pull-to-refresh
  on Updates tab + Library toolbar refresh icon.
- **Method (cheap, polite)**: for each library series × each `series_sources`
  row: fetch the source's series page (05 §4 / 06) — but ONLY if that
  source's `fetched_at` older than 6 h. Madara `latest()` pages are NOT
  sufficient (merged series may not be in latest 500) — the series page
  chapter list is the truth. Rate limiter keeps it gentle (~1.4 req/s/host).
- Diff: new chapters = numbers not in `chapters` for that (series, source).
  Upsert them, set `last_updated_at`, `fetched_at`.
- **Updates feed UI**: bottom-nav does NOT have an updates tab (nav is
  5 tabs, 00 §Navigation). The Library AppBar **bell icon with unread badge**
  opens a full-screen sheet with the merged timeline: "Nano Machine — ตอนที่
  921, 922 (slow-manga, 2 ชม. ที่แล้ว)" rows with cover thumb; tap → open
  reader at that chapter; "อ่านทั้งหมด" per series group. Dismiss-all /
  mark-seen on scroll-out (rows older than last_read get consumed
  automatically).
- Library badges (12) read from the same data: count of chapters with
  `uploaded_at > library.last_read_at`.
- Optional notification: v1 = none (no permission complexity). Note as future.

## C. Cleanup paths (delete flows)

- Delete series download: unpins its chapters' blobs (recompute pins),
  deletes `downloads` rows. Cached-but-unpinned copies may remain until LRU.
- Delete from library: keeps blobs (they're cache-managed), removes `library`
  row + badges. Full "ลบไฟล์ทั้งหมดของเรื่องนี้" choice offered in dialog.

## Definition of Done

- [ ] Download 10-chapter range of a series on Wi-Fi: queue screen shows
  per-chapter page progress, finishes, pins recompute (blob is_pinned=1),
  airplane-mode reading works after cache-janitor forced run.
- [ ] **Offline tab: after deleting a series' downloads (and after simulating
  missing files), the tab no longer lists them — no stale rows. Clearing
  unpinned cache does NOT change the Offline tab.**
- [ ] Pause/resume + pause-all behave; error retry works after toggling
  airplane mode mid-download.
- [ ] Updates: with a series at chapter N in library, after new chapters
  appear upstream, refresh shows them in the Updates tab; badge count on
  library card matches.
- [ ] Wi-Fi-only ON: downloads stay paused on mobile data with visible reason.

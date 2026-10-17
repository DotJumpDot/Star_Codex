# 09 — UI: Series Detail Screen

Opened from browse card or library grid. One screen = one merged series
(all its sources).

## Layout

1. **Header**: cover (left, ~120×170), **Thai title (large, L5)** with
   **`original_title` as a secondary subtitle right below it** (e.g. Thai
   title big, "Nano Machine" smaller; hidden when NULL), alt titles
   (collapsible line), type + origin chips ("Manhwa · เกาหลี" / "Manga ·
   ญี่ปุ่น" / "นิยาย"), status chip, rating if source had one (optional),
   source badges row.
2. **Action row** (sticky-ish below header):
   - **อ่านต่อ (Continue)** — primary filled button: jumps to
     `last_read_chapter_id`, else first unread, else chapter 1. Opens reader
     (10/11) with the series' default mode.
   - **+ เพิ่มในคลัง (Add to library)** / trash icon when already in library.
   - **ดาวน์โหลด (Download)** — opens download sheet (13).
   - **⋯ menu**: หาในเว็บอื่น (re-probe other sources, 07 §3), เปิดในเว็บ
     (url_launcher), แชร์ลิงก์, ผสานเรื่อง (manual merge picker, 12 §4).
3. **Description / Introduction** (collapsible to 4 lines, "อ่านเพิ่ม"
   expander). Merged across sources per 07 §4 (longest non-empty; L7).
   Tiny caption "ข้อมูลจาก slow-manga" naming which source supplied it.
4. **Tags row**: chips — union of genres from ALL sources (tap → browse
   pre-filtered by tag).
5. **Source switcher**: `TabBar` with one tab per `series_sources` member
   (icon + name). Tab shows that source's chapter list. Default tab =
   primary source (07 §4). A banner chip on tabs whose source has MORE
   chapters than primary: "930 ตอน" green.
6. **Chapter list** (per source tab):
   - ListTile: number + raw title, relative upload date (intl Thai locale:
     `timeago`-style via intl `DateFormat`/manual relative), trailing marks:
     ● unread count style dot, ⬇ downloaded mark, ✓ read.
   - Sort toggle: ใหม่ไปเก่า / เก่าไปใหม่ (default: old→new for binging;
     remember per-series last used — settings row `chapter_sort_<seriesId>`).
   - Search-in-chapters field (filters by number/title).
   - Tap chapter → reader. Long-press → sheet: ดาวน์โหลดตอนนี้, ทำเครื่องหมายว่าอ่านแล้ว,
     ทำเครื่องหมายว่ายังไม่อ่าน, ลบไฟล์ที่ดาวน์โหลด (if downloaded).

## Data flow

- `series_repo.load(seriesId)` → `FutureProvider.family` exposing
  `SeriesDetailVm` (series row + sources + per-source chapters + progress
  map). Chapter fetch: if a source's chapters never fetched (`fetched_at`
  null) or older than 12 h → adapter `detail()` refresh, upsert chapters
  (match on `UNIQUE(series_id, source_id, number)`; number-less chapters
  match by title).
- Novels: same screen; reader opens novel mode; download button works the
  same (text is stored in DB — tiny).

## Progress semantics

- A chapter is "read" when `read_progress.completed = 1` (set when user
  reaches last page / taps "จบตอน" / opens next chapter).
- Partial position saved continuously while scrolling (10 §5).

## Definition of Done

- [ ] Series present on ≥2 sources shows tab per source; counts per tab
  differ correctly; switching tabs swaps chapter lists.
- [ ] Continue button opens the exact right chapter in the right reader mode
  (webtoon for manhwa, paged for manga type, novel reader for novels).
- [ ] Long-press mark-read instantly updates dots without refetch.
- [ ] Description collapse/expand and tag chips navigate to browse filtered.

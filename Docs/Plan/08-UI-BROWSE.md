# 08 — UI: Browse / Search Screen

Bottom-nav tab 1 ("ค้นหา" / Browse). This is the front door: search all five
sites at once, merged (07).

## Layout (top → bottom)

1. **Search bar** (TextField, rounded, search icon, history dropdown of last
   10 `search_history` rows). Submit → results below. Debounce-as-you-type is
   NOT wanted (hitting 5 sites per keystroke is rude) — search on submit only.
2. **Source filter row** (horizontal chips): "ทั้งหมด" + one chip per enabled
   source with favicon-ish colored dot. Default: all on. Toggling a chip
   **re-runs the current search/latest feed limited to that site** — this IS
   the per-site tab the user asked for. Long-press a source chip → browse
   that site's genre pages (`/genres/{term}/` on Madara, 05 §3) in a
   full-screen picker that feeds results into the same merged list.
3. **Filter panel** (collapsed behind a tune icon; opens a bottom sheet):
   - ประเภท (type): ทั้งหมด / Manga / Manhwa / Manhua / นิยาย (novel)
   - สถานะ (status): ทั้งหมด / กำลังเข้า / จบแล้ว
   - **จำนวนตอนขั้นต่ำ (min chapters): slider 0–50, DEFAULT 0 = OFF (decision L1)**
   - **ซ่อนเรื่องสั้น/oneshot (hide oneshot): switch, DEFAULT OFF (decision L1)**
   - แท็ก (tags): multi-select chips from `tags` table (populated lazily
     from genres seen on detail pages)
   - Values persist in memory only for the session; do NOT write settings.
4. **Results area**: when no search yet → "อัพเดทล่าสุด" latest feed (lazy
   paged: pull `latest(page)` from all sources in parallel, merged by §7
   grouping, sorted by newest chapter time desc). When searching → grouped
   search results.

## Result card (one per merged group)

```
┌────────┐ Nano Machine                    ┌badges: slow·go·dark·nekopost┐
│ cover  │ มังงะเกาหลี · Action, Sci-Fi     920 ตอน · กำลังเข้า
└────────┘ (tags from primary source)
```
- Cover from primary source (blob-cached, placeholder while loading).
- Source badges: small colored chips, one per `series_sources` member.
- Chapter count = max across sources (from `chapterCountHint`).
- Tap → Series Detail (09). Long-press → quick actions sheet (add to library,
  open on site in browser via url_launcher — add package `url_launcher`).
- If group is a "similar" hint (07 fuzzy 0.88–0.95 band) → tiny "คล้ายกับ
  เรื่องอื่น?" link that expands the similar group inline.

## Behavior details

- Search runs sources in parallel via `Future.wait` on the rate-limited
  `safe_http` (different hosts → fine). Per-source errors → that source's
  chip shows a red dot + toast; results from others still show (never a
  blank error page).
- Empty results → friendly empty state + suggestion to check spelling in
  Thai/English.
- Loading: skeleton shimmer cards (10) not spinners.
- Search history saved on submit (dedupe, keep newest-first, cap 10).
- Pagination of latest feed: infinite scroll, 1 page per source per batch.

## i18n keys (examples)

`browse.title, browse.search_hint, browse.latest, browse.filter.type,
browse.filter.status, browse.filter.min_chapters, browse.filter.hide_oneshot,
browse.empty, browse.sources_error`

## Definition of Done

- [ ] Search "nano machine" shows ONE card per real series, with correct
  multi-source badges (verify ≥2 sources grouped).
- [ ] Filter sheet opens; changing min-chapters slider to 10 hides a known
  short series; defaults are OFF after app restart (decision L1).
- [ ] **Per-site filtering: tapping a single source chip shows results from
  that site only** (search + latest both respect it); long-press opens that
  site's genre browser.
- [ ] Type filter Manhwa/Manhua/Manga/นิยาย filters merged results by
  `series.type` (origin axis, L6).
- [ ] Latest feed scrolls 3+ batches without jank (profile mode ≥ 50 fps).
- [ ] All strings via `t()`; Thai/English toggle flips every label.

# 10 — UI: Webtoon Reader (vertical streaming) — THE CORE SCREEN

Tap chapter → pages stream top-to-bottom like a website (decision R1).
Everything here is about **never showing a blank wait**: placeholders with
correct heights, prefetch ahead, instant fallback.

## Widget tree (concrete — build exactly this)

```
ReaderScreen(chapterId)
├── Scaffold(backgroundColor: black, extendBody: true)
├── Stack
│   ├── NotificationListener<ScrollNotification>      // progress tracking §5
│   │   └── ListView.builder                           // lazy, variable extents
│   │       cacheExtent: 2500 (logical px, ~2 screens ahead)
│   │       itemCount: pages.length (or max(known, estimate 40) while loading list)
│   │       itemBuilder → PageSlot(page)
│   ├── ReaderChrome (top/bottom bars, animated)       // §6
│   └── if loading first page → centered linear progress + "กำลังโหลด..."
```

`PageSlot` logic:
- If blob cached → `ExtendedImage.file(path, fit: BoxFit.fitWidth,
  clearMemoryCacheWhenDispose: true)` wrapped so width = screen width.
- If dims known but blob missing (2nd+ reads) → reserve EXACT height:
  `SizedBox(height: screenWidth / width * height)` + shimmer placeholder +
  trigger fetch.
- If dims unknown (first read) → reserve estimated height
  `screenWidth * 1.9` (observed average ratio from probe data 720:1360) —
  replaced by exact once fetched. This prevents the "jump back" scroll bug.
- On fetch error → error slot with ปุ่มลองใหม่ (retry) + auto source-fallback §7.

## Prefetch (the feel of "like a website")

- `reader_repo` exposes `getPage(chapterId, idx)` returning a `Future` that
  resolves to file path (cache hit) or fetches via pipeline (03 § read path).
- A serial worker queue (max 2 active image fetches) is seeded on open with
  pages [0..5]; as `PageSlot` builds, enqueue `idx + prefetchAhead`
  (setting, default 6) ahead of the **current** page.
- Next-chapter prefetch: when user passes 80% of pages, prefetch chapter
  list info of next chapter (numbers only) and its first 3 pages.
- Chapter page list itself: if `page_count` known, trust it; else the URL
  list fetch (`Source.pages`) runs once on open before rendering slot 0
  (show top progress bar meanwhile).

## Entering/exiting

- Enter: `Navigator.push` with `PageRouteBuilder(opaque: false)` + fade.
- SystemUI: immersive (edge-to-edge), keep-screen-on while reader is open
  (`wakelock_plus` package — add it), brightness left to system (settings
  slider optional later).
- Hero animation from cover is nice-to-have, NOT required.

## Chrome (top/bottom bars) — §6

Tap anywhere (middle 60% of width) toggles chrome visibility (300 ms animation).
- Top bar: back, series title (tap → detail), chapter selector (opens bottom
  sheet: chapter list w/ search, current highlighted), source badge (which
  source is serving right now).
- Bottom bar: page indicator "920.5"? No — for webtoon: "หน้า 12/23" of
  current top-most visible slot; progress bar (draggable → jumps scroll);
  prev/next chapter buttons; settings icon (opens reader settings sheet:
  prefetch count, keep-screen-on, auto-next-chapter switch).
- Auto-next-chapter (default ON): when last page's bottom passes 65% of
  viewport → push next chapter (same reader, scroll reset). Show toast
  "ตอนถัดไปในอีก 3 วิ" with cancel — 3 s countdown.

## Progress tracking — §5

On `ScrollUpdateNotification` (throttle 500 ms):
- current page index = first slot whose extent bottom > scrollOffset + 40%
  viewport height (compute from `ListView` layout delegates or track built
  slot offsets in a map idx→offset while building — the map approach is
  simpler and allowed).
- `read_progress.upsert(chapterId, page_index, completed=false)`.
- Completed: fires when the LAST slot's bottom is within 1 viewport of max
  scroll extent AND user keeps scrolling / auto-next triggers → set
  `completed=1, page_index=last`.

## Source fallback — §7 (uses 07 §5)

Per-page failure path: retry ×3 (04 §5) → try same-number chapter on the
next `series_sources` entry (badge updates "จาก go-manga") → if all fail,
error slot. Chapter-level failure (page list fetch fails): try fallback
source for the whole chapter before showing error.

## Performance rules

- `clearMemoryCacheWhenDispose` on; never keep full decoded chapter in RAM.
- Decode target: images are stored at source resolution (≤ ~1000 px wide);
  `cacheWidth` = screen width × devicePixelRatio rounded — pass to
  ExtendedImage `cacheWidth` so decode matches display.
- Profile in dev: `flutter run --profile`; scrolling a 60-page chapter must
  not exceed ~120 MB RSS.

## Definition of Done

- [ ] Open a 23-page webtoon chapter cold (Wi-Fi): first image visible < 3 s,
  scrolling to bottom without pauses above viewport on 50 Mbps.
- [ ] Airplane mode after a full read-through: reopen → instant, full chapter.
- [ ] Kill switch test: middle 60% tap toggles chrome; back button exits.
- [ ] Progress: reopen chapter from detail → resumes at saved page ± 1.
- [ ] RAM < 150 MB after reading 3 chapters (check via dev overlay).

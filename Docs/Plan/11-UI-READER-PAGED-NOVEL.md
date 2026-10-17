# 11 — UI: Paged Reader (manga) + Novel Reader

Two more reader modes. The webtoon reader (10) is the default for
manhwa/manhua; the paged reader is the default for `type=manga`; the novel
reader for `type=novel`. User can override the mode per series (persisted in
settings key `reader_mode_<seriesId>` ∈ {auto, webtoon, paged}).

## A. Paged reader (horizontal, B&W manga style)

Same shell/chrome/progress/fallback logic as 10 (share `reader_repo`,
chrome widgets, and the Screen wrapper; only the viewport widget differs).

```
PageView.builder(
  scrollDirection: Axis.horizontal,
  reverse: readerRtl,                 // RTL reading option, default OFF
  itemCount: pages,
  itemBuilder -> PageSlotPaged(page)
)
```

`PageSlotPaged`:
- `ExtendedImage.file(path, fit: BoxFit.contain, mode: ExtendedImageMode.gesture,
  clearMemoryCacheWhenDispose: true)` — gesture mode gives double-tap zoom +
  pan for free. On zoom, page-turn taps disabled until back to 1.0 (check
  `ExtendedImageGestureState.gestureConfig.gestureState` or simply gate tap
  handling on scale == 1).
- Tap zones via a `Stack` overlay, active only when scale == 1:
  - left 30% → previous page, right 30% → next page (swap when RTL)
  - middle 40% → toggle chrome.
- Placeholder while loading: blurred previous page or shimmer box
  (BoxFit.contain estimate 2:3 aspect).

Page indicator "12/60" always visible in bottom chrome; slider maps to page
index (webtoon uses scroll extent, paged uses page index — same widget, two
adapters). Chapter transitions: swipe past last page (overscroll) or Next
button → next chapter (auto-advance default ON here too).

## B. Novel reader (nekopost นิยาย)

```
NovelReaderScreen(chapterId)
├── ScrollController-driven Scrollable text
│   └── Padding(horizontal: 20) SelectableText.rich? -> plain SingleChildScrollView+Text
│       style: GoogleFonts.sarabun(fontSize: novel_font_size (14–30, default 18),
│               height: novel_line_height (1.4–2.2, default 1.7),
│               color: theme fg)
│       paragraphs from chapter_text.text.split('\n\n'), first-line indent 1.5em
├── chrome (tap toggle like others)
│   ├── top: title/chapter picker, settings icon
│   └── bottom: progress %, prev/next chapter
└── reader settings sheet: font size stepper, line-height stepper,
    theme: ขาว/น้ำตาลเหลือง (sepia #F5EDDC fg #5B4636)/ดำ — applies to novel reader only
```

- Progress = scroll fraction → `read_progress.page_index` = percent (0–100),
  `completed` at ≥ 97% or next-chapter.
- `chapter_text` loads once from DB; if missing → `Source.novelText()` →
  store → render. Text is small; no blob pipeline.
- End of chapter → "ตอนถัดไป" large button + auto-next after 1.5 s scroll
  dwell (toggleable).

## Shared reader plumbing (implement once)

- `ReaderRouter.open(context, chapterId)` decides mode:
  `series.reader_mode_override ?? (type == manga ? paged : type == novel ? novel : webtoon)`.
- `ReaderChrome`, chapter-switch bottom sheet, countdown auto-next, progress
  persistence, source-fallback — one implementation, parameterized.

## Definition of Done

- [ ] A manga-type chapter (e.g. go-manga Magic Emperor) opens paged; tap
  zones turn pages; double-tap zooms and pan works; RTL toggle flips.
- [ ] A nekopost novel chapter renders Thai text with Sarabun, indent,
  adjustable size/leading; sepia theme applies.
- [ ] Mode override per series persists (set paged on a manhwa → reopens paged).
- [ ] Progress resumes in both modes.

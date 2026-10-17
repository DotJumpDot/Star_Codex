# 12 — UI: Library Screen (categories, sorting, Thai collation)

Bottom-nav tab 2 ("คลังของฉัน"). Shows `library` series only.

## Layout

1. **Category tabs** (horizontal scrollable `TabBar`, default tab = "ทั้งหมด"):
   - Built-ins: ทั้งหมด, กำลังอ่าน (smart: `last_read_at` within 14 d),
     ยังไม่ได้อ่านตอนใหม่ (smart: has chapters newer than last read),
     นิยาย (smart: type=novel), ดาวน์โหลดไว้ (smart: any done download).
   - User categories after a divider, order = `categories.sort`, drag not
     needed v1 (long-press menu: เปลี่ยนชื่อ / ล้างหมวด).
   - "+" chip at end → name dialog → create.
2. **Toolbar row**: search field (filters current tab by title/alt/tags),
   sort dropdown, view toggle (grid/list), filter icon.
3. **Grid** (2–3 columns, responsive): card = cover, title (1 line ellipsis;
   Thai title per L5, original title only on detail screen), badge "3 ตอนใหม่"
   (red) when updates found, progress hairline, downloaded pin icon when any
   download. List view = denser rows with unread count.
   **Library AppBar also carries the updates bell** (badge = new-chapters
   count) opening the updates feed sheet — see 13 §B.
4. Long-press card → multi-select mode: move to category, delete from library
   (ask: เก็บไฟล์ที่ดาวน์โหลดไว้ไหม), remove downloads only.

## Sort options (dropdown)

| key | label | rule |
|---|---|---|
| last_read | อ่านล่าสุด | `library.last_read_at DESC NULLS LAST` |
| updated | อัพเดทล่าสุด | `MAX(chapters.uploaded_at) DESC` |
| added | เพิ่มล่าสุด | `library.added_at DESC` |
| title_az | ชื่อ A–Z | Thai collation §3 ascending |
| unread | ยังไม่อ่านมากสุด | unread count DESC |

Default: last_read. Persist choice in settings `library_sort`.

## Thai title collation (§3) — `core/utils/thai.dart`

Thai Unicode consonants are ALREADY in dictionary order; the problems are
tone marks and above/below vowels comparing before/after wrongly. Practical
v1 algorithm (exact spec — implement this):

```dart
int compareTitlesThai(String a, String b) {
  String key(String s) {
    const toneMarks = '\u0E48\u0E49\u0E4A\u0E4B';   // ่ ้ ๊ ๋
    s = s.replaceAll(RegExp('[$toneMarks]'), '');    // 1) strip tone marks
    s = s.replaceAll('\u0E4D', '\u0E32')             // ไม้หันอากาศ? no — นิคหิต ั ั -> treat ํ as า? keep simple: delete
     ..replaceAll('\u0E4D', '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    return s;
  }
  return key(a).compareTo(key(b));   // codepoint compare on cleaned keys
}
```
Strip tone marks (่ ้ ๊ ๋), strip ็ ์ ํ (non-ordering marks
\u0E47 \u0E4C \u0E4D), collapse spaces, lowercase, then plain codepoint
compare. Latin titles sort after Thai automatically (higher codepoints).
Document the limitation: ำ (\u0E33) and ฤ ฤๅ legacy order may be imperfect —
acceptable v1; do NOT import an ICU collation package.

## Quick filters (toolbar filter icon)

Toggle chips: มีตอนใหม่ / ดาวน์โหลดแล้ว / ตามประเภท (manga/manhwa/manhua/novel) /
ตามแหล่ง (source badges). AND-combined with the active category tab.

## Manual merge (§4 — the escape hatch for imperfect 07)

From multi-select or detail ⋯ menu: pick 2+ series → "ผสานเรื่อง" →
confirmation showing both titles → moves all `series_sources` rows onto the
primary (target = the one user tapped first), unions tags, re-points
`library`/progress rows, deletes the other `series` row in one transaction.
Also "แยกเรื่อง" in detail ⋯ menu: pick a source badge → removes that
`series_sources` row into a new standalone series (for false merges).

## §5 History tab (bottom-nav slot 3 — user requirement)

Chronological "what did I read" list from `reading_history` (02).

- **Layout**: search/filter field (optional) + grouped ListView:
  group headers วันนี้ / เมื่อวาน / วันที่ 17 ต.ค. (intl Thai locale).
  Row: cover thumb (48×68), **series title + original_title subtitle (L5)**,
  "ตอนที่ 920 · เวลา 21:44", trailing chapter-type icon (novel 📄 vs pages 🖼
  — use Material icons, not emoji).
- **Tap row** → reopen that chapter in the reader at saved `read_progress`
  position. Long-press → ลบจากประวัติ (single row).
- **AppBar**: ล้างประวัติทั้งหมด (confirm dialog, wipes `reading_history`
  only — NOT read_progress/library).
- **Write path**: `reader_repo` upserts on chapter completion (same moment
  `completed=1` is set): `read_at = now, times_read + 1` (02 schema).
- Source of truth is `reading_history` — deleted chapters cascade-delete
  their rows, so history never shows ghosts.

## Definition of Done

- [ ] Categories: create "ทั่วไป", assign 2 series, tab filters correctly;
  smart tab นิยาย shows only novels.
- [ ] **History: read 3 chapters across 2 series → tab lists them newest
  first, grouped by day, dual title shown; tap reopens at saved position;
  clear-all works and does not touch library progress.**
- [ ] Sort A–Z on a Thai-titled set reads naturally (ก ข ฃ ค... ไม่กระโดดจาก tone marks).
- [ ] Unread badges reflect new chapters after updates check (13).
- [ ] Manual merge of two duplicates → single entry, both sources' chapters
  visible in detail tabs; un-merge restores two entries with correct
  progress.

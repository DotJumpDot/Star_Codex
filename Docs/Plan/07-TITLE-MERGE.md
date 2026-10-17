# 07 — Title Normalization + Cross-Site Merging (decision L2)

The same series appears on all five sites under slightly different names
("Nano Machine", "นาโน แมชชีน", "Nano Machine (แปลไทย)"). This spec merges
them into ONE library entry.

## 1. `title_norm` — normalization key

`core/utils/title_norm.dart`:

```dart
String normalizeTitle(String raw) {
  var s = raw;
  s = s.normalize(Normalization.nfc);            // NFC (do NOT NFKC-Compat on Thai — keep vowels distinct)
  s = s.toLowerCase();
  // drop common noise tokens (word-boundary, both languages)
  const noise = ['manga','manhwa','manhua','thai','แปลไทย','มังงะ','การ์ตูน','raw','eng','ครั้งแรก'];
  // remove bracketed groups: (…), 【…】, [..]  (scanlator credits etc.)
  s = s.replaceAll(RegExp(r'[(\[【{][^)\]】}]*[)\]】}]'), ' ');
  // keep only Thai consonants/vowels, latin letters, digits, spaces
  s = s.replaceAll(RegExp(r'[^a-z0-9\u0E00-\u0E7F ]'), ' ');
  // collapse Thai spacing variants: remove zero-width & invisible chars already covered; collapse spaces
  s = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  // finally drop noise tokens
  s = s.split(' ').where((w) => !noise.contains(w)).join(' ');
  return s;
}
```

Edge cases to unit-test: `"Nano Machine (แปลไทย)"` → `"nano machine"`;
`"นาโน แมชชีน"` → `"นาโน แมชชีน"` (stays Thai — fine, match via alt titles);
`"SSS-Class Suicide Hunter"` → `"sss-class suicide hunter"` — note the `-`
was stripped to space by the char filter, producing `"sss class suicide hunter"`.
Both sides normalize identically → matches.

## 2. Matching algorithm (used by search-merge and library-add)

```
match(a, b):   // a, b are SourceSeries candidates
  if a.title_norm == b.title_norm -> MERGE (exact)
  if a.title_norm ∈ altNorm(b) or b.title_norm ∈ altNorm(a) -> MERGE (alt)
  jw = jaroWinkler(a.title_norm, b.title_norm)
  if jw >= 0.95 -> MERGE (fuzzy)
  if jw >= 0.88 -> "similar" hint only (shown in UI, never auto-merged)
  else -> separate entries
```

- `altNorm(x)` = normalizeTitle applied to every alt title of x.
- `jaroWinkler` implement in `core/utils/jaro_winkler.dart` (~30 lines,
  standard algorithm; write unit tests against known pairs).
- **Thai vs English titles will NOT fuzzy-match each other** (different
  scripts). That is why alt-title matching is the primary bridge: sites that
  carry the English alt title on the Thai series page get merged through it.
  Nekopost usually lists both. Accept that some Thai-only-named entries stay
  separate — the user can merge manually (12 §4 manual merge).

## 3. Where merging runs

1. **Search results** (`browse_repo`): run all sources' `search()` in
   parallel (rate limiter allows it — different hosts), group results by
   §2 against each other, return groups: each group = one card with
   `List<(sourceId, url, title, chapterCountHint)>`.
2. **Series detail / add-to-library**: after fetching details from the
   opened source, probe OTHER enabled sources with `search(exact title)` +
   alt titles; any §2 match → add `series_sources` row for that source too
   (lazy: fetch that source's detail later/on-demand).
3. **Never re-check on every open** — re-probe on manual "Find on other
   sources" button + during the updates check (13) at most.

## 4. Creating / updating the merged series row

- First sighting → insert `series` (title preference: source title of the
  source with the largest chapter count; prefer a Thai-script title when both
  scripts exist — decision L5 keeps translators' Thai names).
- `type`/`status`/`description`/tags = **union across sources** (first non-null
  in source-sort order; tags = union; description = longest non-empty one,
  because Madara descriptions are often truncated differently per mirror — L7).
- `original_title` pick order (L5):
  1. explicit original-title field from nekopost API if present;
  2. else the first alt title (across all sources, primary first) that is
     majority Latin-script AND `normalizeTitle(alt) != normalizeTitle(title)`;
  3. else NULL (UI simply hides the subtitle).
  Updatable via manual edit (detail screen ⋯ → แก้ไขชื่อเรื่อง/ชื่ออื่น).
- `origin` mapping (L6): Madara type Manga→japan, Manhwa→korea, Manhua→china;
  novels: from source category metadata only (nekopost), else NULL.
- `series.cover_hash` = cover of the current primary source.
- Primary source for reading = max(last_chapter_number), tie → newest
  last_updated_at, tie → user's enabled-source sort order.

## 5. Chapter fallback in reader (uses the merge)

When a page fetch fails for chapter N on source A (network/parse/dead),
`reader_repo` looks for the same series' chapter with `|number - N| < 1e-6`
on the other `series_sources` rows and transparently loads pages from there
(badge in reader UI: "กำลังอ่านจาก go-manga"). Only fail when ALL sources fail.

## 6. Unit tests (must-have pairs)

| a | b | expected |
|---|---|---|
| Nano Machine | nano machine (แปลไทย) | merge exact |
| Nano Machine | นาโน แมชชีน + alt "Nano Machine" | merge alt |
| Lookism | Lukism | no (jw < 0.88... verify ≥ threshold logic) |
| Solo Leveling | Solo Max-Level Newbie | no |
| Overgeared | Overgeared (Novel) | merge (bracket stripped) |

## Definition of Done

- [ ] All §6 unit tests pass.
- [ ] Manual: search "nano machine" → single grouped card showing badges for
  every source that has it; open → detail shows "Available on: …".

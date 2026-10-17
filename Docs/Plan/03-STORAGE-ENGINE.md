# 03 — Storage Engine (content-addressed blob store + image pipeline + LRU)

The storage engine is what makes the app light: every image is stored once
(hash-deduplicated) and compressed (WebP q80). Measured on a real chapter:
15.14 MB → 6.42 MB (−58%).

## Directory layout

Root: `getApplicationSupportDirectory()/manga_library/`

```
manga_library/
└── blobs/ab/abcd3f...webp      2-char shard by hash prefix, filename = <sha256-of-original>.webp
```

`blobs.path` column stores the relative path `blobs/ab/abcd3f….webp`.

## The pipeline (single write path — used by reader cache AND downloads)

`image_pipeline.fetchAndStore(url, referer, {maxWidth}) -> PageResult`:

1. **Fetch** bytes via `safe_http` (04) with the source's Referer + UA.
   Validate: HTTP 200, `content-type` starts with `image/` OR magic bytes are
   JPEG/PNG/WebP/GIF. GIF (site banners/badges) → store as-is, no re-encode.
2. **Hash** the ORIGINAL bytes: `sha256` → `hash`.
3. **Dedup check:** if `blobs` has `hash` and the file exists → bump
   `last_access`, return existing path (no re-encode work).
4. **Compress:** decode → re-encode to WebP quality 80 via
   `flutter_image_compress` (format: `CompressFormat.webp`, quality 80,
   `inSampleSize` 1). If `maxWidth` is set (default null, decision S3) and
   source width > maxWidth → scale down keeping aspect. If compression fails
   (weird format), store original bytes under the same hash name with its
   real extension.
5. **Write** to `blobs/<hash[0:2]>/<hash>.webp`, insert `blobs` row
   (`bytes` = stored size, `is_pinned` = 0, `last_access` = now).
6. Return `{hash, path, width, height, storedBytes}`. Caller (repo) updates
   `chapter_pages` row (`content_hash, width, height, bytes`).

**Crash safety:** write to `path.tmp` then `rename`. A blob row is only
inserted after a successful rename. Startup janitor (below) deletes orphan
files with no DB row.

## Read path (what the reader calls)

`reader_repo.getPage(chapterId, idx) -> (file path or null)`:

- Row lookup in `chapter_pages`:
  - `content_hash != null` **and** blob file exists → serve file (bump
    `last_access`, throttled — max one bump per blob per minute).
  - else → return null; the reader then calls `fetchAndStore` on the URL and
    retries once. This is the "streaming with silent caching" behavior (R1/R2).
- Cover images use the same functions.

## LRU eviction — `cache_janitor`

Runs: (a) 10 s after app start, (b) after every 50 blob writes, (c) from
Settings "clear cache now".

```
target = settings.cache_limit_bytes (default 5 GiB)
unpinnedTotal = SUM(bytes) WHERE is_pinned = 0
if unpinnedTotal <= target: done
rows = SELECT * FROM blobs WHERE is_pinned = 0 ORDER BY last_access ASC
for r in rows while unpinnedTotal > target:
    delete file; delete row; unpinnedTotal -= r.bytes
```

**Never delete pinned blobs.** `is_pinned` maintenance:
- When a chapter download completes → recompute: `UPDATE blobs SET is_pinned =
  1 WHERE hash IN (SELECT content_hash FROM chapter_pages WHERE chapter_id IN
  (SELECT chapter_id FROM downloads WHERE state='done'))`.
- When a download is removed → recompute pinned set the same way (set to 0
  what no longer matches). Single SQL each way; run in a transaction.
- Because of dedup, one blob may serve multiple chapters — the recompute
  handles that naturally.

## Quota (pinned downloads guard — decision S4)

Before enqueuing downloads totalling `incomingBytes` (estimate from
site-average 8 MB/chapter when unknown):

```
pinnedTotal   = SUM(bytes) WHERE is_pinned = 1
if pinnedTotal + incomingBytes > settings.total_quota_bytes (default 100 GiB):
    refuse + show Thai message "พื้นที่ไม่พอ (เหลือ X GB)"
```

Also a hard device check via `path_provider` free space if available
(`StorageStatsManager` is out of scope v1 — quota setting is enough).

## Blob integrity

- `blob_store.exists(hash)` = DB row AND file present.
- Startup janitor pass 2: for DB rows whose file is missing → delete row
  (chapter_pages keeps `content_hash`, so pages re-fetch on next view).
- Orphan files with no row → delete.

## API surface to implement

```dart
class BlobStore   { ensureDir, exists(hash), write(hash, bytes), delete(hash), totalBytes({bool pinned}), pathOf(hash) }
class ImagePipeline { fetchAndStore(url, referer, {int? maxWidth}) -> PageResult }
class CacheJanitor  { runSoon(), runNow(), recomputePins(), enforceQuota(incomingBytes) }
```

All three are singletons provided via Riverpod `Provider`. No UI imports
them directly — only repos.

## Definition of Done

- [ ] Unit test: fetch fake bytes (mock http) → blob written, hash correct,
  second identical fetch hits dedup path (no second file).
- [ ] Unit test: janitor deletes oldest unpinned blob when over limit, never
  pinned ones.
- [ ] Manual on device: open a chapter in reader, check `manga_library/blobs/`
  grows with .webp files whose sizes are ~40% of originals; reopen chapter
  with Wi-Fi off → images still render.

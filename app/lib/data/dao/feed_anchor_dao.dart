import 'package:sqflite/sqflite.dart';

/// `feed_anchors` (db v10, 2026-10-24) — sticky time anchors for the
/// browse feed. fin-manga/dark-manga sit behind a WP-cache + Cloudflare
/// edge that serves the SAME stale copy for 10+ hours (its relative
/// labels still say "2 นาที"); every refetch re-anchored those labels at
/// fetch-now, freezing the feed on a wrong "just updated" age (user
/// report 2026-10-24, mirrored their wording: remember the first-seen
/// time, keep aging it, and only re-anchor when the site actually
/// corrects).
///
/// The rule is pure and unit-tested: when a tile's latest-chapter hint is
/// UNCHANGED since the stored anchor, the chapter hasn't changed — keep
/// the OLDER of the two stamps. A genuinely fresh page's label converges
/// to the same absolute moment (min is a no-op), while a stale copy's
/// re-anchored "2 นาที" (always suspiciously newer) is discarded. A
/// changed or first-seen hint re-anchors at the new stamp.
int stickyStamp({
  required int? storedHint,
  required int? storedStampMs,
  required int? newHint,
  required int newStampMs,
}) {
  if (storedStampMs == null ||
      storedHint == null ||
      newHint == null ||
      storedHint != newHint) {
    return newStampMs;
  }
  return newStampMs < storedStampMs ? newStampMs : storedStampMs;
}

class FeedAnchorRow {
  const FeedAnchorRow({
    required this.chapterHint,
    required this.stampMs,
    required this.updatedAtMs,
  });

  final int? chapterHint;
  final int stampMs;
  final int updatedAtMs;
}

/// Tiny KV-ish store keyed (source_id, series_url). Rows prune on write —
/// the table only serves the visible feed window, so entries older than
/// [pruneAfterMs] are dead weight.
class FeedAnchorDao {
  FeedAnchorDao(this.db);

  final Database db;

  /// ~90 days of staleness before a row stops being worth keeping.
  static const pruneAfterMs = 90 * 24 * 3600 * 1000;

  Future<FeedAnchorRow?> get(String sourceId, String seriesUrl) async {
    final rows = await db.query(
      'feed_anchors',
      where: 'source_id = ? AND series_url = ?',
      whereArgs: [sourceId, seriesUrl],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return FeedAnchorRow(
      chapterHint: r['chapter_hint'] as int?,
      stampMs: r['stamp_ms'] as int,
      updatedAtMs: r['updated_at'] as int,
    );
  }

  Future<void> upsert(
    String sourceId,
    String seriesUrl, {
    required int? chapterHint,
    required int stampMs,
    required int atMs,
  }) async {
    await db.insert(
      'feed_anchors',
      {
        'source_id': sourceId,
        'series_url': seriesUrl,
        'chapter_hint': chapterHint,
        'stamp_ms': stampMs,
        'updated_at': atMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Piggyback the prune — one indexed DELETE per write window is cheap.
    await db.delete(
      'feed_anchors',
      where: 'updated_at < ?',
      whereArgs: [atMs - pruneAfterMs],
    );
  }
}

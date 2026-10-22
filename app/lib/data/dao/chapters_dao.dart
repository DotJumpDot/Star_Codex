import 'package:sqflite/sqflite.dart';

/// `chapters`, `chapter_pages`, `chapter_text` (Plan/02).
/// `number` is REAL: compare with epsilon < 1e-6 when matching across sources.
class Chapter {
  const Chapter({
    this.id,
    required this.seriesId,
    required this.sourceId,
    required this.number,
    this.title,
    required this.url,
    this.pageCount,
    this.uploadedAt,
    required this.fetchedAt,
  });

  final int? id;
  final int seriesId;
  final String sourceId;
  final double number;
  final String? title;
  final String url;
  final int? pageCount;
  final int? uploadedAt;
  final int fetchedAt;

  Chapter copyWith({
    int? id,
    int? pageCount,
  }) =>
      Chapter(
        id: id ?? this.id,
        seriesId: seriesId,
        sourceId: sourceId,
        number: number,
        title: title,
        url: url,
        pageCount: pageCount ?? this.pageCount,
        uploadedAt: uploadedAt,
        fetchedAt: fetchedAt,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'series_id': seriesId,
        'source_id': sourceId,
        'number': number,
        'title': title,
        'url': url,
        'page_count': pageCount,
        'uploaded_at': uploadedAt,
        'fetched_at': fetchedAt,
      };

  static Chapter fromRow(Map<String, Object?> r) => Chapter(
        id: r['id'] as int,
        seriesId: r['series_id'] as int,
        sourceId: r['source_id'] as String,
        number: (r['number'] as num).toDouble(),
        title: r['title'] as String?,
        url: r['url'] as String,
        pageCount: r['page_count'] as int?,
        uploadedAt: r['uploaded_at'] as int?,
        fetchedAt: r['fetched_at'] as int,
      );
}

class ChapterPage {
  const ChapterPage({
    required this.chapterId,
    required this.idx,
    required this.url,
    this.contentHash,
    this.width,
    this.height,
    this.bytes,
  });

  final int chapterId;
  final int idx; // 0-based display order
  final String url;
  final String? contentHash; // sha256 of original bytes; NULL = never fetched
  final int? width;
  final int? height;
  final int? bytes;

  Map<String, Object?> toRow() => {
        'chapter_id': chapterId,
        'idx': idx,
        'url': url,
        'content_hash': contentHash,
        'width': width,
        'height': height,
        'bytes': bytes,
      };

  static ChapterPage fromRow(Map<String, Object?> r) => ChapterPage(
        chapterId: r['chapter_id'] as int,
        idx: r['idx'] as int,
        url: r['url'] as String,
        contentHash: r['content_hash'] as String?,
        width: r['width'] as int?,
        height: r['height'] as int?,
        bytes: r['bytes'] as int?,
      );
}

class ChaptersDao {
  ChaptersDao(this.db);

  final Database db;

  /// Insert or update by the (series_id, source_id, number) unique key.
  Future<int> upsert(Chapter c) async {
    final existing = await find(c.seriesId, c.sourceId, c.number);
    if (existing == null) {
      return db.insert('chapters', c.toRow());
    }
    final id = existing.id!;
    await db.update('chapters', c.copyWith(id: id).toRow()..remove('id'),
        where: 'id = ?', whereArgs: [id]);
    return id;
  }

  /// Bulk [upsert] inside ONE transaction — a 900-chapter detail fetch must
  /// not land half-written (and 900 sequential round-trips are slow).
  Future<void> upsertAll(List<Chapter> chapters) {
    return db.transaction((txn) async {
      for (final c in chapters) {
        final rows = await txn.query('chapters',
            columns: ['id'],
            where:
                'series_id = ? AND source_id = ? AND ABS(number - ?) < 1e-6',
            whereArgs: [c.seriesId, c.sourceId, c.number],
            limit: 1);
        if (rows.isEmpty) {
          await txn.insert('chapters', c.toRow());
        } else {
          final id = rows.first['id'] as int;
          await txn.update('chapters', c.toRow()..remove('id'),
              where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }

  Future<Chapter?> find(int seriesId, String sourceId, double number) async {
    final rows = await db.query('chapters',
        where: 'series_id = ? AND source_id = ? AND ABS(number - ?) < 1e-6',
        whereArgs: [seriesId, sourceId, number],
        limit: 1);
    return rows.isEmpty ? null : Chapter.fromRow(rows.first);
  }

  Future<Chapter?> byId(int id) async {
    final rows =
        await db.query('chapters', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Chapter.fromRow(rows.first);
  }

  /// Whether ANY chapter rows exist for one source link — the detail load
  /// refreshes sources that have no chapters yet (Plan/09 §Data flow).
  Future<bool> hasForSource(int seriesId, String sourceId) async {
    final rows = await db.query('chapters',
        columns: ['id'],
        where: 'series_id = ? AND source_id = ?',
        whereArgs: [seriesId, sourceId],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// (id, number) pairs for explicit ids — the Offline tab's per-chapter
  /// delete picker.
  Future<List<(int, double)>> byIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await db.query('chapters',
        columns: ['id', 'number'],
        where: 'id IN (${ids.join(',')})',
        orderBy: 'number');
    return [
      for (final r in rows) (r['id'] as int, (r['number'] as num).toDouble()),
    ];
  }

  /// Newest first (display order for the detail screen).
  Future<List<Chapter>> listForSeries(int seriesId) async {
    final rows = await db.query('chapters',
        where: 'series_id = ?', whereArgs: [seriesId], orderBy: 'number DESC');
    return rows.map(Chapter.fromRow).toList(growable: false);
  }

  /// Which sources carry chapter [number] of [seriesId] (epsilon match) —
  /// powers the per-chapter source chips + "read from which site" picker
  /// on the detail screen (doc 09 addendum, user decision 2026-10-17).
  Future<List<String>> sourcesForNumber(int seriesId, double number) async {
    final rows = await db.query('chapters',
        columns: ['source_id'],
        where: 'series_id = ? AND ABS(number - ?) < 1e-6',
        whereArgs: [seriesId, number]);
    return rows.map((r) => r['source_id'] as String).toList(growable: false);
  }

  /// Other sources' copies of one chapter number, in link order — the
  /// reader's fallback chain (doc 07 §5).
  Future<List<Chapter>> siblings(int seriesId, double number,
      {required String excludeSourceId}) async {
    final rows = await db.query('chapters',
        where:
            'series_id = ? AND ABS(number - ?) < 1e-6 AND source_id != ?',
        whereArgs: [seriesId, number, excludeSourceId],
        orderBy: 'rowid');
    return rows.map(Chapter.fromRow).toList(growable: false);
  }

  /// Nearest chapter strictly after/before [current] across all sources.
  /// Prefers the SAME source's copy, else the first row in link order —
  /// auto-next + the chrome prev/next buttons (doc 10 §6).
  Future<Chapter?> adjacent(Chapter current, {required bool forward}) async {
    final cmp = forward ? 'c.number > ?' : 'c.number < ?';
    final order = forward ? 'c.number ASC' : 'c.number DESC';
    final rows = await db.rawQuery('''
      SELECT c.* FROM chapters c
      WHERE c.series_id = ? AND $cmp
      ORDER BY $order, (c.source_id = ?) DESC, c.rowid
      LIMIT 1
    ''', [current.seriesId, current.number, current.sourceId]);
    return rows.isEmpty ? null : Chapter.fromRow(rows.first);
  }

  Future<void> setPageCount(int chapterId, int pageCount) =>
      db.update('chapters', {'page_count': pageCount},
          where: 'id = ?', whereArgs: [chapterId]);

  // --- pages ---

  Future<void> replacePages(int chapterId, List<ChapterPage> pages) async {
    await db.transaction((txn) async {
      await txn
          .delete('chapter_pages', where: 'chapter_id = ?', whereArgs: [chapterId]);
      final batch = txn.batch();
      for (final page in pages) {
        batch.insert('chapter_pages', page.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<ChapterPage>> pages(int chapterId) async {
    final rows = await db.query('chapter_pages',
        where: 'chapter_id = ?',
        whereArgs: [chapterId],
        orderBy: 'idx ASC');
    return rows.map(ChapterPage.fromRow).toList(growable: false);
  }

  /// Mark fetched pages with their content hash after pipeline write (03).
  Future<void> setPageHash(int chapterId, int idx, String contentHash) =>
      db.update('chapter_pages', {'content_hash': contentHash},
          where: 'chapter_id = ? AND idx = ?', whereArgs: [chapterId, idx]);

  /// Stored (WebP) size of one page — the download sheet's size estimate
  /// reads real sizes once pages exist (doc 13 §A).
  Future<void> setPageBytes(int chapterId, int idx, int bytes) =>
      db.update('chapter_pages', {'bytes': bytes},
          where: 'chapter_id = ? AND idx = ?', whereArgs: [chapterId, idx]);

  /// Store dims sniffed from the original bytes — the reader reserves the
  /// EXACT slot height on re-reads (doc 10: anti-jump).
  Future<void> setPageDims(
          int chapterId, int idx, int width, int height) =>
      db.update('chapter_pages', {'width': width, 'height': height},
          where: 'chapter_id = ? AND idx = ?', whereArgs: [chapterId, idx]);

  // --- novel text ---

  Future<void> saveText(int chapterId, String text) =>
      db.insert('chapter_text', {'chapter_id': chapterId, 'text': text},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String?> text(int chapterId) async {
    final rows = await db.query('chapter_text',
        where: 'chapter_id = ?', whereArgs: [chapterId], limit: 1);
    return rows.isEmpty ? null : rows.first['text'] as String;
  }

  // --- read_progress ---

  /// Persist reader progress.
  ///
  /// The `completed` flag is STICKY: once a chapter is finished it stays
  /// finished. Without that, re-opening a read chapter and scrolling
  /// (which saves completed=0) silently un-read it — and the detail
  /// page's green "read" dot would flip back to yellow (user report
  /// 2026-10-22). `read_at` keeps the ORIGINAL finish time for the
  /// same reason.
  Future<void> saveProgress(int chapterId,
      {required int pageIndex, required bool completed, int? readAt}) async {
    await db.transaction((txn) async {
      final rows = await txn.query('read_progress',
          columns: ['completed', 'read_at'],
          where: 'chapter_id = ?',
          whereArgs: [chapterId],
          limit: 1);
      final wasCompleted =
          rows.isNotEmpty && (rows.first['completed'] as int) == 1;
      final stayCompleted = completed || wasCompleted;
      final int? finishedAt = rows.isEmpty
          ? null
          : rows.first['read_at'] as int?;
      await txn.insert(
          'read_progress',
          {
            'chapter_id': chapterId,
            'page_index': pageIndex,
            'completed': stayCompleted ? 1 : 0,
            // A finished chapter keeps its ORIGINAL finish time.
            'read_at': stayCompleted ? (readAt ?? finishedAt) : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<({int pageIndex, bool completed, int? readAt})?> progress(
      int chapterId) async {
    final rows = await db.query('read_progress',
        where: 'chapter_id = ?', whereArgs: [chapterId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      pageIndex: r['page_index'] as int,
      completed: (r['completed'] as int) == 1,
      readAt: r['read_at'] as int?,
    );
  }

  /// Progress rows for a whole series (detail screen marks — Plan/09),
  /// keyed by chapter id.
  Future<Map<int, ({int pageIndex, bool completed, int? readAt})>>
      progressForSeries(int seriesId) async {
    final rows = await db.rawQuery('''
      SELECT rp.chapter_id, rp.page_index, rp.completed, rp.read_at
      FROM read_progress rp
      JOIN chapters c ON c.id = rp.chapter_id
      WHERE c.series_id = ?
    ''', [seriesId]);
    return {
      for (final r in rows)
        r['chapter_id'] as int: (
          pageIndex: r['page_index'] as int,
          completed: (r['completed'] as int) == 1,
          readAt: r['read_at'] as int?,
        ),
    };
  }

  /// "ทำเครื่องหมายว่ายังไม่อ่าน" — an unread chapter has NO row.
  Future<void> clearProgress(int chapterId) =>
      db.delete('read_progress', where: 'chapter_id = ?', whereArgs: [chapterId]);

  /// Mark a chapter as STARTED (opened and read for a moment, not
  /// finished). Written as "insert if absent" on purpose:
  ///
  /// - A row that already tracks a page keeps it (the reader's own
  ///   throttled save owns page_index).
  /// - A FINISHED chapter stays finished — this write can never
  ///   regress completed=1 back to 0, so the "next chapter" jump
  ///   (which marks the previous chapter read) is never undone by a
  ///   late "started" marker.
  ///
  /// `read_at` stays NULL: a started chapter is not a completion.
  Future<void> markStarted(int chapterId) async {
    await db.insert(
      'read_progress',
      {
        'chapter_id': chapterId,
        'page_index': 0,
        'completed': 0,
        'read_at': null,
      },
      // IGNORE: an existing row (any state) is left untouched. The
      // return value is deliberately ignored — Android answers -1 on
      // an ignored insert while the ffi shim answers 0 (see AGENTS.md).
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

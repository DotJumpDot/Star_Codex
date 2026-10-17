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

  /// Newest first (display order for the detail screen).
  Future<List<Chapter>> listForSeries(int seriesId) async {
    final rows = await db.query('chapters',
        where: 'series_id = ?', whereArgs: [seriesId], orderBy: 'number DESC');
    return rows.map(Chapter.fromRow).toList(growable: false);
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

  Future<void> saveProgress(int chapterId,
      {required int pageIndex, required bool completed, int? readAt}) async {
    await db.insert(
        'read_progress',
        {
          'chapter_id': chapterId,
          'page_index': pageIndex,
          'completed': completed ? 1 : 0,
          'read_at': readAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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
}

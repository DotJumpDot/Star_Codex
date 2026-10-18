import 'dart:convert';

import '../../core/utils/title_norm.dart';
import '../dao/blobs_dao.dart';
import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart';
import '../dao/series_dao.dart';
import '../sources/source_api.dart';
import '../storage/cache_janitor.dart';
import 'library_cards.dart';

/// Library-tab + History-tab data (Plan/12) + the manual merge/split escape
/// hatches (§4) and delete flows (13 §C). SeriesRepo is already over the
/// ~400-line budget, so the merge/split transactions live here.
class LibraryRepo {
  LibraryRepo({
    required this.seriesDao,
    required this.chaptersDao,
    required this.libraryDao,
    required this.downloadsDao,
    required this.blobsDao,
    this.sources = const [],
    this.janitor,
  });

  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final LibraryDao libraryDao;
  final DownloadsDao downloadsDao;
  final BlobsDao blobsDao;

  /// Null in unit tests that don't exercise pin recompute.
  final CacheJanitor? janitor;

  /// For the cover fallback's Referer header; empty in unit tests.
  final List<Source> sources;

  String? _refererOf(String? sourceId) {
    if (sourceId == null) return null;
    for (final s in sources) {
      if (s.id == sourceId) return s.referer;
    }
    return null;
  }

  /// One pass over a handful of GROUP BY queries — library scale is tens
  /// of series, so assembling cards in Dart beats one mega-SQL.
  Future<List<LibraryCard>> load() async {
    final rows = await seriesDao.db.rawQuery('''
      SELECT l.series_id, l.added_at, l.last_read_at, l.last_seen_at,
             s.title, s.original_title, s.cover_hash, s.type
      FROM library l JOIN series s ON s.id = l.series_id
      ORDER BY l.added_at DESC
    ''');
    if (rows.isEmpty) return const [];

    final numbers = <int, Set<double>>{};
    final completed = <int, Set<double>>{};
    final maxUpdated = <int, int?>{};
    for (final r in await seriesDao.db.rawQuery('''
      SELECT series_id, number, uploaded_at,
             EXISTS(SELECT 1 FROM read_progress rp
                    WHERE rp.chapter_id = c.id AND rp.completed = 1) AS done
      FROM chapters c
    ''')) {
      final sid = r['series_id'] as int;
      final chNum = (r['number'] as num).toDouble();
      (numbers[sid] ??= {}).add(chNum);
      if ((r['done'] as int) == 1) (completed[sid] ??= {}).add(chNum);
      maxUpdated[sid] = _maxOf(
          maxUpdated[sid], (r['uploaded_at'] as num?)?.toInt());
    }
    // Doc-13 badge rule, deduped by NUMBER: mirrors carry the same new
    // chapter and "2 ตอนใหม่" must mean two new chapters, not two copies.
    // Threshold is max(last_read_at, last_seen_at) (db v4): reading a
    // chapter OR visiting the detail page clears the chip — only chapters
    // uploaded after BOTH re-arm it. No threshold at all (added to library
    // but never read/visited — last_seen_at 0 means pre-v4 row) → every
    // dated chapter counts as new; the first detail visit clears it.
    final lastReadById = {
      for (final r in rows)
        r['series_id'] as int: _maxOf(
            r['last_read_at'] as int?,
            (r['last_seen_at'] as int?) == 0
                ? null
                : r['last_seen_at'] as int?),
    };
    final newNumbers = <int, Set<double>>{};
    for (final r in await seriesDao.db.rawQuery(
      'SELECT series_id, number, uploaded_at FROM chapters '
      'WHERE uploaded_at IS NOT NULL',
    )) {
      final sid = r['series_id'] as int;
      final lastRead = lastReadById[sid];
      final at = r['uploaded_at'] as int;
      if (lastRead == null || at > lastRead) {
        (newNumbers[sid] ??= {}).add((r['number'] as num).toDouble());
      }
    }

    final downloads = <int, int>{};
    for (final r in await seriesDao.db.rawQuery('''
      SELECT c.series_id AS sid, COUNT(*) AS n
      FROM downloads d JOIN chapters c ON c.id = d.chapter_id
      WHERE d.state = 'done' GROUP BY c.series_id
    ''')) {
      downloads[r['sid'] as int] = r['n'] as int;
    }

    final sourcesBySeries = <int, List<String>>{};
    final altsBySeries = <int, List<String>>{};
    final coverBySeries = <int, String?>{};
    final coverSourceBySeries = <int, String?>{};
    for (final link in await seriesDao.db.query('series_sources')) {
      final sid = link['series_id'] as int;
      (sourcesBySeries[sid] ??= []).add(link['source_id'] as String);
      // Pair the cover URL with ITS source — a first link without a
      // cover must not donate its referer to a later link's cover.
      if (coverBySeries[sid] == null && link['cover_url'] != null) {
        coverBySeries[sid] = link['cover_url'] as String?;
        coverSourceBySeries[sid] = link['source_id'] as String?;
      }
      final raw = link['alt_titles'] as String?;
      if (raw != null) {
        (altsBySeries[sid] ??= [])
            .addAll((jsonDecode(raw) as List<dynamic>).cast<String>());
      }
    }

    final tagsBySeries = <int, List<String>>{};
    for (final r in await seriesDao.db.rawQuery('''
      SELECT st.series_id AS sid, t.name AS name
      FROM series_tags st JOIN tags t ON t.id = st.tag_id
    ''')) {
      (tagsBySeries[r['sid'] as int] ??= []).add(r['name'] as String);
    }

    return [
      for (final r in rows)
        LibraryCard(
          seriesId: r['series_id'] as int,
          title: r['title'] as String,
          originalTitle: r['original_title'] as String?,
          coverHash: r['cover_hash'] as String?,
          coverUrl: coverBySeries[r['series_id'] as int],
          coverReferer: _refererOf(
              coverSourceBySeries[r['series_id'] as int]),
          type: r['type'] as String?,
          addedAt: r['added_at'] as int,
          lastReadAt: r['last_read_at'] as int?,
          chapterNumbers: numbers[r['series_id'] as int] ?? {},
          completedNumbers: completed[r['series_id'] as int] ?? {},
          newCount: newNumbers[r['series_id'] as int]?.length ?? 0,
          maxUpdatedAt: maxUpdated[r['series_id'] as int],
          doneDownloads: downloads[r['series_id'] as int] ?? 0,
          sources: sourcesBySeries[r['series_id'] as int] ?? const [],
          altTitles: altsBySeries[r['series_id'] as int] ?? const [],
          tags: tagsBySeries[r['series_id'] as int] ?? const [],
        ),
    ];
  }

  static int? _maxOf(int? a, int? b) =>
      a == null ? b : (b == null ? a : (a > b ? a : b));

  /// Delete-from-library (13 §C): removes the `library` row; with
  /// [keepFiles] false it also deletes the downloads rows and recomputes
  /// pins (blobs fall back to plain cache and LRU eventually reclaims
  /// them).
  Future<void> deleteFromLibrary(int seriesId,
      {required bool keepFiles}) async {
    await libraryDao.remove(seriesId);
    if (!keepFiles) {
      for (final c in await chaptersDao.listForSeries(seriesId)) {
        if (c.id != null) await downloadsDao.delete(c.id!);
      }
      await janitor?.recomputePins();
    }
  }

  /// ลบไฟล์ทั้งหมดของเรื่องนี้ without leaving the library.
  Future<void> removeSeriesDownloads(int seriesId) async {
    for (final c in await chaptersDao.listForSeries(seriesId)) {
      if (c.id != null) await downloadsDao.delete(c.id!);
    }
    await janitor?.recomputePins();
  }

  /// Manual merge (Plan/12 §4): every absorbed series' links, chapters,
  /// tags, categories, library row and history move onto [primaryId] and
  /// the absorbed rows are deleted — ONE transaction, all-or-nothing.
  ///
  /// Chapter conflicts (same source + number already on the primary) drop
  /// the absorbed copy; its progress/history cascade away with it, which
  /// is exactly the desired semantics for a duplicate.
  Future<void> merge(int primaryId, List<int> absorbedIds) async {
    if (absorbedIds.isEmpty) return;
    final db = seriesDao.db;
    await db.transaction((txn) async {
      // 1) links: skip sources the primary already carries.
      final primarySources = {
        for (final r in await txn.query('series_sources',
            columns: ['source_id'],
            where: 'series_id = ?',
            whereArgs: [primaryId])) r['source_id'] as String,
      };
      for (final absorbed in absorbedIds) {
        for (final link in await txn.query('series_sources',
            where: 'series_id = ?', whereArgs: [absorbed])) {
          final src = link['source_id'] as String;
          if (primarySources.contains(src)) continue;
          await txn.update(
            'series_sources',
            {'series_id': primaryId},
            where: 'series_id = ? AND source_id = ?',
            whereArgs: [absorbed, src],
          );
          primarySources.add(src);
        }
      }

      // 2) chapters: unique(series, source, number) conflicts → absorbed
      //    copy dies, primary's survives.
      for (final absorbed in absorbedIds) {
        for (final ch in await txn.query('chapters',
            columns: ['id', 'source_id', 'number'],
            where: 'series_id = ?',
            whereArgs: [absorbed])) {
          final clash = await txn.query('chapters',
              columns: ['id'],
              where:
                  'series_id = ? AND source_id = ? AND ABS(number - ?) < 1e-6',
              whereArgs: [
                primaryId,
                ch['source_id'] as String,
                ch['number'] as num,
              ],
              limit: 1);
          if (clash.isNotEmpty) {
            await txn.delete('chapters',
                where: 'id = ?', whereArgs: [ch['id'] as int]);
          } else {
            await txn.update('chapters', {'series_id': primaryId},
                where: 'id = ?', whereArgs: [ch['id'] as int]);
          }
        }
      }

      // 3) tags + categories: union.
      for (final absorbed in absorbedIds) {
        for (final table in const ['series_tags', 'category_members']) {
          final col = table == 'series_tags' ? 'tag_id' : 'category_id';
          await txn.execute(
            'INSERT OR IGNORE INTO $table (series_id, $col) '
            "SELECT $primaryId, $col FROM $table WHERE series_id = $absorbed",
          );
        }
      }

      // 4) library: absorb the row when the primary has none; when both
      //    are in the library keep the NEWEST read state. The absorbed
      //    last-read chapter may be one of the DROPPED duplicates —
      //    copying its id would violate the chapters FK and roll the
      //    whole merge back, so verify it survived ON the primary first.
      Future<int?> survivedOnPrimary(int? chapterId) async {
        if (chapterId == null) return null;
        final rows = await txn.query('chapters',
            columns: ['id'],
            where: 'id = ? AND series_id = ?',
            whereArgs: [chapterId, primaryId],
            limit: 1);
        return rows.isEmpty ? null : chapterId;
      }

      for (final absorbed in absorbedIds) {
        final absorbedEntry = await txn.query('library',
            where: 'series_id = ?', whereArgs: [absorbed], limit: 1);
        if (absorbedEntry.isEmpty) continue;
        final a = LibraryEntry.fromRow(absorbedEntry.first);
        final primaryEntry = await txn.query('library',
            where: 'series_id = ?', whereArgs: [primaryId], limit: 1);
        if (primaryEntry.isEmpty) {
          await txn.insert('library', {
            'series_id': primaryId,
            'added_at': a.addedAt,
            'last_read_at': a.lastReadAt,
            'last_read_chapter_id': await survivedOnPrimary(a.lastReadChapterId),
          });
        } else {
          final p = LibraryEntry.fromRow(primaryEntry.first);
          if ((a.lastReadAt ?? 0) > (p.lastReadAt ?? 0)) {
            await txn.update(
              'library',
              {
                'last_read_at': a.lastReadAt,
                'last_read_chapter_id':
                    await survivedOnPrimary(a.lastReadChapterId) ??
                        p.lastReadChapterId,
              },
              where: 'series_id = ?',
              whereArgs: [primaryId],
            );
          }
        }
      }

      // 5) history re-point + drop the absorbed series rows (cascades the
      //    leftovers: series_tags, category_members, library, links).
      await txn.execute(
        'UPDATE reading_history SET series_id = $primaryId '
        'WHERE series_id IN (${absorbedIds.join(',')})',
      );
      for (final absorbed in absorbedIds) {
        await txn.delete('series', where: 'id = ?', whereArgs: [absorbed]);
      }
    });
  }

  /// แยกเรื่อง (Plan/12 §4, false-merge escape hatch): lifts one source
  /// link + its chapters onto a fresh standalone series row. Progress and
  /// history follow automatically (they key off chapter ids). The new
  /// series is NOT added to the library.
  Future<int> split(int seriesId, String sourceId) async {
    final series = (await seriesDao.byId(seriesId))!;
    final link = (await seriesDao.sourceLink(seriesId, sourceId))!;
    final now = DateTime.now().millisecondsSinceEpoch;

    final title = (link.sourceTitle?.trim().isNotEmpty ?? false)
        ? link.sourceTitle!.trim()
        : series.title;
    var norm = normalizeTitle(title);
    if (norm.isEmpty || await seriesDao.findByTitleNorm(norm) != null) {
      // The unique title_norm index needs a free key for a standalone row
      // whose display title may equal its parent's (same escape pattern as
      // upsertFromDetail's per-URL fallback — norm is never displayed).
      norm = 'raw:split:$seriesId:$sourceId';
    }

    final newId = await seriesDao.insert(Series(
      title: title,
      titleNorm: norm,
      coverHash: series.coverHash,
      createdAt: now,
      updatedAt: now,
    ));

    final db = seriesDao.db;
    await db.transaction((txn) async {
      await txn.delete('series_sources',
          where: 'series_id = ? AND source_id = ?',
          whereArgs: [seriesId, sourceId]);
      await txn.insert('series_sources',
          {...link.toRow(), 'series_id': newId});
      final chapters = await txn.query('chapters',
          columns: ['id'],
          where: 'series_id = ? AND source_id = ?',
          whereArgs: [seriesId, sourceId]);
      for (final ch in chapters) {
        await txn.update('chapters', {'series_id': newId},
            where: 'id = ?', whereArgs: [ch['id'] as int]);
        await txn.update('reading_history', {'series_id': newId},
            where: 'chapter_id = ?', whereArgs: [ch['id'] as int]);
      }
    });
    return newId;
  }
}

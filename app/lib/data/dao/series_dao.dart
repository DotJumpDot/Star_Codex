import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// `series` + `series_sources` rows (Plan/02). Plain const classes with
/// copyWith — no codegen (Plan/01 §7).
class Series {
  const Series({
    this.id,
    required this.title,
    this.originalTitle,
    required this.titleNorm,
    this.coverHash,
    this.type,
    this.origin,
    this.status,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String? originalTitle;
  final String titleNorm;
  final String? coverHash;
  final String? type; // 'manga'|'manhwa'|'manhua'|'novel'|NULL
  final String? origin; // 'japan'|'korea'|'china'|'thailand'|'other'|NULL
  final String? status; // 'ongoing'|'completed'|NULL
  final String? description;
  final int createdAt;
  final int updatedAt;

  Series copyWith({
    int? id,
    String? title,
    String? originalTitle,
    String? titleNorm,
    String? coverHash,
    String? type,
    String? origin,
    String? status,
    String? description,
    int? createdAt,
    int? updatedAt,
  }) => Series(
    id: id ?? this.id,
    title: title ?? this.title,
    originalTitle: originalTitle ?? this.originalTitle,
    titleNorm: titleNorm ?? this.titleNorm,
    coverHash: coverHash ?? this.coverHash,
    type: type ?? this.type,
    origin: origin ?? this.origin,
    status: status ?? this.status,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'title': title,
    'original_title': originalTitle,
    'title_norm': titleNorm,
    'cover_hash': coverHash,
    'type': type,
    'origin': origin,
    'status': status,
    'description': description,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  static Series fromRow(Map<String, Object?> r) => Series(
    id: r['id'] as int,
    title: r['title'] as String,
    originalTitle: r['original_title'] as String?,
    titleNorm: r['title_norm'] as String,
    coverHash: r['cover_hash'] as String?,
    type: r['type'] as String?,
    origin: r['origin'] as String?,
    status: r['status'] as String?,
    description: r['description'] as String?,
    createdAt: r['created_at'] as int,
    updatedAt: r['updated_at'] as int,
  );
}

/// One series' presence on one source — this table IS the cross-site merge.
class SeriesSource {
  const SeriesSource({
    required this.seriesId,
    required this.sourceId,
    required this.sourceUrl,
    this.sourceTitle,
    this.altTitles = const [],
    this.coverUrl,
    this.lastChapterNumber,
    this.lastUpdatedAt,
    required this.fetchedAt,
  });

  final int seriesId;
  final String sourceId;
  final String sourceUrl;
  final String? sourceTitle;

  /// JSON array of strings (encoded by caller).
  final List<String> altTitles;
  final String? coverUrl;
  final double? lastChapterNumber;
  final int? lastUpdatedAt;
  final int fetchedAt;

  Map<String, Object?> toRow() => {
    'series_id': seriesId,
    'source_id': sourceId,
    'source_url': sourceUrl,
    'source_title': sourceTitle,
    'alt_titles': altTitles.isEmpty ? null : jsonEncode(altTitles),
    'cover_url': coverUrl,
    'last_chapter_number': lastChapterNumber,
    'last_updated_at': lastUpdatedAt,
    'fetched_at': fetchedAt,
  };

  static SeriesSource fromRow(Map<String, Object?> r) => SeriesSource(
    seriesId: r['series_id'] as int,
    sourceId: r['source_id'] as String,
    sourceUrl: r['source_url'] as String,
    sourceTitle: r['source_title'] as String?,
    altTitles: _parseAltTitles(r['alt_titles'] as String?),
    coverUrl: r['cover_url'] as String?,
    lastChapterNumber: (r['last_chapter_number'] as num?)?.toDouble(),
    lastUpdatedAt: r['last_updated_at'] as int?,
    fetchedAt: r['fetched_at'] as int,
  );

  static List<String> _parseAltTitles(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<String>();
  }
}

class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.adapter,
    required this.enabled,
    required this.sort,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String adapter;
  final bool enabled;
  final int sort;

  static SourceInfo fromRow(Map<String, Object?> r) => SourceInfo(
    id: r['id'] as String,
    name: r['name'] as String,
    baseUrl: r['base_url'] as String,
    adapter: r['adapter'] as String,
    enabled: (r['enabled'] as int) == 1,
    sort: r['sort'] as int,
  );
}

class SeriesDao {
  SeriesDao(this.db);

  final Database db;

  Future<int> insert(Series s) => db.insert(
    'series',
    s.toRow(),
    conflictAlgorithm: ConflictAlgorithm.abort,
  );

  Future<int> upsertByTitleNorm(Series s) async {
    final existing = await findByTitleNorm(s.titleNorm);
    if (existing == null) return insert(s);
    final id = existing.id!;
    await db.update(
      'series',
      s.copyWith(id: null, createdAt: existing.createdAt).toRow()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
    return id;
  }

  Future<Series?> byId(int id) async {
    final rows = await db.query(
      'series',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Series.fromRow(rows.first);
  }

  Future<Series?> findByTitleNorm(String titleNorm) async {
    final rows = await db.query(
      'series',
      where: 'title_norm = ?',
      whereArgs: [titleNorm],
      limit: 1,
    );
    return rows.isEmpty ? null : Series.fromRow(rows.first);
  }

  Future<int> update(Series s) => db.update(
    'series',
    s.toRow()..remove('id'),
    where: 'id = ?',
    whereArgs: [s.id],
  );

  Future<int> delete(int id) =>
      db.delete('series', where: 'id = ?', whereArgs: [id]);

  /// Every series row (merge picker on the detail screen, Plan/12 §4).
  Future<List<Series>> all() async => (await db.query(
    'series',
    orderBy: 'title',
  )).map(Series.fromRow).toList(growable: false);

  /// Newest-touched series rows first (offline catalog, 2026-10-21) —
  /// updated_at moves on every detail/chapter fetch, so this is the
  /// "what the user actually reads" order.
  Future<List<Series>> recentSeries({int limit = 60}) async {
    final rows = await db.query(
      'series',
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(Series.fromRow).toList(growable: false);
  }

  // --- series_sources ---

  Future<void> upsertSource(SeriesSource link) async {
    await db.insert(
      'series_sources',
      link.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insertion order (rowid) — the first link is the source the series was
  /// opened/added from; the detail screen uses it for tab order and chips.
  Future<List<SeriesSource>> sourcesOf(int seriesId) async {
    final rows = await db.query(
      'series_sources',
      where: 'series_id = ?',
      whereArgs: [seriesId],
      orderBy: 'rowid',
    );
    return rows.map(SeriesSource.fromRow).toList(growable: false);
  }

  /// Newest chapter timestamp across the series' source links — the browse
  /// card "last update" stamp for already-materialized series.
  Future<int?> lastUpdatedAt(int seriesId) async {
    final rows = await db.rawQuery(
      'SELECT MAX(last_updated_at) AS m FROM series_sources WHERE series_id = ?',
      [seriesId],
    );
    return rows.isEmpty ? null : rows.first['m'] as int?;
  }

  Future<SeriesSource?> sourceLink(int seriesId, String sourceId) async {
    final rows = await db.query(
      'series_sources',
      where: 'series_id = ? AND source_id = ?',
      whereArgs: [seriesId, sourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : SeriesSource.fromRow(rows.first);
  }

  /// The exact (source, url) link of a series — [sourceLink] can hit a
  /// different URL when one series carries two links on the same source.
  Future<SeriesSource?> sourceLinkByUrl(
    int seriesId,
    String sourceId,
    String sourceUrl,
  ) async {
    final rows = await db.query(
      'series_sources',
      where: 'series_id = ? AND source_id = ? AND source_url = ?',
      whereArgs: [seriesId, sourceId, sourceUrl],
      limit: 1,
    );
    return rows.isEmpty ? null : SeriesSource.fromRow(rows.first);
  }

  /// A (source, url) pair is the strongest series identity — stronger than
  /// any title match (titles drift between listings). Used by
  /// addToLibrary to reuse the existing series row instead of creating a
  /// duplicate under a drifted title.
  Future<int?> findSeriesIdBySourceLink(
    String sourceId,
    String sourceUrl,
  ) async {
    final rows = await db.query(
      'series_sources',
      columns: ['series_id'],
      where: 'source_id = ? AND source_url = ?',
      whereArgs: [sourceId, sourceUrl],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['series_id'] as int;
  }

  Future<List<SourceInfo>> allSources({bool onlyEnabled = false}) async {
    final rows = await db.query(
      'sources',
      where: onlyEnabled ? 'enabled = 1' : null,
      orderBy: 'sort',
    );
    return rows.map(SourceInfo.fromRow).toList(growable: false);
  }

  /// Settings screen switches (doc 14 §Sources). The live [SourcesController]
  /// list is re-emitted by the caller after the write.
  Future<void> setSourceEnabled(String id, bool enabled) => db.update(
    'sources',
    {'enabled': enabled ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Up/down reordering (doc 14: affects source-priority tiebreaks in
  /// 07 §4). Swaps the sort values of the two neighbours in one pass.
  Future<void> moveSource(String id, {required bool up}) async {
    final rows = await db.query('sources', orderBy: 'sort');
    final ids = [for (final r in rows) r['id'] as String];
    final i = ids.indexOf(id);
    if (i < 0) return;
    final j = up ? i - 1 : i + 1;
    if (j < 0 || j >= ids.length) return;
    final sortA = rows[i]['sort'] as int;
    final sortB = rows[j]['sort'] as int;
    await db.update(
      'sources',
      {'sort': sortB},
      where: 'id = ?',
      whereArgs: [ids[i]],
    );
    await db.update(
      'sources',
      {'sort': sortA},
      where: 'id = ?',
      whereArgs: [ids[j]],
    );
  }
}

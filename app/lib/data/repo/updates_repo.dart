import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart';
import '../dao/series_dao.dart';
import '../dao/settings_dao.dart';
import '../sources/source_api.dart';

/// One Updates-feed group (doc 13 §B): a library series + its unseen new
/// chapters across all its sources.
class UpdateGroup {
  const UpdateGroup({
    required this.seriesId,
    required this.title,
    this.originalTitle,
    this.coverHash,
    required this.items,
  });

  final int seriesId;
  final String title;
  final String? originalTitle;
  final String? coverHash;

  /// Newest first.
  final List<UpdateItem> items;
}

class UpdateItem {
  const UpdateItem({
    required this.chapterId,
    required this.number,
    required this.sourceId,
    this.sourceName,
    required this.uploadedAt,
  });

  final int chapterId;
  final double number;
  final String sourceId;
  final String? sourceName;
  final int uploadedAt;
}

/// Chapter-updates checker (doc 13 §B) — "did any of my series get new
/// chapters?" Cheap + polite: per library series × source link, fetch the
/// series page ONLY when that link is older than 6 h, upsert the diff,
/// stamp fetched_at. The series page (not latest()) is the truth — merged
/// series may not appear in a source's latest 500.
class UpdatesRepo {
  UpdatesRepo({
    required this.sources,
    required this.seriesDao,
    required this.chaptersDao,
    required this.libraryDao,
    required this.settingsDao,
  });

  final List<Source> sources;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final LibraryDao libraryDao;
  final SettingsDao settingsDao;

  static const refreshAfter = Duration(hours: 6);
  static const _lastRunKey = 'updates_last_run';
  static const _lastSeenKey = 'updates_last_seen';

  Source? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Run the checker over the whole library. [force] ignores both the
  /// 6 h run-gate and the per-link freshness gate (pull-to-refresh).
  /// Returns the number of NEW chapter rows inserted.
  Future<int> checkAll({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final settings = await settingsDao.getAll();
    final lastRun = int.tryParse(settings[_lastRunKey] ?? '') ?? 0;
    if (!force && now - lastRun < refreshAfter.inMilliseconds) {
      return 0;
    }

    var added = 0;
    for (final entry in await libraryDao.all()) {
      added += await _checkSeries(entry.seriesId, force: force);
    }
    await settingsDao.upsert(_lastRunKey, '$now');
    return added;
  }

  Future<int> _checkSeries(int seriesId, {required bool force}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    for (final link in await seriesDao.sourcesOf(seriesId)) {
      final source = sourceById(link.sourceId);
      if (source == null) continue;
      if (!force && now - link.fetchedAt < refreshAfter.inMilliseconds) {
        continue;
      }
      try {
        final detail = await source.detail(link.sourceUrl);
        final known = await chaptersDao.listForSeries(seriesId);
        final knownNums = {
          for (final c in known)
            if (c.sourceId == link.sourceId) c.number,
        };
        final fresh = detail.chapters
            .where((c) => !knownNums.any((n) => (n - c.number).abs() < 1e-6))
            .toList();
        if (fresh.isNotEmpty) {
          await chaptersDao.upsertAll([
            for (final c in fresh)
              Chapter(
                seriesId: seriesId,
                sourceId: link.sourceId,
                number: c.number,
                title: c.title,
                url: c.url,
                uploadedAt: c.uploadedAt,
                fetchedAt: now,
              ),
          ]);
          added += fresh.length;
        }
        await seriesDao.upsertSource(SeriesSource(
          seriesId: seriesId,
          sourceId: link.sourceId,
          sourceUrl: link.sourceUrl,
          sourceTitle: detail.title.isNotEmpty ? detail.title : link.sourceTitle,
          altTitles: link.altTitles,
          coverUrl: detail.coverUrl ?? link.coverUrl,
          lastChapterNumber: detail.chapters.isEmpty
              ? link.lastChapterNumber
              : detail.chapters.last.number,
          lastUpdatedAt: detail.chapters.isEmpty
              ? link.lastUpdatedAt
              : detail.chapters.last.uploadedAt,
          fetchedAt: now,
        ));
      } catch (_) {
        // Unreachable source: skip it — never block the rest of the
        // library (same policy as the detail stale-refresh).
      }
    }
    return added;
  }

  /// The bell feed (doc 13 §B): unseen chapters (uploaded_at after
  /// `updates_last_seen`) of library series, grouped newest first. A
  /// never-opened feed (last_seen = 0) shows nothing — a fresh install
  /// must not light up with every chapter the sites ever published.
  Future<List<UpdateGroup>> feed() async {
    final settings = await settingsDao.getAll();
    final lastSeen = int.tryParse(settings[_lastSeenKey] ?? '') ?? 0;
    if (lastSeen == 0) return const [];
    final entries = await libraryDao.all();
    final inLibrary = entries.map((e) => e.seriesId).toSet();
    if (inLibrary.isEmpty) return const [];

    final groups = <int, UpdateGroup>{};
    for (final sid in inLibrary) {
      final series = await seriesDao.byId(sid);
      if (series == null) continue;
      final items = <UpdateItem>[];
      for (final c in await chaptersDao.listForSeries(sid)) {
        if ((c.uploadedAt ?? 0) <= lastSeen) continue;
        items.add(UpdateItem(
          chapterId: c.id!,
          number: c.number,
          sourceId: c.sourceId,
          sourceName: sourceById(c.sourceId)?.name,
          uploadedAt: c.uploadedAt!,
        ));
      }
      if (items.isEmpty) continue;
      items.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      groups[sid] = UpdateGroup(
        seriesId: sid,
        title: series.title,
        originalTitle: series.originalTitle,
        coverHash: series.coverHash,
        items: items,
      );
    }
    final list = groups.values.toList()
      ..sort((a, b) => b.items.first.uploadedAt
          .compareTo(a.items.first.uploadedAt));
    return list;
  }

  /// Opening the sheet consumes the feed (mark-seen, doc 13 §B).
  Future<void> markSeen() async {
    await settingsDao.upsert(_lastSeenKey,
        '${DateTime.now().millisecondsSinceEpoch}');
  }

  /// Bell badge: unseen chapters across the library.
  Future<int> unseenCount() async {
    var n = 0;
    for (final g in await feed()) {
      n += g.items.length;
    }
    return n;
  }
}

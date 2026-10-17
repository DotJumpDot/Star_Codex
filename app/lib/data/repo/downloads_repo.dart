import 'dart:async';
import 'dart:math';

import '../../core/settings_provider.dart';
import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart' show DownloadsDao;
import '../dao/series_dao.dart';
import '../dao/settings_dao.dart';
import '../storage/cache_janitor.dart';
import 'reader_repo.dart';

/// One Offline-tab queue row (doc 13 §A): chapter identity + live page
/// progress + state.
class QueueRow {
  const QueueRow({
    required this.chapterId,
    required this.seriesId,
    required this.seriesTitle,
    required this.coverHash,
    required this.number,
    required this.sourceId,
    required this.state,
    this.error,
    this.pagesDone = 0,
    this.pagesTotal = 0,
    required this.isNovel,
  });

  final int chapterId;
  final int seriesId;
  final String seriesTitle;
  final String? coverHash;
  final double number;
  final String sourceId;
  final String state; // queued | running | paused | error
  final String? error;
  final int pagesDone;
  final int pagesTotal;
  final bool isNovel;
}

/// Immutable snapshot of the downloads queue — the Offline tab's second
/// section + progress bars (doc 13 §A).
class QueueSnapshot {
  const QueueSnapshot({
    this.rows = const [],
    this.wifiPaused = false,
    this.pinnedBytes = 0,
  });

  final List<QueueRow> rows;
  final bool wifiPaused;
  final int pinnedBytes;

  bool get hasActive =>
      rows.any((r) => r.state == 'running' || r.state == 'queued');
}

/// The pinned-downloads queue engine (doc 13 §A). ONE foreground worker:
/// `Timer.periodic(1 s)` while the app runs (v1 has NO background service —
/// the Offline tab says so). Tests drive [tick] directly and never call
/// [start].
///
/// Page fetches reuse the READER's machinery ([ReaderRepo.fetchPage]) so
/// downloads share the 2-slot politeness pool, the dedup pipeline, and the
/// hash/dims persistence.
class DownloadsRepo {
  DownloadsRepo({
    required this.readerRepo,
    required this.seriesDao,
    required this.chaptersDao,
    required this.downloadsDao,
    required this.settingsDao,
    required this.janitor,
    this.isUnmetered,
  });

  final ReaderRepo readerRepo;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final DownloadsDao downloadsDao;
  final SettingsDao settingsDao;
  final CacheJanitor janitor;

  /// Broadcast after every state change — the Offline tab + bell UI
  /// listen instead of polling.
  final _snapshots = StreamController<QueueSnapshot>.broadcast();
  Stream<QueueSnapshot> get snapshots => _snapshots.stream;

  /// Injectable network check (connectivity_plus in main(), faked in
  /// tests). False = metered connection right now.
  final Future<bool> Function()? isUnmetered;

  Timer? _timer;
  bool _ticking = false;
  bool _wifiPausedAnnounced = false;

  /// 3 retries with doubling backoff, then state=error (doc 13 §Engine).
  /// In-memory only — the v1 worker dies with the app anyway.
  final _failures = <int, int>{};
  final _notBefore = <int, int>{};

  static const _maxRetries = 3;
  static const _estimateBytesPerChapter = 8 * 1024 * 1024;
  static const _estimateBytesPerNovel = 64 * 1024;

  /// Section 1 of the Offline tab (doc 13 §A): done downloads whose files
  /// STILL EXIST on disk, grouped per series. The JOIN through `blobs` is
  /// the truthfulness rule — a done row whose pages lost their blobs never
  /// appears (the janitor demotes the row itself at startup; this query is
  /// the belt-and-braces that the list equals disk between runs).
  Future<List<OfflineSeries>> readyOffline() async {
    final db = seriesDao.db;
    final rows = await db.rawQuery('''
      SELECT s.id AS sid, s.title, s.original_title, s.cover_hash,
             COUNT(DISTINCT c.id) AS n, SUM(b.bytes) AS bytes,
             GROUP_CONCAT(c.id) AS chapter_ids
      FROM downloads d
      JOIN chapters c ON c.id = d.chapter_id
      JOIN series s ON s.id = c.series_id
      JOIN chapter_pages cp ON cp.chapter_id = c.id
        AND cp.content_hash IS NOT NULL
      JOIN blobs b ON b.hash = cp.content_hash
      WHERE d.state = 'done'
      GROUP BY s.id
    ''');
    final novelRows = await db.rawQuery('''
      SELECT s.id AS sid, s.title, s.original_title, s.cover_hash,
             COUNT(DISTINCT c.id) AS n, 0 AS bytes,
             GROUP_CONCAT(c.id) AS chapter_ids
      FROM downloads d
      JOIN chapters c ON c.id = d.chapter_id
      JOIN series s ON s.id = c.series_id
      JOIN chapter_text ct ON ct.chapter_id = c.id
      WHERE d.state = 'done'
        AND s.id NOT IN (
          SELECT c2.series_id FROM downloads d2
          JOIN chapters c2 ON c2.id = d2.chapter_id
          JOIN chapter_pages cp2 ON cp2.chapter_id = c2.id
            AND cp2.content_hash IS NOT NULL
          JOIN blobs b2 ON b2.hash = cp2.content_hash
          WHERE d2.state = 'done')
      GROUP BY s.id
    ''');
    return [
      for (final r in [...rows, ...novelRows])
        OfflineSeries(
          seriesId: r['sid'] as int,
          title: r['title'] as String,
          originalTitle: r['original_title'] as String?,
          coverHash: r['cover_hash'] as String?,
          chapterCount: r['n'] as int,
          bytes: (r['bytes'] as num?)?.toInt() ?? 0,
          chapterIds:
              (r['chapter_ids'] as String).split(',').map(int.parse).toList(),
        ),
    ];
  }

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Download size estimate for the sheet (doc 13: unfetched chapters ×
  /// 8 MB default, fetched ones × their real size). Novels are text —
  /// the 8 MB page default would over-refuse the quota by ~100×.
  Future<int> estimateBytes(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return 0;
    final rows = await seriesDao.db.rawQuery('''
      SELECT s.type AS type,
             (SELECT COALESCE(SUM(bytes), 0) FROM chapter_pages
              WHERE chapter_id = c.id) AS known
      FROM chapters c JOIN series s ON s.id = c.series_id
      WHERE c.id IN (${chapterIds.join(',')})
    ''');
    var total = 0;
    for (final r in rows) {
      final known = (r['known'] as num).toInt();
      if (known > 0) {
        total += known;
      } else if (r['type'] == 'novel') {
        total += _estimateBytesPerNovel;
      } else {
        total += _estimateBytesPerChapter;
      }
    }
    return total;
  }

  Future<void> pause(int chapterId) async {
    await downloadsDao.updateState(chapterId, 'paused');
    _failures.remove(chapterId);
    _notBefore.remove(chapterId);
    await refreshSnapshot();
  }

  Future<void> resume(int chapterId) async {
    // Retrying an ERROR row is a user decision → fresh attempt budget.
    // Resuming a queued/paused row mid-retry keeps the failure count (the
    // backoff skip must not reset the strikes).
    final errors = await downloadsDao.byState('error');
    if (errors.any((r) => r['chapter_id'] as int == chapterId)) {
      _failures.remove(chapterId);
    }
    _notBefore.remove(chapterId);
    await downloadsDao.updateState(chapterId, 'queued');
    await refreshSnapshot();
  }

  Future<void> pauseAll() async {
    for (final state in const ['queued', 'running']) {
      for (final row in await downloadsDao.byState(state)) {
        await downloadsDao.updateState(row['chapter_id'] as int, 'paused');
      }
    }
    await refreshSnapshot();
  }

  Future<void> delete(int chapterId) async {
    _failures.remove(chapterId);
    _notBefore.remove(chapterId);
    await downloadsDao.delete(chapterId);
    await janitor.recomputePins();
    await refreshSnapshot();
  }

  /// One worker step. Serialized: a slow chapter never overlaps the next
  /// tick (doc 13: fetch its pages serially through the pipeline).
  Future<void> tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final wifiOnly = AppSettings(await settingsDao.getAll())
          .getBool('downloads_wifi_only', true);
      final check = isUnmetered; // promote once; await drops field promotion
      if (wifiOnly && check != null && !await check()) {
        if (!_wifiPausedAnnounced) {
          _wifiPausedAnnounced = true;
          await refreshSnapshot(wifiPaused: true);
        }
        return;
      }
      final hadWifiChip = _wifiPausedAnnounced;
      _wifiPausedAnnounced = false;

      var ran = false;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in await downloadsDao.byState('queued')) {
        final id = row['chapter_id'] as int;
        if ((_notBefore[id] ?? 0) > now) continue;
        await _runChapter(id);
        ran = true;
        break; // one chapter per pass; the next tick picks the next
      }
      // An idle worker doesn't re-emit snapshots every second — refresh
      // only when a chapter ran, or once to clear the Wi-Fi-paused chip.
      if (ran || hadWifiChip) await refreshSnapshot();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _runChapter(int chapterId) async {
    final chapter = await chaptersDao.byId(chapterId);
    if (chapter == null) {
      await downloadsDao.delete(chapterId); // ghost queue row
      return;
    }
    await downloadsDao.updateState(chapterId, 'running');
    await refreshSnapshot();
    try {
      final series = await seriesDao.byId(chapter.seriesId);
      if (series?.type == 'novel') {
        // Novels: download = fetch + store chapter_text (doc 13 §A) —
        // instant, no page loop. loadNovelText persists on success.
        final text = await readerRepo.loadNovelText(chapter);
        if (text.isEmpty) throw const DownloadException('empty novel text');
      } else {
        final source = readerRepo.sourceById(chapter.sourceId);
        if (source == null) {
          throw DownloadException('source missing: ${chapter.sourceId}');
        }
        // Page list is DB-first (same rule as the reader). A chapter that
        // was NEVER opened has no chapter_pages rows yet — persist them
        // BEFORE fetching: setPageHash targets those rows, so without this
        // every hash write is a silent no-op, the blobs land unlinked, and
        // the "done" download demotes at the next integrity pass.
        var pages = await chaptersDao.pages(chapterId);
        if (pages.isEmpty) {
          final fetched = await source.pages(chapter.url);
          await chaptersDao.replacePages(chapterId, [
            for (var i = 0; i < fetched.imageUrls.length; i++)
              ChapterPage(
                  chapterId: chapterId, idx: i, url: fetched.imageUrls[i]),
          ]);
          await chaptersDao.setPageCount(chapterId, fetched.imageUrls.length);
          pages = await chaptersDao.pages(chapterId);
        }
        for (final page in pages) {
          await readerRepo.fetchPage(
            chapterId,
            ReaderPageRef(idx: page.idx, url: page.url),
            source.referer,
          );
          await refreshSnapshot(); // live "12/23 หน้า" progress
        }
      }
      await downloadsDao.updateState(chapterId, 'done');
      _failures.remove(chapterId);
      _notBefore.remove(chapterId);
      await janitor.recomputePins();
    } catch (e) {
      final fails = (_failures[chapterId] ?? 0) + 1;
      _failures[chapterId] = fails;
      if (fails >= _maxRetries) {
        await downloadsDao.updateState(chapterId, 'error',
            error: e.toString());
      } else {
        // Back to the queue; the backoff gate keeps the next attempt from
        // stampeding a just-failed host.
        await downloadsDao
            .updateState(chapterId, 'queued', error: e.toString());
        _notBefore[chapterId] = DateTime.now().millisecondsSinceEpoch +
            Duration(seconds: pow(2, fails).toInt()).inMilliseconds;
      }
    }
  }

  QueueSnapshot? _lastSnapshot;

  /// Rows compare by identity-relevant fields only — the Offline tab
  /// re-runs its ready-offline query on every distinct snapshot.
  static bool _sameSnapshot(QueueSnapshot a, QueueSnapshot b) {
    if (a.wifiPaused != b.wifiPaused || a.pinnedBytes != b.pinnedBytes) {
      return false;
    }
    if (a.rows.length != b.rows.length) return false;
    for (var i = 0; i < a.rows.length; i++) {
      final x = a.rows[i];
      final y = b.rows[i];
      if (x.chapterId != y.chapterId ||
          x.state != y.state ||
          x.pagesDone != y.pagesDone ||
          x.pagesTotal != y.pagesTotal ||
          x.error != y.error) {
        return false;
      }
    }
    return true;
  }

  /// Rebuild the snapshot: queue rows + live page counts + pinned size.
  /// Identical snapshots are suppressed (idle no-op).
  Future<void> refreshSnapshot({bool wifiPaused = false}) async {
    final rows = <QueueRow>[];
    for (final state in const ['running', 'queued', 'paused', 'error']) {
      for (final r in await downloadsDao.byState(state)) {
        final chapter =
            await chaptersDao.byId(r['chapter_id'] as int);
        if (chapter == null) continue;
        final series = await seriesDao.byId(chapter.seriesId);
        final pages = await chaptersDao.pages(chapter.id!);
        final done = pages.where((p) => p.contentHash != null).length;
        rows.add(QueueRow(
          chapterId: chapter.id!,
          seriesId: chapter.seriesId,
          seriesTitle: series?.title ?? '?',
          coverHash: series?.coverHash,
          number: chapter.number,
          sourceId: chapter.sourceId,
          state: r['state'] as String,
          error: r['error'] as String?,
          pagesDone: done,
          pagesTotal: pages.length,
          isNovel: series?.type == 'novel',
        ));
      }
    }
    final snap = QueueSnapshot(
      rows: rows,
      wifiPaused: wifiPaused,
      pinnedBytes: await readerRepo.blobs.totalBytes(pinned: true),
    );
    final last = _lastSnapshot;
    if (last != null && _sameSnapshot(last, snap)) return;
    _lastSnapshot = snap;
    _snapshots.add(snap);
  }
}

/// One ready-offline group (doc 13 §A section 1).
class OfflineSeries {
  const OfflineSeries({
    required this.seriesId,
    required this.title,
    this.originalTitle,
    this.coverHash,
    required this.chapterCount,
    required this.bytes,
    required this.chapterIds,
  });

  final int seriesId;
  final String title;
  final String? originalTitle;
  final String? coverHash;
  final int chapterCount;
  final int bytes;
  final List<int> chapterIds;
}

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

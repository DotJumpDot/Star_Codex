import 'dart:async' show StreamController;
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart' show RequestOptions, Response;
import 'package:sqflite/sqflite.dart' show Database;

import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/dao/blobs_dao.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/repo/downloads_repo.dart';
import 'package:star_codex/data/repo/reader_repo.dart';
import 'package:star_codex/data/storage/blob_store.dart';
import 'package:star_codex/data/storage/cache_janitor.dart';
import 'package:star_codex/data/storage/image_pipeline.dart';

import 'fake_source.dart';
import 'helpers.dart';

Uint8List fakePng(int seed, int size) {
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = (seed + i) & 0xFF;
  }
  b[0] = 0x89;
  b[1] = 0x50;
  b[2] = 0x4E;
  b[3] = 0x47;
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late io.Directory tempRoot;
  late ChaptersDao chaptersDao;
  late SeriesDao seriesDao;
  late SettingsDao settingsDao;
  late DownloadsDao downloadsDao;
  late BlobStore blobs;
  late ReaderRepo readerRepo;
  late CacheJanitor janitor;
  late FakeSource source;
  late StreamController<QueueSnapshot> snapshots;
  final fetchedUrls = <String>[];

  setUp(() async {
    db = await openTestDb();
    tempRoot = await io.Directory.systemTemp.createTemp('starcodex_dl_t');
    await SeriesDao(db).upsertByTitleNorm(Series(
      title: 'Nano Machine',
      titleNorm: 'nano machine',
      createdAt: 0,
      updatedAt: 0,
    ));
    seriesDao = SeriesDao(db);
    chaptersDao = ChaptersDao(db);
    settingsDao = SettingsDao(db);
    downloadsDao = DownloadsDao(db);
    blobs = BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db));
    await blobs.ensureDir();
    source = FakeSource('slow-manga');
    readerRepo = ReaderRepo(
      sources: [source],
      seriesDao: seriesDao,
      chaptersDao: chaptersDao,
      blobs: blobs,
      pipeline: ImagePipeline(
        http: SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async {
            fetchedUrls.add(uri.toString());
            return Response<List<int>>(
              requestOptions: RequestOptions(path: uri.toString()),
              statusCode: 200,
              data: fakePng(uri.toString().hashCode & 0xFF, 500),
            );
          },
        ),
        blobs: blobs,
        compressor: (bytes, {originalW, originalH, maxWidth}) async =>
            Uint8List.fromList(bytes.reversed.toList()),
      ),
    );
    janitor = CacheJanitor(
        db: db, blobs: blobs, settings: settingsDao);
    snapshots = StreamController<QueueSnapshot>.broadcast();
  });

  tearDown(() async {
    await snapshots.close();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  DownloadsRepo repo({Future<bool> Function()? isUnmetered}) =>
      DownloadsRepo(
        readerRepo: readerRepo,
        seriesDao: seriesDao,
        chaptersDao: chaptersDao,
        downloadsDao: downloadsDao,
        settingsDao: settingsDao,
        janitor: janitor,
        isUnmetered: isUnmetered,
      )..snapshots.listen(snapshots.add);

  /// [prepopulatePages] false simulates a chapter the user NEVER opened in
  /// the reader (no chapter_pages rows) — the normal download case.
  Future<int> seedChapter(
      {List<String> pages = const ['https://www.example.com/p1.jpg'],
      String type = 'manhwa',
      double number = 1,
      bool prepopulatePages = true}) async {
    await db.update('series', {'type': type},
        where: 'title_norm = ?', whereArgs: ['nano machine']);
    final urlNum =
        number == number.roundToDouble() ? number.toInt() : number;
    final c = Chapter(
      seriesId: 1,
      sourceId: 'slow-manga',
      number: number,
      url: 'https://www.slow-manga.net/c$urlNum',
      fetchedAt: 0,
    );
    source.pagesResults[c.url] = pages;
    final id = await chaptersDao.upsert(c);
    if (prepopulatePages) {
      await chaptersDao.replacePages(id, [
        for (var i = 0; i < pages.length; i++)
          ChapterPage(chapterId: id, idx: i, url: pages[i]),
      ]);
    }
    await downloadsDao.enqueue(id, createdAt: 1);
    return id;
  }

  test('tick downloads a chapter: blobs land, state=done, pins recompute',
      () async {
    final id = await seedChapter();
    final got = <QueueSnapshot>[];
    final sub = snapshots.stream.listen(got.add);
    final repo1 = repo();
    await repo1.tick();
    await repo1.tick(); // snapshot pass

    expect(await downloadsDao.isDownloaded(id), isTrue);
    final pages = await chaptersDao.pages(id);
    expect(pages.every((p) => p.contentHash != null), isTrue);
    expect(await blobs.totalBytes(pinned: true), greaterThan(0));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(got, isNotEmpty);
    expect(got.last.hasActive, isFalse);
    await sub.cancel();
  });

  test('unfailing retries: 3 strikes → error, backoff gates the 2nd try',
      () async {
    final id = await seedChapter(prepopulatePages: false);
    source.error = StateError('host down');
    final repo1 = repo();
    await repo1.tick(); // fail 1 → queued + backoff
    expect((await downloadsDao.byState('queued')).length, 1);
    await repo1.tick(); // backoff-gated: still queued, no new attempt
    expect((await downloadsDao.byState('queued')).length, 1);

    // Force past the backoff gate by resuming (clears it) twice more.
    await repo1.resume(id);
    await repo1.tick(); // fail 2
    await repo1.resume(id);
    await repo1.tick(); // fail 3 → error
    final rows = await downloadsDao.byState('error');
    expect(rows.single['chapter_id'] as int, id);
    expect(rows.single['error'], isNotNull);
  });

  test('resume retries a failed chapter and finishes it', () async {
    final id = await seedChapter(prepopulatePages: false);
    source.error = StateError('down');
    final repo1 = repo();
    await repo1.tick();
    await repo1.resume(id);
    await repo1.tick();
    source.error = null;
    await repo1.resume(id);
    await repo1.tick();
    expect(await downloadsDao.isDownloaded(id), isTrue);
  });

  test('pause + pauseAll keep rows out of the worker', () async {
    final id = await seedChapter();
    final repo1 = repo();
    await repo1.pause(id);
    await repo1.tick();
    expect(await downloadsDao.isDownloaded(id), isFalse);

    await downloadsDao.updateState(id, 'queued');
    final id2 = await seedChapter(number: 2);
    expect(id2, isNot(id)); // distinct row, not an upsert onto chapter 1
    await repo1.pauseAll();
    await repo1.tick();
    expect(await downloadsDao.isDownloaded(id), isFalse);
    expect(await downloadsDao.isDownloaded(id2), isFalse);
  });

  test('wi-fi-only ON + metered check → queue untouched', () async {
    final id = await seedChapter();
    var meteredCalls = 0;
    final repo1 = repo(isUnmetered: () async {
      meteredCalls++;
      return false;
    });
    final got = <QueueSnapshot>[];
    final sub = snapshots.stream.listen(got.add);
    await repo1.tick();
    expect(meteredCalls, 1);
    expect(await downloadsDao.isDownloaded(id), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(got.any((s) => s.wifiPaused), isTrue);
    await sub.cancel();
  });

  test('novel chapter: text stored via loadNovelText, done without pages',
      () async {
    final id = await seedChapter(type: 'novel');
    source.novelTexts['https://www.slow-manga.net/c1'] = 'ตอนที่ 1\n\nจบ';
    final repo1 = repo();
    // Text, not pages — the estimate must not burn the 8 MB page default.
    expect(await repo1.estimateBytes([id]), 64 * 1024);
    await repo1.tick();
    expect(await downloadsDao.isDownloaded(id), isTrue);
    expect(await chaptersDao.text(id), 'ตอนที่ 1\n\nจบ');
  });

  test('readyOffline lists only series with blobs still on disk', () async {
    await seedChapter(pages: const [
      'https://www.example.com/p1.jpg',
      'https://www.example.com/p2.jpg',
    ]);
    final repo1 = repo();
    await repo1.tick();
    await repo1.tick();

    var ready = await repo1.readyOffline();
    expect(ready.single.chapterCount, 1);
    expect(ready.single.bytes, greaterThan(0));

    // Simulate cache loss: delete the blob FILES (integrity pass drops the
    // rows; the downloads row must then demote → tab no longer lists).
    final dir = blobs.blobsDir;
    await for (final f in dir.list(recursive: true)) {
      if (f is io.File) await f.delete();
    }
    await janitor.runNow(withIntegrity: true);
    ready = await repo1.readyOffline();
    expect(ready, isEmpty);
    final done = await downloadsDao.byState('done');
    expect(done, isEmpty); // demoted, not stale-listed
  });

  test('un-opened chapter (no page rows): download persists pages + hashes',
      () async {
    final id = await seedChapter(prepopulatePages: false, pages: const [
      'https://www.example.com/a.jpg',
      'https://www.example.com/b.jpg',
    ]);
    final repo1 = repo();
    await repo1.tick();
    await repo1.tick();

    // Before the fix: setPageHash wrote to nothing, blobs landed unlinked,
    // and the done row demoted at the next integrity pass.
    expect(await downloadsDao.isDownloaded(id), isTrue);
    final pages = await chaptersDao.pages(id);
    expect(pages.length, 2);
    expect(pages.every((p) => p.contentHash != null), isTrue);
    expect((await chaptersDao.byId(id))!.pageCount, 2);
    expect(await repo1.readyOffline(), isNotEmpty);
  });

  test('estimate: unfetched → 8 MB default; fetched pages use real size',
      () async {
    final id = await seedChapter(pages: const [
      'https://www.example.com/p1.jpg',
    ]);
    final repo1 = repo();
    expect(await repo1.estimateBytes([id]), 8 * 1024 * 1024);
    await repo1.tick();
    expect(await repo1.estimateBytes([id]),
        lessThan(8 * 1024 * 1024)); // real ~500-byte page
  });
}

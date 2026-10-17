import 'dart:async' show Completer;
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart' show RequestOptions, Response;
import 'package:sqflite/sqflite.dart' show Database;

import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/dao/blobs_dao.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/repo/reader_repo.dart';
import 'package:star_codex/data/storage/blob_store.dart';
import 'package:star_codex/data/storage/image_pipeline.dart';
import 'package:star_codex/data/sources/source_api.dart';

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
  late ReaderRepo repo;

  setUp(() async {
    db = await openTestDb();
    tempRoot = await io.Directory.systemTemp.createTemp('starcodex_reader_t');
    // chapters.series_id has an FK to series — seed row id 1.
    await SeriesDao(db).upsertByTitleNorm(Series(
      title: 'Nano Machine',
      titleNorm: 'nano machine',
      createdAt: 0,
      updatedAt: 0,
    ));
    chaptersDao = ChaptersDao(db);
    final blobs = BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db));
    await blobs.ensureDir();
    repo = ReaderRepo(
      sources: const [],
      seriesDao: SeriesDao(db),
      chaptersDao: chaptersDao,
      blobs: blobs,
      pipeline: ImagePipeline(
        http: SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async => Response<List<int>>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 200,
            data: fakePng(uri.toString().hashCode & 0xFF, 500),
          ),
        ),
        blobs: blobs,
        // Deterministic "webp": reversed original bytes.
        compressor: (bytes, {originalW, originalH, maxWidth}) async =>
            Uint8List.fromList(bytes.reversed.toList()),
      ),
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  Chapter seed(int seriesId, String source, double number, String url) =>
      Chapter(
        seriesId: seriesId,
        sourceId: source,
        number: number,
        title: 'ตอนที่ $number',
        url: url,
        fetchedAt: 0,
      );

  Future<int> seedChapter(Chapter c, {List<String>? pageUrls}) async {
    final id = await chaptersDao.upsert(c);
    if (pageUrls != null) {
      await chaptersDao.replacePages(
          id,
          [
            for (var i = 0; i < pageUrls.length; i++)
              ChapterPage(chapterId: id, idx: i, url: pageUrls[i]),
          ],
      );
      await chaptersDao.setPageCount(id, pageUrls.length);
    }
    return id;
  }

  group('loadChapter', () {
    test('serves the DB page list with NO network (doc 10 §Prefetch)', () async {
      final c = seed(1, 'slow-manga', 5, 'https://a/ch5');
      final id = await seedChapter(
          c, pageUrls: ['https://img/1.jpg', 'https://img/2.jpg']);
      final loaded = await repo.loadChapter(
          (await chaptersDao.byId(id))!);
      expect(loaded.pages, hasLength(2));
      expect(loaded.pages.first.url, 'https://img/1.jpg');
    });

    test('empty list → source fetch → persisted (R2 bookkeeping)',
        () async {
      final source = FakeSource('slow-manga', pagesResults: {
        'https://a/ch5': ['https://img/x1.jpg', 'https://img/x2.jpg'],
      });
      final c = seed(1, 'slow-manga', 5, 'https://a/ch5');
      final id = await seedChapter(c);
      final repoWithSource = ReaderRepo(
        sources: [source],
        seriesDao: SeriesDao(db),
        chaptersDao: chaptersDao,
        blobs: BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db)),
        pipeline: repo.pipeline,
      );
      final loaded = await repoWithSource.loadChapter(
          (await chaptersDao.byId(id))!);
      expect(loaded.pages, hasLength(2));
      expect(source.pagesCalls, 1);
      // Persisted: a reload hits the DB only.
      await repoWithSource.loadChapter((await chaptersDao.byId(id))!);
      expect(source.pagesCalls, 1);
    });

    test('whole-chapter fallback: own source fails → sibling serves (07 §5)',
        () async {
      final dead = FakeSource('slow-manga'); // no pages → parse error
      final alive = FakeSource('go-manga', pagesResults: {
        'https://b/ch5': ['https://img/y1.jpg'],
      });
      final c1 = seed(1, 'slow-manga', 5, 'https://a/ch5');
      final c2 = seed(1, 'go-manga', 5, 'https://b/ch5');
      await seedChapter(c1);
      await seedChapter(c2);
      final repoWithSources = ReaderRepo(
        sources: [dead, alive],
        seriesDao: SeriesDao(db),
        chaptersDao: chaptersDao,
        blobs: BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db)),
        pipeline: repo.pipeline,
      );
      final loaded = await repoWithSources.loadChapter(c1);
      expect(loaded.chapter.sourceId, 'go-manga');
      expect(loaded.pages.first.url, 'https://img/y1.jpg');
    });

    test('all sources failing throws', () async {
      final dead1 = FakeSource('slow-manga');
      final dead2 = FakeSource('go-manga');
      final c1 = seed(1, 'slow-manga', 5, 'https://a/ch5');
      await seedChapter(c1);
      final c2 = seed(1, 'go-manga', 5, 'https://b/ch5');
      await seedChapter(c2);
      final repoWithSources = ReaderRepo(
        sources: [dead1, dead2],
        seriesDao: SeriesDao(db),
        chaptersDao: chaptersDao,
        blobs: BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db)),
        pipeline: repo.pipeline,
      );
      expect(() => repoWithSources.loadChapter(c1), throwsA(isA<SourceException>()));
    });
  });

  group('fetchPage + TaskQueue', () {
    test('resolvePage fallback: sibling serves once, hash lands on the '
        'ORIGINAL row, second resolve is disk-only', () async {
      // Primary's page URL never resolves → DNS validation fails fast →
      // resolvePage falls to the sibling whose URL the fetcher serves.
      final c1 = seed(1, 'slow-manga', 5, 'https://a/ch5');
      final id1 =
          await seedChapter(c1, pageUrls: ['https://dead.invalid/p0.jpg']);
      final c2 = seed(1, 'go-manga', 5, 'https://b/ch5');
      final id2 =
          await seedChapter(c2, pageUrls: ['https://www.example.com/p0.jpg']);

      var downloads = 0;
      final blobs = BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db));
      final repoFallback = ReaderRepo(
        sources: const [],
        seriesDao: SeriesDao(db),
        chaptersDao: chaptersDao,
        blobs: blobs,
        pipeline: ImagePipeline(
          http: SafeHttp(
            rateLimiter: RateLimiter(seed: 1),
            fetcher: (uri, options) async {
              downloads++;
              return Response<List<int>>(
                requestOptions: RequestOptions(path: uri.toString()),
                statusCode: 200,
                data: fakePng(9, 400),
              );
            },
          ),
          blobs: blobs,
          compressor: (bytes, {originalW, originalH, maxWidth}) async =>
              Uint8List.fromList(bytes.reversed.toList()),
        ),
      );

      final loaded =
          await repoFallback.loadChapter((await chaptersDao.byId(id1))!);
      final pf = await repoFallback.resolvePage(loaded, 0);
      expect(pf.hash, isNotNull);
      expect(downloads, 1, reason: 'sibling fetched exactly once');

      // The resolved hash is persisted onto the REQUESTED chapter's row —
      // the next open is a plain cache hit on the original ref.
      final rows = await chaptersDao.pages(id1);
      expect(rows.single.contentHash, pf.hash);

      final pf2 = await repoFallback.resolvePage(loaded, 0);
      expect(pf2.hash, pf.hash);
      expect(downloads, 1, reason: 'second resolve is disk-only');
      expect(await chaptersDao.pages(id2), isNotEmpty);
    });

    test('fetch stores blob, persists hash+dims back on chapter_pages',
        () async {
      final source = FakeSource('slow-manga');
      final repoWithSource = ReaderRepo(
        sources: [source],
        seriesDao: SeriesDao(db),
        chaptersDao: chaptersDao,
        blobs: BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db)),
        pipeline: repo.pipeline,
      );
      final c = seed(1, 'slow-manga', 1, 'https://a/ch1');
      final id = await seedChapter(c, pageUrls: ['https://www.example.com/p1.jpg']);
      final ref = ReaderPageRef(idx: 0, url: 'https://www.example.com/p1.jpg');

      final pf = await repoWithSource.fetchPage(id, ref, source.referer);
      expect(pf.path, startsWith('blobs/'));

      final rows = await chaptersDao.pages(id);
      expect(rows.single.contentHash, isNotNull);
    });

    test('queue: max 2 active under load (doc 10 §Prefetch)', () async {
      var active = 0;
      var peak = 0;
      final gate = <Completer<void>>[];
      final q = TaskQueue(maxActive: 2);
      final futures = <Future<int>>[];
      for (var i = 0; i < 6; i++) {
        futures.add(q.run(() async {
          active++;
          peak = peak > active ? peak : active;
          final c = Completer<void>();
          gate.add(c);
          await c.future;
          active--;
          return i;
        }));
      }
      // First two run; the rest wait.
      await Future<void>.delayed(Duration.zero);
      expect(peak, 2);
      // Release the gates in waves — every finished task lets exactly one
      // waiter through, which opens the next gate.
      var released = 0;
      while (released < 6) {
        await Future<void>.delayed(Duration.zero);
        final wave = [...gate];
        gate.clear();
        for (final g in wave) {
          g.complete();
          released++;
        }
      }
      expect(await Future.wait(futures), [0, 1, 2, 3, 4, 5]);
    });
  });

  group('adjacentChapter', () {
    test('next prefers the same source, nearest number wins', () async {
      await seedChapter(seed(1, 'slow-manga', 9, 'https://a/9'));
      await seedChapter(seed(1, 'go-manga', 9, 'https://b/9'));
      await seedChapter(seed(1, 'go-manga', 9.5, 'https://b/9.5'));
      await seedChapter(seed(1, 'slow-manga', 10, 'https://a/10'));

      final current = seed(1, 'go-manga', 9, 'https://b/9');
      final next = await chaptersDao.adjacent(current, forward: true);
      expect(next!.number, 9.5); // nearest above, same source go-manga
      final prev = await chaptersDao.adjacent(
          seed(1, 'go-manga', 9, 'https://b/9'), forward: false);
      expect(prev, isNull); // nothing below 9
    });
  });
}

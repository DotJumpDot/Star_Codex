import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/dao/blobs_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/storage/blob_store.dart';
import 'package:star_codex/data/storage/cache_janitor.dart';
import 'package:star_codex/data/storage/image_pipeline.dart';

import 'helpers.dart';

Uint8List fakePng(int seed, int size) {
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = (seed + i) & 0xFF;
  }
  // PNG magic so the pipeline accepts the bytes.
  b[0] = 0x89; b[1] = 0x50; b[2] = 0x4E; b[3] = 0x47;
  return b;
}

Response<List<int>> okResponse(Uri uri, List<int> data) =>
    Response<List<int>>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
      data: data,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempRoot;
  late Database db;
  late BlobStore blobs;
  late CacheJanitor janitor;

  setUp(() async {
    tempRoot = await io.Directory.systemTemp.createTemp('starcodex-test');
    db = await openTestDb();
    blobs = BlobStore(rootDir: tempRoot, blobsDao: BlobsDao(db));
    janitor = CacheJanitor(
      db: db,
      blobs: blobs,
      settings: SettingsDao(db),
    );
    await blobs.ensureDir();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('ImagePipeline', () {
    test('fetch → blob written with correct hash; second fetch hits dedup',
        () async {
      final payload = fakePng(1, 1000);
      var fetchCalls = 0;
      final pipeline = ImagePipeline(
        http: SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async {
            fetchCalls++;
            return okResponse(uri, payload);
          },
        ),
        blobs: blobs,
        // Fake compressor: "webp" = reversed original (deterministic).
        compressor: (bytes, {originalW, originalH, maxWidth}) async =>
            Uint8List.fromList(bytes.reversed.toList()),
      );

      final r1 =
          await pipeline.fetchAndStore('https://www.example.com/a.jpg');
      expect(r1.fromCache, isFalse);
      expect(r1.hash, sha256.convert(payload).toString(),
          reason: 'hash is of the ORIGINAL bytes (S1)');
      expect(r1.path, endsWith('.webp'));
      expect(r1.path, startsWith('blobs/'));

      final file = io.File(blobs.absolutePath(r1.path));
      expect(await file.exists(), isTrue);
      expect(await file.length(), r1.storedBytes);

      final r2 =
          await pipeline.fetchAndStore('https://www.example.com/a.jpg');
      expect(r2.fromCache, isTrue);
      expect(r2.hash, r1.hash);
      expect(r2.path, r1.path);
      // fetchAndStore must fetch to hash the bytes (the no-network dedup is
      // the repo read path); the guarantee is: still only ONE stored file.
      expect(fetchCalls, 2);
      expect(await blobs.listAll(), hasLength(1),
          reason: 'identical bytes stored exactly once (S1)');
    });

    test('big buffers hash off the UI isolate, hash value unchanged',
        () async {
      // > _isolateHashThreshold (256 KiB) → Isolate.run path. Regression
      // (2026-10-21): pure-Dart sha256 over multi-MB webtoon strips ran
      // on the UI isolate and froze first-read scrolling. Only magic
      // bytes gate entry into the pipeline, so a synthetic payload with
      // a PNG header exercises the hashing path fine.
      final payload = fakePng(7, 600 * 1024);
      final pipeline = ImagePipeline(
        http: SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async => okResponse(uri, payload),
        ),
        blobs: blobs,
        compressor: (bytes, {originalW, originalH, maxWidth}) async => null,
      );
      final r =
          await pipeline.fetchAndStore('https://www.example.com/big.png');
      expect(r.hash, sha256.convert(payload).toString());
      expect(r.storedBytes, payload.length);
    });

    test('GIF passthrough: stored as-is with .gif, no re-encode', () async {
      final gif = Uint8List.fromList(
          [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2, 3, 4, 5, 6]);
      var compressed = false;
      final pipeline = ImagePipeline(
        http: SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async => okResponse(uri, gif),
        ),
        blobs: blobs,
        compressor: (bytes, {originalW, originalH, maxWidth}) async {
          compressed = true;
          return bytes;
        },
      );

      final r = await pipeline.fetchAndStore('https://www.example.com/b.gif');
      expect(r.path, endsWith('.gif'));
      expect(compressed, isFalse, reason: 'GIF stored as-is (03 §1)');
      expect(await io.File(blobs.absolutePath(r.path)).readAsBytes(), gif);
    });

    test('non-image bytes are rejected', () async {
      final pipeline = ImagePipeline(
        http: SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: (uri, options) async => okResponse(
              uri, '<html>error page</html>'.codeUnits),
        ),
        blobs: blobs,
      );

      await expectLater(
        () => pipeline.fetchAndStore('https://www.example.com/c.html'),
        throwsA(isA<StoreException>()),
      );
    });

    test('fetchAndStoreIndexed: warm start answers from disk, no network',
        () async {
      // User report 2026-10-20: covers re-downloaded on every app start
      // because the content-hash dedup only fires AFTER a download. The
      // blob_urls index must make the second app start (fresh pipeline
      // AND fresh session memo — only the DB/store persist) a pure disk
      // hit.
      final payload = fakePng(2, 800);
      var fetchCalls = 0;
      ImagePipeline makePipeline() => ImagePipeline(
            http: SafeHttp(
              rateLimiter: RateLimiter(seed: 1),
              fetcher: (uri, options) async {
                fetchCalls++;
                return okResponse(uri, payload);
              },
            ),
            blobs: blobs,
            compressor: (bytes, {originalW, originalH, maxWidth}) async =>
                Uint8List.fromList(bytes.reversed.toList()),
          );

      final r1 = await makePipeline()
          .fetchAndStoreIndexed('https://www.example.com/cover.jpg');
      expect(r1.fromCache, isFalse);
      expect(fetchCalls, 1);

      // "App restart": new pipeline instance, same DB + store.
      final r2 = await makePipeline()
          .fetchAndStoreIndexed('https://www.example.com/cover.jpg');
      expect(r2.fromCache, isTrue, reason: 'warm start must not re-download');
      expect(r2.hash, r1.hash);
      expect(r2.path, r1.path);
      expect(fetchCalls, 1);
    });

    test('fetchAndStoreIndexed self-heals after LRU eviction', () async {
      final payload = fakePng(3, 500);
      var fetchCalls = 0;
      ImagePipeline makePipeline() => ImagePipeline(
            http: SafeHttp(
              rateLimiter: RateLimiter(seed: 1),
              fetcher: (uri, options) async {
                fetchCalls++;
                return okResponse(uri, payload);
              },
            ),
            blobs: blobs,
            compressor: (bytes, {originalW, originalH, maxWidth}) async =>
                Uint8List.fromList(bytes.reversed.toList()),
          );
      const url = 'https://www.example.com/evicted.jpg';
      final r1 = await makePipeline().fetchAndStoreIndexed(url);
      expect(fetchCalls, 1);
      // Evict the blob (janitor LRU): the index row alone must miss and
      // re-fetch rather than answering with a dead path.
      await blobs.delete(r1.hash);
      final r2 = await makePipeline().fetchAndStoreIndexed(url);
      expect(r2.fromCache, isFalse);
      expect(fetchCalls, 2);
    });

    test('bandsFor slices oversized pages once, then serves from cache',
        () async {
      // Oversized webtoon strip (800×25049 — the slow-manga ch.67 black
      // void, 2026-10-21). Fake slicer returns two tiny PNG bands.
      final payload = fakePng(4, 1200);
      var sliceCalls = 0;
      ImagePipeline makePipeline() => ImagePipeline(
            http: SafeHttp(
              rateLimiter: RateLimiter(seed: 1),
              fetcher: (uri, options) async => okResponse(uri, payload),
            ),
            blobs: blobs,
            compressor: (bytes, {originalW, originalH, maxWidth}) async =>
                Uint8List.fromList(bytes.reversed.toList()),
            bandSlicer: (absolutePath, maxBandHeight) async {
              sliceCalls++;
              return [fakePng(5, 600), fakePng(6, 600)];
            },
          );
      final parent =
          await makePipeline().fetchAndStore('https://www.example.com/tall.jpg');
      // Synthesize an oversized parent: dims come from the URL row path,
      // so call bandsFor with a tall PageResult over the same blob.
      final tall = PageResult(
        hash: parent.hash,
        path: parent.path,
        storedBytes: parent.storedBytes,
        width: 800,
        height: 25049,
        fromCache: true,
      );
      expect(ImagePipeline.gpuBandThreshold, lessThan(25049));

      final b1 = await makePipeline().bandsFor(tall);
      expect(b1, hasLength(2), reason: 'two bands from the fake slicer');
      expect(sliceCalls, 1);

      // Second resolve (fresh pipeline): served from page_bands, no
      // re-slicing.
      final b2 = await makePipeline().bandsFor(tall);
      expect(b2, hasLength(2));
      expect(sliceCalls, 1);

      // Normal-height pages never slice.
      final normal = PageResult(
        hash: parent.hash,
        path: parent.path,
        storedBytes: parent.storedBytes,
        width: 800,
        height: 1200,
        fromCache: true,
      );
      expect(await makePipeline().bandsFor(normal), isEmpty);
      expect(sliceCalls, 1);

      // Slicer unavailable (tests/desktop channel) with no cached rows →
      // empty, caller renders the unsliced page.
      await blobs.putBands(tall.hash, const []);
      final bare = ImagePipeline(
        http: SafeHttp(
            rateLimiter: RateLimiter(seed: 1),
            fetcher: (uri, options) async => okResponse(uri, payload)),
        blobs: blobs,
      );
      expect(await bare.bandsFor(tall), isEmpty);
    });
  });

  group('CacheJanitor', () {
    Future<String> addBlob(String hash, int bytes,
        {bool pinned = false, required int lastAccess}) async {
      final rel = await blobs.write(hash, Uint8List(bytes));
      await blobs.insertRow(BlobRow(
        hash: hash,
        path: rel,
        bytes: bytes,
        isPinned: pinned,
        lastAccess: lastAccess,
      ));
      return rel;
    }

    test('evicts oldest unpinned over the limit, never pinned', () async {
      await addBlob('aa${'1' * 62}', 100, lastAccess: 1000);
      final pinnedRel =
          await addBlob('bb${'2' * 62}', 300, pinned: true, lastAccess: 500);
      await addBlob('cc${'3' * 62}', 200, lastAccess: 2000);

      // Unpinned total = 300; limit 250 → evict oldest unpinned (aa…).
      await SettingsDao(db).upsert('cache_limit_bytes', '250');
      final evicted = await janitor.enforceLru();
      expect(evicted, 1);

      expect(await blobs.exists('aa${'1' * 62}'), isFalse,
          reason: 'oldest unpinned evicted (row + file)');
      expect(await blobs.exists('cc${'3' * 62}'), isTrue);
      expect(await blobs.exists('bb${'2' * 62}'), isTrue,
          reason: 'pinned never evicted');
      expect(io.File(blobs.absolutePath(pinnedRel)).existsSync(), isTrue);
    });

    test('integrityPass drops rows without files and orphan files',
        () async {
      final rowRel = await addBlob('dd${'4' * 62}', 50, lastAccess: 1);
      io.File(blobs.absolutePath(rowRel)).deleteSync(); // row without file
      final orphanDir =
          io.Directory(p.join(tempRoot.path, 'blobs', 'ee'));
      await orphanDir.create(recursive: true);
      final orphan = io.File(p.join(orphanDir.path, 'ee${'5' * 62}.webp'));
      await orphan.writeAsBytes([1, 2, 3]); // file without row

      final result = await blobs.integrityPass();
      expect(result.rowsDropped, 1);
      expect(result.filesDeleted, 1);
      expect(await blobs.exists('dd${'4' * 62}'), isFalse);
      expect(await orphan.exists(), isFalse);
    });

    test('recomputePins pins done-download blobs and unpins stale',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final seriesId = await db.insert('series', {
        'title': 'S',
        'title_norm': 's',
        'created_at': now,
        'updated_at': now,
      });
      final chId = await db.insert('chapters', {
        'series_id': seriesId,
        'source_id': 'go-manga',
        'number': 1.0,
        'url': 'u',
        'fetched_at': now,
      });
      await db.insert('chapter_pages', {
        'chapter_id': chId,
        'idx': 0,
        'url': 'u0',
        'content_hash': 'ff${'6' * 62}',
      });
      await addBlob('ff${'6' * 62}', 10, lastAccess: 1);
      final downloads = DownloadsDao(db);

      await downloads.enqueue(chId, createdAt: now);
      await janitor.recomputePins();
      expect((await blobs.blobRow('ff${'6' * 62}'))!.isPinned, isFalse,
          reason: 'queued only — not pinned yet');

      await downloads.updateState(chId, 'done');
      await janitor.recomputePins();
      expect((await blobs.blobRow('ff${'6' * 62}'))!.isPinned, isTrue);

      await downloads.delete(chId);
      await janitor.recomputePins();
      expect((await blobs.blobRow('ff${'6' * 62}'))!.isPinned, isFalse,
          reason: 'removed download → unpinned');
    });

    test('enforceQuota refuses when pinned + incoming exceeds quota',
        () async {
      await addBlob('ab${'7' * 62}', 300, pinned: true, lastAccess: 1);
      await SettingsDao(db).upsert('total_quota_bytes', '350');

      await janitor.enforceQuota(50); // 300 + 50 = 350 → boundary OK
      await expectLater(
        () => janitor.enforceQuota(51),
        throwsA(isA<QuotaException>()
            .having((e) => e.freeBytes, 'freeBytes', 50)),
      );
    });
  });
}

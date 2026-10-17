import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
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
import 'package:star_codex/ui/reader/reader_router.dart';

import 'fake_source.dart';
import 'helpers.dart';

void main() {
  late Database db;
  late io.Directory tempDir;
  late ChaptersDao chaptersDao;

  setUp(() async {
    db = await openTestDb();
    tempDir = await io.Directory.systemTemp.createTemp('starcodex_novel_t');
    await SeriesDao(db).upsertByTitleNorm(
        Series(title: 'X', titleNorm: 'x', createdAt: 0, updatedAt: 0));
    chaptersDao = ChaptersDao(db);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ReaderRepo repoWith(List<FakeSource> sources) {
    final blobs = BlobStore(rootDir: tempDir, blobsDao: BlobsDao(db));
    return ReaderRepo(
      sources: sources,
      seriesDao: SeriesDao(db),
      chaptersDao: chaptersDao,
      blobs: blobs,
      pipeline: ImagePipeline(
        http: SafeHttp(rateLimiter: RateLimiter(seed: 1)),
        blobs: blobs,
      ),
    );
  }

  group('resolveReaderMode (doc 11: override wins over type default)', () {
    test('type defaults', () {
      expect(readerModeForType('manga'), ReaderMode.paged);
      expect(readerModeForType('novel'), ReaderMode.novel);
      expect(readerModeForType('manhwa'), ReaderMode.webtoon);
      expect(readerModeForType(null), ReaderMode.webtoon);
    });

    test('per-series override wins', () {
      expect(resolveReaderMode('manhwa', 'paged'), ReaderMode.paged);
      expect(resolveReaderMode('manga', 'webtoon'), ReaderMode.webtoon);
      expect(resolveReaderMode('manhwa', 'auto'), ReaderMode.webtoon);
    });
  });

  group('ReaderRepo.loadNovelText (doc 06 §3 + doc 11 B)', () {
    test('chapter_text hit → no network', () async {
      final id = await chaptersDao.upsert(Chapter(
        seriesId: 1,
        sourceId: 'nekopost',
        number: 1,
        title: 'ตอนที่ 1',
        url: 'nekopost:chapter:1',
        fetchedAt: 0,
      ));
      await chaptersDao.saveText(id, 'ย่อหน้าแรก\n\nย่อหน้าที่สอง');
      final repo = repoWith(const []);
      final text =
          await repo.loadNovelText((await chaptersDao.byId(id))!);
      expect(text, 'ย่อหน้าแรก\n\nย่อหน้าที่สอง');
    });

    test('missing → source.novelText → persisted (doc 06 §3)', () async {
      final source = FakeSource('nekopost', novelTexts: {
        'nekopost:chapter:2': 'เนื้อหาจากเว็บ',
      });
      final id = await chaptersDao.upsert(Chapter(
        seriesId: 1,
        sourceId: 'nekopost',
        number: 2,
        title: 'ตอนที่ 2',
        url: 'nekopost:chapter:2',
        fetchedAt: 0,
      ));
      final repo = repoWith([source]);
      final text =
          await repo.loadNovelText((await chaptersDao.byId(id))!);
      expect(text, 'เนื้อหาจากเว็บ');
      expect(source.novelCalls, 1);
      // Persisted: a reload hits chapter_text, not the source.
      await repo.loadNovelText((await chaptersDao.byId(id))!);
      expect(source.novelCalls, 1);
      expect(await chaptersDao.text(id), 'เนื้อหาจากเว็บ');
    });

    test('null/empty novel text is a parse bug (doc 06 §3)', () async {
      final source = FakeSource('nekopost'); // no novelTexts → null
      final id = await chaptersDao.upsert(Chapter(
        seriesId: 1,
        sourceId: 'nekopost',
        number: 3,
        title: 'ตอนที่ 3',
        url: 'nekopost:chapter:3',
        fetchedAt: 0,
      ));
      final repo = repoWith([source]);
      expect(
          () async => repo.loadNovelText((await chaptersDao.byId(id))!),
          throwsA(isA<SourceException>()));
    });
  });
}

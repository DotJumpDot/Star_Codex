import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:star_codex/data/dao/blobs_dao.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/dao/tags_dao.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SeriesDao seriesDao;
  late ChaptersDao chaptersDao;
  late TagsDao tagsDao;
  late LibraryDao libraryDao;
  late BlobsDao blobsDao;
  late SettingsDao settingsDao;
  late HistoryDao historyDao;
  late DownloadsDao downloadsDao;

  setUp(() async {
    db = await openTestDb();
    seriesDao = SeriesDao(db);
    chaptersDao = ChaptersDao(db);
    tagsDao = TagsDao(db);
    libraryDao = LibraryDao(db);
    blobsDao = BlobsDao(db);
    settingsDao = SettingsDao(db);
    historyDao = HistoryDao(db);
    downloadsDao = DownloadsDao(db);
  });

  test('series + 2 sources + chapters + pages round-trip', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seriesId = await seriesDao.insert(Series(
      title: 'มังกรผยาม',
      originalTitle: 'Dragon Awakens',
      titleNorm: 'มังกรผยาม',
      type: 'manhwa',
      origin: 'korea',
      status: 'ongoing',
      createdAt: now,
      updatedAt: now,
    ));

    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: 'go-manga',
      sourceUrl: 'https://www.go-manga.com/series/dragon',
      sourceTitle: 'Dragon Awakens',
      altTitles: ['มังกรผยาม', 'Dragon'],
      lastChapterNumber: 42,
      fetchedAt: now,
    ));
    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: 'slow-manga',
      sourceUrl: 'https://www.slow-manga.net/dragon',
      fetchedAt: now,
    ));

    final links = await seriesDao.sourcesOf(seriesId);
    expect(links.length, 2);
    final go = links.firstWhere((l) => l.sourceId == 'go-manga');
    expect(go.altTitles, ['มังกรผยาม', 'Dragon']);
    expect(go.lastChapterNumber, 42);

    final chId = await chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: 'go-manga',
      number: 42,
      title: 'ตอนที่ 42',
      url: 'https://www.go-manga.com/series/dragon/42',
      fetchedAt: now,
    ));
    await chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: 'go-manga',
      number: 41.5,
      url: 'https://www.go-manga.com/series/dragon/41.5',
      fetchedAt: now,
    ));
    // Upsert on the same (series, source, number) must not duplicate.
    await chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: 'go-manga',
      number: 42,
      url: 'https://www.go-manga.com/series/dragon/42',
      fetchedAt: now + 1,
    ));

    final chapters = await chaptersDao.listForSeries(seriesId);
    expect(chapters.length, 2);
    expect(chapters.first.number, 42); // DESC order
    expect(chapters.first.id, chId);

    await chaptersDao.replacePages(chId, [
      const ChapterPage(chapterId: 0, idx: 0, url: 'u0'),
      const ChapterPage(chapterId: 0, idx: 1, url: 'u1'),
    ].map((p) => ChapterPage(chapterId: chId, idx: p.idx, url: p.url)).toList());
    final pages = await chaptersDao.pages(chId);
    expect(pages.length, 2);
    expect(pages[1].idx, 1);

    await chaptersDao.setPageHash(chId, 0, 'deadbeef');
    final hashed = await chaptersDao.pages(chId);
    expect(hashed[0].contentHash, 'deadbeef');
    expect(hashed[1].contentHash, isNull);

    await chaptersDao.saveText(chId, 'นิยาย บทที่ 1 เนื้อหา...');
    expect(await chaptersDao.text(chId), contains('บทที่ 1'));
  });

  test('tags get-or-create and replace set', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await seriesDao.insert(Series(
      title: 'T',
      titleNorm: 't',
      createdAt: now,
      updatedAt: now,
    ));
    await tagsDao.setForSeries(id, ['Action', 'พระเอกเทพ']);
    await tagsDao.setForSeries(id, ['Action', 'Drama']);
    expect(await tagsDao.tagsOf(id), ['Action', 'Drama']);
    expect((await db.query('tags')).length, 3); // orphaned tag stays, by design
  });

  test('library, progress, history, downloads, blobs', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seriesId = await seriesDao.insert(Series(
      title: 'L',
      titleNorm: 'l',
      createdAt: now,
      updatedAt: now,
    ));
    final chId = await chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: 'go-manga',
      number: 1,
      url: 'u',
      fetchedAt: now,
    ));

    await libraryDao.add(seriesId, now);
    expect(await libraryDao.contains(seriesId), isTrue);
    await chaptersDao.saveProgress(chId,
        pageIndex: 3, completed: false, readAt: now);
    final p = await chaptersDao.progress(chId);
    expect(p!.pageIndex, 3);

    await historyDao.recordCompletion(chId, seriesId, now);
    await historyDao.recordCompletion(chId, seriesId, now + 1);
    var h = await db.query('reading_history',
        where: 'chapter_id = ?', whereArgs: [chId]);
    // +1 ms is same-session completion spam (the readers save every
    // 500 ms at the chapter end) — refreshes read_at, does NOT bump.
    expect(h.single['times_read'], 1);
    expect(h.single['read_at'], now + 1);
    await historyDao.recordCompletion(chId, seriesId, now + 120000);
    h = await db.query('reading_history',
        where: 'chapter_id = ?', whereArgs: [chId]);
    expect(h.single['times_read'], 2); // a later re-read counts

    await downloadsDao.enqueue(chId, createdAt: now);
    await downloadsDao.updateState(chId, 'done');
    expect(await downloadsDao.isDownloaded(chId), isTrue);

    await blobsDao.upsert(BlobRow(
        hash: 'h1', path: 'ab/h1.webp', bytes: 100, lastAccess: now));
    await blobsDao.setPinned('h1', true);
    expect(await blobsDao.pinnedBytes(), 100);
    expect((await blobsDao.evictableOldestFirst()), isEmpty); // pinned
    expect(await blobsDao.totalBytes(), 100);

    final catId = await libraryDao.addCategory('กำลังอ่าน');
    await libraryDao.addToCategory(seriesId, catId);
    expect((await libraryDao.categoriesOf(seriesId)).single.name, 'กำลังอ่าน');

    await settingsDao.upsert('language', 'en');
    final all = await settingsDao.getAll();
    expect(all['language'], 'en');
    expect(all['cache_limit_bytes'], '5368709120'); // seeded default intact
  });

  test('deleting a series cascades chapters/pages/downloads/progress/history/library',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seriesId = await seriesDao.insert(Series(
      title: 'C',
      titleNorm: 'c',
      createdAt: now,
      updatedAt: now,
    ));
    final chId = await chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: 'go-manga',
      number: 1,
      url: 'u',
      fetchedAt: now,
    ));
    await chaptersDao.replacePages(chId, [
      ChapterPage(chapterId: chId, idx: 0, url: 'u0'),
    ]);
    await downloadsDao.enqueue(chId, createdAt: now);
    await chaptersDao.saveProgress(chId, pageIndex: 0, completed: false, readAt: now);
    await historyDao.recordCompletion(chId, seriesId, now);
    await libraryDao.add(seriesId, now);

    await seriesDao.delete(seriesId);

    expect(await db.query('chapters'), isEmpty);
    expect(await db.query('chapter_pages'), isEmpty);
    expect(await db.query('downloads'), isEmpty);
    expect(await db.query('read_progress'), isEmpty);
    expect(await db.query('reading_history'), isEmpty);
    expect(await db.query('library'), isEmpty);
  });
}

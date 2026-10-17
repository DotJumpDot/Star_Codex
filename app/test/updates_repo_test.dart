import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/repo/updates_repo.dart';
import 'package:star_codex/data/sources/source_api.dart';

import 'fake_source.dart';
import 'helpers.dart';

const _detailV1 = SourceSeriesDetail(
  title: 'Nano Machine',
  chapters: [
    SourceChapter(
        url: 'https://www.slow-manga.net/n/1',
        title: 'ตอนที่ 1',
        number: 1,
        uploadedAt: 1000),
    SourceChapter(
        url: 'https://www.slow-manga.net/n/2',
        title: 'ตอนที่ 2',
        number: 2,
        uploadedAt: 2000),
  ],
);

void main() {
  late Database db;
  late SeriesDao seriesDao;
  late ChaptersDao chaptersDao;
  late LibraryDao libraryDao;
  late SettingsDao settingsDao;
  late FakeSource source;

  setUp(() async {
    db = await openTestDb();
    seriesDao = SeriesDao(db);
    chaptersDao = ChaptersDao(db);
    libraryDao = LibraryDao(db);
    settingsDao = SettingsDao(db);
    source = FakeSource('slow-manga');
  });

  UpdatesRepo repo() => UpdatesRepo(
        sources: [source],
        seriesDao: seriesDao,
        chaptersDao: chaptersDao,
        libraryDao: libraryDao,
        settingsDao: settingsDao,
      );

  Future<int> seedLibrary({required int fetchedAt}) async {
    final id = await seriesDao.upsertByTitleNorm(Series(
      title: 'Nano Machine',
      titleNorm: 'nano machine',
      createdAt: 0,
      updatedAt: 0,
    ));
    await seriesDao.upsertSource(SeriesSource(
      seriesId: id,
      sourceId: 'slow-manga',
      sourceUrl: 'https://www.slow-manga.net/n/',
      fetchedAt: fetchedAt,
    ));
    // Chapter 1 known, chapter 2 is the new one upstream.
    await chaptersDao.upsert(Chapter(
      seriesId: id,
      sourceId: 'slow-manga',
      number: 1,
      url: 'https://www.slow-manga.net/n/1',
      uploadedAt: 1000,
      fetchedAt: 0,
    ));
    await libraryDao.add(id, 5);
    return id;
  }

  test('checkAll upserts ONLY the diff and stamps fetched_at + last_run',
      () async {
    final sid = await seedLibrary(fetchedAt: 0);
    source.details['https://www.slow-manga.net/n/'] = _detailV1;

    final added = await repo().checkAll(force: true);
    expect(added, 1);

    final chapters = await chaptersDao.listForSeries(sid);
    expect(chapters.length, 2);
    final link = await seriesDao.sourceLink(sid, 'slow-manga');
    expect(link!.fetchedAt, greaterThan(0));
    expect(link.lastChapterNumber, 2);
    expect(
        int.parse((await settingsDao.get('updates_last_run'))!),
        greaterThan(0));
  });

  test('run-gate: a check < 6 h ago does nothing unless forced', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await settingsDao.upsert('updates_last_run', '$now');
    final sid = await seedLibrary(fetchedAt: 0);
    source.details['https://www.slow-manga.net/n/'] = _detailV1;

    expect(await repo().checkAll(), 0);
    expect((await chaptersDao.listForSeries(sid)).length, 1);

    expect(await repo().checkAll(force: true), 1);
  });

  test('link-freshness gate: links < 6 h old are skipped when not forced',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sid = await seedLibrary(fetchedAt: now);
    source.details['https://www.slow-manga.net/n/'] = _detailV1;

    expect(await repo().checkAll(), 0);
    expect((await chaptersDao.listForSeries(sid)).length, 1);
    expect(source.detailCalls, 0); // polite: never even hit the source
  });

  test('failing source never blocks the rest (and adds nothing)', () async {
    final sid = await seedLibrary(fetchedAt: 0);
    source.error = StateError('cloudflare');
    expect(await repo().checkAll(force: true), 0);
    expect((await chaptersDao.listForSeries(sid)).length, 1);
  });

  test('feed groups unseen chapters, markSeen consumes them', () async {
    final sid = await seedLibrary(fetchedAt: 0);
    source.details['https://www.slow-manga.net/n/'] = _detailV1;
    final r = repo();
    await r.checkAll(force: true);

    // Never-opened feed (last_seen=0) is silent — no fresh-install noise.
    expect(await r.feed(), isEmpty);

    // The user opened the feed once; chapter 2 arrives AFTER that moment.
    await r.markSeen();
    final seenAt = int.parse((await settingsDao.get('updates_last_seen'))!);
    await chaptersDao.upsert(Chapter(
      seriesId: sid,
      sourceId: 'slow-manga',
      number: 2,
      url: 'https://www.slow-manga.net/n/2',
      uploadedAt: seenAt + 1000,
      fetchedAt: 0,
    ));

    final feed = await r.feed();
    expect(feed.single.seriesId, sid);
    expect(feed.single.items.map((i) => i.number), [2]); // unseen only
    expect(await r.unseenCount(), 1);

    // Re-opening the feed later consumes the badge (hermetic: stamp the
    // setting directly — two markSeen() calls can land in the same ms).
    await settingsDao
        .upsert('updates_last_seen', '${seenAt + 2000}');
    expect(await r.feed(), isEmpty);
    expect(await r.unseenCount(), 0);

    // Not-in-library series never appear (the checker is library-scoped).
    await libraryDao.remove(sid);
    expect(await r.unseenCount(), 0);
  });
}

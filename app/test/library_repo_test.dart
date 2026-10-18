import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, Database;

import 'package:star_codex/data/dao/blobs_dao.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/repo/library_cards.dart';
import 'package:star_codex/data/repo/library_repo.dart';
import 'package:star_codex/core/utils/title_norm.dart';

import 'fake_source.dart';
import 'helpers.dart';

void main() {
  late Database db;
  late SeriesDao seriesDao;
  late ChaptersDao chaptersDao;
  late LibraryDao libraryDao;
  late DownloadsDao downloadsDao;
  late HistoryDao historyDao;
  late LibraryRepo repo;

  final now = DateTime.now().millisecondsSinceEpoch;

  setUp(() async {
    db = await openTestDb();
    seriesDao = SeriesDao(db);
    chaptersDao = ChaptersDao(db);
    libraryDao = LibraryDao(db);
    downloadsDao = DownloadsDao(db);
    historyDao = HistoryDao(db);
    repo = LibraryRepo(
      seriesDao: seriesDao,
      chaptersDao: chaptersDao,
      libraryDao: libraryDao,
      downloadsDao: downloadsDao,
      blobsDao: BlobsDao(db),
    );
  });

  Future<int> series(String title,
      {String? type, List<String> tags = const []}) async {
    final id = await seriesDao.insert(Series(
      title: title,
      titleNorm: normalizeTitle(title),
      type: type,
      createdAt: now,
      updatedAt: now,
    ));
    await libraryDao.add(id, now);
    if (tags.isNotEmpty) {
      for (final t in tags) {
        final tagId = await db.insert('tags', {'name': t},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('series_tags', {'series_id': id, 'tag_id': tagId},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    return id;
  }

  Future<void> link(int seriesId, String source, String url,
      {List<String> alts = const [], String? coverUrl}) async {
    await db.insert('series_sources', {
      'series_id': seriesId,
      'source_id': source,
      'source_url': url,
      'alt_titles': alts.isEmpty ? null : '["${alts.join('","')}"]',
      'cover_url': coverUrl,
      'fetched_at': now,
    });
  }

  Future<int> chapter(int seriesId, String source, double number,
      {int? uploadedAt, String url = 'x'}) async {
    return chaptersDao.upsert(Chapter(
      seriesId: seriesId,
      sourceId: source,
      number: number,
      url: '$url/$number',
      uploadedAt: uploadedAt ?? now,
      fetchedAt: now,
    ));
  }

  group('LibraryRepo.load + filterAndSortCards', () {
    test('counters: distinct numbers, completed, new-since-read, downloads',
        () async {
      final a = await series('Novel One', type: 'novel');
      final b = await series('Manga Two');

      // A: novel, two chapters, one completed.
      await link(a, 'nekopost', 'https://n/1');
      final a1 = await chapter(a, 'nekopost', 1);
      await chapter(a, 'nekopost', 2);
      await chaptersDao.saveProgress(a1, pageIndex: 0, completed: true);

      // B: 3 chapters, #1 completed, #2 arrived AFTER last_read.
      await link(b, 'slow-manga', 'https://s/1', alts: ['นาโน']);
      final b1 = await chapter(b, 'slow-manga', 1, uploadedAt: now - 10000);
      await chapter(b, 'slow-manga', 2, uploadedAt: now + 5000);
      // Mirror copy of #2 ALSO counts as new upstream — the badge must
      // still say ONE new chapter (dedupe by number).
      await chapter(b, 'go-manga', 2, uploadedAt: now + 6000);
      await chaptersDao.saveProgress(b1, pageIndex: 0, completed: true);
      await libraryDao.markRead(b, b1, now - 1000);
      final d = await chapter(b, 'go-manga', 99, uploadedAt: now - 10000);
      await downloadsDao.enqueue(d, createdAt: now);
      await downloadsDao.updateState(d, 'done');

      final cards = {for (final c in await repo.load()) c.title: c};

      final cardB = cards['Manga Two']!;
      expect(cardB.chapterNumbers.length, 3); // {1, 2, 99} — dup 2 counts once
      expect(cardB.completedNumbers, {1});
      expect(cardB.unreadCount, 2);
      expect(cardB.newCount, 1); // only the chapter newer than last_read
      expect(cardB.doneDownloads, 1);
      expect(cardB.altTitles, ['นาโน']);

      final cardA = cards['Novel One']!;
      expect(cardA.chapterNumbers.length, 2);
      expect(cardA.unreadCount, 1);
      // Never read/visited (no last_read_at, pre-v4 last_seen_at 0):
      // EVERY dated chapter counts as new — the first detail visit
      // stamps last_seen_at and clears the chip.
      expect(cardA.newCount, 2);
      expect(cardA.type, 'novel');
    });

    test('tabs + filters + sorts (Thai A–Z, unread)', () {
      final millis = DateTime.now().millisecondsSinceEpoch;
      LibraryCard card(String title,
              {String? type,
              int newCount = 0,
              int unread = 9,
              int done = 0,
              int? lastRead,
              List<String> sources = const ['s1'],
              List<String> alts = const [],
              List<String> tags = const []}) =>
          LibraryCard(
            seriesId: title.hashCode,
            title: title,
            addedAt: millis,
            type: type,
            lastReadAt: lastRead,
            chapterNumbers: {
              for (var i = 0; i <= unread; i++) i.toDouble(),
            },
            completedNumbers: const {},
            newCount: newCount,
            maxUpdatedAt: millis,
            doneDownloads: done,
            sources: sources,
            altTitles: alts,
            tags: tags,
          );

      final novel = card('นิยายเรื่องหนึ่ง', type: 'novel', unread: 12);
      final fresh = card('มีตอนใหม่', newCount: 2, unread: 4);
      final thaiB = card('ข้าวผัด', unread: 1);
      final thaiA = card('ก๋วยเตี๋ยว', unread: 1);
      final dl = card('ดาวน์โหลดแล้ว', done: 3);
      final all = [novel, fresh, thaiB, thaiA, dl];

      // Smart tab นิยาย.
      var out = filterAndSortCards(all,
          tab: const SmartTab(SmartKind.novel),
          filters: const LibraryFilters(),
          search: '',
          sort: LibrarySort.lastRead);
      expect(out, [novel]);

      // Smart tab ตอนใหม่.
      out = filterAndSortCards(all,
          tab: const SmartTab(SmartKind.hasNew),
          filters: const LibraryFilters(),
          search: '',
          sort: LibrarySort.lastRead);
      expect(out, [fresh]);

      // Quick filter + source filter AND-combined.
      out = filterAndSortCards(all,
          tab: const AllTab(),
          filters: const LibraryFilters(downloaded: true),
          search: '',
          sort: LibrarySort.lastRead);
      expect(out, [dl]);

      // Search hits alt titles, not just titles.
      final altCard = card('หัวข้ออื่น', alts: ['นาโน แมชชีน']);
      out = filterAndSortCards([novel, altCard],
          tab: const AllTab(),
          filters: const LibraryFilters(),
          search: 'นาโน',
          sort: LibrarySort.lastRead);
      expect(out, [altCard]);

      // Thai A–Z: ก before ข despite the tone mark on ก๋วยเตี๋ยว.
      out = filterAndSortCards([thaiB, thaiA],
          tab: const AllTab(),
          filters: const LibraryFilters(),
          search: '',
          sort: LibrarySort.titleAz);
      expect(out, [thaiA, thaiB]);

      // Unread DESC — but the New-chip partition floats above every sort
      // (user QA 2026-10-18): the fresh-update card leads, then the
      // unread-sorted rest.
      out = filterAndSortCards(all,
          tab: const AllTab(),
          filters: const LibraryFilters(),
          search: '',
          sort: LibrarySort.unread);
      expect(out.first.title, fresh.title);
      expect(out[1].title, novel.title);
    });
  });

  group('History (Plan/12 §5)', () {
    test('recent joins chapter+series, newest first, times_read bumps',
        () async {
      final s1 = await series('Series One');
      final s2 = await series('Two (原作)', type: 'novel');
      await db.update('series', {'original_title': 'Original Two'},
          where: 'id = ?', whereArgs: [s2]);
      final c1 = await chapter(s1, 'slow-manga', 1);
      final c2 = await chapter(s1, 'slow-manga', 2);
      final c3 = await chapter(s2, 'nekopost', 10);

      await historyDao.recordCompletion(c1, s1, now - 100);
      await historyDao.recordCompletion(c3, s2, now - 50);
      await historyDao.recordCompletion(c2, s1, now); // newest
      // A genuine re-read 10 minutes later bumps (10 ms later would be
      // same-session spam and must NOT).
      await historyDao.recordCompletion(c2, s1, now + 600000);

      final rows = await historyDao.recent();
      expect(rows.map((r) => r.chapterId).toList(), [c2, c3, c1]);
      expect(rows.first.timesRead, 2);
      expect(rows.first.title, 'Series One');
      expect(rows[1].title, 'Two (原作)');
      expect(rows[1].originalTitle, 'Original Two');
      expect(rows[1].type, 'novel');
      expect(rows[1].number, 10);
    });

    test('clear wipes history only — read_progress + library untouched',
        () async {
      final s = await series('S');
      final c = await chapter(s, 'slow-manga', 1);
      await chaptersDao.saveProgress(c, pageIndex: 3, completed: true);
      await historyDao.recordCompletion(c, s, now);

      expect(await historyDao.clear(), 1);
      expect(await historyDao.recent(), isEmpty);
      expect((await chaptersDao.progress(c))!.pageIndex, 3);
      expect(await libraryDao.contains(s), isTrue);
    });

    test('deleted chapter cascades its history row (no ghosts)', () async {
      final s = await series('S');
      final c = await chapter(s, 'slow-manga', 1);
      await historyDao.recordCompletion(c, s, now);
      await db.delete('chapters', where: 'id = ?', whereArgs: [c]);
      expect(await historyDao.recent(), isEmpty);
    });

    test('same-session completion spam does not inflate times_read',
        () async {
      final s = await series('S');
      final c = await chapter(s, 'slow-manga', 1);

      // First completion at t=1_000_000.
      await chaptersDao.saveProgress(c,
          pageIndex: 9, completed: true, readAt: 1000000);
      await historyDao.recordCompletion(c, s, 1000000);
      // The reader saves completed=1 every 500 ms while the user sits at
      // the chapter end — these must refresh read_at, NOT times_read.
      await chaptersDao.saveProgress(c,
          pageIndex: 9, completed: true, readAt: 1001000);
      await historyDao.recordCompletion(c, s, 1001000);
      await chaptersDao.saveProgress(c,
          pageIndex: 9, completed: true, readAt: 1002000);
      await historyDao.recordCompletion(c, s, 1002000);

      var rows = await historyDao.recent();
      expect(rows.single.timesRead, 1);
      expect(rows.single.readAt, 1002000);

      // A genuine re-read an hour later DOES count.
      await chaptersDao.saveProgress(c,
          pageIndex: 9, completed: true, readAt: 4600000);
      await historyDao.recordCompletion(c, s, 4600000);
      rows = await historyDao.recent();
      expect(rows.single.timesRead, 2);
    });
  });

  group('Manual merge (Plan/12 §4)', () {
    test('moves links/chapters/tags/library/history onto the primary',
        () async {
      final primary = await series('Nano Machine', tags: ['Action']);
      final absorbed = await series('nanomachine ฉบับแปล', tags: ['Drama']);

      await link(primary, 'slow-manga', 'https://s/nano');
      await link(absorbed, 'go-manga', 'https://g/nano');
      await chapter(primary, 'slow-manga', 1);
      await chapter(absorbed, 'go-manga', 2);
      final clash = await chapter(absorbed, 'slow-manga', 1); // duplicate!

      // category: absorbed is in "ตามอ่าน"
      final catId = await libraryDao.addCategory('ตามอ่าน');
      await libraryDao.addToCategory(absorbed, catId);

      // progress + history on the absorbed-only chapter (go-manga #2)
      final absorbedGo2 = (await chaptersDao.listForSeries(absorbed))
          .firstWhere((c) => c.sourceId == 'go-manga');
      await chaptersDao.saveProgress(absorbedGo2.id!,
          pageIndex: 1, completed: true, readAt: now);
      await historyDao.recordCompletion(absorbedGo2.id!, absorbed, now);

      // library rows: both in library, absorbed read MORE recently.
      await libraryDao.markRead(
          absorbed, absorbedGo2.id!, now + 7000);

      await repo.merge(primary, [absorbed]);

      expect(await seriesDao.byId(absorbed), isNull);
      final links = await seriesDao.sourcesOf(primary);
      expect(links.map((l) => l.sourceId).toSet(), {'slow-manga', 'go-manga'});

      final chapters = await chaptersDao.listForSeries(primary);
      expect(chapters.length, 2); // clash dropped, go-manga #2 moved
      expect(
          chapters.map((c) => c.id).contains(clash), isFalse);

      final progress = await chaptersDao.progressForSeries(primary);
      expect(progress[absorbedGo2.id]?.completed, isTrue);

      final history = await historyDao.recent();
      expect(history.single.seriesId, primary);

      final tags = await db.rawQuery(
          'SELECT t.name FROM series_tags st JOIN tags t ON t.id = st.tag_id '
          'WHERE st.series_id = ?', [primary]);
      expect(tags.map((r) => r['name']).toSet(), {'Action', 'Drama'});

      final members = await libraryDao.membersOf(catId);
      expect(members, {primary});

      final entry = await libraryDao.entry(primary);
      expect(entry!.lastReadAt, now + 7000); // newer read state won
    });

    test('survives an absorbed last-read that was a dropped duplicate',
        () async {
      final primary = await series('Nano Machine');
      final absorbed = await series('nanomachine ฉบับแปลอื่น');
      await link(primary, 'slow-manga', 'https://s/nano');
      await link(absorbed, 'slow-manga', 'https://s2/nano'); // SAME source

      final pCh1 =
          await chapter(primary, 'slow-manga', 1, url: 'https://s/nano');
      final aCh1 =
          await chapter(absorbed, 'slow-manga', 1, url: 'https://s2/nano');

      // Absorbed is in the library, read MORE recently, pointing at ITS
      // ch1 — which merge step 2 drops as a duplicate. Copying that id
      // would violate the chapters FK and roll the whole merge back.
      await libraryDao.add(absorbed, now - 5000);
      await libraryDao.markRead(absorbed, aCh1, now + 9000);

      await repo.merge(primary, [absorbed]); // must not throw

      final entry = await libraryDao.entry(primary);
      expect(entry!.lastReadAt, now + 9000); // newer read state kept
      expect(entry.lastReadChapterId, isNull); // dangling id NOT copied
      expect(await chaptersDao.byId(pCh1), isNotNull);
      expect(await chaptersDao.byId(aCh1), isNull); // the dropped clash
    });
  });

  group('แยกเรื่อง split (Plan/12 §4)', () {
    test('lifts one source link + its chapters onto a standalone series',
        () async {
      final merged = await series('False Merge');
      await link(merged, 'slow-manga', 'https://s/fm',
          alts: ['Alt A']);
      await link(merged, 'go-manga', 'https://g/fm',
          alts: ['Alt B']);
      final aCh = await chapter(merged, 'slow-manga', 1, url: 'https://s/fm');
      final bCh = await chapter(merged, 'go-manga', 1, url: 'https://g/fm');
      await chaptersDao.saveProgress(bCh, pageIndex: 2, completed: false);
      await historyDao.recordCompletion(bCh, merged, now);

      final newId = await repo.split(merged, 'go-manga');

      final original = await seriesDao.byId(merged);
      final fresh = await seriesDao.byId(newId);
      expect(fresh, isNotNull);
      expect(fresh!.title, 'False Merge'); // go-manga's source_title is null
      expect(original!.coverHash, isNull);

      final origLinks =
          (await seriesDao.sourcesOf(merged)).map((l) => l.sourceId);
      expect(origLinks, ['slow-manga']);

      final moved = await chaptersDao.listForSeries(newId);
      expect(moved.single.id, bCh);
      expect((await chaptersDao.progress(bCh))!.pageIndex, 2);
      expect((await historyDao.recent()).single.seriesId, newId);
      expect(await chaptersDao.progressForSeries(newId), isNotEmpty);

      // The moved chapter's URL survives the lift; the original keeps its
      // own copy untouched.
      expect(moved.single.url, 'https://g/fm/1.0');
      expect(aCh, isNot(equals(bCh)));
    });
  });

  group('deleteFromLibrary (13 §C)', () {
    test('keepFiles=true keeps downloads; false removes them', () async {
      final s = await series('S');
      final c = await chapter(s, 'slow-manga', 1);
      await downloadsDao.enqueue(c, createdAt: now);
      await downloadsDao.updateState(c, 'done');

      await repo.deleteFromLibrary(s, keepFiles: true);
      expect(await downloadsDao.isDownloaded(c), isTrue);

      await libraryDao.add(s, now);
      await repo.deleteFromLibrary(s, keepFiles: false);
      expect(await downloadsDao.isDownloaded(c), isFalse);
    });
  });

  group('cover fallback referer', () {
    test('pairs the cover URL with the source that actually supplied it',
        () async {
      final s = await series('Cover Pairing');
      await link(s, 'slow-manga', 'https://s/1'); // first link: NO cover
      await link(s, 'go-manga', 'https://g/1',
          coverUrl: 'https://img.example.com/c.jpg');

      final goManga = FakeSource('go-manga');
      final repoWithSources = LibraryRepo(
        seriesDao: seriesDao,
        chaptersDao: chaptersDao,
        libraryDao: libraryDao,
        downloadsDao: downloadsDao,
        blobsDao: BlobsDao(db),
        sources: [FakeSource('slow-manga'), goManga],
      );
      final card = (await repoWithSources.load()).single;
      expect(card.coverUrl, 'https://img.example.com/c.jpg');
      expect(card.coverReferer, goManga.referer); // NOT slow-manga's
    });
  });
}

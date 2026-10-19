import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'package:star_codex/core/utils/title_match.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/search_history_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/dao/tags_dao.dart';
import 'package:star_codex/data/repo/browse_repo.dart';
import 'package:star_codex/data/repo/series_repo.dart';
import 'package:star_codex/data/sources/source_api.dart';

import 'fake_source.dart';
import 'helpers.dart';

BrowseCandidate cand(String source, String title,
        {int? hint, String? type, String? urlPrefix = 'x', String? cover, int? updated}) =>
    BrowseCandidate(
      sourceId: source,
      referer: 'https://r/',
      url: 'https://s/$urlPrefix/${title.hashCode}/',
      title: title,
      chapterCountHint: hint,
      type: type,
      coverUrl: cover,
      lastUpdatedMs: updated,
    );

void main() {
  group('mergeIntoGroups (Plan/07 §3)', () {
    test('same title on two sources merges into one group', () {
      final groups = mergeIntoGroups(const [], [
        cand('a', 'Nano Machine', hint: 920),
        cand('b', 'nano machine (แปลไทย)', hint: 900),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.members, hasLength(2));
      expect(groups.first.chapterCount, 920);
      expect(groups.first.primary.sourceId, 'a'); // most chapters
    });

    test('different titles stay separate', () {
      final groups = mergeIntoGroups(const [], [
        cand('a', 'Solo Leveling', hint: 100),
        cand('b', 'Solo Max-Level Newbie', hint: 200),
      ]);
      expect(groups, hasLength(2));
    });

    test('duplicate (source,url) across pages is dropped', () {
      final first = mergeIntoGroups(
          const [], [cand('a', 'Nano Machine', hint: 10)]);
      final second = mergeIntoGroups(first, [
        cand('a', 'Nano Machine', hint: 10),
        cand('a', 'Nano Machine ch.2 page', hint: 11, urlPrefix: 'y'),
      ]);
      expect(second, hasLength(2)); // dupe dropped, page-2 hit is new url
    });

    test('similar band pairs annotated, not merged', () {
      final groups = mergeIntoGroups(const [], [
        cand('a', 'Overgeared', hint: 100),
        cand('b', 'ovegeared', hint: 90), // typo'd mirror title
      ]);
      expect(groups, hasLength(2));
      final i = groups.indexWhere((g) => g.displayTitle == 'Overgeared');
      final j = 1 - i;
      expect(groups[i].similarTo, contains(j));
      expect(groups[j].similarTo, contains(i));
      expect(merges(TitleMatchKind.similar), isFalse);
    });

    test('displayTitle prefers Thai script (L5)', () {
      // One merged group carrying both scripts; primary is the Latin one.
      final g = SearchGroup([
        cand('a', 'Solo Max-Level Newbie', hint: 900),
        cand('b', 'โซโล่ เลเวลลิ่ง', hint: 100),
      ]);
      expect(g.primary.sourceId, 'a'); // most chapters
      expect(g.displayTitle, 'โซโล่ เลเวลลิ่ง');
    });
  });

  group('needsMaterialization (background date/cover backfill)', () {
    test('madara-style card (cover, no date) needs it', () {
      final g = SearchGroup([
        cand('a', 'Baek XX', hint: 199, cover: 'https://s/c.jpg'),
      ]);
      expect(g.needsMaterialization, isTrue,
          reason: 'listing tile has no date — detail fetch must backfill');
    });

    test('nekopost-style card (date + cover) is complete', () {
      final g = SearchGroup([
        BrowseCandidate(
          sourceId: 'nekopost',
          referer: 'https://r/',
          url: 'https://s/1',
          title: 'Nano',
          coverUrl: 'https://s/c.jpg',
          lastUpdatedMs: 1729000000000,
        ),
      ]);
      expect(g.needsMaterialization, isFalse);
    });

    test('card with cover but DB date is complete', () {
      final g = SearchGroup([
        cand('a', 'Regressor', hint: 156, cover: 'https://s/c.jpg'),
      ]);
      g.dbLastUpdatedMs = 1729000000000;
      expect(g.needsMaterialization, isFalse);
    });

    test('coverless card (AVIF-skipped / dead tile) needs it even with a date',
        () {
      final g = SearchGroup([cand('a', 'Poison Master', hint: 109)]);
      g.dbLastUpdatedMs = 1729000000000;
      expect(g.needsMaterialization, isTrue,
          reason: 'cross-probe may find a sibling site cover');
    });
  });

  group('filterGroups (Plan/08 §3, defaults OFF per L1)', () {
    final groups = mergeIntoGroups(const [], [
      cand('a', 'Long Series', hint: 50, type: 'manhwa'),
      cand('a', 'Short Series', hint: 5, type: 'manga'),
      cand('a', 'Oneshot', hint: 1, type: 'manga'),
    ]);

    test('default filters keep everything', () {
      expect(filterGroups(groups, const BrowseFilters()), hasLength(3));
    });

    test('min chapters = 10 hides short series', () {
      final kept = filterGroups(groups, const BrowseFilters(minChapters: 10));
      expect(kept.map((g) => g.displayTitle), ['Long Series']);
    });

    test('hide oneshot removes 1-chapter entries', () {
      final kept = filterGroups(groups, const BrowseFilters(hideOneshot: true));
      expect(kept, hasLength(2));
    });

    test('type filter keeps matching type only', () {
      final kept = filterGroups(groups, const BrowseFilters(type: 'manhwa'));
      expect(kept.map((g) => g.displayTitle), ['Long Series']);
    });
  });

  group('sortGroups (user request 2026-10-20)', () {
    // Alpha(db 1000), Bravo(listing 3000), Charlie(no date), Delta(db 2000),
    // Echo(no date).
    List<SearchGroup> datedGroups() {
      final groups = mergeIntoGroups(const [], [
        cand('a', 'Alpha'),
        cand('a', 'Bravo', updated: 3000),
        cand('a', 'Charlie'),
        cand('a', 'Delta'),
        cand('a', 'Echo'),
      ]);
      groups[0].dbLastUpdatedMs = 1000;
      groups[3].dbLastUpdatedMs = 2000;
      return groups;
    }

    test('latest update (default): dated desc, unknown dates last, stable',
        () {
      final sorted = sortGroups(datedGroups(), BrowseSortOrder.latestUpdate);
      expect(
        sorted.map((g) => g.displayTitle),
        ['Bravo', 'Delta', 'Alpha', 'Charlie', 'Echo'],
      );
    });

    test('oldest update: dated asc, unknown dates STILL last', () {
      final sorted = sortGroups(datedGroups(), BrowseSortOrder.oldestUpdate);
      expect(
        sorted.map((g) => g.displayTitle),
        ['Alpha', 'Delta', 'Bravo', 'Charlie', 'Echo'],
      );
    });

    test('chapter sorts: desc/asc with null hints last in both directions',
        () {
      final groups = mergeIntoGroups(const [], [
        cand('a', 'Mid', hint: 10),
        cand('a', 'Big', hint: 50),
        cand('a', 'NoHint'),
        cand('a', 'Tiny', hint: 1),
      ]);
      expect(
        sortGroups(groups, BrowseSortOrder.chaptersDesc)
            .map((g) => g.displayTitle),
        ['Big', 'Mid', 'Tiny', 'NoHint'],
      );
      expect(
        sortGroups(groups, BrowseSortOrder.chaptersAsc)
            .map((g) => g.displayTitle),
        ['Tiny', 'Mid', 'Big', 'NoHint'],
      );
    });

    test('stable: equal keys keep listing order in every direction', () {
      final groups = mergeIntoGroups(const [], [
        cand('a', 'First', updated: 1000, hint: 7),
        cand('a', 'Second', updated: 1000, hint: 7),
        cand('a', 'Third', updated: 1000, hint: 7),
      ]);
      for (final order in BrowseSortOrder.values) {
        expect(sortGroups(groups, order).map((g) => g.displayTitle),
            ['First', 'Second', 'Third'],
            reason: '$order must not shuffle ties');
      }
    });

    test('BrowseFilters: default sort latestUpdate; non-default flips badge',
        () {
      const filters = BrowseFilters();
      expect(filters.sort, BrowseSortOrder.latestUpdate);
      expect(filters.isDefault, isTrue);
      final changed = filters.copyWith(sort: BrowseSortOrder.chaptersDesc);
      expect(changed.isDefault, isFalse);
      expect(changed.copyWith().sort, BrowseSortOrder.chaptersDesc);
      expect(filters.copyWith(sort: BrowseSortOrder.oldestUpdate).isDefault,
          isFalse);
    });
  });

  group('BrowseRepo', () {
    late Database db;
    late SeriesDao seriesDao;
    late ChaptersDao chaptersDao;
    late LibraryDao libraryDao;
    late TagsDao tagsDao;
    late SearchHistoryDao historyDao;

    setUp(() async {
      db = await openTestDb();
      seriesDao = SeriesDao(db);
      chaptersDao = ChaptersDao(db);
      libraryDao = LibraryDao(db);
      tagsDao = TagsDao(db);
      historyDao = SearchHistoryDao(db);
    });

    BrowseRepo repoWith(List<FakeSource> sources) => BrowseRepo(
          sources: sources,
          seriesDao: seriesDao,
          chaptersDao: chaptersDao,
          libraryDao: libraryDao,
          tagsDao: tagsDao,
          historyDao: historyDao,
          seriesRepo: SeriesRepo(
            sources: sources,
            seriesDao: seriesDao,
            chaptersDao: chaptersDao,
            tagsDao: tagsDao,
            libraryDao: libraryDao,
            downloadsDao: DownloadsDao(db),
            settingsDao: SettingsDao(db),
          ),
        );

    test('search groups across sources and records history', () async {
      final a = FakeSource('a', searchResults: {
        'nano': [
          const SourceSeries(
              url: 'https://a/nano-machine/',
              title: 'Nano Machine',
              chapterCountHint: 920,
              type: 'manhwa'),
        ],
      });
      final b = FakeSource('b', searchResults: {
        'nano': [
          const SourceSeries(
              url: 'https://b/nano-machine/',
              title: 'nano machine (แปลไทย)',
              chapterCountHint: 900),
        ],
      });
      final page = await repoWith([a, b]).search(' nano ');
      expect(page.groups, hasLength(1));
      expect(page.groups.first.members, hasLength(2));
      expect(page.failures, isEmpty);
      expect(await historyDao.recent(), ['nano']); // trimmed, recorded once
    });

    test('one failing source never blanks results (Plan/08)', () async {
      final a = FakeSource('a',
          error: SourceException.cloudflare('a'));
      final b = FakeSource('b', searchResults: {
        'nano': [
          const SourceSeries(url: 'https://b/n/', title: 'Nano Machine'),
        ],
      });
      final page = await repoWith([a, b]).search('nano');
      expect(page.groups, hasLength(1));
      expect(page.failures, hasLength(1));
      expect(page.failures.first.sourceId, 'a');
    });

    test('blocked-search sources report cloudflare failures', () async {
      final blocked = FakeSource('up', error: SourceException.cloudflare('up'));
      final page = await repoWith([blocked]).search('x');
      expect(page.groups, isEmpty);
      expect(page.failures.first.error, isA<SourceException>());
    });

    test('empty query returns nothing and records nothing', () async {
      final page = await repoWith([]).search('   ');
      expect(page.groups, isEmpty);
      expect(await historyDao.recent(), isEmpty);
    });

    test('history dedupes, newest first, capped at 10 by dao', () async {
      final repo = repoWith([]);
      for (var i = 1; i <= 12; i++) {
        await repo.search('q$i');
      }
      await repo.search('q3'); // bump to newest
      final recent = await historyDao.recent(limit: 10);
      expect(recent.first, 'q3');
      expect(recent, hasLength(10));
      expect(recent.contains('q1'), isFalse); // oldest fell off
    });

    test('materializeIncompleteGroups backfills dates on EVERY undated card',
        () async {
      // User report 2026-10-20: most search cards showed no last-update
      // while their detail pages had every chapter stamp — the pass used
      // to stop after a budget of 12. Here 16 cover-bearing but dateless
      // cards must ALL get their newest-chapter stamp even with the
      // cross-probe budget at 0 (dates must not depend on the probe).
      // Detail titles deliberately DIFFER from the tile titles (each
      // site's Thai subtitle differs — the live Overgeared case), so a
      // date landing here can only come from the materialize pass
      // writing the row it already knows onto the card, never from a
      // title-norm lookup.
      // Real seeded source id — series_sources FKs to `sources`.
      const names = [
        'Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf',
        'Hotel', 'India', 'Juliet', 'Kilo', 'Lima', 'Mike', 'November',
        'Oscar', 'Papa',
      ];
      final src = FakeSource('slow-manga', searchResults: {
        'q': [
          for (var i = 0; i < names.length; i++)
            SourceSeries(
              url: 'https://s/$i/',
              title: names[i],
              coverUrl: 'https://s/c$i.jpg', // cover fine → date is the gap
            ),
        ],
      }, details: {
        for (var i = 0; i < names.length; i++)
          'https://s/$i/': SourceSeriesDetail(
            title: '${names[i]} จ้าวแห่งบททดสอบ',
            chapters: [
              SourceChapter(
                url: 'https://s/$i/c1/',
                title: 'ตอนที่ 1',
                number: 1,
                uploadedAt: 1700000000000 + i,
              ),
            ],
          ),
      });
      final repo = repoWith([src]);
      final page = await repo.search('q');
      expect(page.groups, hasLength(names.length));
      // No onCardDone enrichment — the direct row→card write is the only
      // path under test.
      await repo.materializeIncompleteGroups(page.groups, budget: 0);
      expect(src.detailCalls, names.length,
          reason: 'every undated card needs its detail fetch');
      for (final g in page.groups) {
        expect(g.dbLastUpdatedMs, isNotNull,
            reason: '${g.displayTitle} stayed dateless');
      }
      // Persisted + session-memoized: a re-presented page fetches nothing.
      final again = await repo.search('q');
      await repo.materializeIncompleteGroups(again.groups, budget: 0);
      expect(src.detailCalls, names.length);
    });

    test('merges carry db enrichment to the rebuilt groups (2026-10-20)',
        () async {
      final first = mergeIntoGroups(const [], [cand('a', 'Long Series', hint: 50)]);
      first.single.dbLastUpdatedMs = 1700000000000;
      first.single.dbType = 'manhwa';
      // A second page merges → every existing group is REBUILT; the
      // enriched fields must ride along or page-1 cards lose their dates.
      final merged = mergeGroupLists(first, [
        SearchGroup([cand('a', 'Other Series', hint: 3)]),
      ]);
      expect(merged.first.dbLastUpdatedMs, 1700000000000);
      expect(merged.first.dbType, 'manhwa');
    });

    test('addToLibrary creates merged rows + cross-probes other sources',
        () async {
      // Real seeded source ids — series_sources has a FK to `sources`.
      final a = FakeSource('slow-manga', searchResults: {
        'nano': [
          const SourceSeries(
              url: 'https://a/nano-machine/',
              title: 'Nano Machine',
              chapterCountHint: 920,
              type: 'manhwa'),
        ],
      }, details: {
        'https://a/nano-machine/': const SourceSeriesDetail(
          title: 'Nano Machine',
          altTitles: [],
          description: 'desc',
          tags: ['Action', 'Sci-Fi'],
          type: 'manhwa',
          status: 'ongoing',
          chapters: [
            SourceChapter(
                url: 'https://a/nano-1/', title: 'ตอนที่ 1', number: 1),
          ],
        ),
      });
      // Cross-probe hit on the other source (alt spellings count).
      final b = FakeSource('go-manga', searchResults: {
        'Nano Machine': [
          const SourceSeries(
              url: 'https://b/nano/', title: 'nano machine (แปลไทย)', chapterCountHint: 880),
        ],
      });
      final repo = repoWith([a, b]);

      final page = await repo.search('nano');
      final seriesId = await repo.addToLibrary(page.groups.first);

      final series = (await seriesDao.byId(seriesId))!;
      expect(series.type, 'manhwa');
      expect(series.origin, 'korea'); // L6
      expect(series.status, 'ongoing');
      expect(series.description, 'desc');

      final links = await seriesDao.sourcesOf(seriesId);
      expect(links.map((l) => l.sourceId),
          containsAll(['slow-manga', 'go-manga'])); // §3.2

      final chapters = await chaptersDao.listForSeries(seriesId);
      expect(chapters, hasLength(1));
      expect(chapters.first.number, 1);

      // Per-chapter source visibility (doc 09 addendum).
      expect(await chaptersDao.sourcesForNumber(seriesId, 1),
          ['slow-manga']);

      expect(await libraryDao.contains(seriesId), isTrue);
      expect(await tagsDao.tagsOf(seriesId),
          containsAll(['Action', 'Sci-Fi'])); // L7 union path

      // URL-dedup: re-adding the SAME source page under a drifted title
      // reuses the series row — no second series (review-pass regression).
      final again = await repo.addToLibrary(SearchGroup([
        BrowseCandidate(
          sourceId: 'slow-manga',
          referer: 'https://r/',
          url: 'https://a/nano-machine/',
          title: 'นาโน แมชชีน', // drifted Thai title, no alt bridge
          chapterCountHint: 920,
        ),
      ]));
      expect(again, seriesId); // same row — (source,url) identity wins
      expect(await seriesDao.findByTitleNorm('nano machine'), isNotNull);
    });

    test('cross-probe never re-links a URL owned by another series',
        () async {
      // Source b's URL is already linked to an existing series.
      final existing = await seriesDao.upsertByTitleNorm(Series(
        title: 'Unrelated',
        titleNorm: 'unrelated',
        createdAt: 1,
        updatedAt: 1,
      ));
      await seriesDao.upsertSource(SeriesSource(
        seriesId: existing,
        sourceId: 'go-manga',
        sourceUrl: 'https://b/nano/',
        fetchedAt: 1,
      ));

      final a = FakeSource('slow-manga', searchResults: {
        'nano': [
          const SourceSeries(url: 'https://a/nano/', title: 'Nano Machine'),
        ],
      }, details: {
        'https://a/nano/': const SourceSeriesDetail(
            title: 'Nano Machine', chapters: []),
      });
      final b = FakeSource('go-manga', searchResults: {
        'Nano Machine': [
          const SourceSeries(
              url: 'https://b/nano/', title: 'nano machine (แปลไทย)'),
        ],
      });
      final repo = repoWith([a, b]);
      final page = await repo.search('nano');
      final seriesId = await repo.addToLibrary(page.groups.first);

      // b's link stays on the series that owns it.
      final owner =
          await seriesDao.findSeriesIdBySourceLink('go-manga', 'https://b/nano/');
      expect(owner, existing);
      final links = await seriesDao.sourcesOf(seriesId);
      expect(links.map((l) => l.sourceId), ['slow-manga']);
    });

    test('pure-noise title never collides on empty title_norm', () async {
      // Both pages titled ONLY 'มังงะ' (a pure noise word → norm '').
      final a = FakeSource('slow-manga', details: {
        'https://a/one/': const SourceSeriesDetail(
            title: 'มังงะ', chapters: []),
        'https://a/two/': const SourceSeriesDetail(
            title: 'มังงะ', chapters: []),
      });
      final repo = repoWith([a]);
      final one = await repo.addToLibrary(SearchGroup([
        BrowseCandidate(
            sourceId: 'slow-manga',
            referer: 'https://r/',
            url: 'https://a/one/',
            title: 'มังงะ'),
      ]));
      final two = await repo.addToLibrary(SearchGroup([
        BrowseCandidate(
            sourceId: 'slow-manga',
            referer: 'https://r/',
            url: 'https://a/two/',
            title: 'มังงะ'),
      ]));
      // Two different pages must NOT fuse onto one ''-normed row.
      expect(one, isNot(two));
      expect(await seriesDao.findByTitleNorm(''), isNull); // never ''
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/title_match.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/search_history_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/tags_dao.dart';
import 'package:star_codex/data/repo/browse_repo.dart';
import 'package:star_codex/data/sources/source_api.dart';

import 'fake_source.dart';
import 'helpers.dart';

BrowseCandidate cand(String source, String title,
        {int? hint, String? type, String? urlPrefix = 'x'}) =>
    BrowseCandidate(
      sourceId: source,
      referer: 'https://r/',
      url: 'https://s/$urlPrefix/${title.hashCode}/',
      title: title,
      chapterCountHint: hint,
      type: type,
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

  group('BrowseRepo', () {
    late SeriesDao seriesDao;
    late ChaptersDao chaptersDao;
    late LibraryDao libraryDao;
    late TagsDao tagsDao;
    late SearchHistoryDao historyDao;

    setUp(() async {
      final db = await openTestDb();
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

      expect(await libraryDao.contains(seriesId), isTrue);
      expect(await tagsDao.tagsOf(seriesId),
          containsAll(['Action', 'Sci-Fi'])); // L7 union path
    });
  });
}

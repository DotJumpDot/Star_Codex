import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'package:star_codex/core/utils/title_match.dart';
import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/dao/tags_dao.dart';
import 'package:star_codex/data/repo/series_repo.dart';
import 'package:star_codex/data/sources/source_api.dart';

import 'fake_source.dart';
import 'helpers.dart';

const _detailA = SourceSeriesDetail(
  title: 'Nano Machine',
  altTitles: ['นาโน แมชชีน'],
  description: 'short desc',
  tags: ['Action', 'Sci-fi'],
  type: 'manhwa',
  status: 'ongoing',
  chapters: [
    SourceChapter(url: 'https://slow-manga.net/nano/1', title: 'ตอนที่ 1', number: 1),
    SourceChapter(url: 'https://slow-manga.net/nano/2', title: 'ตอนที่ 2', number: 2),
    SourceChapter(url: 'https://slow-manga.net/nano/3', title: 'ตอนที่ 3', number: 3),
  ],
);

const _detailB = SourceSeriesDetail(
  title: 'nano machine (แปลไทย)',
  description:
      'A much longer description that must win the L7 longest-non-empty merge.',
  tags: ['Action', 'Drama'],
  type: 'manhwa',
  status: 'ongoing',
  chapters: [
    SourceChapter(url: 'https://go-manga.com/nano/1', title: 'ตอนที่ 1', number: 1),
    SourceChapter(url: 'https://go-manga.com/nano/2', title: 'ตอนที่ 2', number: 2),
    SourceChapter(url: 'https://go-manga.com/nano/2.5', title: 'ตอนที่ 2.5', number: 2.5),
  ],
);

void main() {
  late Database db;
  late SeriesDao seriesDao;
  late ChaptersDao chaptersDao;
  late TagsDao tagsDao;
  late LibraryDao libraryDao;
  late DownloadsDao downloadsDao;
  late SettingsDao settingsDao;

  setUp(() async {
    db = await openTestDb();
    seriesDao = SeriesDao(db);
    chaptersDao = ChaptersDao(db);
    tagsDao = TagsDao(db);
    libraryDao = LibraryDao(db);
    downloadsDao = DownloadsDao(db);
    settingsDao = SettingsDao(db);
  });

  SeriesRepo repoWith(List<FakeSource> sources) => SeriesRepo(
        sources: sources,
        seriesDao: seriesDao,
        chaptersDao: chaptersDao,
        tagsDao: tagsDao,
        libraryDao: libraryDao,
        downloadsDao: downloadsDao,
        settingsDao: settingsDao,
      );

  /// Series on `source` with `detail`'s chapters, freshly fetched.
  Future<int> seedSeries(Source source, SourceSeriesDetail detail) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seriesId = await seriesDao.upsertByTitleNorm(Series(
      title: 'Nano Machine',
      titleNorm: normalizeTitle('Nano Machine'),
      type: detail.type,
      status: detail.status,
      description: detail.description,
      createdAt: now,
      updatedAt: now,
    ));
    await chaptersDao.upsertAll([
      for (final ch in detail.chapters)
        Chapter(
          seriesId: seriesId,
          sourceId: source.id,
          number: ch.number,
          title: ch.title,
          url: ch.url,
          uploadedAt: ch.uploadedAt,
          fetchedAt: now,
        ),
    ]);
    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: source.id,
      sourceUrl:
          detail.chapters.first.url.replaceAll(RegExp(r'/[^/]+$'), '/'),
      lastChapterNumber: detail.chapters.last.number,
      fetchedAt: now,
    ));
    await tagsDao.setForSeries(seriesId, detail.tags);
    return seriesId;
  }

  group('SeriesRepo.load', () {
    test('fresh links are NOT refetched (07 §3.3)', () async {
      final a = FakeSource('slow-manga');
      final seriesId = await seedSeries(a, _detailA);
      await repoWith([a]).load(seriesId);
      expect(a.detailCalls, 0);
    });

    test('stale link refreshes; fresh one does not; L7 merge applies',
        () async {
      final a = FakeSource('slow-manga');
      final b = FakeSource('go-manga', details: {
        'https://go-manga.com/nano/': _detailB,
      });
      final seriesId = await seedSeries(a, _detailA);
      // Add a lazy cross-probe link on B with NO chapters — never fetched.
      await seriesDao.upsertSource(SeriesSource(
        seriesId: seriesId,
        sourceId: 'go-manga',
        sourceUrl: 'https://go-manga.com/nano/',
        lastChapterNumber: 2.5,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
      ));

      final vm = await repoWith([a, b]).load(seriesId);
      expect(a.detailCalls, 0); // fresh
      expect(b.detailCalls, 1); // no chapters yet → refresh
      expect(vm.links, hasLength(2));
      expect(vm.chaptersBySource['go-manga'], hasLength(3));
      expect(vm.chaptersByNumber.keys, containsAll([1.0, 2.0, 2.5, 3.0]));
      // Description union: B's is longer (L7) + attribution set.
      expect(vm.descriptionSourceId, 'go-manga');
      expect(vm.series.description, contains('much longer'));
      // Tags union: A's Sci-fi survives B's setForSeries.
      expect(await tagsDao.tagsOf(seriesId),
          containsAll(['Sci-fi', 'Drama', 'Action']));
    });

    test('one failing source never blanks the screen (doc 09)', () async {
      final a = FakeSource('slow-manga');
      final dead = FakeSource('go-manga', error: 'cloudflare');
      final seriesId = await seedSeries(a, _detailA);
      await seriesDao.upsertSource(SeriesSource(
        seriesId: seriesId,
        sourceId: 'go-manga',
        sourceUrl: 'https://go-manga.com/nano/',
        fetchedAt: DateTime.now()
            .subtract(const Duration(hours: 13))
            .millisecondsSinceEpoch,
      ));

      final vm = await repoWith([a, dead]).load(seriesId);
      expect(vm.links, hasLength(2));
      expect(vm.chaptersBySource['slow-manga'], isNotEmpty);
      expect(vm.chaptersBySource['go-manga'], isEmpty);
    });
  });

  group('SeriesRepo.probeOtherSources', () {
    test('merge-hit links the other source; owner-guard skips foreign rows',
        () async {
      final a = FakeSource('slow-manga');
      final b = FakeSource('go-manga', searchResults: {
        'Nano Machine': [
          const SourceSeries(
              url: 'https://go-manga.com/nano/', title: 'Nano Machine'),
        ],
        'นาโน แมชชีน': [
          // Owned by ANOTHER series — must not be re-linked here.
          const SourceSeries(
              url: 'https://go-manga.com/other/', title: 'Nano Machine'),
        ],
      });
      final seriesId = await seedSeries(a, _detailA);
      final otherId = await seriesDao.upsertByTitleNorm(Series(
        title: 'Other',
        titleNorm: 'other',
        createdAt: 0,
        updatedAt: 0,
      ));
      await seriesDao.upsertSource(SeriesSource(
        seriesId: otherId,
        sourceId: 'go-manga',
        sourceUrl: 'https://go-manga.com/other/',
        fetchedAt: 0,
      ));

      final added = await repoWith([a, b]).probeOtherSources(
        seriesId,
        candidate: TitleCandidate(
          norm: normalizeTitle('Nano Machine'),
          altNorms: [normalizeTitle('นาโน แมชชีน')],
        ),
        queries: const ['Nano Machine', 'นาโน แมชชีน'],
      );
      expect(added, isTrue);
      final links = await seriesDao.sourcesOf(seriesId);
      expect(links.map((l) => l.sourceUrl),
          contains('https://go-manga.com/nano/'));
      final owner = await seriesDao.findSeriesIdBySourceLink(
          'go-manga', 'https://go-manga.com/other/');
      expect(owner, otherId);
    });
  });

  group('continueTarget (Plan/09: last read → first unread → chapter 1)', () {
    test('prefers the last-read chapter row', () {
      final vm = _vm(completedIds: const {}, lastReadId: 22);
      final target = continueTarget(vm)!;
      expect(target.chapter.id, 22);
      expect(target.sourceId, 'go-manga');
    });

    test('COMPLETED last-read → Continue picks the next unread ("อ่านต่อ")',
        () {
      // Chapter 1 finished (any source's copy marks the NUMBER read);
      // Continue must NOT replay ch 1's last page — it opens ch 2 from
      // the primary link.
      final vm = _vm(completedIds: const {11}, lastReadId: 11);
      final target = continueTarget(vm)!;
      expect(target.chapter.id, 12);
      expect(target.chapter.number, 2);
      expect(target.sourceId, 'slow-manga');
    });

    test('falls back to the first unread number', () {
      final vm = _vm(completedIds: const {11}, lastReadId: null);
      final target = continueTarget(vm)!;
      expect(target.chapter.number, 2);
    });

    test('no progress → lowest chapter from the primary link', () {
      final vm = _vm(completedIds: const {}, lastReadId: null);
      final target = continueTarget(vm)!;
      expect(target.chapter.number, 1);
      expect(target.sourceId, 'slow-manga');
    });
  });

  group('SeriesRepo.upsertFromDetail enrichment (L7 on re-add)', () {
    test('same title, new URL: no clobber, longest description, tags union',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final seriesId = await seriesDao.upsertByTitleNorm(Series(
        title: 'Nano Machine',
        titleNorm: normalizeTitle('Nano Machine'),
        type: 'manhwa',
        status: 'ongoing',
        description: 'short desc',
        createdAt: now,
        updatedAt: now,
      ));
      await tagsDao.setForSeries(seriesId, ['Action']);

      const url = 'https://slow-manga.net/nano/';
      const detail = SourceSeriesDetail(
        title: 'Nano Machine',
        // no type/status here — the existing row must keep its values
        description: 'a much longer description from the second source',
        tags: ['Drama'],
        chapters: [
          SourceChapter(
              url: 'https://slow-manga.net/nano/1',
              title: 'ตอนที่ 1',
              number: 1),
        ],
      );
      final source = FakeSource('slow-manga', details: {url: detail});

      final id = await repoWith([source]).upsertFromDetail(
        source: source,
        sourceUrl: url,
        fallbackTitle: 'nano machine',
        detail: detail,
      );

      expect(id, seriesId, reason: 'title-norm match reuses the row');
      final series = (await seriesDao.byId(seriesId))!;
      expect(series.description, contains('much longer'));
      expect(series.type, 'manhwa', reason: 'null from new source must not clobber');
      expect(series.status, 'ongoing');
      expect(await tagsDao.tagsOf(seriesId),
          containsAll(['Action', 'Drama']), reason: 'tags union, not replace');
    });
  });

  group('pure helpers', () {
    test('pickLongestDescription keeps the longest non-empty (L7)', () {
      expect(pickLongestDescription([null, '', 'abc', 'abcd']), 'abcd');
      expect(pickLongestDescription([null, '']), isNull);
    });

    test('pickOriginalTitle: first differing Latin alt, else null (L5)', () {
      // All alts either non-Latin or normalize equal → null.
      expect(
          pickOriginalTitle('nano machine',
              const ['นาโน แมชชีน', 'Nano Machine (แปลไทย)', 'NANO MACHINE']),
          isNull);
      // First Latin alt with a DIFFERENT norm wins.
      expect(
          pickOriginalTitle('nano machine',
              const ['นาโน แมชชีน', 'Nano Machine 2', 'NANO MACHINE 3']),
          'Nano Machine 2');
    });
  });
}

/// Hand-built VM: one series on two sources; primary = slow-manga (bigger
/// last_chapter_number, 07 §4). Chapter ids 11/12 (slow n1/n2) and
/// 21/22 (go n1/n2).
SeriesDetailVm _vm({
  required Set<int> completedIds,
  required int? lastReadId,
}) {
  final progress = <int, ({int pageIndex, bool completed, int? readAt})>{
    for (final id in completedIds)
      id: (pageIndex: 0, completed: true, readAt: 1),
  };
  Chapter ch(int id, double n, String source) => Chapter(
        id: id,
        seriesId: 1,
        sourceId: source,
        number: n,
        title: 'ตอนที่ ${n.toInt()}',
        url: 'https://$source/$n',
        fetchedAt: 0,
      );
  final bySource = {
    'slow-manga': [ch(11, 1, 'slow-manga'), ch(12, 2, 'slow-manga')],
    'go-manga': [ch(21, 1, 'go-manga'), ch(22, 2, 'go-manga')],
  };
  final byNumber = <double, List<Chapter>>{};
  for (final list in bySource.values) {
    for (final c in list) {
      byNumber.putIfAbsent(c.number, () => []).add(c);
    }
  }
  return SeriesDetailVm(
    series: Series(
      id: 1,
      title: 'Nano Machine',
      titleNorm: 'nano machine',
      type: 'manhwa',
      createdAt: 0,
      updatedAt: 0,
    ),
    links: const [
      SeriesSource(
          seriesId: 1,
          sourceId: 'go-manga',
          sourceUrl: 'https://go-manga.com/nano/',
          lastChapterNumber: 2,
          fetchedAt: 0),
      SeriesSource(
          seriesId: 1,
          sourceId: 'slow-manga',
          sourceUrl: 'https://slow-manga.net/nano/',
          lastChapterNumber: 3,
          fetchedAt: 0),
    ],
    sourceNames: const {
      'slow-manga': 'Slow Manga',
      'go-manga': 'Go-Manga',
    },
    chaptersBySource: bySource,
    chaptersByNumber: byNumber,
    progress: progress,
    downloadedChapterIds: const {},
    inLibrary: false,
    lastReadChapterId: lastReadId,
    altTitles: const [],
    sortOldestFirst: true,
    coverUrl: null,
    coverReferer: null,
    tags: const [],
  );
}

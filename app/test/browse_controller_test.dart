import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/search_history_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/settings_dao.dart';
import 'package:star_codex/data/dao/tags_dao.dart';
import 'package:star_codex/data/repo/browse_repo.dart';
import 'package:star_codex/data/repo/series_repo.dart';
import 'package:star_codex/data/sources/source_api.dart';
import 'package:star_codex/ui/browse/browse_controller.dart';

import 'fake_source.dart';
import 'helpers.dart';

/// Delays only its FIRST latest() call — lets tests force a stale (older)
/// fetch to complete after a newer one (browse race regression).
class SlowFirstSource extends FakeSource {
  SlowFirstSource(super.id, {super.latestResults});
  var _calls = 0;

  @override
  Future<List<SourceSeries>> latest(
      {int page = 1, bool popular = false}) async {
    if (_calls++ == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return super.latest(page: page, popular: popular);
  }
}

void main() {
  late BrowseRepo repo;
  late SeriesDao seriesDao;

  setUp(() async {
    final db = await openTestDb();
    seriesDao = SeriesDao(db);
    final sources = [
      FakeSource('slow-manga',
          latestResults: const [
            SourceSeries(url: 'https://a/one/', title: 'Alpha'),
          ],
          searchResults: const {
            'alpha': [SourceSeries(url: 'https://a/one/', title: 'Alpha')],
          },
          genreResults: const {
            'action': [
              SourceSeries(url: 'https://a/one/', title: 'Alpha'),
            ],
          }),
      FakeSource('go-manga',
          latestResults: const [
            SourceSeries(url: 'https://b/one/', title: 'Beta'),
          ],
          error: null),
    ];
    repo = BrowseRepo(
      sources: sources,
      seriesDao: seriesDao,
      chaptersDao: ChaptersDao(db),
      libraryDao: LibraryDao(db),
      tagsDao: TagsDao(db),
      historyDao: SearchHistoryDao(db),
      seriesRepo: SeriesRepo(
        sources: sources,
        seriesDao: SeriesDao(db),
        chaptersDao: ChaptersDao(db),
        tagsDao: TagsDao(db),
        libraryDao: LibraryDao(db),
        downloadsDao: DownloadsDao(db),
        settingsDao: SettingsDao(db),
      ),
    );
  });

  test('ensureLoaded shows latest feed', () async {
    final c = BrowseController(repo);
    await c.ensureLoaded();
    expect(c.state.mode, BrowseMode.latest);
    expect(c.state.groups, hasLength(2)); // Alpha + Beta (different titles)
    expect(normalizeTitle('Alpha'), 'alpha'); // sanity
  });

  test('popular as a sort chip refetches with the popular ordering '
      '(merged sort section 2026-10-21)', () async {
    final src = repo.sources.whereType<FakeSource>().first;
    final c = BrowseController(repo);
    await c.ensureLoaded();
    expect(src.latestPopular, isFalse);

    // Pick ยอดนิยม in the sort section → server param + no re-sort.
    c.setFilters(const BrowseFilters(sort: BrowseSortOrder.popular));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.feedPopular, isTrue);
    expect(src.latestPopular, isTrue,
        reason: 'the ordering must reach the sources');

    // Back to the default sort → refetch without popular.
    c.setFilters(const BrowseFilters());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.feedPopular, isFalse);
    expect(src.latestPopular, isFalse);
  });

  test('total feed failure falls back to the offline catalog (2026-10-21)',
      () async {
    // Seed one visited series + link so the DB has something to show.
    final now = DateTime.now().millisecondsSinceEpoch;
    final sid = await seriesDao.insert(Series(
      title: 'Cached Series',
      titleNorm: 'cached series',
      createdAt: now,
      updatedAt: now,
    ));
    await seriesDao.upsertSource(SeriesSource(
      seriesId: sid,
      sourceId: 'slow-manga',
      sourceUrl: 'https://a/cached/',
      sourceTitle: 'Cached Series',
      coverUrl: 'https://a/c.jpg',
      lastChapterNumber: 12,
      lastUpdatedAt: now,
      fetchedAt: now,
    ));

    // Every source offline.
    for (final s in repo.sources.whereType<FakeSource>()) {
      s.error = StateError('offline');
    }
    final c = BrowseController(repo);
    await c.ensureLoaded();
    expect(c.state.offline, isTrue, reason: 'banner shows');
    expect(c.state.groups, hasLength(1));
    expect(c.state.groups.first.displayTitle, 'Cached Series');
    expect(c.state.groups.first.dbLastUpdatedMs, now,
        reason: 'card date from the stored link');
    expect(c.state.endReached, isTrue, reason: 'no pagination offline');

    // Recovery: sources back → next refresh clears the offline state.
    for (final s in repo.sources.whereType<FakeSource>()) {
      s.error = null;
    }
    await c.retry();
    expect(c.state.offline, isFalse);
    expect(c.state.groups, isNotEmpty);
  });

  test('chip toggle while in genre mode returns to latest, filtered',
      () async {
    final c = BrowseController(repo);
    await c.ensureLoaded();
    await c.showGenre('slow-manga', 'action');
    expect(c.state.mode, BrowseMode.genre);
    expect(c.state.groups, hasLength(1)); // genre = Alpha only

    await c.toggleSource('go-manga');
    expect(c.state.mode, BrowseMode.latest); // left genre mode
    expect(c.state.genreSourceId, isNull);
    expect(c.state.activeSourceIds, {'go-manga'});
    expect(c.state.groups, hasLength(1));
    expect(c.state.groups.first.primary.sourceId, 'go-manga');
  });

  test('clearSourceFilter from genre mode also returns to latest', () async {
    final c = BrowseController(repo);
    await c.ensureLoaded();
    await c.showGenre('slow-manga', 'action');
    await c.clearSourceFilter();
    expect(c.state.mode, BrowseMode.latest);
    expect(c.state.activeSourceIds, isEmpty);
    expect(c.state.groups, hasLength(2));
  });

  test('retry re-runs the current mode and clears failure state', () async {
    final c = BrowseController(repo);
    await c.ensureLoaded();
    await c.submitSearch('alpha');
    expect(c.state.mode, BrowseMode.search);
    await c.retry();
    expect(c.state.loading, isFalse);
    expect(c.state.groups, isNotEmpty);
    expect(c.state.failedSources, isEmpty);
  });

  test('loadMore merges the next batch and stops at empty', () async {
    final c = BrowseController(repo);
    await c.ensureLoaded();
    // FakeSource returns [] for page > 1 → endReached after first loadMore.
    await c.loadMore();
    expect(c.state.endReached, isTrue);
    expect(c.state.groups, hasLength(2)); // nothing duplicated
  });

  // Regression (on-device 2026-10-19): toggling site filters back-to-back
  // let an OLDER in-flight fetch finish last and overwrite the feed with
  // results for a filter the user had already changed away from.
  test('a stale fetch never overwrites a newer filter result', () async {
    final slow = SlowFirstSource('slow-manga', latestResults: const [
      SourceSeries(url: 'https://a/stale/', title: 'Stale Slow Series'),
    ]);
    final fast = FakeSource('go-manga', latestResults: const [
      SourceSeries(url: 'https://b/fresh/', title: 'Fresh Fast Series'),
    ]);
    final db = await openTestDb();
    final scopedRepo = BrowseRepo(
      sources: [slow, fast],
      seriesDao: SeriesDao(db),
      chaptersDao: ChaptersDao(db),
      libraryDao: LibraryDao(db),
      tagsDao: TagsDao(db),
      historyDao: SearchHistoryDao(db),
      seriesRepo: SeriesRepo(
        sources: [slow, fast],
        seriesDao: SeriesDao(db),
        chaptersDao: ChaptersDao(db),
        tagsDao: TagsDao(db),
        libraryDao: LibraryDao(db),
        downloadsDao: DownloadsDao(db),
        settingsDao: SettingsDao(db),
      ),
    );

    final c = BrowseController(scopedRepo);
    // Filter to slow-manga only (stale fetch #1, delayed), then clear the
    // filter (fetch #2 completes instantly). Fetch #1 finishes LAST.
    unawaited(c.toggleSource('slow-manga'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    unawaited(c.toggleSource('slow-manga'));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(c.state.activeSourceIds, isEmpty);
    expect(c.state.loading, isFalse);
    // The stale slow-only result must NOT have won: the all-sources feed
    // contains BOTH series.
    final titles = c.state.groups.map((g) => g.primary.title).toSet();
    expect(titles, containsAll(['Stale Slow Series', 'Fresh Fast Series']));
  });

  test('scoped controller never queries sources outside its universe',
      () async {
    final c = BrowseController(repo, allowedSourceIds: {'go-manga'});
    await c.ensureLoaded();
    expect(c.state.groups, hasLength(1));
    expect(c.state.groups.first.primary.sourceId, 'go-manga');
    // Selecting only an out-of-scope source yields nothing (never "all").
    await c.toggleSource('slow-manga');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.state.groups, isEmpty);
  });
}

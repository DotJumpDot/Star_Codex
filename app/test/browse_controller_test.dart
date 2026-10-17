import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/search_history_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/data/dao/tags_dao.dart';
import 'package:star_codex/data/repo/browse_repo.dart';
import 'package:star_codex/data/sources/source_api.dart';
import 'package:star_codex/ui/browse/browse_controller.dart';

import 'fake_source.dart';
import 'helpers.dart';

void main() {
  late BrowseRepo repo;

  setUp(() async {
    final db = await openTestDb();
    repo = BrowseRepo(
      sources: [
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
      ],
      seriesDao: SeriesDao(db),
      chaptersDao: ChaptersDao(db),
      libraryDao: LibraryDao(db),
      tagsDao: TagsDao(db),
      historyDao: SearchHistoryDao(db),
    );
  });

  test('ensureLoaded shows latest feed', () async {
    final c = BrowseController(repo);
    await c.ensureLoaded();
    expect(c.state.mode, BrowseMode.latest);
    expect(c.state.groups, hasLength(2)); // Alpha + Beta (different titles)
    expect(normalizeTitle('Alpha'), 'alpha'); // sanity
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
}

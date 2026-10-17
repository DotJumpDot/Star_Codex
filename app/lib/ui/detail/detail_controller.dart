import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/dao/library_dao.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/repo/browse_merge.dart' show SearchGroup;
import '../../data/repo/series_repo.dart';

/// Detail screen state machine (Plan/09): one load → snapshot VM; user
/// actions write through to the DB AND patch the VM so read-marks update
/// instantly without a refetch (09 §DoD).
class DetailController extends StateNotifier<AsyncValue<SeriesDetailVm>> {
  DetailController({
    required int? seriesId,
    required this.group,
    required this.repo,
    required this.chaptersDao,
    required this.downloadsDao,
    required this.libraryDao,
    required this.settingsDao,
  }) : _explicitId = seriesId, super(const AsyncValue.loading());

  /// Browse-card entries carry a group and NO id; the row is materialized
  /// on first load ([SeriesRepo.ensureSeries]). Library/detail entries
  /// carry the id directly.
  final int? _explicitId;
  final SearchGroup? group;
  int? _resolvedId;

  final SeriesRepo repo;
  final ChaptersDao chaptersDao;
  final DownloadsDao downloadsDao;
  final LibraryDao libraryDao;
  final SettingsDao settingsDao;

  Future<int> _ensureId() async {
    final id = _resolvedId ?? _explicitId;
    if (id != null) {
      _resolvedId = id;
      return id;
    }
    final created = await repo.ensureSeries(group!);
    _resolvedId = created;
    return created;
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final id = await _ensureId();
      state = AsyncValue.data(await _emit(repo.load(id)));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> retry() => load();

  Future<SeriesDetailVm> _emit(Future<SeriesDetailVm> future) async {
    final id = _resolvedId;
    final vm = await future;
    final sort = await settingsDao.get('chapter_sort_$id');
    return vm.copyWith(sortOldestFirst: sort != 'desc');
  }

  /// Long-press mark read/unread (Plan/09 §DoD: instant dots, no refetch).
  Future<void> markRead(int chapterId, {required bool completed}) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    if (completed) {
      final existing = cur.progress[chapterId];
      final now = DateTime.now().millisecondsSinceEpoch;
      await chaptersDao.saveProgress(chapterId,
          pageIndex: existing?.pageIndex ?? 0, completed: true, readAt: now);
      await libraryDao.markRead(seriesId, chapterId, now);
      state = AsyncValue.data(cur.copyWith(
        progress: {
          ...cur.progress,
          chapterId: (pageIndex: existing?.pageIndex ?? 0, completed: true, readAt: now),
        },
        lastReadChapterId: chapterId,
      ));
    } else {
      await chaptersDao.clearProgress(chapterId);
      final progress = {...cur.progress}..remove(chapterId);
      state = AsyncValue.data(cur.copyWith(progress: progress));
    }
  }

  /// Sort toggle — persisted per series (settings `chapter_sort_<id>`).
  Future<void> setSort({required bool oldestFirst}) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await settingsDao.upsert(
        'chapter_sort_$seriesId', oldestFirst ? 'asc' : 'desc');
    state = AsyncValue.data(cur.copyWith(sortOldestFirst: oldestFirst));
  }

  Future<void> toggleLibrary() async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    if (cur.inLibrary) {
      await libraryDao.remove(seriesId);
      state = AsyncValue.data(cur.copyWith(inLibrary: false));
    } else {
      await libraryDao.add(
          seriesId, DateTime.now().millisecondsSinceEpoch);
      state = AsyncValue.data(cur.copyWith(inLibrary: true));
    }
  }

  Future<void> enqueueDownload(int chapterId) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await downloadsDao.enqueue(chapterId,
        createdAt: DateTime.now().millisecondsSinceEpoch);
    state = AsyncValue.data(cur.copyWith(downloadedChapterIds: {
      ...cur.downloadedChapterIds,
      chapterId,
    }));
  }

  Future<void> deleteDownload(int chapterId) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await downloadsDao.delete(chapterId);
    final ids = {...cur.downloadedChapterIds}..remove(chapterId);
    state = AsyncValue.data(cur.copyWith(downloadedChapterIds: ids));
  }

  /// หาในเว็บอื่น (Plan/09 ⋯ menu + 07 §3.2). Re-emits when a new link
  /// landed so a fresh tab appears (its chapters refresh in load()).
  Future<bool> probeOthers() async {
    final cur = state.valueOrNull;
    if (cur == null) return false;
    final series = cur.series;
    final added = await repo.probeOtherSources(
      seriesId,
      candidate: TitleCandidate(
        norm: series.titleNorm,
        altNorms: [
          for (final l in cur.links)
            for (final a in l.altTitles) normalizeTitle(a),
        ],
      ),
      queries: {
        series.title,
        for (final l in cur.links)
          if (l.sourceTitle != null) l.sourceTitle!,
        for (final l in cur.links) ...l.altTitles,
      }.toList(),
    );
    if (added) {
      state = AsyncValue.data(await _emit(repo.load(seriesId)));
    }
    return added;
  }

  int get seriesId {
    final id = _resolvedId ?? _explicitId;
    if (id == null) {
      throw StateError('series id not resolved yet');
    }
    return id;
  }
}

final detailControllerProvider = StateNotifierProvider.family<
    DetailController, AsyncValue<SeriesDetailVm>, int>((ref, key) {
  return DetailController(
    seriesId: key < 0 ? null : key,
    group: ref.watch(detailGroupProvider(key)),
    repo: ref.watch(seriesRepoProvider),
    chaptersDao: ref.watch(chaptersDaoProvider),
    downloadsDao: ref.watch(downloadsDaoProvider),
    libraryDao: ref.watch(libraryDaoProvider),
    settingsDao: ref.watch(settingsDaoProvider),
  );
});

/// Browse-card → detail passes the listing group through this family
/// provider, overridden by the nested ProviderScope at the push site (a
/// SearchGroup can't be a provider-family key; -1 is the "from browse"
/// sentinel key).
final detailGroupProvider =
    Provider.family<SearchGroup?, int>((ref, key) => null);

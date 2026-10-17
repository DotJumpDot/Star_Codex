import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/dao/library_dao.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/repo/browse_merge.dart' show SearchGroup;
import '../../data/repo/downloads_repo.dart';
import '../../data/repo/library_repo.dart';
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
    required this.historyDao,
    required this.libraryRepo,
    required this.settingsDao,
    required this.downloadsRepo,
  }) : _explicitId = seriesId,
       super(const AsyncValue.loading());

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
  final HistoryDao historyDao;
  final LibraryRepo libraryRepo;
  final SettingsDao settingsDao;
  final DownloadsRepo downloadsRepo;

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
      await chaptersDao.saveProgress(
        chapterId,
        pageIndex: existing?.pageIndex ?? 0,
        completed: true,
        readAt: now,
      );
      await libraryDao.markRead(seriesId, chapterId, now);
      // Same "completed=1" moment as the readers (doc 12 §5 write path).
      await historyDao.recordCompletion(chapterId, seriesId, now);
      state = AsyncValue.data(
        cur.copyWith(
          progress: {
            ...cur.progress,
            chapterId: (
              pageIndex: existing?.pageIndex ?? 0,
              completed: true,
              readAt: now,
            ),
          },
          lastReadChapterId: chapterId,
        ),
      );
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
      'chapter_sort_$seriesId',
      oldestFirst ? 'asc' : 'desc',
    );
    state = AsyncValue.data(cur.copyWith(sortOldestFirst: oldestFirst));
  }

  Future<void> toggleLibrary() async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    if (cur.inLibrary) {
      await libraryDao.remove(seriesId);
      state = AsyncValue.data(cur.copyWith(inLibrary: false));
    } else {
      await libraryDao.add(seriesId, DateTime.now().millisecondsSinceEpoch);
      state = AsyncValue.data(cur.copyWith(inLibrary: true));
    }
  }

  Future<void> enqueueDownload(int chapterId) =>
      enqueueDownloads([chapterId], priority: 2); // manual single > range

  /// Enqueue a batch (download sheet: range / unread / all). Quota is
  /// checked FIRST with the repo's size estimate — throws QuotaException
  /// with the remaining free bytes on refusal (doc 13 §A).
  Future<void> enqueueDownloads(
    List<int> chapterIds, {
    int priority = 1,
  }) async {
    final cur = state.valueOrNull;
    if (cur == null || chapterIds.isEmpty) return;
    await downloadsRepo.janitor.enforceQuota(
      await downloadsRepo.estimateBytes(chapterIds),
    );
    final base = DateTime.now().millisecondsSinceEpoch;
    var i = 0;
    for (final id in chapterIds) {
      await downloadsDao.enqueue(id, priority: priority, createdAt: base + i++);
    }
    state = AsyncValue.data(
      cur.copyWith(
        downloadedChapterIds: {...cur.downloadedChapterIds, ...chapterIds},
      ),
    );
  }

  Future<void> deleteDownload(int chapterId) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await downloadsDao.delete(chapterId);
    await downloadsRepo.janitor.recomputePins();
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

  /// Manual merge (Plan/12 §4): absorb [otherIds] into THIS series, then
  /// re-emit so the tabs show the incoming sources. Returns false when the
  /// merge failed (e.g. another series' link is owned elsewhere).
  Future<void> mergeIn(List<int> otherIds) async {
    await libraryRepo.merge(seriesId, otherIds);
    await load();
  }

  /// แยกเรื่อง (Plan/12 §4): lift one source link onto a standalone series.
  Future<void> splitOut(String sourceId) async {
    await libraryRepo.split(seriesId, sourceId);
    await load();
  }

  int get seriesId {
    final id = _resolvedId ?? _explicitId;
    if (id == null) {
      throw StateError('series id not resolved yet');
    }
    return id;
  }
}

/// Provider-family key for detail controllers (Plan/09): library opens
/// carry the saved [id]; browse-card opens carry the listing [group] and
/// the series row materializes on first load. The group uses IDENTITY
/// equality (two cards with the same title keep separate controllers).
class DetailKey {
  const DetailKey.id(int this.id) : group = null;
  const DetailKey.forGroup(SearchGroup this.group) : id = null;

  final int? id;
  final SearchGroup? group;

  @override
  bool operator ==(Object other) =>
      other is DetailKey && other.id == id && identical(other.group, group);

  @override
  int get hashCode => id ?? identityHashCode(group);
}

final detailControllerProvider =
    StateNotifierProvider.family<
      DetailController,
      AsyncValue<SeriesDetailVm>,
      DetailKey
    >((ref, key) {
      return DetailController(
        seriesId: key.id,
        group: key.group,
        repo: ref.watch(seriesRepoProvider),
        chaptersDao: ref.watch(chaptersDaoProvider),
        downloadsDao: ref.watch(downloadsDaoProvider),
        libraryDao: ref.watch(libraryDaoProvider),
        historyDao: ref.watch(historyDaoProvider),
        libraryRepo: ref.watch(libraryRepoProvider),
        settingsDao: ref.watch(settingsDaoProvider),
        downloadsRepo: ref.watch(downloadsRepoProvider),
      );
    });

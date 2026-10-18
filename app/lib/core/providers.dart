import 'dart:io';

import 'package:flutter/material.dart' show GlobalKey, ScaffoldState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/dao/blobs_dao.dart';
import '../data/dao/chapters_dao.dart';
import '../data/dao/library_dao.dart';
import '../data/dao/search_history_dao.dart';
import '../data/dao/series_dao.dart';
import '../data/dao/settings_dao.dart';
import '../data/dao/tags_dao.dart';
import '../data/repo/browse_repo.dart';
import '../data/repo/downloads_repo.dart';
import '../data/repo/library_repo.dart';
import '../data/repo/reader_repo.dart';
import '../data/repo/series_repo.dart';
import '../data/repo/updates_repo.dart';
import '../data/sources/source_api.dart';
import '../data/storage/blob_store.dart';
import '../data/storage/cache_janitor.dart';
import '../data/storage/image_pipeline.dart';
import 'net/rate_limiter.dart';
import 'net/safe_http.dart';

/// Opened once in `main()` and overridden here; tests override with an
/// in-memory database (sqflite_common_ffi).
final dbProvider = Provider<Database>(
    (ref) => throw UnimplementedError('dbProvider must be overridden in main()'));

/// Settings snapshot read before runApp; overridden in `main()`.
final initialSettingsProvider = Provider<Map<String, String>>((ref) => const {});

final seriesDaoProvider = Provider((ref) => SeriesDao(ref.watch(dbProvider)));
final chaptersDaoProvider =
    Provider((ref) => ChaptersDao(ref.watch(dbProvider)));
final blobsDaoProvider = Provider((ref) => BlobsDao(ref.watch(dbProvider)));
final libraryDaoProvider =
    Provider((ref) => LibraryDao(ref.watch(dbProvider)));
final settingsDaoProvider =
    Provider((ref) => SettingsDao(ref.watch(dbProvider)));
final tagsDaoProvider = Provider((ref) => TagsDao(ref.watch(dbProvider)));
final searchHistoryDaoProvider =
    Provider((ref) => SearchHistoryDao(ref.watch(dbProvider)));
final downloadsDaoProvider =
    Provider((ref) => DownloadsDao(ref.watch(dbProvider)));
final historyDaoProvider = Provider((ref) => HistoryDao(ref.watch(dbProvider)));

/// Mutable holder so Settings can enable/disable/reorder sources at
/// runtime (doc 14 DoD: a disabled source leaves browse/search/fallback
/// immediately). main() seeds it via `loadSources`; tests override with
/// fake sources.
class SourcesController extends StateNotifier<List<Source>> {
  SourcesController(super.initial);

  void replace(List<Source> next) => state = next;
}

final sourcesProvider = StateNotifierProvider<SourcesController, List<Source>>(
    (ref) => throw UnimplementedError('sourcesProvider must be overridden'));

// --- network + storage singletons (Plan/03 §API surface) ---

final rateLimiterProvider = Provider((ref) => RateLimiter());

/// Single shared network door — uses the shared rate limiter so runtime
/// image-host registrations (ts_reader CDN domains) apply to every request.
final safeHttpProvider = Provider(
    (ref) => SafeHttp(rateLimiter: ref.watch(rateLimiterProvider)));

/// Overridden in `main()` with the real library dir; tests use temp dirs.
final libraryDirProvider = Provider<Directory>(
    (ref) => throw UnimplementedError('libraryDirProvider must be overridden'));

final blobStoreProvider = Provider((ref) => BlobStore(
      rootDir: ref.watch(libraryDirProvider),
      blobsDao: ref.watch(blobsDaoProvider),
    ));

final imagePipelineProvider = Provider((ref) => ImagePipeline(
      http: ref.watch(safeHttpProvider),
      blobs: ref.watch(blobStoreProvider),
    ));

final cacheJanitorProvider = Provider((ref) => CacheJanitor(
      db: ref.watch(dbProvider),
      blobs: ref.watch(blobStoreProvider),
      settings: ref.watch(settingsDaoProvider),
    ));

/// Detail-side orchestration (Plan/09): stale refresh, metadata union,
/// cross-source probe, series materialization from a browse card.
final seriesRepoProvider = Provider((ref) => SeriesRepo(
      sources: ref.watch(sourcesProvider),
      seriesDao: ref.watch(seriesDaoProvider),
      chaptersDao: ref.watch(chaptersDaoProvider),
      tagsDao: ref.watch(tagsDaoProvider),
      libraryDao: ref.watch(libraryDaoProvider),
      downloadsDao: ref.watch(downloadsDaoProvider),
      settingsDao: ref.watch(settingsDaoProvider),
      pipeline: ref.watch(imagePipelineProvider),
    ));

/// Browse orchestration (Plan/07): source adapters → normalize → group.
final browseRepoProvider = Provider((ref) => BrowseRepo(
      sources: ref.watch(sourcesProvider),
      seriesDao: ref.watch(seriesDaoProvider),
      chaptersDao: ref.watch(chaptersDaoProvider),
      libraryDao: ref.watch(libraryDaoProvider),
      tagsDao: ref.watch(tagsDaoProvider),
      historyDao: ref.watch(searchHistoryDaoProvider),
      pipeline: ref.watch(imagePipelineProvider),
      seriesRepo: ref.watch(seriesRepoProvider),
    ));

/// Active tab index — shared so detail screens can jump to Browse
/// (tag chip tap, doc 09 §4) without lifting shell state.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Global header search overlay (slides over every tab from the top
/// right; submit jumps to Browse and runs the merged search).
final searchOpenProvider = StateProvider<bool>((ref) => false);

/// The shell's Scaffold key — created once per container so every tab's
/// hamburger can open the navigation drawer (inner tab Scaffolds are
/// nearer in the tree than the shell Scaffold).
final shellScaffoldKeyProvider =
    Provider<GlobalKey<ScaffoldState>>((ref) => GlobalKey<ScaffoldState>());

/// Library-tab orchestration (Plan/12): card list, Thai sort, merge/split
/// transactions, delete flows. Null janitor is overridden nowhere — the
/// real provider always has one.
final libraryRepoProvider = Provider((ref) => LibraryRepo(
      seriesDao: ref.watch(seriesDaoProvider),
      chaptersDao: ref.watch(chaptersDaoProvider),
      libraryDao: ref.watch(libraryDaoProvider),
      downloadsDao: ref.watch(downloadsDaoProvider),
      blobsDao: ref.watch(blobsDaoProvider),
      sources: ref.watch(sourcesProvider),
      janitor: ref.watch(cacheJanitorProvider),
    ));

/// Metered-network check for the download worker (doc 13: Wi-Fi-only
/// switch, default ON). Overridden in main() with connectivity_plus;
/// null in tests (the check is skipped → queue always allowed).
final unmeteredCheckProvider =
    Provider<Future<bool> Function()?>((ref) => null);

/// Downloads queue engine (Plan/13 §A): foreground worker + snapshot
/// stream. The 1 s timer starts in main() — tests drive tick() directly.
final downloadsRepoProvider = Provider((ref) => DownloadsRepo(
      readerRepo: ref.watch(readerRepoProvider),
      seriesDao: ref.watch(seriesDaoProvider),
      chaptersDao: ref.watch(chaptersDaoProvider),
      downloadsDao: ref.watch(downloadsDaoProvider),
      settingsDao: ref.watch(settingsDaoProvider),
      janitor: ref.watch(cacheJanitorProvider),
      isUnmetered: ref.watch(unmeteredCheckProvider),
    ));

/// Chapter-updates checker (Plan/13 §B).
final updatesRepoProvider = Provider((ref) => UpdatesRepo(
      sources: ref.watch(sourcesProvider),
      seriesDao: ref.watch(seriesDaoProvider),
      chaptersDao: ref.watch(chaptersDaoProvider),
      libraryDao: ref.watch(libraryDaoProvider),
      settingsDao: ref.watch(settingsDaoProvider),
    ));

/// Reader orchestration (Plan/10): page lists + source fallback + the
/// shared 2-slot fetch queue.
final readerRepoProvider = Provider((ref) => ReaderRepo(
      sources: ref.watch(sourcesProvider),
      seriesDao: ref.watch(seriesDaoProvider),
      chaptersDao: ref.watch(chaptersDaoProvider),
      blobs: ref.watch(blobStoreProvider),
      pipeline: ref.watch(imagePipelineProvider),
    ));

/// Resolves the real library dir (Plan/03: getApplicationSupportDirectory()/
/// manga_library). Called in main() before runApp.
Future<Directory> defaultLibraryDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/manga_library');
}

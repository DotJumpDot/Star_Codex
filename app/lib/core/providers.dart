import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/dao/blobs_dao.dart';
import '../data/dao/chapters_dao.dart';
import '../data/dao/library_dao.dart';
import '../data/dao/series_dao.dart';
import '../data/dao/settings_dao.dart';
import '../data/dao/tags_dao.dart';
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

// --- network + storage singletons (Plan/03 §API surface) ---

final safeHttpProvider = Provider((ref) => SafeHttp());
final rateLimiterProvider = Provider((ref) => RateLimiter());

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

/// Resolves the real library dir (Plan/03: getApplicationSupportDirectory()/
/// manga_library). Called in main() before runApp.
Future<Directory> defaultLibraryDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/manga_library');
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../data/dao/blobs_dao.dart';
import '../data/dao/chapters_dao.dart';
import '../data/dao/library_dao.dart';
import '../data/dao/series_dao.dart';
import '../data/dao/settings_dao.dart';
import '../data/dao/tags_dao.dart';

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

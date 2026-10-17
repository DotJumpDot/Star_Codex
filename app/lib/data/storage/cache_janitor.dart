import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../core/settings_provider.dart';
import '../dao/settings_dao.dart';
import 'blob_store.dart';

/// LRU eviction + integrity + pins + quota (Plan/03).
/// Runs: 10 s after app start, after every 50 blob writes, and from
/// Settings "clear cache now".
class CacheJanitor {
  CacheJanitor({
    required this.db,
    required this.blobs,
    required this.settings,
  });

  final Database db;
  final BlobStore blobs;
  final SettingsDao settings;

  Timer? _pending;

  void runSoon({Duration delay = const Duration(seconds: 10)}) {
    _pending?.cancel();
    _pending = Timer(delay, runNow);
  }

  /// Periodic pass: LRU enforcement only (cheap). [withIntegrity] adds the
  /// startup pass (row/file consistency — a full directory walk, so it runs
  /// at app start, not on every 50th write; Plan/03 §LRU/§integrity).
  Future<void> runNow({bool withIntegrity = false}) async {
    await blobs.ensureDir();
    if (withIntegrity) {
      await blobs.integrityPass();
    }
    await enforceLru();
  }

  int _writesSinceRun = 0;

  /// Called by the pipeline/repo after blob writes (every 50 → run).
  Future<void> onBlobWrite() async {
    _writesSinceRun++;
    if (_writesSinceRun >= 50) {
      _writesSinceRun = 0;
      await runNow();
    }
  }

  /// LRU: evict oldest unpinned blobs until unpinned total ≤ cache limit.
  /// Never touches pinned blobs (Plan/03 §LRU).
  Future<int> enforceLru() async {
    final limit = AppSettings(await settings.getAll())
        .getInt('cache_limit_bytes', 5368709120);
    var unpinnedTotal = await blobs.totalBytes(pinned: false);
    if (unpinnedTotal <= limit) return 0;
    var evicted = 0;
    for (final row in await blobs.evictableOldestFirst()) {
      if (unpinnedTotal <= limit) break;
      await blobs.delete(row.hash);
      unpinnedTotal -= row.bytes;
      evicted++;
    }
    return evicted;
  }

  /// One statement both pins done-download blobs and unpins stale ones —
  /// dedup (one blob serving several chapters) is handled naturally
  /// (Plan/03 §is_pinned maintenance).
  Future<void> recomputePins() {
    return db.execute('''
      UPDATE blobs SET is_pinned = CASE WHEN hash IN (
        SELECT cp.content_hash FROM chapter_pages cp
        JOIN downloads d ON d.chapter_id = cp.chapter_id
        WHERE d.state = 'done' AND cp.content_hash IS NOT NULL
      ) THEN 1 ELSE 0 END
    ''');
  }

  /// Pinned-quota guard (decision S4): throws [QuotaException] with the
  /// remaining free bytes when incoming would exceed the total quota.
  Future<void> enforceQuota(int incomingBytes) async {
    final quota = AppSettings(await settings.getAll())
        .getInt('total_quota_bytes', 107374182400);
    final pinnedTotal = await blobs.totalBytes(pinned: true);
    if (pinnedTotal + incomingBytes > quota) {
      throw QuotaException(quota - pinnedTotal);
    }
  }
}

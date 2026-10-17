import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repo/downloads_repo.dart';

/// Mirrors the engine's snapshot stream for the Offline tab; actions
/// delegate straight to the repo. Also the handle the detail download
/// sheet uses for estimates and quota-then-enqueue.
class DownloadsController extends StateNotifier<QueueSnapshot> {
  DownloadsController(this._repo) : super(const QueueSnapshot()) {
    _sub = _repo.snapshots.listen((s) {
      if (mounted) state = s;
    });
    _repo.refreshSnapshot();
  }

  final DownloadsRepo _repo;
  StreamSubscription<QueueSnapshot>? _sub;

  Future<void> pause(int chapterId) => _repo.pause(chapterId);
  Future<void> resume(int chapterId) => _repo.resume(chapterId);
  Future<void> pauseAll() => _repo.pauseAll();
  Future<void> delete(int chapterId) => _repo.delete(chapterId);
  Future<int> estimateBytes(List<int> ids) => _repo.estimateBytes(ids);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final downloadsControllerProvider =
    StateNotifierProvider<DownloadsController, QueueSnapshot>(
        (ref) => DownloadsController(ref.watch(downloadsRepoProvider)));

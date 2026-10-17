import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repo/updates_repo.dart';

/// Updates bell + feed state (doc 13 §B): feed groups, unseen badge count,
/// and the run gate ("รีเฟรช" only actually checks when stale or forced).
class UpdatesFeedState {
  const UpdatesFeedState({
    this.groups = const [],
    this.unseen = 0,
    this.checking = false,
    this.lastError,
  });

  final List<UpdateGroup> groups;
  final int unseen;
  final bool checking;
  final Object? lastError;

  UpdatesFeedState copyWith({
    List<UpdateGroup>? groups,
    int? unseen,
    bool? checking,
    Object? lastError,
  }) =>
      UpdatesFeedState(
        groups: groups ?? this.groups,
        unseen: unseen ?? this.unseen,
        checking: checking ?? this.checking,
        lastError: lastError,
      );
}

class UpdatesController extends StateNotifier<UpdatesFeedState> {
  UpdatesController(this._repo) : super(const UpdatesFeedState());

  final UpdatesRepo _repo;

  Future<void> reload() async {
    // One feed() pass — the unseen count falls out of the same groups
    // (unseenCount() would re-run the whole query).
    final groups = await _repo.feed();
    if (!mounted) return;
    state = state.copyWith(
      groups: groups,
      unseen: groups.fold<int>(0, (n, g) => n + g.items.length),
    );
  }

  /// Pull-to-refresh / library refresh icon / sheet refresh. [force]
  /// bypasses the 6 h run-gate (user intent).
  Future<void> check({bool force = false}) async {
    if (state.checking) return;
    state = state.copyWith(checking: true, lastError: null);
    try {
      await _repo.checkAll(force: force);
      await reload();
    } catch (e) {
      if (mounted) state = state.copyWith(lastError: e);
    } finally {
      if (mounted) state = state.copyWith(checking: false);
    }
  }

  /// Opening the sheet consumes the badge (mark-seen on open, doc 13 §B).
  Future<void> markSeen() async {
    await _repo.markSeen();
    if (!mounted) return;
    state = state.copyWith(unseen: 0);
  }
}

final updatesControllerProvider =
    StateNotifierProvider<UpdatesController, UpdatesFeedState>(
        (ref) => UpdatesController(ref.watch(updatesRepoProvider)));

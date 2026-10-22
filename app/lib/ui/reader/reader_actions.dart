import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/dao/chapters_dao.dart';

/// The single write path for reader progress (Plan/12 §5): read_progress
/// always; the reading_history row is upserted on EVERY throttled save so
/// the History tab reflects chapters the moment they are opened (not only
/// when finished) — `times_read` stays session-guarded inside the DAO.
/// The same moment `completed=1` is set also bumps library.last_read.
/// [pageIndex] is a page number for webtoon/paged, a percent for novels
/// (reader screens keep that contract).
Future<void> persistReaderProgress(
  WidgetRef ref,
  Chapter chapter, {
  required int pageIndex,
  required bool completed,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await ref
      .read(chaptersDaoProvider)
      .saveProgress(
        chapter.id!,
        pageIndex: pageIndex,
        completed: completed,
        readAt: completed ? now : null,
      );
  await ref
      .read(historyDaoProvider)
      .recordCompletion(chapter.id!, chapter.seriesId, now);
  if (completed) {
    await ref
        .read(libraryDaoProvider)
        .markRead(chapter.seriesId, chapter.id!, now);
  }
}

/// Mark a chapter as STARTED — opened and actually read for a moment,
/// but not finished. The detail screen shows this as the yellow
/// "on reading" state (user request 2026-10-22: opening a chapter and
/// reading it for 2-3 s should already count).
///
/// Deliberately NOT the same path as [persistReaderProgress]: no
/// history row and no library bump — the chapter is only OPENED, not
/// completed. The write cannot regress a finished chapter (the DAO
/// inserts only when no row exists), so a chapter that was read to the
/// end stays read.
Future<void> markChapterStarted(WidgetRef ref, Chapter chapter) async {
  final id = chapter.id;
  if (id == null) return;
  await ref.read(chaptersDaoProvider).markStarted(id);
}

/// How long a chapter must be OPEN before it counts as "on reading".
/// The user asked for ~2-3 s of reading to register (2026-10-22) — a
/// chapter opened and instantly left again stays unread.
const kStartedMarkerDelay = Duration(seconds: 2);

/// Arm the "started" marker for a chapter the reader just opened.
///
/// Returns the timer so the caller can cancel it (on dispose, or when
/// the chapter is finished first — a finished chapter must never be
/// dragged back to "on reading"). [isAlive] lets the caller skip the
/// write when its screen is already gone.
Timer armStartedMarker(
  WidgetRef ref,
  Chapter chapter, {
  Duration delay = kStartedMarkerDelay,
  bool Function()? isAlive,
}) {
  return Timer(delay, () {
    if (isAlive != null && !isAlive()) return;
    markChapterStarted(ref, chapter);
  });
}


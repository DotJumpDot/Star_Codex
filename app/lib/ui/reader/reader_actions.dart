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

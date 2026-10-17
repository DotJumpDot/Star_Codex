import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/dao/chapters_dao.dart';

/// The single write path for reader progress (Plan/12 §5): read_progress
/// always; the same moment `completed=1` is set also bumps
/// library.last_read AND upserts the reading_history row
/// (read_at = now, times_read + 1). [pageIndex] is a page number for
/// webtoon/paged, a percent for novels (reader screens keep that contract).
Future<void> persistReaderProgress(
  WidgetRef ref,
  Chapter chapter, {
  required int pageIndex,
  required bool completed,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await ref.read(chaptersDaoProvider).saveProgress(chapter.id!,
      pageIndex: pageIndex, completed: completed,
      readAt: completed ? now : null);
  if (completed) {
    await ref
        .read(libraryDaoProvider)
        .markRead(chapter.seriesId, chapter.id!, now);
    await ref
        .read(historyDaoProvider)
        .recordCompletion(chapter.id!, chapter.seriesId, now);
  }
}

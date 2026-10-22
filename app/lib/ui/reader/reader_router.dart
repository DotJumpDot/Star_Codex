import 'package:flutter/material.dart';

import '../../data/dao/chapters_dao.dart';
import '../../data/dao/series_dao.dart';
import 'novel_reader_screen.dart';
import 'paged_reader_screen.dart';
import 'reader_screen.dart';

enum ReaderMode { webtoon, paged, novel }

/// Plan/11 §Shared plumbing — the per-series override
/// (`reader_mode_<seriesId>` ∈ auto|webtoon|paged|novel) wins over the
/// type default: manga → paged, novel → novel, else webtoon.
ReaderMode resolveReaderMode(String? type, String? override) {
  switch (override) {
    case 'webtoon':
      return ReaderMode.webtoon;
    case 'paged':
      return ReaderMode.paged;
    case 'novel':
      return ReaderMode.novel;
  }
  return readerModeForType(type);
}

ReaderMode readerModeForType(String? type) => switch (type) {
  'manga' => ReaderMode.paged,
  'novel' => ReaderMode.novel,
  _ => ReaderMode.webtoon,
};

/// Doc 14 default-mode setting: the per-series override wins; 'auto' falls
/// through to the global default (`reader_mode_default`) and then the
/// type default. Pass the result as [openReader]'s modeOverride.
String? effectiveModeOverride(String perSeries, String globalDefault) {
  if (perSeries != 'auto') return perSeries;
  return globalDefault == 'auto' ? null : globalDefault;
}

/// The single entry point every chapter tap funnels through (detail rows,
/// continue button, "read from which site" picker).
Future<void> openReader(
  BuildContext context, {
  required Chapter chapter,
  required String sourceId,
  required SeriesDao seriesDao,
  String? modeOverride,
}) async {
  final series = await seriesDao.byId(chapter.seriesId);
  final mode = resolveReaderMode(series?.type, modeOverride);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => switch (mode) {
        ReaderMode.webtoon => ReaderScreen(chapter: chapter),
        ReaderMode.paged => PagedReaderScreen(chapter: chapter),
        ReaderMode.novel => NovelReaderScreen(chapter: chapter),
      },
    ),
  );
}

/// System-bars handover between two readers (user report 2026-10-23:
/// the Android status/navigation bars came back after a force-drag
/// chapter switch and after a webtoon↔paged mode flip). The incoming
/// reader asserts immersive in its initState, but the OUTGOING reader's
/// dispose only runs when the new route's entrance animation COMPLETES —
/// its "restore the bars" call landed last and un-hid them. While this
/// flag is set, a disposing reader skips the restore: its successor
/// owns the system-UI state.
bool readerHandsOverSystemBars = false;

/// Every reader→reader replacement (chapter switch, mode flip) goes
/// through HERE so the handover flag is always set around the swap.
Future<void> replaceReaderRoute(
  BuildContext context,
  WidgetBuilder builder,
) async {
  readerHandsOverSystemBars = true;
  try {
    await Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: builder));
  } finally {
    // The old route's dispose (during the await above) already consumed
    // the flag; clear it defensively in case the swap never landed.
    readerHandsOverSystemBars = false;
  }
}

/// Mode flips apply to the OPEN reader, not just the next chapter (user
/// report 2026-10-19: flipping เว็บตูน ↔ หน้าต่อหน้า in the drawer used to
/// need an exit + re-enter). Callers save progress FIRST so the
/// replacement resumes at the same spot; when the freshly resolved mode
/// lands on the same screen as [current], this is a no-op.
Future<void> replaceWithResolvedReader(
  BuildContext context, {
  required Chapter chapter,
  required ReaderMode current,
  required SeriesDao seriesDao,
  String? modeOverride,
  bool chromeVisible = true,
}) async {
  final series = await seriesDao.byId(chapter.seriesId);
  final mode = resolveReaderMode(series?.type, modeOverride);
  if (mode == current || !context.mounted) return;
  await replaceReaderRoute(
    context,
    (_) => switch (mode) {
      ReaderMode.webtoon => ReaderScreen(
        chapter: chapter,
        chromeVisible: chromeVisible,
      ),
      ReaderMode.paged => PagedReaderScreen(
        chapter: chapter,
        chromeVisible: chromeVisible,
      ),
      ReaderMode.novel => NovelReaderScreen(
        chapter: chapter,
        chromeVisible: chromeVisible,
      ),
    },
  );
}

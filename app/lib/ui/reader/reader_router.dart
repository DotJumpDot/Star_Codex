import 'package:flutter/material.dart';

import '../../data/dao/chapters_dao.dart';
import '../../data/dao/series_dao.dart';
import 'reader_stub.dart';

enum ReaderMode { webtoon, paged, novel }

/// Plan/11 §Shared plumbing — mode from the series type. The per-series
/// override (`reader_mode_<seriesId>`) is applied here in Phase 8 when the
/// paged reader ships; webtoon is the default for manhwa/manhua/unknown.
ReaderMode readerModeForType(String? type) => switch (type) {
      'manga' => ReaderMode.paged,
      'novel' => ReaderMode.novel,
      _ => ReaderMode.webtoon,
    };

/// The single entry point every chapter tap funnels through (detail rows,
/// continue button, "read from which site" picker). Phase 6 renders the
/// stub; Phases 7/8 replace the destination behind this same signature.
Future<void> openReader(
  BuildContext context, {
  required Chapter chapter,
  required String sourceId,
  required SeriesDao seriesDao,
}) async {
  final series = await seriesDao.byId(chapter.seriesId);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ReaderStubScreen(
      chapter: chapter,
      sourceId: sourceId,
      mode: readerModeForType(series?.type),
    ),
  ));
}

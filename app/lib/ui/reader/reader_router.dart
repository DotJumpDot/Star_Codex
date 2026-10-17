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
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => switch (mode) {
      ReaderMode.webtoon => ReaderScreen(chapter: chapter),
      ReaderMode.paged => PagedReaderScreen(chapter: chapter),
      ReaderMode.novel => NovelReaderScreen(chapter: chapter),
    },
  ));
}

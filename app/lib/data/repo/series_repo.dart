import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';
import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart';
import '../dao/series_dao.dart';
import '../dao/settings_dao.dart';
import '../dao/tags_dao.dart';
import '../sources/source_api.dart';
import 'browse_merge.dart';
import '../storage/image_pipeline.dart';

/// Doc 09 §Data flow: a source's chapter list refreshes when it was never
/// fetched or its link is older than this.
const chapterRefreshAfter = Duration(hours: 12);

/// A chapter's read state (projection of its `read_progress` row).
typedef ChapterProgress = ({int pageIndex, bool completed, int? readAt});

/// One screen = one merged series (Plan/09). Immutable snapshot; user
/// actions go through DetailController which patches the affected fields.
class SeriesDetailVm {
  SeriesDetailVm({
    required this.series,
    required this.links,
    required this.sourceNames,
    required this.chaptersBySource,
    required this.chaptersByNumber,
    required this.progress,
    required this.downloadedChapterIds,
    required this.inLibrary,
    required this.lastReadChapterId,
    required this.altTitles,
    required this.sortOldestFirst,
    required this.coverUrl,
    required this.coverReferer,
    required this.tags,
    this.descriptionSourceId,
  });

  final Series series;

  /// Insertion order — the first link is the source the series came from.
  final List<SeriesSource> links;
  final Map<String, String> sourceNames;

  /// Per-source chapter lists (detail tabs).
  final Map<String, List<Chapter>> chaptersBySource;

  /// All copies of a chapter number, epsilon-grouped (doc 09 addendum:
  /// per-chapter source chips + "read from which site" picker).
  final Map<double, List<Chapter>> chaptersByNumber;

  final Map<int, ChapterProgress> progress;
  final Set<int> downloadedChapterIds;
  final bool inLibrary;
  final int? lastReadChapterId;
  final List<String> altTitles; // union across links
  final bool sortOldestFirst; // settings `chapter_sort_<seriesId>`

  /// First link's cover as fallback when `series.cover_hash` is evicted.
  final String? coverUrl;
  final String? coverReferer;

  /// Union of the series' tags (L7) — the tags chip row.
  final List<String> tags;

  /// Set only when this load's refresh supplied the description.
  final String? descriptionSourceId;

  int get chapterCount => chaptersByNumber.length;

  /// Reading-primary link per Plan/07 §4: max(last_chapter_number), tie →
  /// newest last_updated_at, tie → link order.
  SeriesSource get primaryLink {
    var best = links.first;
    for (final l in links.skip(1)) {
      final lNum = l.lastChapterNumber ?? -1;
      final bNum = best.lastChapterNumber ?? -1;
      if (lNum > bNum ||
          (lNum == bNum && (l.lastUpdatedAt ?? -1) > (best.lastUpdatedAt ?? -1))) {
        best = l;
      }
    }
    return best;
  }

  SeriesDetailVm copyWith({
    Map<int, ChapterProgress>? progress,
    Set<int>? downloadedChapterIds,
    bool? inLibrary,
    int? lastReadChapterId,
    bool clearLastRead = false,
    bool? sortOldestFirst,
    List<SeriesSource>? links,
    Map<String, List<Chapter>>? chaptersBySource,
    Map<double, List<Chapter>>? chaptersByNumber,
    List<String>? altTitles,
  }) =>
      SeriesDetailVm(
        series: series,
        links: links ?? this.links,
        sourceNames: sourceNames,
        chaptersBySource: chaptersBySource ?? this.chaptersBySource,
        chaptersByNumber: chaptersByNumber ?? this.chaptersByNumber,
        progress: progress ?? this.progress,
        downloadedChapterIds: downloadedChapterIds ?? this.downloadedChapterIds,
        inLibrary: inLibrary ?? this.inLibrary,
        lastReadChapterId: clearLastRead ? null : (lastReadChapterId ?? this.lastReadChapterId),
        altTitles: altTitles ?? this.altTitles,
        sortOldestFirst: sortOldestFirst ?? this.sortOldestFirst,
        coverUrl: coverUrl,
        coverReferer: coverReferer,
        tags: tags,
        descriptionSourceId: descriptionSourceId,
      );
}

/// Doc 09: continue = the last-read chapter, else the first unread number
/// (opened from the primary link's copy), else the lowest chapter. Null
/// only when the series has no chapters at all.
({Chapter chapter, String sourceId})? continueTarget(SeriesDetailVm vm) {
  if (vm.lastReadChapterId != null) {
    Chapter? lastRead;
    for (final list in vm.chaptersBySource.values) {
      for (final c in list) {
        if (c.id == vm.lastReadChapterId) lastRead = c;
      }
    }
    if (lastRead != null &&
        !(vm.progress[lastRead.id]?.completed ?? false)) {
      return (chapter: lastRead, sourceId: lastRead.sourceId);
    }
    // Finished it → Continue means the NEXT unread chapter, not a replay
    // of the final page.
  }
  final numbers = vm.chaptersByNumber.keys.toList()..sort();
  for (final n in numbers) {
    final copies = vm.chaptersByNumber[n]!;
    if (copies.any((c) => vm.progress[c.id]?.completed ?? false)) continue;
    final primaryId = vm.primaryLink.sourceId;
    var pick = copies.first;
    for (final c in copies) {
      if (c.sourceId == primaryId) pick = c;
    }
    return (chapter: pick, sourceId: pick.sourceId);
  }
  return null;
}

/// L7: description = longest non-empty across sources (mirrors truncate
/// differently). Returns null when every candidate is empty.
String? pickLongestDescription(Iterable<String?> candidates) {
  String? best;
  for (final c in candidates) {
    if (c == null || c.isEmpty) continue;
    if (best == null || c.length > best.length) best = c;
  }
  return best;
}

/// L5 order 2: first majority-Latin alt whose normalized form differs from
/// the display title.
String? pickOriginalTitle(String titleNorm, Iterable<String> altTitles) {
  for (final alt in altTitles) {
    final n = normalizeTitle(alt);
    if (isMostlyLatin(alt) && n.isNotEmpty && n != titleNorm) return alt;
  }
  return null;
}


/// Alt titles across mirrors repeat heavily — dedupe (trimmed, order kept).
List<String> dedupeAltTitles(Iterable<String> raw) {
  final seen = <String>{};
  return [
    for (final s in raw)
      if (s.trim().isNotEmpty && seen.add(s.trim())) s.trim(),
  ];
}

/// Detail-side orchestration (Plan/09 §Data flow + 07 §3.2/§4): stale-tab
/// refresh, incremental metadata merge, re-probe, series materialization.
class SeriesRepo {
  SeriesRepo({
    required this.sources,
    required this.seriesDao,
    required this.chaptersDao,
    required this.tagsDao,
    required this.libraryDao,
    required this.downloadsDao,
    required this.settingsDao,
    this.pipeline,
  });

  final List<Source> sources;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final TagsDao tagsDao;
  final LibraryDao libraryDao;
  final DownloadsDao downloadsDao;
  final SettingsDao settingsDao;

  /// Null in unit tests that don't exercise cover downloads.
  final ImagePipeline? pipeline;

  Source? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Build the detail VM. Sources with no chapters yet (lazy cross-probe
  /// links) or links older than [chapterRefreshAfter] are refreshed on the
  /// way in; one failing source never blanks the screen (doc 09).
  Future<SeriesDetailVm> load(int seriesId) async {
    final links = await seriesDao.sourcesOf(seriesId);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Stale or never-fetched links refresh in parallel — different hosts
    // don't share a rate-limit gate, and a serial loop multiplied the
    // open latency by the number of sources.
    final staleLinks = <SeriesSource>[];
    for (final link in links) {
      final hasChapters =
          await chaptersDao.hasForSource(seriesId, link.sourceId);
      final stale =
          !hasChapters || now - link.fetchedAt > chapterRefreshAfter.inMilliseconds;
      if (stale && sourceById(link.sourceId) != null) {
        staleLinks.add(link);
      }
    }
    String? descriptionSourceId;
    if (staleLinks.isNotEmpty) {
      final suppliedList = await Future.wait([
        for (final link in staleLinks)
          () async {
            try {
              final detail =
                  await sourceById(link.sourceId)!.detail(link.sourceUrl);
              return await _applyDetail(seriesId, link, detail, now);
            } catch (_) {
              return null; // unreachable source: keep what's in the DB
            }
          }(),
      ]);
      for (final supplied in suppliedList) {
        descriptionSourceId ??= supplied;
      }
    }

    final fresh = await seriesDao.sourcesOf(seriesId);
    return _buildVm(seriesId, fresh,
        descriptionSourceId: descriptionSourceId);
  }

  Future<SeriesDetailVm> _buildVm(int seriesId, List<SeriesSource> links,
      {String? descriptionSourceId}) async {
    final series = (await seriesDao.byId(seriesId))!;
    final chapters = await chaptersDao.listForSeries(seriesId);
    final bySource = {
      for (final l in links) l.sourceId: <Chapter>[],
    };
    final byNumber = <double, List<Chapter>>{};
    for (final c in chapters) {
      bySource[c.sourceId]?.add(c);
      byNumber.putIfAbsent(c.number, () => []).add(c);
    }
    final entry = await libraryDao.entry(seriesId);
    String? coverUrl;
    String? coverReferer;
    for (final l in links) {
      if (l.coverUrl != null) {
        coverUrl = l.coverUrl;
        coverReferer = sourceById(l.sourceId)?.referer;
        break;
      }
    }
    return SeriesDetailVm(
      series: series,
      links: links,
      sourceNames: {
        for (final l in links)
          if (sourceById(l.sourceId) != null)
            l.sourceId: sourceById(l.sourceId)!.name,
      },
      chaptersBySource: bySource,
      chaptersByNumber: byNumber,
      progress: await chaptersDao.progressForSeries(seriesId),
      downloadedChapterIds: await downloadsDao.downloadedForSeries(seriesId),
      inLibrary: entry != null,
      lastReadChapterId: entry?.lastReadChapterId,
      altTitles: dedupeAltTitles([
        for (final l in links) ...l.altTitles,
      ]),
        sortOldestFirst:
            (await settingsDao.get('chapter_sort_$seriesId')) == 'asc',
        coverUrl: coverUrl,
        coverReferer: coverReferer,
        tags: await tagsDao.tagsOf(seriesId),
        descriptionSourceId: descriptionSourceId,
      );
  }

  /// Store one source's detail into the series: chapters, link row, and the
  /// incremental L7 metadata union. Returns this source's id when IT
  /// supplied the (longer) description.
  Future<String?> _applyDetail(int seriesId, SeriesSource link,
      SourceSeriesDetail detail, int nowMs) async {
    await chaptersDao.upsertAll([
      for (final ch in detail.chapters)
        Chapter(
          seriesId: seriesId,
          sourceId: link.sourceId,
          number: ch.number,
          title: ch.title,
          url: ch.url,
          uploadedAt: ch.uploadedAt,
          fetchedAt: nowMs,
        ),
    ]);
    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: link.sourceId,
      sourceUrl: link.sourceUrl,
      sourceTitle: detail.title,
      altTitles: detail.altTitles,
      coverUrl: detail.coverUrl ?? link.coverUrl,
      lastChapterNumber: detail.chapters.isEmpty
          ? link.lastChapterNumber
          : detail.chapters.last.number,
      lastUpdatedAt: detail.chapters.isEmpty
          ? link.lastUpdatedAt
          : detail.chapters.last.uploadedAt,
      fetchedAt: nowMs,
    ));

    return _mergeMetadata(seriesId, link.sourceId, detail);
  }

  /// L7 metadata union onto the series row: description = longest
  /// non-empty, type/status/origin/original_title = first non-null, tags =
  /// UNION (mirrors report different subsets). Returns the source id when
  /// THIS call supplied the new description, for the UI caption.
  Future<String?> _mergeMetadata(
      int seriesId, String sourceId, SourceSeriesDetail detail) async {
    final stored = await seriesDao.byId(seriesId);
    if (stored == null) return null;
    var series = stored;

    String? descriptionSourceId;
    String? type = series.type;
    String? status = series.status;
    String? origin = series.origin;
    String? originalTitle = series.originalTitle;

    final description =
        pickLongestDescription([series.description, detail.description]);
    if (description != null && description != series.description) {
      series = series.copyWith(description: description);
      descriptionSourceId = sourceId;
    }
    if (type == null && detail.type != null) type = detail.type;
    if (status == null && detail.status != null) status = detail.status;
    if (origin == null && type != null) origin = originForType(type);
    originalTitle ??= pickOriginalTitle(series.titleNorm, detail.altTitles);

    await seriesDao.update(series.copyWith(
      type: type,
      status: status,
      origin: origin,
      originalTitle: originalTitle,
    ));

    if (detail.tags.isNotEmpty) {
      final existing = await tagsDao.tagsOf(seriesId);
      final union = {...existing, ...detail.tags}.toList();
      if (union.length != existing.length) {
        await tagsDao.setForSeries(seriesId, union);
      }
    }
    return descriptionSourceId;
  }

  /// Plan/07 §3.2 re-probe (detail ⋯ menu + add-to-library). Best-effort:
  /// a failing source is skipped silently, and a (source,url) already owned
  /// by ANOTHER series is never re-linked. Returns true when a new link
  /// landed on this series.
  Future<bool> probeOtherSources(
    int seriesId, {
    required TitleCandidate candidate,
    required List<String> queries,
  }) async {
    final links = await seriesDao.sourcesOf(seriesId);
    final linkedIds = links.map((l) => l.sourceId).toSet();
    var added = false;
    for (final other in sources) {
      if (linkedIds.contains(other.id)) continue;
      var linked = false;
      for (final q in queries.take(3)) {
        try {
          final items = await other.search(q);
          for (final item in items) {
            if (!merges(
                matchTitles(candidate, TitleCandidate.fromRaw(item.title)))) {
              continue;
            }
            final owner =
                await seriesDao.findSeriesIdBySourceLink(other.id, item.url);
            if (owner != null && owner != seriesId) {
              linked = true; // belongs to another series — leave it there
              break;
            }
            await seriesDao.upsertSource(SeriesSource(
              seriesId: seriesId,
              sourceId: other.id,
              sourceUrl: item.url,
              sourceTitle: item.title,
              coverUrl: item.coverUrl,
              lastChapterNumber: item.chapterCountHint?.toDouble(),
              fetchedAt: DateTime.now().millisecondsSinceEpoch,
            ));
            linked = true;
            added = true;
            break;
          }
        } catch (_) {
          break; // source unreachable/blocked — skip it
        }
        if (linked) break;
      }
    }
    return added;
  }

  /// Create-or-merge the series row from one source's detail (Plan/07 §4).
  /// Identity order: an existing (source, url) link IS this series —
  /// stronger than any title match (titles drift between listings). An
  /// empty normalization (noise title) falls back to the detail title, then
  /// to a per-URL escape key so unrelated series can't fuse on the unique
  /// `title_norm` index. Writes chapters + link + tags in the same pass.
  Future<int> upsertFromDetail({
    required Source source,
    required String sourceUrl,
    required String fallbackTitle,
    required SourceSeriesDetail detail,
    String? fallbackCoverUrl,
    String? fallbackType,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingId =
        await seriesDao.findSeriesIdBySourceLink(source.id, sourceUrl);

    var title = fallbackTitle;
    var norm = normalizeTitle(title);
    if (norm.isEmpty) {
      title = detail.title;
      norm = normalizeTitle(title);
      if (norm.isEmpty) norm = 'raw:$sourceUrl';
    }

    String? originalTitle;
    for (final alt in detail.altTitles) {
      final altNorm = normalizeTitle(alt);
      if (isMostlyLatin(alt) && altNorm.isNotEmpty && altNorm != norm) {
        originalTitle = alt;
        break;
      }
    }

    final type = detail.type ?? fallbackType;

    String? coverHash;
    final coverUrl = detail.coverUrl ?? fallbackCoverUrl;
    final pipe = pipeline;
    if (coverUrl != null && pipe != null) {
      try {
        coverHash =
            (await pipe.fetchAndStore(coverUrl, referer: source.referer)).hash;
      } catch (_) {
        // Cover is optional; the series row is still created.
      }
    }

    // Identity order 2: same title_norm on a DIFFERENT url = same
    // series. The row is NOT rewritten wholesale — upsertByTitleNorm would
    // clobber an existing longer description / type / status with the new
    // source's nulls. The L7 union happens in _mergeMetadata below.
    final int seriesId;
    if (existingId != null) {
      seriesId = existingId;
    } else {
      final byNorm = await seriesDao.findByTitleNorm(norm);
      if (byNorm != null) {
        seriesId = byNorm.id!;
        if (coverHash != null && byNorm.coverHash == null) {
          await seriesDao.update(byNorm.copyWith(coverHash: coverHash));
        }
      } else {
        seriesId = await seriesDao.insert(Series(
          title: title,
          titleNorm: norm,
          originalTitle: originalTitle,
          coverHash: coverHash,
          type: type,
          origin: originForType(type),
          status: detail.status,
          description: detail.description,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    // One transaction: a 900-chapter series must not land half-written.
    await chaptersDao.upsertAll([
      for (final ch in detail.chapters)
        Chapter(
          seriesId: seriesId,
          sourceId: source.id,
          number: ch.number,
          title: ch.title,
          url: ch.url,
          uploadedAt: ch.uploadedAt,
          fetchedAt: now,
        ),
    ]);

    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: source.id,
      sourceUrl: sourceUrl,
      sourceTitle: detail.title,
      altTitles: detail.altTitles,
      coverUrl: coverUrl,
      lastChapterNumber:
          detail.chapters.isEmpty ? null : detail.chapters.last.number,
      lastUpdatedAt:
          detail.chapters.isEmpty ? null : detail.chapters.last.uploadedAt,
      fetchedAt: now,
    ));
    // Re-adding on an EXISTING series must still enrich it (L7): a new
    // source's longer description / missing type / extra tags land here —
    // and tags UNION instead of replace, so the first source's tags
    // survive.
    await _mergeMetadata(seriesId, source.id, detail);
    return seriesId;
  }

  /// Browse card tap (Plan/09: detail opens from browse too): resolve the
  /// series id for a listing group, materializing the row on first open.
  /// NO library insert here — that stays an explicit action. Every OTHER
  /// member of the group is linked in the same pass: the listing already
  /// proved (source,url) identity, so the detail screen shows all sites
  /// immediately (fixes "second site disappears after opening a merged
  /// card" — previously only the primary linked, the rest waited for a
  /// manual probe).
  Future<int> ensureSeries(SearchGroup group) async {
    final primary = group.primary;
    final source = sourceById(primary.sourceId);
    if (source == null) {
      throw StateError('unknown source: ${primary.sourceId}');
    }
    final existing =
        await seriesDao.findSeriesIdBySourceLink(source.id, primary.url);
    final int seriesId;
    if (existing != null) {
      seriesId = existing;
    } else {
      final detail = await source.detail(primary.url);
      seriesId = await upsertFromDetail(
        source: source,
        sourceUrl: primary.url,
        fallbackTitle: group.displayTitle,
        fallbackCoverUrl: primary.coverUrl,
        fallbackType: group.type,
        detail: detail,
      );
    }
    // Link the remaining members (skip ones already owned by another
    // series — a link is the stronger identity and never moves).
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final member in group.members) {
      if (member.sourceId == primary.sourceId &&
          member.url == primary.url) {
        continue;
      }
      final memberSource = sourceById(member.sourceId);
      if (memberSource == null) continue;
      try {
        final owner = await seriesDao
            .findSeriesIdBySourceLink(member.sourceId, member.url);
        if (owner != null) continue; // belongs elsewhere — leave it there
        await seriesDao.upsertSource(SeriesSource(
          seriesId: seriesId,
          sourceId: member.sourceId,
          sourceUrl: member.url,
          sourceTitle: member.title,
          coverUrl: member.coverUrl,
          fetchedAt: now,
        ));
      } catch (_) {
        // best-effort enrichment — the primary link is what matters
      }
    }
    return seriesId;
  }
}

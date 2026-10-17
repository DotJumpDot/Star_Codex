import 'dart:async';

import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';
import '../dao/chapters_dao.dart';
import '../dao/library_dao.dart';
import '../dao/search_history_dao.dart';
import '../dao/series_dao.dart';
import '../dao/tags_dao.dart';
import '../sources/source_api.dart';
import '../storage/image_pipeline.dart';

/// One listing tile from one source — a [SourceSeries] plus the source
/// context (referer for image fetches) the UI layer needs downstream.
class BrowseCandidate {
  const BrowseCandidate({
    required this.sourceId,
    required this.referer,
    required this.url,
    required this.title,
    this.coverUrl,
    this.chapterCountHint,
    this.type,
  });

  final String sourceId;
  final String referer;
  final String url;
  final String title;
  final String? coverUrl;
  final int? chapterCountHint;
  final String? type;

  TitleCandidate get candidate => TitleCandidate.fromRaw(title);
}

/// One merged result card (Plan/08): one real series, N source members.
class SearchGroup {
  SearchGroup(Iterable<BrowseCandidate> initial)
      : members = [...initial];

  final List<BrowseCandidate> members;

  /// Indices (into the page's group list) of groups in the "similar"
  /// 0.88–0.95 band — UI hint only, never merged (Plan/07 §2). Recomputed
  /// by [annotateSimilar] after every grouping pass.
  final List<int> similarTo = [];

  /// Max chapter hint across members; null when no source reports one.
  int? get chapterCount {
    final hints = members
        .map((m) => m.chapterCountHint)
        .whereType<int>()
        .toList(growable: false);
    return hints.isEmpty ? null : hints.reduce(max2);
  }

  /// First non-null type in member (source sort) order.
  String? get type {
    for (final m in members) {
      if (m.type != null) return m.type;
    }
    return null;
  }

  /// Primary source = most chapters, tie → member order (source sort order;
  /// listings carry no timestamps — see Plan/05 drift addendum).
  BrowseCandidate get primary {
    var best = members.first;
    for (final m in members.skip(1)) {
      if ((m.chapterCountHint ?? -1) > (best.chapterCountHint ?? -1)) {
        best = m;
      }
    }
    return best;
  }

  /// Display title: primary source's pick, but prefer a Thai-script title
  /// when both scripts exist (decision L5).
  String get displayTitle {
    var best = primary;
    for (final m in members) {
      if (hasThaiScript(m.title) && !hasThaiScript(best.title)) best = m;
    }
    return best.title;
  }
}

int max2(int a, int b) => a > b ? a : b;

/// One source failing inside a parallel fetch — browse NEVER blanks on a
/// single source error (Plan/08 §Behavior); the UI marks the chip instead.
class SourceFailure {
  const SourceFailure(this.sourceId, this.error);

  final String sourceId;
  final Object error;
}

class BrowsePage {
  const BrowsePage({required this.groups, this.failures = const []});

  final List<SearchGroup> groups;
  final List<SourceFailure> failures;
}

class _SourceResult {
  const _SourceResult(this.source, this.items, this.error);

  final Source source;
  final List<SourceSeries> items;
  final Object? error;
}

/// Merge [incoming] candidates into [existing] groups (Plan/07 §2):
/// duplicate (source,url) dropped; match by exact/alt/fuzzy against every
/// member; else a new group. Used both within one page and across latest-
/// feed pages. Similar-band pairs are annotated afterwards.
List<SearchGroup> mergeIntoGroups(
    List<SearchGroup> existing, Iterable<BrowseCandidate> incoming) {
  final groups = [for (final g in existing) SearchGroup(g.members)];
  for (final c in incoming) {
    if (groups.any((g) => g.members
        .any((m) => m.sourceId == c.sourceId && m.url == c.url))) {
      continue;
    }
    SearchGroup? target;
    for (final g in groups) {
      if (g.members.any((m) => merges(matchTitles(m.candidate, c.candidate)))) {
        target = g;
        break;
      }
    }
    if (target == null) {
      groups.add(SearchGroup([c]));
    } else {
      target.members.add(c);
    }
  }
  annotateSimilar(groups);
  return groups;
}

/// Mark group pairs whose primary titles land in the 0.88–0.95 similar
/// band (Plan/08 card: "คล้ายกับเรื่องอื่น?").
void annotateSimilar(List<SearchGroup> groups) {
  for (final g in groups) {
    g.similarTo.clear();
  }
  for (var i = 0; i < groups.length; i++) {
    for (var j = i + 1; j < groups.length; j++) {
      if (matchTitles(groups[i].primary.candidate, groups[j].primary.candidate) ==
          TitleMatchKind.similar) {
        groups[i].similarTo.add(j);
        groups[j].similarTo.add(i);
      }
    }
  }
}

/// Merge whole group lists (latest-feed pagination: page N+1's groups can
/// be the same series as page N's from another source).
List<SearchGroup> mergeGroupLists(
    List<SearchGroup> existing, List<SearchGroup> incoming) {
  final groups = [for (final g in existing) SearchGroup(g.members)];
  bool anyMatch(SearchGroup a, SearchGroup b) => a.members
      .any((m) => b.members.any((n) => merges(matchTitles(m.candidate, n.candidate))));
  for (final ig in incoming) {
    SearchGroup? target;
    for (final g in groups) {
      if (anyMatch(g, ig)) {
        target = g;
        break;
      }
    }
    if (target == null) {
      groups.add(SearchGroup(ig.members));
    } else {
      for (final m in ig.members) {
        if (!target.members
            .any((x) => x.sourceId == m.sourceId && x.url == m.url)) {
          target.members.add(m);
        }
      }
    }
  }
  annotateSimilar(groups);
  return groups;
}

/// Session-only browse filters (Plan/08 §3) — NEVER written to settings;
/// defaults OFF per decision L1 (restart ⇒ defaults).
class BrowseFilters {
  const BrowseFilters({
    this.type,
    this.status,
    this.minChapters = 0,
    this.hideOneshot = false,
    this.tags = const {},
  });

  final String? type; // 'manga'|'manhwa'|'manhua'|'novel'
  final String? status; // 'ongoing'|'completed'
  final int minChapters; // 0 = off
  final bool hideOneshot;
  final Set<String> tags;

  bool get isDefault =>
      type == null &&
      status == null &&
      minChapters == 0 &&
      !hideOneshot &&
      tags.isEmpty;

  BrowseFilters copyWith({
    String? type,
    bool clearType = false,
    String? status,
    bool clearStatus = false,
    int? minChapters,
    bool? hideOneshot,
    Set<String>? tags,
  }) =>
      BrowseFilters(
        type: clearType ? null : (type ?? this.type),
        status: clearStatus ? null : (status ?? this.status),
        minChapters: minChapters ?? this.minChapters,
        hideOneshot: hideOneshot ?? this.hideOneshot,
        tags: tags ?? this.tags,
      );
}

/// Apply filters to grouped results. Status/tag filters are honest no-ops
/// on browse listings (no status/tags until a detail fetch) — the controls
/// exist per Plan/08 §3 and start filtering once detail data flows.
List<SearchGroup> filterGroups(List<SearchGroup> groups, BrowseFilters f) {
  return groups.where((g) {
    final chapters = g.chapterCount ?? 0;
    if (f.hideOneshot && chapters <= 1) return false;
    if (f.minChapters > 0 && chapters < f.minChapters) return false;
    if (f.type != null && g.type != f.type) return false;
    return true;
  }).toList(growable: false);
}

/// Type → origin mapping (decision L6). Novels get origin only from
/// nekopost metadata (Phase 8) — never guessed from titles.
String? originForType(String? type) {
  switch (type) {
    case 'manga':
      return 'japan';
    case 'manhwa':
      return 'korea';
    case 'manhua':
      return 'china';
    default:
      return null;
  }
}

/// Orchestrates source adapters → normalize → group (Plan/07 §3) for the
/// Browse screen. Adapters stay dumb; this is the only merge point.
class BrowseRepo {
  BrowseRepo({
    required this.sources,
    required this.seriesDao,
    required this.chaptersDao,
    required this.libraryDao,
    required this.tagsDao,
    required this.historyDao,
    this.pipeline,
  });

  final List<Source> sources;
  final SeriesDao seriesDao;
  final ChaptersDao chaptersDao;
  final LibraryDao libraryDao;
  final TagsDao tagsDao;
  final SearchHistoryDao historyDao;

  /// Null in unit tests that don't exercise cover downloads.
  final ImagePipeline? pipeline;

  Source? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Source> _active(Set<String> onlySourceIds) {
    if (onlySourceIds.isEmpty) return sources;
    return sources.where((s) => onlySourceIds.contains(s.id)).toList();
  }

  Future<BrowsePage> search(String query,
      {Set<String> onlySourceIds = const {}, int page = 1}) async {
    final q = query.trim();
    if (q.isEmpty) return const BrowsePage(groups: []);
    final results = await _gather(
        _active(onlySourceIds), (s) => s.search(q, page: page));
    // Fire-and-forget: history must never delay results (and a DB write
    // can't complete inside a widget-test FakeAsync zone anyway).
    unawaited(historyDao
        .record(q, atMs: DateTime.now().millisecondsSinceEpoch)
        .catchError((Object _) {}));
    final groups = mergeIntoGroups(const [], _candidates(results));
    // Search results: biggest series first (nulls last).
    groups.sort((a, b) => (b.chapterCount ?? -1).compareTo(a.chapterCount ?? -1));
    return BrowsePage(groups: groups, failures: _failures(results));
  }

  Future<BrowsePage> latest(
      {Set<String> onlySourceIds = const {}, int page = 1}) async {
    final results =
        await _gather(_active(onlySourceIds), (s) => s.latest(page: page));
    // Latest feed keeps append order: each site's listing is already
    // newest-first; sources are interleaved (Plan/05 drift addendum —
    // listings carry no timestamps to sort by).
    return BrowsePage(
        groups: mergeIntoGroups(const [], _candidates(results)),
        failures: _failures(results));
  }

  Future<BrowsePage> genre(Source source, String term, {int page = 1}) async {
    final results =
        await _gather([source], (s) => s.browseGenre(term, page: page));
    return BrowsePage(
        groups: mergeIntoGroups(const [], _candidates(results)),
        failures: _failures(results));
  }

  Future<List<SourceGenre>> genres(Source source) => source.genres();

  Future<List<_SourceResult>> _gather(List<Source> active,
      Future<List<SourceSeries>> Function(Source) call) {
    return Future.wait(active.map((s) async {
      try {
        return _SourceResult(s, await call(s), null);
      } catch (e) {
        return _SourceResult(s, const [], e);
      }
    }));
  }

  List<BrowseCandidate> _candidates(List<_SourceResult> results) => [
        for (final r in results)
          for (final item in r.items)
            BrowseCandidate(
              sourceId: r.source.id,
              referer: r.source.referer,
              url: item.url,
              title: item.title,
              coverUrl: item.coverUrl,
              chapterCountHint: item.chapterCountHint,
              type: item.type,
            ),
      ];

  List<SourceFailure> _failures(List<_SourceResult> results) => [
        for (final r in results)
          if (r.error != null) SourceFailure(r.source.id, r.error!),
      ];

  /// Long-press quick action (Plan/08): fetch the primary source's detail,
  /// create/merge the series row (Plan/07 §4), save chapters + source link
  /// + tags, then best-effort cross-probe other sources (§3.2) and insert
  /// the library row. Returns the series id.
  Future<int> addToLibrary(SearchGroup group) async {
    final primary = group.primary;
    final source = sourceById(primary.sourceId);
    if (source == null) {
      throw StateError('unknown source: ${primary.sourceId}');
    }
    final detail = await source.detail(primary.url);
    final now = DateTime.now().millisecondsSinceEpoch;

    final title = group.displayTitle;
    final norm = normalizeTitle(title);

    // original_title (L5 order 2): first majority-Latin alt whose norm
    // differs; ts pages carry no alt titles → often null (subtitle hidden).
    String? originalTitle;
    for (final alt in detail.altTitles) {
      final altNorm = normalizeTitle(alt);
      if (isMostlyLatin(alt) && altNorm.isNotEmpty && altNorm != norm) {
        originalTitle = alt;
        break;
      }
    }

    final type = detail.type ?? group.type;

    String? coverHash;
    final coverUrl = detail.coverUrl ?? primary.coverUrl;
    if (coverUrl != null && pipeline != null) {
      try {
        coverHash = (await pipeline!
            .fetchAndStore(coverUrl, referer: source.referer))
            .hash;
      } catch (_) {
        // Cover is optional; series row still created.
      }
    }

    final seriesId = await seriesDao.upsertByTitleNorm(Series(
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

    for (final ch in detail.chapters) {
      await chaptersDao.upsert(Chapter(
        seriesId: seriesId,
        sourceId: source.id,
        number: ch.number,
        title: ch.title,
        url: ch.url,
        uploadedAt: ch.uploadedAt,
        fetchedAt: now,
      ));
    }

    await seriesDao.upsertSource(SeriesSource(
      seriesId: seriesId,
      sourceId: source.id,
      sourceUrl: primary.url,
      sourceTitle: detail.title,
      altTitles: detail.altTitles,
      coverUrl: coverUrl,
      lastChapterNumber:
          detail.chapters.isEmpty ? null : detail.chapters.last.number,
      lastUpdatedAt:
          detail.chapters.isEmpty ? null : detail.chapters.last.uploadedAt,
      fetchedAt: now,
    ));
    if (detail.tags.isNotEmpty) {
      await tagsDao.setForSeries(seriesId, detail.tags);
    }

    await _crossProbe(seriesId, group, title, norm, detail.altTitles);
    await libraryDao.add(seriesId, now);
    return seriesId;
  }

  /// Plan/07 §3.2: probe other enabled sources with exact title queries;
  /// any merge-hit gets a series_sources row (lazy detail later). Blocked
  /// (Cloudflare) or erroring sources are skipped silently — this is a
  /// best-effort enrichment, never a failure.
  Future<void> _crossProbe(int seriesId, SearchGroup group, String title,
      String titleNorm, List<String> altTitles) async {
    final groupCand = TitleCandidate(
      norm: titleNorm,
      altNorms: [
        for (final a in altTitles) normalizeTitle(a),
        for (final m in group.members) normalizeTitle(m.title),
      ],
    );
    final queries = <String>{
      title,
      group.primary.title,
      for (final m in group.members) m.title,
    }.toList();

    for (final other in sources) {
      if (other.id == group.primary.sourceId) continue;
      var linked = false;
      for (final q in queries.take(3)) {
        try {
          final items = await other.search(q);
          for (final item in items) {
            if (merges(matchTitles(groupCand, TitleCandidate.fromRaw(item.title)))) {
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
              break;
            }
          }
        } catch (_) {
          break; // source unreachable/blocked — skip it
        }
        if (linked) break;
      }
    }
  }
}

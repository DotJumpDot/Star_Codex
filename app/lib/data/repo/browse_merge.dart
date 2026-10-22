import '../../core/utils/title_match.dart';
import '../../core/utils/title_norm.dart';

/// Pure grouping/filter logic for browse (Plan/07 §2–§3, Plan/08 §3) —
/// no I/O, fully unit-testable. Orchestration lives in `browse_repo.dart`
/// (which re-exports this file).

/// One listing tile from one source — a wire item plus the source context
/// (referer for image fetches) the UI layer needs downstream.
class BrowseCandidate {
  const BrowseCandidate({
    required this.sourceId,
    required this.referer,
    required this.url,
    required this.title,
    this.coverUrl,
    this.chapterCountHint,
    this.type,
    this.lastUpdatedMs,
  });

  final String sourceId;
  final String referer;
  final String url;
  final String title;
  final String? coverUrl;
  final int? chapterCountHint;
  final String? type;
  final int? lastUpdatedMs;

  TitleCandidate get candidate => TitleCandidate.fromRaw(title);
}

/// One merged result card (Plan/08): one real series, N source members.
class SearchGroup {
  SearchGroup(Iterable<BrowseCandidate> initial) : members = [...initial];

  final List<BrowseCandidate> members;

  /// Indices (into the page's group list) of groups in the "similar"
  /// 0.88–0.95 band — UI hint only, never merged (Plan/07 §2). Recomputed
  /// by [annotateSimilar] after every grouping pass.
  final List<int> similarTo = [];

  /// Enriched from a materialized series row (BrowseRepo._enrich) so the
  /// filter sheet can actually filter by status/type/tag and the card can
  /// show a last-update stamp. Nullable — listing-only series carry none.
  String? dbStatus;
  String? dbType;
  int? dbLastUpdatedMs;
  List<String> dbTags = const [];

  /// Series description from the materialized row — the browse card shows
  /// it in the leftover space under the chip row, as much as fits
  /// (user request 2026-10-22: short-title cards had a dead gap there).
  String? dbDescription;

  /// Cover from the materialized series' links (BrowseRepo.enrichGroups).
  /// Listing tiles can point at dead/AVIF files while a sibling site's
  /// cover works — after cross-probe links one, the card renders it from
  /// here even though the listing itself never had it.
  String? dbCoverUrl;
  String? dbCoverReferer;

  /// Max chapter hint across members; null when no source reports one.
  int? get chapterCount {
    final hints = members
        .map((m) => m.chapterCountHint)
        .whereType<int>()
        .toList(growable: false);
    return hints.isEmpty ? null : hints.reduce(_max);
  }

  /// Card update stamp: the FRESHEST of the DB-enriched value and the
  /// listing-carried stamps. The DB used to win unconditionally, which
  /// shadowed a fresh nekopost listing stamp with a stale persisted date
  /// (user report 2026-10-22: site tiles said "16 ชั่วโมงที่แล้ว" while
  /// the card said 3–6 days). Madara/bully tiles carry no stamp at all,
  /// so for them this is still just the DB date.
  int? get lastUpdatedMs {
    int? best = dbLastUpdatedMs;
    for (final m in members) {
      final v = m.lastUpdatedMs;
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  /// True when the card is missing a usable date or cover from what the
  /// listing alone provided — such cards are candidates for background
  /// materialization (detail fetch + cross-probe, BrowseRepo).
  bool get needsMaterialization =>
      lastUpdatedMs == null ||
      !members.any((m) => (m.coverUrl ?? '').isNotEmpty);

  /// First non-null type in member (source sort) order.
  String? get type {
    for (final m in members) {
      if (m.type != null) return m.type;
    }
    return null;
  }

  /// Primary Source = most chapters, tie → member order (source sort order;
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

int _max(int a, int b) => a > b ? a : b;

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

/// DB-enrichment fields survive group rebuilds: merges recreate every
/// existing group as a fresh object, and without this carry the enriched
/// date/type/tags/cover would VANISH from all earlier pages the moment
/// infinite-scroll merges the next page (2026-10-20).
void _carryEnrichment(SearchGroup dst, SearchGroup src) {
  dst.dbStatus = src.dbStatus;
  dst.dbType = src.dbType;
  dst.dbLastUpdatedMs = src.dbLastUpdatedMs;
  dst.dbTags = src.dbTags;
  dst.dbCoverUrl = src.dbCoverUrl;
  dst.dbCoverReferer = src.dbCoverReferer;
  dst.dbDescription = src.dbDescription;
}

/// Merge [incoming] candidates into [existing] groups (Plan/07 §2):
/// duplicate (source,url) dropped; match by exact/alt/fuzzy against every
/// member; else a new group. Used both within one page and across latest-
/// feed pages. Similar-band pairs are annotated afterwards.
List<SearchGroup> mergeIntoGroups(
  List<SearchGroup> existing,
  Iterable<BrowseCandidate> incoming,
) {
  final groups = [for (final g in existing) SearchGroup(g.members)];
  for (var i = 0; i < existing.length; i++) {
    _carryEnrichment(groups[i], existing[i]);
  }
  for (final c in incoming) {
    if (groups.any(
      (g) => g.members.any((m) => m.sourceId == c.sourceId && m.url == c.url),
    )) {
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
      if (matchTitles(
            groups[i].primary.candidate,
            groups[j].primary.candidate,
          ) ==
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
  List<SearchGroup> existing,
  List<SearchGroup> incoming,
) {
  final groups = [for (final g in existing) SearchGroup(g.members)];
  for (var i = 0; i < existing.length; i++) {
    _carryEnrichment(groups[i], existing[i]);
  }
  bool anyMatch(SearchGroup a, SearchGroup b) => a.members.any(
    (m) => b.members.any((n) => merges(matchTitles(m.candidate, n.candidate))),
  );
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
        if (!target.members.any(
          (x) => x.sourceId == m.sourceId && x.url == m.url,
        )) {
          target.members.add(m);
        }
      }
    }
  }
  annotateSimilar(groups);
  return groups;
}

/// View sort order for the browse/search list (user request 2026-10-20;
/// merged with the feed ordering 2026-10-21). Pure client-side ordering
/// of what already loaded — the listing itself keeps paging in source
/// order. [popular] is the exception: it requests the servers' own
/// popularity ordering (feed fetch param) and then does NOT re-sort
/// client-side, so that order shows through. "Popular" is only
/// honored by the ts archive; search ignores ordering params there.
enum BrowseSortOrder {
  latestUpdate,
  oldestUpdate,
  chaptersDesc,
  chaptersAsc,
  popular,
}

/// Session-only browse filters (Plan/08 §3) — NEVER written to settings;
/// defaults OFF per decision L1 (restart ⇒ defaults). Sort is the one
/// exception with a non-off default (L1 addendum, user request
/// 2026-10-20): the list opens on latest-update ordering.
class BrowseFilters {
  const BrowseFilters({
    this.type,
    this.status,
    this.minChapters = 0,
    this.hideOneshot = false,
    this.tags = const {},
    this.sort = BrowseSortOrder.latestUpdate,
  });

  final String? type; // 'manga'|'manhwa'|'manhua'|'novel'
  final String? status; // 'ongoing'|'completed'
  final int minChapters; // 0 = off
  final bool hideOneshot;
  final Set<String> tags;
  final BrowseSortOrder sort;

  bool get isDefault =>
      type == null &&
      status == null &&
      minChapters == 0 &&
      !hideOneshot &&
      tags.isEmpty &&
      sort == BrowseSortOrder.latestUpdate;

  BrowseFilters copyWith({
    String? type,
    bool clearType = false,
    String? status,
    bool clearStatus = false,
    int? minChapters,
    bool? hideOneshot,
    Set<String>? tags,
    BrowseSortOrder? sort,
  }) => BrowseFilters(
    type: clearType ? null : (type ?? this.type),
    status: clearStatus ? null : (status ?? this.status),
    minChapters: minChapters ?? this.minChapters,
    hideOneshot: hideOneshot ?? this.hideOneshot,
    tags: tags ?? this.tags,
    sort: sort ?? this.sort,
  );
}

/// Apply filters to grouped results. Status/tags (and type when a listing
/// carries none) come from the DB enrichment — they filter as soon as the
/// series row exists (visited detail / added to library), and stay honest
/// no-ops otherwise (Plan/08 §3).
List<SearchGroup> filterGroups(List<SearchGroup> groups, BrowseFilters f) {
  return groups
      .where((g) {
        final chapters = g.chapterCount ?? 0;
        if (f.hideOneshot && chapters <= 1) return false;
        if (f.minChapters > 0 && chapters < f.minChapters) return false;
        final type = g.type ?? g.dbType;
        if (f.type != null && type != f.type) return false;
        if (f.status != null && g.dbStatus != f.status) return false;
        if (f.tags.isNotEmpty && !f.tags.any((tag) => g.dbTags.contains(tag))) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
}

/// Sort the filtered view (user request 2026-10-20). STABLE by original
/// position — Dart's List.sort is not, and a re-sort on every enrichment
/// re-emit must not shuffle undated ties. Groups whose key is unknown
/// (no date yet / no chapter hint) sink to the bottom in BOTH directions
/// rather than claiming to be newest/oldest/most/fewest.
List<SearchGroup> sortGroups(List<SearchGroup> groups, BrowseSortOrder order) {
  if (order == BrowseSortOrder.popular) {
    // Server ordering (feed fetch param): show it through untouched —
    // a client re-sort would erase the popularity order.
    return groups;
  }
  final positions = List<int>.generate(groups.length, (i) => i);
  int compare(int a, int b) {
    final ka = _sortKey(groups[a], order);
    final kb = _sortKey(groups[b], order);
    if (ka == null && kb == null) return a.compareTo(b);
    if (ka == null) return 1;
    if (kb == null) return -1;
    final descending =
        order == BrowseSortOrder.latestUpdate ||
        order == BrowseSortOrder.chaptersDesc;
    final byValue = descending ? kb.compareTo(ka) : ka.compareTo(kb);
    return byValue != 0 ? byValue : a.compareTo(b);
  }

  positions.sort(compare);
  return [for (final i in positions) groups[i]];
}

int? _sortKey(SearchGroup g, BrowseSortOrder order) {
  switch (order) {
    case BrowseSortOrder.latestUpdate:
    case BrowseSortOrder.oldestUpdate:
      return g.lastUpdatedMs;
    case BrowseSortOrder.chaptersDesc:
    case BrowseSortOrder.chaptersAsc:
      return g.chapterCount;
    case BrowseSortOrder.popular:
      return null; // unreachable — sortGroups returns early for popular
  }
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

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
  SearchGroup(Iterable<BrowseCandidate> initial) : members = [...initial];

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
    return hints.isEmpty ? null : hints.reduce(_max);
  }

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

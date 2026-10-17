import 'jaro_winkler.dart';
import 'title_norm.dart';

/// Result of comparing two normalized title candidates (Plan/07 §2).
enum TitleMatchKind {
  exact, // same title_norm
  alt, // one side's title_norm is in the other's alt titles
  fuzzy, // jaroWinkler >= 0.95 → auto-merge
  similar, // 0.88–0.95 → UI hint only, NEVER auto-merged
  none,
}

/// A title prepared for matching: its normalization key plus normalized
/// alt titles (empty for browse listings, filled from detail pages/DB).
class TitleCandidate {
  const TitleCandidate({required this.norm, this.altNorms = const []});

  factory TitleCandidate.fromRaw(String rawTitle, {List<String> altTitles = const []}) =>
      TitleCandidate(
        norm: normalizeTitle(rawTitle),
        altNorms: altTitles.map(normalizeTitle).toList(growable: false),
      );

  final String norm;
  final List<String> altNorms;
}

/// The Plan/07 §2 decision table. Empty norms never match (unknown ≠ same).
TitleMatchKind matchTitles(TitleCandidate a, TitleCandidate b,
    {double fuzzyMerge = 0.95, double similarBand = 0.88}) {
  if (a.norm.isEmpty || b.norm.isEmpty) return TitleMatchKind.none;
  if (a.norm == b.norm) return TitleMatchKind.exact;
  if (a.altNorms.contains(b.norm) || b.altNorms.contains(a.norm)) {
    return TitleMatchKind.alt;
  }
  final jw = jaroWinkler(a.norm, b.norm);
  if (jw >= fuzzyMerge) return TitleMatchKind.fuzzy;
  if (jw >= similarBand) return TitleMatchKind.similar;
  return TitleMatchKind.none;
}

/// True when the kind is one that auto-merges two entries.
bool merges(TitleMatchKind kind) =>
    kind == TitleMatchKind.exact ||
    kind == TitleMatchKind.alt ||
    kind == TitleMatchKind.fuzzy;

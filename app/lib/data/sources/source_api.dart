/// Source interface + wire models (Plan/04 §1). Adapters are dumb
/// translators — no caching, no DB. Repos orchestrate adapter →
/// normalize (07) → DB.
abstract class Source {
  String get id;
  String get name;
  String get baseUrl;
  String get referer;
  bool get supportsNovels; // only nekopost: true

  /// Search this source. Free-text, Thai or English.
  Future<List<SourceSeries>> search(String query, {int page = 1});

  /// Latest-updated series (browse home / updates).
  Future<List<SourceSeries>> latest({int page = 1});

  /// Full detail for a series URL: description, tags, type, status,
  /// alt titles, cover url, chapter list (ascending by number).
  Future<SourceSeriesDetail> detail(String sourceUrl);

  /// Ordered image URLs for one chapter URL. For novels: empty list +
  /// `novelText` instead.
  Future<ChapterPages> pages(String chapterUrl);

  /// Novel chapter body (nekopost only). Returns null for image sources.
  Future<String?> novelText(String chapterUrl);

  /// Genre list for the browse picker (Plan/08): display names + URL terms.
  /// [browseGenre] consumes the term — it is source-defined, never guessed.
  Future<List<SourceGenre>> genres();

  /// Series in one genre, filtered server-side, parse like listings.
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1});
}

/// One browsable genre of a source (Plan/08 §2 long-press picker).
class SourceGenre {
  const SourceGenre({required this.name, required this.term});

  final String name; // display, e.g. 'Action' or 'มังงะเกาหลี'
  final String term; // opaque term for browseGenre(), e.g. 'action'
}

class SourceSeries {
  const SourceSeries({
    required this.url,
    required this.title,
    this.coverUrl,
    this.chapterCountHint,
    this.type,
    this.lastUpdatedMs,
  });

  final String url;
  final String title;
  final String? coverUrl;
  final int? chapterCountHint;
  final String? type; // 'manga'|'manhwa'|'manhua'|null (from tile badge)

  /// Epoch ms of the newest known chapter WHEN the listing itself carries
  /// it (nekopost API does; Madara/bully tiles don't). The browse card
  /// prefers the DB-enriched stamp and falls back to this.
  final int? lastUpdatedMs;
}

class SourceSeriesDetail {
  const SourceSeriesDetail({
    required this.title,
    this.altTitles = const [],
    this.description,
    this.tags = const [],
    this.type,
    this.status,
    this.coverUrl,
    required this.chapters,
  });

  final String title;
  final List<String> altTitles;
  final String? description;
  final List<String> tags;
  final String? type;
  final String? status; // normalized lowercase: 'ongoing'|'completed'
  final String? coverUrl;
  final List<SourceChapter> chapters; // ascending by number
}

class SourceChapter {
  const SourceChapter({
    required this.url,
    required this.title,
    required this.number,
    this.uploadedAt,
  });

  final String url;
  final String title;
  final double number;
  final int? uploadedAt;
}

class ChapterPages {
  const ChapterPages({required this.imageUrls});

  final List<String> imageUrls;
}

/// Typed source-layer exception (Plan/04 §6).
enum SourceErrorKind { network, cloudflare, notFound, parse, unknown }

class SourceException implements Exception {
  const SourceException(this.sourceId, this.kind, {this.detail});

  factory SourceException.cloudflare(String sourceId) =>
      SourceException(sourceId, SourceErrorKind.cloudflare);

  final String sourceId;
  final SourceErrorKind kind;
  final String? detail;

  @override
  String toString() => 'SourceException($sourceId, $kind'
      '${detail != null ? ': $detail' : ''})';
}

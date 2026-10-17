import 'package:star_codex/data/sources/source_api.dart';

/// Canned in-memory Source for repo/widget tests — never touches the
/// network, never goes through safe_http.
class FakeSource implements Source {
  FakeSource(
    this.id, {
    this.searchResults = const {},
    this.latestResults = const [],
    this.genreResults = const {},
    this.genreList = const [],
    this.details = const {},
    this.pagesResults = const {},
    this.novelTexts = const {},
    this.error,
  });

  @override
  final String id;

  /// Keyed by trimmed query; missing key → empty results.
  final Map<String, List<SourceSeries>> searchResults;
  final List<SourceSeries> latestResults;
  final Map<String, List<SourceSeries>> genreResults;
  final List<SourceGenre> genreList;
  final Map<String, SourceSeriesDetail> details;

  /// Keyed by chapter URL; missing key → parse error (empty list).
  final Map<String, List<String>> pagesResults;

  /// Keyed by chapter URL; missing key → null (doc 06: image+null = bug).
  final Map<String, String> novelTexts;

  /// When non-null, every network call throws it (Cloudflare simulation).
  final Object? error;

  int searchCalls = 0;
  int detailCalls = 0;
  int pagesCalls = 0;
  int novelCalls = 0;
  List<String> searchedQueries = [];

  @override
  String get name => id;
  @override
  String get baseUrl => 'https://example.com/$id';
  @override
  String get referer => 'https://example.com/$id/';
  @override
  bool get supportsNovels => false;

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    searchCalls++;
    searchedQueries.add(query);
    if (error != null) throw error!;
    return searchResults[query] ?? const [];
  }

  @override
  Future<List<SourceSeries>> latest({int page = 1}) async {
    if (error != null) throw error!;
    return page == 1 ? latestResults : const [];
  }

  @override
  Future<List<SourceGenre>> genres() async {
    if (error != null) throw error!;
    return genreList;
  }

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) async {
    if (error != null) throw error!;
    return page == 1 ? (genreResults[term] ?? const []) : const [];
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    detailCalls++;
    if (error != null) throw error!;
    return details[sourceUrl] ??
        const SourceSeriesDetail(title: 'detail?', chapters: []);
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    pagesCalls++;
    if (error != null) throw error!;
    final urls = pagesResults[chapterUrl];
    if (urls == null || urls.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse, detail: 'no pages');
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async {
    novelCalls++;
    if (error != null) throw error!;
    return novelTexts[chapterUrl];
  }
}

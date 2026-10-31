/// Per-site configs for the Toonary-platform sources (MIX scope —
/// probed 2026-10-28, see toonary_source.dart for the payload layout).
class ToonaryConfig {
  const ToonaryConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.listingInQuery,
    this.cdnPrefix,
    this.genresFromHtmlLinks = false,
    this.genresInFlight = false,
    this.episodeInPath = true,
  });

  final String id;
  final String name;
  final String baseUrl;

  /// true → `/latest?page=N` (mangary); false → `/browse/page/N`
  /// (whytoon). Genres always browse `/latest/<term>?page=N` style on
  /// the query form; whytoon has no genre pages (genres() → empty).
  final bool listingInQuery;

  /// whytoon's flight images are RELATIVE "content/…" paths — resolved
  /// against this CDN origin. mangary serves absolute URLs (null).
  final String? cdnPrefix;

  /// mangary renders the series' categories as /categories/ links in the
  /// detail HTML; whytoon only ships them inside the flight payload.
  final bool genresFromHtmlLinks;

  /// whytoon's LISTING flight embeds each card's content record (slug +
  /// genres) — lets the Mix tab's yaoi filter work from the feed itself
  /// (mangary uses DOM chips instead).
  final bool genresInFlight;

  /// mangary chapter URLs: `/content/<slug>/episode/<no>`; whytoon:
  /// `/content/<slug>/<no>` (the /episode/ form 308-redirects there).
  final bool episodeInPath;

  Uri listingUri(int page) => listingInQuery
      ? Uri.parse('$baseUrl/latest${page > 1 ? '?page=$page' : ''}')
      : Uri.parse('$baseUrl/browse${page > 1 ? '/page/$page' : ''}');

  /// Server-rendered search (probed live 2026-11-01): both sites filter
  /// their listing route with `?q=` — mangary `/latest?q=…(&page=N)`,
  /// whytoon `/browse(/page/N)?q=…`. Same card markup as the feed.
  Uri searchUri(String query, int page) {
    if (listingInQuery) {
      return Uri.parse('$baseUrl/latest').replace(
        queryParameters: {'q': query, if (page > 1) 'page': '$page'},
      );
    }
    final base = '$baseUrl/browse${page > 1 ? '/page/$page' : ''}';
    return Uri.parse(base).replace(queryParameters: {'q': query});
  }

  Uri genreUri(String term, int page) => Uri.parse(
      '$baseUrl/latest/$term${page > 1 ? '?page=$page' : ''}');
}

const toonaryConfigs = [
  ToonaryConfig(
    id: 'mangary',
    name: 'Mangary',
    baseUrl: 'https://mangary.com',
    listingInQuery: true,
    genresFromHtmlLinks: true,
    episodeInPath: true,
  ),
  ToonaryConfig(
    id: 'whytoon',
    name: 'WhyToon',
    baseUrl: 'https://whytoon.com',
    listingInQuery: false,
    cdnPrefix: 'https://gd.whytoon.com/',
    genresFromHtmlLinks: false,
    genresInFlight: true,
    episodeInPath: false,
  ),
];

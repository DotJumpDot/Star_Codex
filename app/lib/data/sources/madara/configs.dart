/// Per-site configs for the Madara-family sites (Plan/05 §1 + §8, with
/// the 2026-10-17 drift record applied; fin-manga + ntr-manga + doujin-lc
/// added 2026-10-18/19).
class MadaraSiteConfig {
  const MadaraSiteConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.seriesUnderMangaPrefix,
    this.searchSupported = true,
    this.classicLayout = false,
    this.archivePath = 'manga',
  });

  final String id;
  final String name;
  final String baseUrl;

  /// slow-manga, up-manga, ntr-manga: `/manga/{slug}/`;
  /// go-manga, dark-manga, fin-manga, doujin-lc (`/doujin/{slug}/`): false.
  /// (Never construct series URLs anyway — always from listing/search links.)
  final bool seriesUnderMangaPrefix;

  /// up-manga & dark-manga: search endpoint sits behind a Cloudflare
  /// challenge (verified 2026-10-17); browse via latest()/genres still works.
  final bool searchSupported;

  /// CLASSIC Madara layout (doujin-lc): listing/search render
  /// `.c-tabs-item` rows instead of ts `.listupd .bsx` tiles, and the
  /// detail page uses `post-title`/`post-content_item`/`wp-manga-chapter`
  /// instead of the ts classes (probed 2026-10-19).
  final bool classicLayout;

  /// Archive/listing path segment — ts sites list under `/manga/`,
  /// doujin-lc registers its custom post type under `/doujin/`.
  final String archivePath;
}

const madaraConfigs = [
  MadaraSiteConfig(
    id: 'slow-manga',
    name: 'Slow Manga',
    baseUrl: 'https://www.slow-manga.net',
    seriesUnderMangaPrefix: true,
    searchSupported: true,
  ),
  MadaraSiteConfig(
    id: 'go-manga',
    name: 'Go-Manga',
    baseUrl: 'https://www.go-manga.com',
    seriesUnderMangaPrefix: false,
    searchSupported: true,
  ),
  MadaraSiteConfig(
    id: 'up-manga',
    name: 'Up-Manga',
    baseUrl: 'https://www.up-manga.com',
    seriesUnderMangaPrefix: true,
    // ?s= was 403-blocked pre-ladder (2026-10-17); the WAF ladder
    // (v1.4.0) escalates the HOST on the CF-signed 403, so search rides
    // cronet/webview like every other page now (user report 2026-10-24:
    // search showed this source as dead).
    searchSupported: true,
  ),
  MadaraSiteConfig(
    id: 'dark-manga',
    name: 'Dark Manga',
    baseUrl: 'https://www.dark-manga.com',
    seriesUnderMangaPrefix: false,
    // Whole site sits behind the challenge and browse already clears it
    // via the ladder — search on the same host rides the same clearance.
    searchSupported: true,
  ),
  MadaraSiteConfig(
    id: 'fin-manga',
    name: 'Fin-Manga',
    baseUrl: 'https://www.fin-manga.com',
    seriesUnderMangaPrefix: false, // /<slug>/ (probed 2026-10-18)
    searchSupported: true,
  ),
  // v11 (2026-10-28): user-added main-feed site. Classic Madara layout
  // (c-tabs-item rows, /manga/page/N/ archive, working ?s= search —
  // probed 2026-10-28, same family as doujin-lc).
  MadaraSiteConfig(
    id: 'nano-manga',
    name: 'Nano-Manga',
    baseUrl: 'https://nano-manga.com',
    seriesUnderMangaPrefix: true, // /manga/<slug>/ (probed 2026-10-28)
    searchSupported: true,
    classicLayout: true,
  ),
  // v13 (2026-11-03): user-added main-feed sites (probed live 2026-11-03)
  // — same ts family end to end: /manga/ .listupd .bsx archive,
  // ?s=&post_type=wp-manga search, entry-title/tsinfo/mgen/eph-num
  // detail. madoo is manhwa-heavy; 1668 is manhua+manhwa and wraps its
  // ts_reader payload in base64 data-URI scripts (pages() decodes them).
  MadaraSiteConfig(
    id: 'madoo-manga',
    name: 'Madoo-Manga',
    baseUrl: 'https://www.madoo-manga.com',
    seriesUnderMangaPrefix: true, // /manga/<slug>/ (probed 2026-11-03)
  ),
  MadaraSiteConfig(
    id: '1668manga',
    name: '1668Manga',
    baseUrl: 'https://1668manga.com',
    seriesUnderMangaPrefix: true, // /manga/<slug>/ (probed 2026-11-03)
  ),
  // --- adult (18+), scoped to the Doujin page only ---
  MadaraSiteConfig(
    id: 'ntr-manga',
    name: 'NTR-Manga',
    baseUrl: 'https://www.ntr-manga.net',
    seriesUnderMangaPrefix: true,
    searchSupported: true, // ts theme + .bsx layouts (probed 2026-10-19)
  ),
  MadaraSiteConfig(
    id: 'doujin-lc',
    name: 'Doujin-LC',
    baseUrl: 'https://doujin-lc.net',
    seriesUnderMangaPrefix: false, // /doujin/<thai-slug>/
    searchSupported: true,
    classicLayout: true,
    archivePath: 'doujin',
    // CLOUDFLARE BLOCKED (2026-10-19 live probe): the zone fingerprint-
    // blocks Dart's TLS stack — "Attention Required!" 403 for every app
    // request while browsers/curl pass (UA/header/HTTP-version probes all
    // 200). Adapters stay correct; the source seeds disabled (db v6).
  ),
];

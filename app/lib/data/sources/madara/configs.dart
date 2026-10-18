/// Per-site configs for the four ts-theme sites (Plan/05 §1 + §8, with the
/// 2026-10-17 drift record applied).
class MadaraSiteConfig {
  const MadaraSiteConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.seriesUnderMangaPrefix,
    this.searchSupported = true,
  });

  final String id;
  final String name;
  final String baseUrl;

  /// slow-manga, up-manga: `/manga/{slug}/`; go-manga, dark-manga: `/{slug}/`.
  /// (Never construct series URLs anyway — always from listing/search links.)
  final bool seriesUnderMangaPrefix;

  /// up-manga & dark-manga: search endpoint sits behind a Cloudflare
  /// challenge (verified 2026-10-17); browse via latest()/genres still works.
  final bool searchSupported;
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
    searchSupported: false, // Cloudflare on ?s= (2026-10-17)
  ),
  MadaraSiteConfig(
    id: 'dark-manga',
    name: 'Dark Manga',
    baseUrl: 'https://www.dark-manga.com',
    seriesUnderMangaPrefix: false,
    searchSupported: false, // Cloudflare on ?s= (2026-10-17)
  ),
  MadaraSiteConfig(
    id: 'fin-manga',
    name: 'Fin-Manga',
    baseUrl: 'https://www.fin-manga.com',
    seriesUnderMangaPrefix: false, // /<slug>/ (probed 2026-10-18)
    searchSupported: true,
  ),
];

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../source_api.dart';

/// Adapter for hentaithai.net (added 2026-10-19, adult scope). A
/// forum-style community site — NOT WordPress. Probed structure:
///
/// - listing: the homepage is a LANDING page (30 `a.number-even` /
///   `a.number-odd` cards + a "see all" button). The real feed is the
///   `/page-<N>` chain the button points at (2026-10-23 probe:
///   `/page-1814` = newest 24 threads, `/page-1813` the next-older 24,
///   descending page numbers, ascending thread ids t51943–t51966).
///   latest(page) walks that chain: page 1 learns N from the homepage
///   link, page k fetches `/page-(N-k+1)`; past the end returns empty.
///   Feed cards are `a.col-6.col-md-3` (title in the attr, cover in a
///   sibling `<style>` background) — a DIFFERENT family from the
///   landing grid. The user-seen `/prev-<id>`//`/next-<id>` links are
///   per-thread JS navigation that 404 on direct GET — not pagination.
/// - search: NOT supported (the site's own search is a Google CSE form).
/// - thread page = detail + reader in one: every page image is inline
///   (`img[src*="hentaithai.net/"]` on the s1 CDN). TWO page-image
///   layouts exist and both are live: `s1.hentaithai.net/thai/2026/
///   2026-10-10/05484/1.webp` and `s1.hentaithai.net/image/2026/
///   2026-10-16/{slug}-001.jpg` (the newer one, probed 2026-10-22 on
///   t51989). One-shot → one chapter.
class HentaiThaiSource implements Source {
  HentaiThaiSource(this.http);

  final SafeHttp http;

  /// Newest `/page-N` listing number, learned once from the homepage
  /// "see all" link and reused for the whole session (newest only ever
  /// grows, so a cached N stays a valid walk start; a mid-session new
  /// thread just makes page 1 one thread stale — same drift as every
  /// other source's TTL).
  int? _newestListingPage;

  @override
  String get id => 'hentaithai';
  @override
  String get name => 'HentaiThai';
  @override
  String get baseUrl => 'https://hentaithai.net';
  @override
  String get referer => '$baseUrl/';
  @override
  bool get supportsNovels => false;

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    throw SourceException(
      id,
      SourceErrorKind.notFound,
      detail: 'hentaithai search is a Google CSE form — browse the feed',
    );
  }

  @override
  Future<List<SourceSeries>> latest({
    int page = 1,
    bool popular = false,
  }) async {
    final newest = _newestListingPage ?? await _learnNewestPage();
    if (newest == null) {
      // Redesign fallback: no /page-N link on the homepage — keep the
      // old landing-grid behavior (30 cards, single page).
      if (page > 1) return const [];
      final body = await _fetch(Uri.parse('$baseUrl/'));
      if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
      return parseHentaiThaiListing(body);
    }
    final target = newest - (page - 1);
    if (target < 1) return const []; // walked past the oldest page
    try {
      final body = await _fetch(Uri.parse('$baseUrl/page-$target'));
      if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
      return parseHentaiThaiFeedListing(body);
    } on SourceException catch (e) {
      // A cached N can outlive the site's own history window: pages
      // beyond the end are a clean empty, not an error (page 1 failing
      // is still a real error).
      if (e.kind == SourceErrorKind.notFound && page > 1) return const [];
      rethrow;
    }
  }

  /// The homepage's "see all" button links the current newest
  /// `/page-N` listing page. Returns null when the link is gone.
  Future<int?> _learnNewestPage() async {
    final home = await _fetch(Uri.parse('$baseUrl/'));
    if (_looksLikeCloudflare(home)) throw SourceException.cloudflare(id);
    final doc = html_parser.parse(home);
    for (final a in doc.querySelectorAll('a[href*="/page-"]')) {
      final m =
          RegExp(r'/page-(\d+)').firstMatch(a.attributes['href'] ?? '');
      if (m != null) {
        _newestListingPage = int.parse(m.group(1)!);
        return _newestListingPage;
      }
    }
    return null;
  }

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) async {
    if (page > 1) return const [];
    final body = await _fetch(Uri.parse('$baseUrl/$term'));
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    return parseHentaiThaiListing(body);
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final body = await _fetch(Uri.parse(sourceUrl));
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    final detail = parseHentaiThaiDetail(body, sourceUrl);
    if (detail == null) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no hentaithai thread content on $sourceUrl',
      );
    }
    return detail;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    final urls = parseHentaiThaiPages(body);
    if (urls.isEmpty) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no thread images on $chapterUrl',
      );
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

  /// No homepage recent-grid on this engine — [Source.recentStamps]
  /// stays a no-op here.
  @override
  Future<List<SourceRecentStamp>> recentStamps() async => const [];

  /// Tag pages off the homepage nav (`/tag-<id>`) — same card grid.
  @override
  Future<List<SourceGenre>> genres() async {
    final body = await _fetch(Uri.parse('$baseUrl/'));
    return parseHentaiThaiGenres(body);
  }

  Future<String> _fetch(Uri uri) async {
    try {
      return await http.getHtml(uri, referer: referer);
    } on NetException catch (e) {
      if (e.statusCode == 403) {
        throw SourceException(
          id,
          SourceErrorKind.cloudflare,
          detail: 'HTTP 403 at $uri',
        );
      }
      if (e.statusCode == 404) {
        throw SourceException(
          id,
          SourceErrorKind.notFound,
          detail: 'HTTP 404 at $uri',
        );
      }
      throw SourceException(id, SourceErrorKind.network, detail: e.toString());
    }
  }

  bool _looksLikeCloudflare(String body) => looksLikeCloudflarePage(body);
}

// --- pure parsers (fixture-tested, no I/O) ---

@visibleForTesting
List<SourceSeries> parseHentaiThaiListing(String body) {
  return _parseCards(body, 'a.number-even, a.number-odd');
}

/// The /page-N feed listing (2026-10-23 probe): 24 cards per page, a
/// DIFFERENT family from the landing grid — `a.col-6.col-md-3`, title in
/// the attribute, cover + upload date in the sibling `<style>` block.
@visibleForTesting
List<SourceSeries> parseHentaiThaiFeedListing(String body) {
  return _parseCards(body, 'a.col-6.col-md-3');
}

/// Shared card walk: both hentaithai listing families carry the thread
/// URL in href (`//hentaithai.net/t<id>`, mixed host case), the title in
/// the `title` attribute, and NO <img>/date — the cover is the CDN
/// background-image in the card's preceding <style> block, whose path
/// embeds the upload date (/thai/2026/2026-10-10/…, /image/2026/…).
List<SourceSeries> _parseCards(String body, String selector) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final a in doc.querySelectorAll(selector)) {
    final href = a.attributes['href'] ?? '';
    final title = (a.attributes['title'] ?? '').trim();
    if (href.isEmpty || title.isEmpty) continue;
    // //HentaiThai.net/t51996 → canonical lowercase-host https URL (the
    // site mixes host cases; Uri normalizes the host for identity).
    final url =
        Uri.tryParse(href.startsWith('//') ? 'https:$href' : href)
            ?.toString() ??
        href;
    final img = a.querySelector('img');
    var cover = _imgUrl(img);
    // Cards carry no <img> and no date text — both live in the card's
    // preceding <style> block as a CDN background-image URL whose path
    // embeds the upload date: /thai/2026/2026-10-10/05484/2.webp
    // (probed 2026-10-21: the thread pages expose no <time> stamps).
    if (cover == null) {
      final bg = _cardBackgroundUrl(a);
      cover = bg;
    }
    final stampUrl = cover ?? _cardBackgroundUrl(a);
    out.add(
      SourceSeries(
        url: url,
        title: title,
        coverUrl: cover,
        lastUpdatedMs: hentaiThaiUploadDate(stampUrl),
      ),
    );
  }
  return out;
}

/// The card art rides in a sibling `<style>` (`.post_N { background-image:
/// url(...) }`) — return that URL, or null.
String? _cardBackgroundUrl(html_dom.Element a) {
  var node = a.previousElementSibling;
  while (node != null) {
    final m = RegExp(r'''url\(['"]?([^'")]+)['"]?\)''').firstMatch(node.text);
    if (m != null) {
      final raw = m.group(1)!.trim();
      if (raw.isEmpty) break;
      return raw.startsWith('//') ? 'https:$raw' : raw;
    }
    node = node.previousElementSibling;
  }
  return null;
}

/// Upload date embedded in the CDN path (`/thai/2026/2026-10-10/…` or
/// `/image/2026/2026-10-16/…`) as epoch ms (UTC midnight) — the site's
/// only reliable stamp.
@visibleForTesting
int? hentaiThaiUploadDate(String? url) {
  if (url == null) return null;
  final m = _hentaiThaiDateRe.firstMatch(url);
  if (m == null) return null;
  final dt = DateTime.tryParse('${m.group(1)}-${m.group(2)}-${m.group(3)}');
  return dt?.millisecondsSinceEpoch;
}

/// The CDN carries the upload date in the path for BOTH content layouts:
/// `/thai/<year>/<yyyy-mm-dd>/…` and `/image/<year>/<yyyy-mm-dd>/…`.
/// A blind `/thai/` match silently dropped every `/image/` thread — the
/// detail page then had no pages and showed "can't load" (probed
/// 2026-10-22: t51989 uses `/image/`, t51996 uses `/thai/`).
final _hentaiThaiDateRe = RegExp(
  r'/(?:thai|image)/\d{4}/(\d{4})-(\d{2})-(\d{2})/',
);

@visibleForTesting
SourceSeriesDetail? parseHentaiThaiDetail(String body, String sourceUrl) {
  final doc = html_parser.parse(body);
  final imgs = parseHentaiThaiImages(doc);
  if (imgs.isEmpty) return null;

  var title = (doc.querySelector('title')?.text ?? '').trim();
  // Title pattern: "<Thai title> - [Circle (Author)] <original>" — keep it
  // whole; split off any trailing site boilerplate if present.
  title = title.split(RegExp(r'\s*[|·]\s*HentaiThai')).first.trim();
  if (title.isEmpty) title = sourceUrl;

  final tags = <String>{
    for (final a in doc.querySelectorAll('a[href*="/tag-"]'))
      if (a.text.trim().isNotEmpty) a.text.trim(),
  }.toList();

  return SourceSeriesDetail(
    title: title,
    description: null,
    tags: tags,
    coverUrl: imgs.first,
    chapters: [
      SourceChapter(
        url: sourceUrl,
        title: 'ตอนที่ 1',
        number: 1,
        // Only stamp on the page: the upload date embedded in the CDN
        // image paths (no <time> elements — probed 2026-10-21).
        uploadedAt: hentaiThaiUploadDate(imgs.first),
      ),
    ],
  );
}

@visibleForTesting
List<String> parseHentaiThaiPages(String body) {
  final doc = html_parser.parse(body);
  return parseHentaiThaiImages(doc);
}

List<String> parseHentaiThaiImages(html_dom.Document doc) {
  final out = <String>[];
  for (final img in doc.querySelectorAll('img')) {
    final u = _imgUrl(img);
    if (u != null) out.add(u);
  }
  return out;
}

/// Content images only: the s1 CDN carries the manga pages. TWO layouts
/// exist (probed 2026-10-22):
///   - `/thai/<year>/<yyyy-mm-dd>/<id>/<n>.webp`   (t51996 and older)
///   - `/image/<year>/<yyyy-mm-dd>/<slug>-<nnn>.jpg` (t51989 and newer)
/// The date-bearing path segment is what marks a page image; avatars,
/// banners, stickers and credits live under `/image/other/`,
/// `/image/sticker/`, `/image/credit/` — no date segment, so they are
/// excluded by the same rule.
String? _imgUrl(html_dom.Element? img) {
  if (img == null) return null;
  final raw =
      (img.attributes['data-src'] ??
              img.attributes['data-original'] ??
              img.attributes['src'] ??
              '')
          .trim();
  if (raw.isEmpty || raw.startsWith('data:')) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (!uri.host.endsWith('hentaithai.net')) return null;
  if (!_hentaiThaiDateRe.hasMatch(uri.path)) return null;
  return raw.startsWith('//') ? 'https:$raw' : raw;
}

@visibleForTesting
List<SourceGenre> parseHentaiThaiGenres(String body) {
  final doc = html_parser.parse(body);
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in doc.querySelectorAll('a[href*="/tag-"]')) {
    final name = a.text.trim();
    final href = a.attributes['href'] ?? '';
    if (name.isEmpty || href.isEmpty) continue;
    final m = RegExp(r'/tag-(\w+)').firstMatch(href);
    if (m == null) continue;
    final term = 'tag-${m.group(1)!}';
    if (!seen.add(term)) continue;
    out.add(SourceGenre(name: name, term: term));
  }
  return out;
}

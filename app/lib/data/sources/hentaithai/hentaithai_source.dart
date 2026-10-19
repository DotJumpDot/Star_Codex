import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../source_api.dart';

/// Adapter for hentaithai.net (added 2026-10-19, adult scope). A
/// forum-style community site — NOT WordPress. Probed structure:
///
/// - listing: homepage grid only (`a.number-even` / `a.number-odd` cards;
///   the full title rides in the `title` attribute, thread link is
///   `/t<id>`). `/page/N` 404s → latest() is a single page; paging
///   returns empty (feed stays honest).
/// - search: NOT supported (the site's own search is a Google CSE form).
/// - thread page = detail + reader in one: every page image is inline
///   (`img[src*="hentaithai.net/"]` on the s1 CDN, e.g.
///   `s1.hentaithai.net/thai/2026/.../N.webp`). One-shot → one chapter.
class HentaiThaiSource implements Source {
  HentaiThaiSource(this.http);

  final SafeHttp http;

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
    throw SourceException(id, SourceErrorKind.notFound,
        detail: 'hentaithai search is a Google CSE form — browse the feed');
  }

  @override
  Future<List<SourceSeries>> latest({int page = 1}) async {
    if (page > 1) return const []; // single-page homepage feed (probed)
    final body = await _fetch(Uri.parse('$baseUrl/'));
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    return parseHentaiThaiListing(body);
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
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no hentaithai thread content on $sourceUrl');
    }
    return detail;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    final urls = parseHentaiThaiPages(body);
    if (urls.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no thread images on $chapterUrl');
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

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
        throw SourceException(id, SourceErrorKind.cloudflare,
            detail: 'HTTP 403 at $uri');
      }
      if (e.statusCode == 404) {
        throw SourceException(id, SourceErrorKind.notFound,
            detail: 'HTTP 404 at $uri');
      }
      throw SourceException(id, SourceErrorKind.network, detail: e.toString());
    }
  }

  bool _looksLikeCloudflare(String body) =>
      body.contains('Just a moment...') ||
      body.contains('challenge-platform') ||
      body.contains('cf-mitigated');
}

// --- pure parsers (fixture-tested, no I/O) ---

@visibleForTesting
List<SourceSeries> parseHentaiThaiListing(String body) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final a in doc.querySelectorAll('a.number-even, a.number-odd')) {
    final href = a.attributes['href'] ?? '';
    final title = (a.attributes['title'] ?? '').trim();
    if (href.isEmpty || title.isEmpty) continue;
    // //HentaiThai.net/t51996 → canonical lowercase-host https URL (the
    // site mixes host cases; Uri normalizes the host for identity).
    final url = Uri.tryParse(href.startsWith('//') ? 'https:$href' : href)
            ?.toString() ??
        href;
    final img = a.querySelector('img');
    final cover = _imgUrl(img);
    out.add(SourceSeries(
      url: url,
      title: title,
      coverUrl: cover,
    ));
  }
  return out;
}

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

/// Content images only: the s1 CDN carries the manga pages
/// (`s1.hentaithai.net/thai/...`); avatars/banners/icons live elsewhere.
String? _imgUrl(html_dom.Element? img) {
  if (img == null) return null;
  final raw = (img.attributes['data-src'] ??
          img.attributes['data-original'] ??
          img.attributes['src'] ??
          '')
      .trim();
  if (raw.isEmpty || raw.startsWith('data:')) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (!uri.host.endsWith('hentaithai.net')) return null;
  if (!uri.path.startsWith('/thai/')) return null;
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

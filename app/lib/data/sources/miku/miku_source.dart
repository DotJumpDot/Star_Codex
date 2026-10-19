import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../source_api.dart';

/// Adapter for miku-doujin.com (added 2026-10-19, adult scope). WordPress
/// with a fully custom "inz" theme. Probed structure:
///
/// - listing: homepage + `?paged=N` (verified) — cards are `a.inz-a` with
///   the title in `.inz-title`/`.inz-title-sm` and the cover in
///   `img.inz-img-thumbnail` (lazy data-src).
/// - search: NOT supported — `?s=` is ignored and renders the homepage.
/// - series page = the READER (one-shot doujin): all pages are
///   `#manga-content img.lazy[data-src]` inline. Detail therefore reports
///   exactly one chapter whose URL IS the series URL; tags come from
///   `a[href*="/category/"]`.
class MikuDoujinSource implements Source {
  MikuDoujinSource(this.http);

  final SafeHttp http;

  @override
  String get id => 'miku-doujin';
  @override
  String get name => 'Miku-Doujin';
  @override
  String get baseUrl => 'https://miku-doujin.com';
  @override
  String get referer => '$baseUrl/';
  @override
  bool get supportsNovels => false;

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    // The theme ignores ?s= entirely (probed 2026-10-19).
    throw SourceException(id, SourceErrorKind.notFound,
        detail: 'miku-doujin has no working search — browse the feed');
  }

  @override
  Future<List<SourceSeries>> latest({int page = 1}) =>
      _listing(Uri.parse('$baseUrl/').replace(queryParameters: {
        if (page > 1) 'paged': '$page',
      }));

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) =>
      _listing(Uri.parse(
          '$baseUrl/category/${Uri.encodeComponent(term)}/').replace(
        queryParameters: {
          if (page > 1) 'paged': '$page',
        },
      ));

  Future<List<SourceSeries>> _listing(Uri uri) async {
    final body = await _fetch(uri);
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    return parseMikuListing(body, baseUrl);
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final body = await _fetch(Uri.parse(sourceUrl));
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    final detail = parseMikuDetail(body, sourceUrl, baseUrl);
    if (detail == null) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no miku series content on $sourceUrl');
    }
    return detail;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    final urls = parseMikuPages(body);
    if (urls.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no #manga-content images on $chapterUrl');
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

  /// Category cloud off the homepage (Thai category names; the term is the
  /// raw path segment, percent-encoded back into the browse URL).
  @override
  Future<List<SourceGenre>> genres() async {
    final body = await _fetch(Uri.parse('$baseUrl/'));
    return parseMikuGenres(body);
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
List<SourceSeries> parseMikuListing(String body, String baseUrl) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final a in doc.querySelectorAll('a.inz-a')) {
    final href = a.attributes['href'] ?? '';
    final title = (a.querySelector('.inz-title') ??
            a.querySelector('.inz-title-sm'))
            ?.text
            .trim() ??
        a.attributes['title']?.trim() ??
        '';
    if (href.isEmpty || title.isEmpty) continue;
    final img = a.querySelector('img');
    out.add(SourceSeries(
      url: href,
      title: title,
      coverUrl: _imgUrl(img, baseUrl),
    ));
  }
  return out;
}

@visibleForTesting
SourceSeriesDetail? parseMikuDetail(
    String body, String sourceUrl, String baseUrl) {
  final doc = html_parser.parse(body);
  final content = doc.querySelector('#manga-content');
  if (content == null) return null;

  // <title>อัศวินอกโตชาร์ล็อต (Onomeshin)</title> — also strip any
  // " :: MIKU-DOUJIN" style suffix just in case.
  var title = (doc.querySelector('title')?.text ?? '').trim();
  title = title.split(RegExp(r'\s*[|·::]+\s*MIKU')).first.trim();
  if (title.isEmpty) title = sourceUrl;

  final imgs = content.querySelectorAll('img');
  String? cover;
  for (final img in imgs) {
    final u = _imgUrl(img, baseUrl);
    if (u != null) {
      cover = u;
      break;
    }
  }

  final tags = <String>{
    for (final a in doc.querySelectorAll('a[href*="/category/"]'))
      if (a.text.trim().isNotEmpty) a.text.trim(),
  }.toList();

  // One-shot: the series page IS the chapter.
  return SourceSeriesDetail(
    title: title,
    description: null,
    tags: tags,
    coverUrl: cover,
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
List<String> parseMikuPages(String body) {
  final doc = html_parser.parse(body);
  final content = doc.querySelector('#manga-content');
  if (content == null) return const [];
  final out = <String>[];
  for (final img in content.querySelectorAll('img')) {
    final u = _imgUrl(img, null);
    if (u != null && !u.startsWith('data:')) out.add(u);
  }
  return out;
}

@visibleForTesting
List<SourceGenre> parseMikuGenres(String body) {
  final doc = html_parser.parse(body);
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in doc.querySelectorAll('a[href*="/category/"]')) {
    final name = a.text.trim();
    final href = a.attributes['href'] ?? '';
    if (name.isEmpty || href.isEmpty) continue;
    final segs = Uri.tryParse(href)?.pathSegments ?? const [];
    // /category/<term>/ → term (Thai, possibly URL-encoded in href).
    var i = segs.indexOf('category');
    if (i < 0 || i + 1 >= segs.length) continue;
    final term = Uri.decodeComponent(segs[i + 1]);
    if (term.isEmpty || !seen.add(term)) continue;
    out.add(SourceGenre(name: name, term: term));
  }
  return out;
}

String? _imgUrl(html_dom.Element? img, String? baseUrl) {
  if (img == null) return null;
  final raw = (img.attributes['data-src'] ?? img.attributes['src'] ?? '')
      .trim();
  if (raw.isEmpty || raw.startsWith('data:')) return null;
  if (raw.startsWith('http')) return raw;
  if (baseUrl == null) return null;
  try {
    return Uri.parse(baseUrl).resolve(raw).toString();
  } on Exception {
    return null;
  }
}

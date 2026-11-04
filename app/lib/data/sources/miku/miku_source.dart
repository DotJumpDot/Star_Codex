import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../source_api.dart';

/// Adapter for miku-doujin.com (added 2026-10-19, adult scope). WordPress
/// with a fully custom "inz" theme. Probed structure:
///
/// - listing: homepage + `?page=N` (theme rebuild 2026-10-28 moved the
///   pagination param from `?paged=N` — the old param now answers with a
///   COPY of page 1, which stalled the infinite feed). Cards are
///   `a.inz-a` with the title in `.inz-title`/`.inz-title-sm` and the
///   cover in `img.inz-img-thumbnail` (lazy data-src).
/// - search: POST `/controller/search/general/` with `keysearch=<q>`
///   (2026-11-04 — the endpoint the theme's own header search injects;
///   the WP `?s=` route renders the homepage verbatim and wp-json is
///   404). Returns the feed's `.inz-a` card fragment, single page.
/// - genres: `/genre/<term>/` (2026-10-28 — was `/category/`; the old
///   paths still answer 200 but render an EMPTY list).
/// - series page = the READER (one-shot doujin): all pages are
///   `#manga-content img.lazy[data-src]` inline. Detail therefore reports
///   exactly one chapter whose URL IS the series URL; tags come from
///   `a[href*="/genre/"]`.
///
/// Cloudflare fingerprint-blocked Dart's TLS stack (2026-10-19 probe);
/// the WAF ladder's cronet tier (2026-10-23) unlocks it and the source
/// ships enabled since db v9.
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
  String? get imageReferer => referer;
  @override
  bool get supportsNovels => false;

  @override
  // Interface default spelled out: these sites serve permanent page URLs.
  bool get pageUrlsExpire => false;

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    if (page > 1) return const []; // ajax results are a single page
    // The theme's header search box POSTs /controller/search/general/
    // with `keysearch` and injects the returned .inz-a card fragment
    // (found in the page's own inline search(), 2026-11-04 — the WP
    // `?s=` route renders the homepage verbatim and wp-json is 404).
    // The fragment reuses the feed's card markup, so parseMikuListing
    // reads it unchanged.
    final body = await _postForm(
      Uri.parse('$baseUrl/controller/search/general/'),
      {'keysearch': query},
    );
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    return parseMikuListing(body, baseUrl);
  }

  @override
  Future<List<SourceSeries>> latest({int page = 1, bool popular = false}) =>
      _listing(Uri.parse(page > 1 ? '$baseUrl/?page=$page' : '$baseUrl/'));

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) =>
      _listing(
        Uri.parse(
          page > 1
              ? '$baseUrl/genre/${Uri.encodeComponent(term)}/?page=$page'
              : '$baseUrl/genre/${Uri.encodeComponent(term)}/',
        ),
      );

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
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no miku series content on $sourceUrl',
      );
    }
    return detail;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    final urls = parseMikuPages(body);
    if (urls.isEmpty) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no #manga-content images on $chapterUrl',
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
      throw _netError(e, uri);
    }
  }

  /// POST a small urlencoded form (the search endpoint) and decode the
  /// fragment — same exception mapping as [_fetch].
  Future<String> _postForm(Uri uri, Map<String, String> fields) async {
    try {
      final bytes = await http.postForm(uri, fields, referer: referer);
      return utf8.decode(bytes, allowMalformed: true);
    } on NetException catch (e) {
      throw _netError(e, uri);
    }
  }

  SourceException _netError(NetException e, Uri uri) {
    if (e.statusCode == 403) {
      return SourceException(
        id,
        SourceErrorKind.cloudflare,
        detail: 'HTTP 403 at $uri',
      );
    }
    if (e.statusCode == 404) {
      return SourceException(
        id,
        SourceErrorKind.notFound,
        detail: 'HTTP 404 at $uri',
      );
    }
    return SourceException(id, SourceErrorKind.network, detail: e.toString());
  }

  bool _looksLikeCloudflare(String body) => looksLikeCloudflarePage(body);
}

// --- pure parsers (fixture-tested, no I/O) ---

@visibleForTesting
List<SourceSeries> parseMikuListing(String body, String baseUrl) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final a in doc.querySelectorAll('a.inz-a')) {
    final href = a.attributes['href'] ?? '';
    final title =
        (a.querySelector('.inz-title') ?? a.querySelector('.inz-title-sm'))
            ?.text
            .trim() ??
        a.attributes['title']?.trim() ??
        '';
    if (href.isEmpty || title.isEmpty) continue;
    final img = a.querySelector('img');
    out.add(
      SourceSeries(url: href, title: title, coverUrl: _imgUrl(img, baseUrl)),
    );
  }
  return out;
}

@visibleForTesting
SourceSeriesDetail? parseMikuDetail(
  String body,
  String sourceUrl,
  String baseUrl,
) {
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
    for (final a in doc.querySelectorAll('a[href*="/genre/"]'))
      if (a.text.trim().isNotEmpty) a.text.trim(),
  }.toList();

  // One-shot: the series page IS the chapter.
  return SourceSeriesDetail(
    title: title,
    description: null,
    tags: tags,
    coverUrl: cover,
    chapters: [SourceChapter(url: sourceUrl, title: 'ตอนที่ 1', number: 1)],
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
  for (final a in doc.querySelectorAll('a[href*="/genre/"]')) {
    final name = a.text.trim();
    final href = a.attributes['href'] ?? '';
    if (name.isEmpty || href.isEmpty) continue;
    final segs = Uri.tryParse(href)?.pathSegments ?? const [];
    // /genre/<term>/ → term. pathSegments arrives ALREADY
    // percent-decoded (Thai terms decode fine); a second
    // Uri.decodeComponent on the decoded Thai throws "Illegal percent
    // encoding" (caught by the 2026-10-28 genre-cloud test).
    var i = segs.indexOf('genre');
    if (i < 0 || i + 1 >= segs.length) continue;
    final term = segs[i + 1];
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

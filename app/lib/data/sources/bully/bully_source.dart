import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../../../core/utils/thai.dart';
import '../source_api.dart';

/// Adapter for bully-manga.com (added 2026-10-18). NOT a WordPress/ts
/// theme — a static server-rendered site, so it gets its own adapter
/// instead of a MadaraSiteConfig. Probed structure (all server-rendered,
/// no JS needed):
///
/// - listing: `/genres/all[/<page>]` — `div.mc-card` tiles (a.mc-img-wrap
///   href = series `/slug`, img.mc-img alt = title + data-src = real
///   cover behind a placeholder src, .mc-badge img = type icon
///   `/static/images/{manga|manhwa|manhua|novel}.svg`, first .mc-ep-num
///   "ตอน N" = latest-chapter hint). 39 pages, real per-page content.
/// - search: `/search?keyword=<q>&page=<n>` — same cards, but the index
///   ALSO returns chapter pages (`<slug>-epNNNN`) which are filtered out.
/// - genre browse: `/genres/<Term>[/<page>]`.
/// - detail: series page with JSON-LD `ComicSeries` (name/description/
///   image), `a.sh-genre` Thai genre tags, `span.sh-badge-status`
///   ("On Going"), and the FULL chapter list as `a.sh-ep` rows
///   (href, data-title = number, .sh-ep-label = title, .sh-ep-date =
///   relative Thai stamp). Absolute last-update lives in the
///   `อัปเดท` meta pill.
/// - pages: chapter page embeds `const IMAGE_MAP = ["/img/backcat/<ep>_1.jpg", …]`.
class BullyMangaSource implements Source {
  BullyMangaSource(this.http);

  final SafeHttp http;

  @override
  String get id => 'bully-manga';
  @override
  String get name => 'Bully Manga';
  @override
  String get baseUrl => 'https://bully-manga.com';
  @override
  String get referer => '$baseUrl/';
  @override
  bool get supportsNovels => false;

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    final items = await _listing(Uri.parse('$baseUrl/search').replace(
      queryParameters: {
        'keyword': query,
        'page': '$page',
      },
    ));
    // The site's search index includes chapter pages — keep series only.
    final seriesRe = RegExp(r'-ep\d+$');
    String? lastSegment(String url) {
      final segs = Uri.parse(url).pathSegments;
      return segs.isEmpty ? null : segs.last;
    }

    return [
      for (final s in items)
        if (!(seriesRe.hasMatch(lastSegment(s.url) ?? ''))) s,
    ];
  }

  @override
  Future<List<SourceSeries>> latest({int page = 1, bool popular = false}) =>
      _listing(_genrePage('all', page));

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) =>
      _listing(_genrePage(term, page));

  Uri _genrePage(String term, int page) =>
      Uri.parse('$baseUrl/genres/$term${page > 1 ? '/$page' : ''}');

  Future<List<SourceSeries>> _listing(Uri uri) async {
    final body = await _fetch(uri);
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    return parseBullyListing(body, baseUrl);
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final body = await _fetch(Uri.parse(sourceUrl));
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    final detail = parseBullyDetail(body, sourceUrl, baseUrl);
    if (detail == null) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no bully series data on $sourceUrl');
    }
    return detail;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    final urls = parseBullyImageMap(body, baseUrl);
    if (urls.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no IMAGE_MAP on $chapterUrl');
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

  /// Genre links scraped off a listing page (English terms, e.g. Action).
  @override
  Future<List<SourceGenre>> genres() async {
    final body = await _fetch(Uri.parse('$baseUrl/genres/all'));
    return parseBullyGenres(body);
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

  bool _looksLikeCloudflare(String body) => looksLikeCloudflarePage(body);
}

// --- pure parsers (fixture-tested, no I/O) ---

@visibleForTesting
List<SourceSeries> parseBullyListing(String body, String baseUrl) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final card in doc.querySelectorAll('.mc-card')) {
    final anchor = card.querySelector('a.mc-img-wrap');
    final url = _resolveUrl(baseUrl, anchor?.attributes['href'] ?? '');
    if (anchor == null || url == null) continue;
    final img = anchor.querySelector('img.mc-img');
    final title =
        (img?.attributes['alt'] ?? card.querySelector('.mc-title')?.text ?? '')
            .trim();
    if (title.isEmpty) continue;
    // Real cover rides in data-src behind a default placeholder in src.
    final cover = _cleanUrl(img?.attributes['data-src'], baseUrl) ??
        _cleanUrl(img?.attributes['src'], baseUrl);
    final type = _typeFromBadge(
        card.querySelector('.mc-badge img')?.attributes['src']);
    final epText = card.querySelector('.mc-ep-num')?.text.trim();
    final hint = epText == null ? null : parseChapterNumber(epText);
    out.add(SourceSeries(
      url: url,
      title: title,
      coverUrl: cover,
      chapterCountHint: hint?.toInt(),
      type: type,
    ));
  }
  return out;
}

@visibleForTesting
List<SourceGenre> parseBullyGenres(String body) {
  final doc = html_parser.parse(body);
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in doc.querySelectorAll('a[href*="/genres/"]')) {
    final href = a.attributes['href'] ?? '';
    final name = a.text.trim();
    if (href.isEmpty || name.isEmpty) continue;
    final segs = _safePathSegments(href);
    if (segs == null || segs.length < 2 || segs.first != 'genres') continue;
    final term = segs[1];
    if (term == 'all' || !seen.add(term)) continue;
    out.add(SourceGenre(name: name, term: term));
  }
  return out;
}

@visibleForTesting
SourceSeriesDetail? parseBullyDetail(
    String body, String sourceUrl, String baseUrl) {
  final doc = html_parser.parse(body);

  // JSON-LD block carries the cleanest name/description/cover.
  String? title;
  String? description;
  String? cover;
  final ldRaw = RegExp(
    r'<script type="application/ld\+json">\s*(\{.*?\})\s*</script>',
    multiLine: true,
    dotAll: true,
  ).firstMatch(body);
  if (ldRaw != null) {
    try {
      final ld = jsonDecode(ldRaw.group(1)!) as Map<String, dynamic>;
      title = (ld['name'] as String?)?.trim();
      // The site embeds literal markdown bold markers — strip them.
      description = (ld['description'] as String?)
          ?.trim()
          .replaceAll('**', '');
      cover = _cleanUrl(ld['image'] as String?, baseUrl);
    } on Exception {
      // fall through to DOM fallbacks below
    }
  }
  title ??= doc
      .querySelector('.sh-title, h1')
      ?.text
      .replaceAll('มังงะ', '')
      .replaceAll('เรื่อง', '')
      .trim();
  if (title == null || title.isEmpty) return null;
  cover ??= _cleanUrl(
      doc.querySelector('img.mc-img, .sh-cover img')?.attributes['data-src'],
      baseUrl);

  final tags = [
    for (final a in doc.querySelectorAll('a.sh-genre'))
      if (a.text.trim().isNotEmpty) a.text.trim(),
  ];

  // Series pages badge type as text (`sh-badge-type` "MANGA"); listing
  // cards use /static/images/<type>.svg icons. Try text first.
  String? type;
  final badgeType = doc.querySelector('.sh-badge-type')?.text.trim();
  if (badgeType != null && badgeType.isNotEmpty) {
    type = _typeFromBadge(badgeType.toLowerCase());
  }
  type ??= _typeFromBadge(
      doc.querySelector('img[src*="/static/images/"]')?.attributes['src']);

  final statusText =
      doc.querySelector('.sh-badge-status')?.text.trim().toLowerCase();
  final status = _normalizeStatus(statusText);

  final chapters = <SourceChapter>[];
  for (final a in doc.querySelectorAll('a.sh-ep')) {
    final url = _resolveUrl(sourceUrl, a.attributes['href'] ?? '');
    if (url == null) continue;
    final number = double.tryParse(a.attributes['data-title'] ?? '') ??
        parseChapterNumber(a.querySelector('.sh-ep-label')?.text ?? '') ??
        parseChapterNumber(a.attributes['data-ep'] ?? '');
    if (number == null) continue;
    final label =
        a.querySelector('.sh-ep-label')?.text.trim() ?? 'ตอนที่ ${number.toInt()}';
    chapters.add(SourceChapter(
      url: url,
      title: label,
      number: number,
      uploadedAt: parseRelativeThaiDate(
          a.querySelector('.sh-ep-date')?.text.trim() ?? ''),
    ));
  }
  chapters.sort((a, b) => a.number.compareTo(b.number));

  return SourceSeriesDetail(
    title: title,
    altTitles: const [],
    description: (description == null || description.isEmpty)
        ? null
        : description,
    tags: tags,
    type: type,
    status: status,
    coverUrl: cover,
    chapters: chapters,
  );
}

@visibleForTesting
List<String> parseBullyImageMap(String body, String baseUrl) {
  final m =
      RegExp(r'IMAGE_MAP\s*=\s*\[(.*?)\]', multiLine: true, dotAll: true)
          .firstMatch(body);
  if (m == null) return const [];
  final urls = RegExp(r'"([^"]+)"')
      .allMatches(m.group(1)!)
      .map((mm) => _cleanUrl(mm.group(1), baseUrl))
      .whereType<String>()
      .toList(growable: false);
  return urls;
}

/// Resolve [href] against [base]; malformed hrefs (raw Thai, broken %)
/// return null instead of throwing — one bad anchor must never kill a
/// whole listing (same policy as the Madara adapter's genre parser).
String? _resolveUrl(String base, String href) {
  if (href.isEmpty) return null;
  try {
    final resolved = Uri.parse(base).resolve(href);
    if (!resolved.isScheme('http') && !resolved.isScheme('https')) {
      return null;
    }
    return resolved.toString();
  } on Exception {
    return null;
  }
}

List<String>? _safePathSegments(String href) {
  try {
    return Uri.parse(href).pathSegments;
  } on Exception {
    return null;
  }
}

/// Null for anything the app can't render (data: URIs, AVIF — Flutter's
/// engine has no AVIF decoder; callers fall through to the next candidate).
String? _cleanUrl(String? raw, String baseUrl) {
  if (raw == null || raw.isEmpty || raw.startsWith('data:')) return null;
  if (raw.toLowerCase().endsWith('.avif')) return null;
  return _resolveUrl(baseUrl, raw);
}

String? _typeFromBadge(String? src) {
  if (src == null) return null;
  if (src.contains('manhwa')) return 'manhwa';
  if (src.contains('manhua')) return 'manhua';
  if (src.contains('novel')) return 'novel';
  if (src.contains('manga')) return 'manga';
  return null;
}

String? _normalizeStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'on going':
    case 'ongoing':
    case 'กำลังเข้า':
      return 'ongoing';
    case 'completed':
    case 'complete':
    case 'end':
    case 'จบแล้ว':
      return 'completed';
    default:
      return null;
  }
}

/// "N นาที / ชั่วโมง / วัน / สัปดาห์ / เดือน / ปี" (the site's chapter
/// stamps) → approximate epoch ms. Empty/unparseable → null.
@visibleForTesting
int? parseRelativeThaiDate(String text) {
  final m = RegExp(r'^(\d+)\s*(นาที|ชั่วโมง|วัน|สัปดาห์|เดือน|ปี)').firstMatch(text.trim());
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  final unitMs = switch (m.group(2)) {
    'นาที' => const Duration(minutes: 1),
    'ชั่วโมง' => const Duration(hours: 1),
    'วัน' => const Duration(days: 1),
    'สัปดาห์' => const Duration(days: 7),
    'เดือน' => const Duration(days: 30),
    _ => const Duration(days: 365),
  }.inMilliseconds;
  return DateTime.now().millisecondsSinceEpoch - n * unitMs;
}

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../../../core/utils/thai.dart';
import '../source_api.dart';

/// oremanga.net — Thai manga site on a custom WP theme (probed live
/// 2026-11-03; main feed — carries an explicit Manga/Manhwa/Manhua type
/// badge on tiles and series pages). Feed paginates as `/page/N/`
/// (`.flexbox4-item` tiles, mixed-case `/series/<Slug>/` URLs), search is
/// GET `/?s=<q>` (`.flexbox2-item` tiles), chapters
/// `/<series-slug>/<n>-<series-slug>/` with Thai-month dates, reader
/// images are plain `img` tags inside `.reader-area-main`.
class OremangaSource implements Source {
  OremangaSource(this.http);

  final SafeHttp http;

  @override
  String get id => 'oremanga';
  @override
  String get name => 'Oremanga';
  @override
  String get baseUrl => 'https://www.oremanga.net';
  @override
  String get referer => '$baseUrl/';
  @override
  String? get imageReferer => referer;
  @override
  bool get supportsNovels => false;
  @override
  bool get pageUrlsExpire => false;

  @override
  Future<List<SourceSeries>> latest({
    int page = 1,
    bool popular = false,
  }) async {
    // The homepage renders several "มาใหม่" sections (มังงะ/มังฮวา/…) of
    // the same tile shape and paginates as a whole; the union is the
    // feed (deduped by URL). No separate popular ordering exists.
    final uri =
        Uri.parse(page <= 1 ? '$baseUrl/' : '$baseUrl/page/$page/');
    return parseOremangaTiles(await _fetch(uri));
  }

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    if (page > 1) return const []; // WP search page 1 is enough here
    return parseOremangaSearchCards(await _fetch(
      Uri.parse('$baseUrl/').replace(queryParameters: {'s': query}),
    ));
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    return parseOremangaDetail(await _fetch(Uri.parse(sourceUrl)), sourceUrl);
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final doc = html_parser.parse(await _fetch(Uri.parse(chapterUrl)));
    final urls = doc
        .querySelectorAll('.reader-area-main img[src]')
        .map((img) => img.attributes['src'])
        .whereType<String>()
        .where((u) => u.startsWith('http'))
        .toList();
    if (urls.isEmpty) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no reader-area-main images on $chapterUrl',
      );
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

  @override
  Future<List<SourceRecentStamp>> recentStamps() async => const [];

  @override
  Future<List<SourceGenre>> genres() async {
    final doc = html_parser.parse(await _fetch(Uri.parse('$baseUrl/')));
    return parseOremangaGenres(doc);
  }

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) async {
    final path = page <= 1
        ? '$baseUrl/genre/$term/'
        : '$baseUrl/genre/$term/page/$page/';
    return parseOremangaSearchCards(await _fetch(Uri.parse(path)));
  }

  Future<String> _fetch(Uri uri) async {
    try {
      return await http.getHtml(uri, referer: referer);
    } on NetException catch (e) {
      throw _netError(e, uri);
    }
  }

  SourceException _netError(NetException e, Uri uri) {
    if (e.statusCode == 403) return SourceException.cloudflare(id);
    if (e.statusCode == 404) {
      return SourceException(id, SourceErrorKind.notFound, detail: '$uri');
    }
    return SourceException(id, SourceErrorKind.network, detail: e.toString());
  }
}

/// Feed tiles (`.flexbox4-item`): thumb link = series URL, `span.type` =
/// platform type, `.title a` = title, first `ul.chapter li` carries the
/// chapter label + a relative stamp ("5 ชั่วโมง ที่แล้ว"). Section
/// repeats of the same series collapse via the URL dedupe.
@visibleForTesting
List<SourceSeries> parseOremangaTiles(String body) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  final seen = <String>{};
  for (final tile in doc.querySelectorAll('.flexbox4-item')) {
    final href = tile.querySelector('.flexbox4-thumb a[href]')
            ?.attributes['href'] ??
        '';
    final title = tile.querySelector('.title a')?.text.trim() ?? '';
    if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;
    final first = tile.querySelector('ul.chapter li');
    final stamp = parseSiteDate(
        first?.querySelector('.date')?.text.trim() ?? '');
    out.add(SourceSeries(
      url: href,
      title: title,
      coverUrl: _abs(href,
          tile.querySelector('.flexbox4-thumb img')?.attributes['src']),
      chapterCountHint: parseChapterNumber(
              first?.querySelector('a')?.text.trim() ?? '')
          ?.toInt(),
      type: _normalizeType(
          tile.querySelector('.flexbox4-thumb .type')?.text.trim()),
      lastUpdatedMs: stamp,
    ));
  }
  return out;
}

/// Search + genre tiles (`.flexbox2-item`): big cover link with the
/// title inside, `.type <Name>` div and a `.genres` chip row.
@visibleForTesting
List<SourceSeries> parseOremangaSearchCards(String body) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  final seen = <String>{};
  for (final tile in doc.querySelectorAll('.flexbox2-item')) {
    final a = tile.querySelector('a[href][title]');
    final href = a?.attributes['href'] ?? '';
    final title = a?.attributes['title']?.trim() ?? '';
    if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;
    out.add(SourceSeries(
      url: href,
      title: title,
      coverUrl: _abs(href, tile.querySelector('img')?.attributes['src']),
      type: _normalizeType(tile.querySelector('.type')?.text.trim()),
      genres: [
        for (final g in tile.querySelectorAll('.genres a'))
          if (g.text.trim().isNotEmpty) g.text.trim(),
      ],
    ));
  }
  return out;
}

/// Series page: `.series-thumb img` cover, `h2` title, `span.type` /
/// `span.status` (class-suffixed English values), `.series-genres a`,
/// `.series-synops`, chapters in `ul.series-chapterlist` (newest first,
/// "ตอนที่ 161" + Thai-month dates).
@visibleForTesting
SourceSeriesDetail parseOremangaDetail(String body, String sourceUrl) {
  final doc = html_parser.parse(body);
  final title = doc.querySelector('.series-titlex h2')?.text.trim() ??
      doc.querySelector('.series-title h2')?.text.trim() ??
      '';
  if (title.isEmpty) {
    throw SourceException(
      'oremanga',
      SourceErrorKind.parse,
      detail: 'no series title on $sourceUrl',
    );
  }

  final chapters = <SourceChapter>[];
  final rows = doc.querySelectorAll('.series-chapterlist .flexch-infoz a');
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i];
    final href = a.attributes['href'] ?? '';
    final label = a.querySelector('span')?.text.trim() ?? '';
    if (href.isEmpty || label.isEmpty) continue;
    // The date span nests inside the same <span> — strip it from the
    // label before number parsing (its Thai-month text is not a number).
    final dateText = a.querySelector('.date')?.text.trim();
    var cleanLabel = label;
    if (dateText != null && dateText.isNotEmpty) {
      cleanLabel = label.replaceAll(dateText, '').trim();
    }
    chapters.add(SourceChapter(
      url: href,
      title: cleanLabel,
      number:
          parseChapterNumber(cleanLabel) ?? (rows.length - i).toDouble(),
      uploadedAt: dateText == null ? null : parseSiteDate(dateText),
    ));
  }
  chapters.sort((a, b) => a.number.compareTo(b.number));

  return SourceSeriesDetail(
    title: title,
    description: _nonEmpty(doc.querySelector('.series-synops')?.text),
    tags: [
      for (final g in doc.querySelectorAll('.series-genres a'))
        if (g.text.trim().isNotEmpty) g.text.trim(),
    ],
    type: _normalizeType(doc.querySelector('.series-info .type')?.text.trim()),
    status: _normalizeStatus(doc.querySelector('.status')?.text.trim()),
    coverUrl: _abs(
        sourceUrl, doc.querySelector('.series-thumb img')?.attributes['src']),
    chapters: chapters,
  );
}

@visibleForTesting
List<SourceGenre> parseOremangaGenres(html_dom.Document home) {
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in home.querySelectorAll('a[href*="/genre/"]')) {
    final href = a.attributes['href'] ?? '';
    final name = a.text.trim();
    if (href.isEmpty || name.isEmpty) continue;
    final term = Uri.tryParse(href)?.pathSegments
            .where((s) => s.isNotEmpty)
            .last ??
        '';
    if (term.isEmpty || !seen.add(term)) continue;
    out.add(SourceGenre(name: name, term: term));
  }
  return out;
}

String? _nonEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

String? _normalizeType(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'manga':
      return 'manga';
    case 'manhwa':
      return 'manhwa';
    case 'manhua':
      return 'manhua';
    case 'novel':
      return 'novel';
    default:
      return null;
  }
}

String? _normalizeStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'ongoing':
    case 'on going':
    case 'publishing':
      return 'ongoing';
    case 'completed':
    case 'complete':
    case 'end':
      return 'completed';
    default:
      return null;
  }
}

String? _abs(String base, String? url) {
  if (url == null || url.isEmpty) return null;
  return Uri.parse(base).resolve(url).toString();
}

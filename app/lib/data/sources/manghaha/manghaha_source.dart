import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../../../core/utils/thai.dart';
import '../source_api.dart';

/// manghaha.com — adult manhwa site on the "obito" custom theme (probed
/// live 2026-11-03; scoped to the Doujin 18+ page). Series at
/// `/<slug>/`, chapters at `/<series>/<chapter>/`, feed grid on the
/// homepage (`/?page=N` pagination), search at `/search/?s=`.
/// Everything is server-rendered — chapter images are plain
/// `img.page-img` tags.
class ManghahaSource implements Source {
  ManghahaSource(this.http);

  final SafeHttp http;

  @override
  String get id => 'manghaha';
  @override
  String get name => 'Manghaha';
  @override
  String get baseUrl => 'https://manghaha.com';
  @override
  String get referer => '$baseUrl/';
  @override
  bool get supportsNovels => false;
  @override
  bool get pageUrlsExpire => false;

  @override
  Future<List<SourceSeries>> latest({
    int page = 1,
    bool popular = false,
  }) async {
    // The homepage grid ("มังงะอัพเดทใหม่") paginates as ?page=N; the
    // site keeps no separate popular ordering.
    final uri = Uri.parse(page <= 1 ? '$baseUrl/' : '$baseUrl/?page=$page');
    return parseManghahaTiles(await _fetch(uri));
  }

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    if (page > 1) return const []; // the search page has no pagination
    return parseManghahaTiles(await _fetch(
      Uri.parse('$baseUrl/search/').replace(queryParameters: {'s': query}),
    ));
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    return parseManghahaDetail(
        await _fetch(Uri.parse(sourceUrl)), sourceUrl);
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final doc = html_parser.parse(await _fetch(Uri.parse(chapterUrl)));
    final urls = doc
        .querySelectorAll('.manga-image-contain img.page-img')
        .map((img) => img.attributes['src'])
        .whereType<String>()
        .where((u) => u.startsWith('http'))
        .toList();
    if (urls.isEmpty) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no page-img on $chapterUrl',
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
    return parseManghahaTags(doc);
  }

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) async {
    if (page > 1) return const []; // tag pages are single-page grids
    return parseManghahaTiles(
        await _fetch(Uri.parse('$baseUrl/tag/$term/')));
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

/// Feed/search/tag tiles — the SAME `.latest-item-contain` grid markup on
/// the homepage, the search results and the tag pages (probed
/// 2026-11-03): thumb link = series URL, `.title a` = title, the newest
/// `.last .d-flex` row carries the chapter label + a relative stamp
/// ("7 ชั่วโมง").
@visibleForTesting
List<SourceSeries> parseManghahaTiles(String body) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final tile in doc.querySelectorAll('.latest-item-contain')) {
    final href = tile.querySelector('.thumb a')?.attributes['href'] ?? '';
    final img = tile.querySelector('.thumb img');
    final title = tile.querySelector('.title a')?.text.trim() ?? '';
    if (href.isEmpty || title.isEmpty) continue;
    final first = tile.querySelector('.last .d-flex');
    final chapterA = first?.querySelector('a');
    final stamp =
        parseRelativeStamp(first?.querySelector('small')?.text.trim() ?? '');
    out.add(SourceSeries(
      url: href,
      title: title,
      coverUrl: _abs(href, img?.attributes['src']),
      chapterCountHint:
          parseChapterNumber(chapterA?.text.trim() ?? '')?.toInt(),
      lastUpdatedMs: stamp,
    ));
  }
  return out;
}

/// Series page: `h1.manga-title` reads "อ่านมังงะ <title> แปลไทย";
/// `.manga-content-heading`/`.manga-content-value` label rows;
/// `.description` (+ `.tag-list` inside it); chapters in `.ep-list`.
@visibleForTesting
SourceSeriesDetail parseManghahaDetail(String body, String sourceUrl) {
  final doc = html_parser.parse(body);
  final h1 = doc.querySelector('h1.manga-title')?.text.trim() ?? '';
  final title = h1
      .replaceFirst(RegExp(r'^อ่านมังงะ\s*'), '')
      .replaceFirst(RegExp(r'\s*แปลไทย$'), '')
      .trim();
  if (title.isEmpty) {
    throw SourceException(
      'manghaha',
      SourceErrorKind.parse,
      detail: 'no manga-title on $sourceUrl',
    );
  }

  String? status;
  for (final row in doc.querySelectorAll('.manga-content')) {
    final labels = row.querySelectorAll('.manga-content-heading');
    final values = row.querySelectorAll('.manga-content-value');
    if (labels.length != values.length) continue;
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i].text.trim();
      if (label.contains('สถานะ')) {
        status = _normalizeStatus(values[i].text.trim());
      }
    }
  }

  // Description div also contains the tag buttons — walk its nodes and
  // keep only the text OUTSIDE the .tag-list subtree ("No Story" is the
  // site's own empty placeholder).
  final description = _collapse(
      _textOutside(doc.querySelector('.description'), '.tag-list'));
  final hasStory = description.isNotEmpty && description != 'No Story';

  final chapters = <SourceChapter>[];
  final rows = doc.querySelectorAll('.ep-list .ep-item');
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i].querySelector('a[href]');
    if (a == null) continue;
    final label = a.querySelector('.ep-heading')?.text.trim() ?? '';
    if (label.isEmpty) continue;
    final stamp = parseRelativeStamp(
        a.querySelector('.ep-time')?.text.trim() ?? '');
    chapters.add(SourceChapter(
      url: a.attributes['href']!,
      title: label,
      number:
          parseChapterNumber(label) ?? (rows.length - i).toDouble(),
      uploadedAt: stamp,
    ));
  }
  chapters.sort((a, b) => a.number.compareTo(b.number));

  return SourceSeriesDetail(
    title: title,
    description: hasStory ? description : null,
    tags: [
      for (final a in doc.querySelectorAll('.tag-list a'))
        if (a.text.trim().isNotEmpty) a.text.trim(),
    ],
    status: status,
    coverUrl: _abs(sourceUrl, doc.querySelector('img.manga-thumb')?.attributes['src']),
    chapters: chapters,
  );
}

@visibleForTesting
List<SourceGenre> parseManghahaTags(html_dom.Document home) {
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in home.querySelectorAll('a[href*="/tag/"]')) {
    final href = a.attributes['href'] ?? '';
    final name = a.text.trim();
    if (href.isEmpty || name.isEmpty) continue;
    // Tag links are /tag/<name>/ — the segment AFTER "tag" is the term.
    final segments = Uri.tryParse(href)?.pathSegments
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    if (segments.length < 2 || !seen.add(segments[1])) continue;
    out.add(SourceGenre(name: name, term: segments[1]));
  }
  return out;
}

/// Text of [root] with every subtree matching [excludeSelector]
/// removed, whitespace-collapsed.
String _textOutside(html_dom.Element? root, String excludeSelector) {
  if (root == null) return '';
  final clone = root.clone(true);
  for (final drop in clone.querySelectorAll(excludeSelector)) {
    drop.remove();
  }
  return _collapse(clone.text);
}

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String? _normalizeStatus(String raw) {
  switch (raw.trim()) {
    case 'ยังไม่จบ':
      return 'ongoing';
    case 'จบแล้ว':
    case 'จบ':
      return 'completed';
  }
  switch (raw.trim().toLowerCase()) {
    case 'ongoing':
    case 'on going':
      return 'ongoing';
    case 'completed':
    case 'complete':
    case 'end':
      return 'completed';
  }
  return null;
}

String? _abs(String base, String? url) {
  if (url == null || url.isEmpty) return null;
  return Uri.parse(base).resolve(url).toString();
}

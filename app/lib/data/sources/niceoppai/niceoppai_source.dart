import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../../../core/utils/thai.dart';
import '../source_api.dart';

/// niceoppai.net — long-running Thai site on the NOPOrange theme (probed
/// live 2026-11-03; MIX scope — the catalog mixes normal and Adult/yaoi
/// content, so it never joins the main feed). Feed at
/// `/manga_list/all/any/last-updated/<page>/`, search POSTS
/// `/manga_list/search/` (the theme reads `$_POST` only — GET variants
/// render "Search result of ''"), series at `/<Title-Slug>/`, chapters
/// `/<Title-Slug>/<n>/`. Chapter stamps are ABSOLUTE unix seconds in
/// `data-ago` attributes.
class NiceoppaiSource implements Source {
  NiceoppaiSource(this.http);

  final SafeHttp http;

  @override
  String get id => 'niceoppai';
  @override
  String get name => 'Niceoppai';
  @override
  String get baseUrl => 'https://www.niceoppai.net';
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
    // popular ≈ most-popular ordering is a separate page the theme does
    // not expose through this URL shape — the update order serves both.
    return parseNiceoppaiCards(await _fetch(
      Uri.parse('$baseUrl/manga_list/all/any/last-updated/$page/'),
    ));
  }

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    if (page > 1) return const []; // search results are a single page
    try {
      final bytes = await http.postForm(
        Uri.parse('$baseUrl/manga_list/search/'),
        {
          'cmd_wpm_wgt_mng_sch_sbm': 'Search',
          'txt_wpm_wgt_mng_sch_nme': query,
        },
        referer: referer,
      );
      return parseNiceoppaiCards(
          utf8.decode(bytes, allowMalformed: true));
    } on NetException catch (e) {
      throw _netError(e, Uri.parse('$baseUrl/manga_list/search/'));
    }
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    return parseNiceoppaiDetail(
        await _fetch(Uri.parse(sourceUrl)), sourceUrl);
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final doc = html_parser.parse(await _fetch(Uri.parse(chapterUrl)));
    final urls = doc
        .querySelectorAll('#image-container img[src]')
        .map((img) => img.attributes['src'])
        .whereType<String>()
        .where((u) => u.startsWith('http'))
        .toList();
    if (urls.isEmpty) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no images in #image-container on $chapterUrl',
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
    // The manga_list page sidebar carries the full category cloud.
    final doc = html_parser
        .parse(await _fetch(Uri.parse('$baseUrl/manga_list/')));
    return parseNiceoppaiCategories(doc);
  }

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) async {
    if (page > 1) return const []; // category pages are single-page
    return parseNiceoppaiCards(
        await _fetch(Uri.parse('$baseUrl/manga_list/category/$term/')));
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

/// `.fcard.panel` tiles — the SAME card on the feed, category and search
/// pages (probed 2026-11-03): `.cover a` = series URL, `img.cover__img`,
/// `.fcard__title`, and the newest `.fcard__ch` row whose `.ago` carries
/// an absolute unix-seconds stamp in `data-ago`.
@visibleForTesting
List<SourceSeries> parseNiceoppaiCards(String body) {
  final doc = html_parser.parse(body);
  final out = <SourceSeries>[];
  for (final card in doc.querySelectorAll('.fcard.panel')) {
    final href =
        card.querySelector('.cover a[href]')?.attributes['href'] ?? '';
    final title = card.querySelector('.fcard__title')?.text.trim() ?? '';
    if (href.isEmpty || title.isEmpty) continue;
    final ch = card.querySelector('.fcard__ch');
    final agoRaw = ch?.querySelector('.ago')?.attributes['data-ago'];
    final ago = agoRaw == null ? null : int.tryParse(agoRaw);
    out.add(SourceSeries(
      url: href,
      title: title,
      coverUrl: _encodeSpaces(
          _abs(href, card.querySelector('img.cover__img')?.attributes['src'])),
      chapterCountHint:
          parseChapterNumber(ch?.querySelector('span')?.text.trim() ?? '')
              ?.toInt(),
      lastUpdatedMs: ago == null ? null : ago * 1000,
    ));
  }
  return out;
}

/// Series page: `h1` title, itemprop cover img, `.chip--genre` genres
/// (one of them names the platform type), `p.series__syn` synopsis,
/// `.series__facts .fact` label rows, `.chrow` chapter rows with
/// `data-ch` numbers and "Sep 20, 2026" dates (newest first).
@visibleForTesting
SourceSeriesDetail parseNiceoppaiDetail(String body, String sourceUrl) {
  final doc = html_parser.parse(body);
  final title = doc.querySelector('h1')?.text.trim() ?? '';
  if (title.isEmpty) {
    throw SourceException(
      'niceoppai',
      SourceErrorKind.parse,
      detail: 'no h1 title on $sourceUrl',
    );
  }

  final tags = <String>[];
  String? type;
  for (final chip in doc.querySelectorAll('.series__genres .chip--genre')) {
    final name = chip.text.trim();
    if (name.isEmpty) continue;
    tags.add(name);
    if (type == null) {
      final lower = name.toLowerCase();
      if (lower == 'manhwa' || lower == 'manhua' || lower == 'manga') {
        type = lower;
      }
    }
  }

  String? status;
  var chapterCountHint = 0;
  for (final fact in doc.querySelectorAll('.series__facts .fact')) {
    final label = fact.querySelector('span')?.text.trim() ?? '';
    final value = fact.querySelector('b')?.text.trim() ?? '';
    if (label.contains('สถานะ')) status = _normalizeStatus(value);
    if (label.contains('ตอนทั้งหมด')) {
      chapterCountHint = int.tryParse(value) ?? 0;
    }
  }

  final chapters = <SourceChapter>[];
  final rows = doc.querySelectorAll('.chlist__rows .chrow');
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i];
    final href = a.attributes['href'] ?? '';
    if (href.isEmpty) continue;
    final numRaw = a.attributes['data-ch'];
    final label =
        a.querySelector('.chrow__t')?.text.trim() ?? 'ตอนที่ ${i + 1}';
    final number = (numRaw != null && double.tryParse(numRaw) != null)
        ? double.parse(numRaw)
        : parseChapterNumber(label) ?? (rows.length - i).toDouble();
    final dateText = a.querySelector('.chrow__d')?.text.trim();
    chapters.add(SourceChapter(
      url: href,
      title: 'ตอนที่ ${formatChapterNumber(number)}',
      number: number,
      uploadedAt: dateText == null ? null : parseSiteDate(dateText),
    ));
  }
  chapters.sort((a, b) => a.number.compareTo(b.number));
  if (chapterCountHint == 0) chapterCountHint = chapters.length;

  return SourceSeriesDetail(
    title: title,
    description: _nonEmpty(doc.querySelector('.series__syn')?.text),
    tags: tags,
    type: type,
    status: status,
    coverUrl: _encodeSpaces(_abs(
        sourceUrl, doc.querySelector('.series__cover img')?.attributes['src'])),
    chapters: chapters,
  );
}

@visibleForTesting
List<SourceGenre> parseNiceoppaiCategories(html_dom.Document listPage) {
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in listPage.querySelectorAll('a[href*="/manga_list/category/"]')) {
    final href = a.attributes['href'] ?? '';
    final name = a.text.trim();
    if (href.isEmpty || name.isEmpty) continue;
    final term = Uri.tryParse(href)?.pathSegments
            .where((s) => s.isNotEmpty)
            .last ??
        '';
    // Category links end with the term: /manga_list/category/<Term>/
    if (term.isEmpty || !seen.add(term)) continue;
    out.add(SourceGenre(name: name, term: term));
  }
  return out;
}

String? _nonEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

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
    case 'publishing':
      return 'ongoing';
    case 'completed':
    case 'complete':
    case 'end':
      return 'completed';
  }
  return null;
}

/// The theme emits cover paths with literal spaces ("the lazy prince
/// becomes a genius.jpg") — encode them so the image pipeline's URL
/// validation never sees a malformed URL.
String? _encodeSpaces(String? url) =>
    url?.replaceAll(' ', '%20');

String? _abs(String base, String? url) {
  if (url == null || url.isEmpty) return null;
  return Uri.parse(base).resolve(url).toString();
}

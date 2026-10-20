import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../../../core/utils/thai.dart';
import '../source_api.dart';
import 'configs.dart';

/// Shared adapter for the four Thai aggregator sites (Plan/05).
///
/// All four run WordPress with MangaStream-family ("ts") themes — see the
/// DRIFT RECORD in Plan/05 (live re-verified 2026-10-17). One engine, four
/// [MadaraSiteConfig]s.
class MadaraSource implements Source {
  MadaraSource(this.config, this.http);

  final MadaraSiteConfig config;
  final SafeHttp http;

  @override
  String get id => config.id;
  @override
  String get name => config.name;
  @override
  String get baseUrl => config.baseUrl;
  @override
  String get referer => '$baseUrl/';
  @override
  bool get supportsNovels => false; // §7.6: novels are nekopost-only

  @override
  Future<List<SourceSeries>> latest({int page = 1, bool popular = false}) =>
      _parseTiles(Uri.parse('$baseUrl/${config.archivePath}/')
          .replace(queryParameters: {
        // order=popular is server-side (probed 2026-10-20: the ts archive
        // returns a genuinely different list; search ignores the param).
        'order': popular ? 'popular' : 'update',
        'page': '$page',
      }));

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    if (!config.searchSupported) {
      throw SourceException(id, SourceErrorKind.cloudflare,
          detail: 'search endpoint blocked (Cloudflare) — use latest()');
    }
    return _parseTiles(Uri.parse('$baseUrl/').replace(queryParameters: {
      's': query,
      'post_type': 'wp-manga',
      if (page > 1) 'page': '$page',
    }));
  }

  Future<List<SourceSeries>> _parseTiles(Uri uri) async {
    final body = await _fetch(uri);
    final doc = html_parser.parse(body);
    if (config.classicLayout) {
      final rows = parseClassicRows(body);
      if (_looksLikeCloudflare(body) && rows.isEmpty) {
        throw SourceException.cloudflare(id);
      }
      return rows;
    }
    final tiles = doc.querySelectorAll('.listupd .bsx');
    if (tiles.isEmpty) {
      // A challenge page instead of content → Cloudflare (04 §3).
      if (_looksLikeCloudflare(body)) {
        throw SourceException.cloudflare(id);
      }
      return const [];
    }
    return tiles.map((tile) {
      final a = tile.querySelector('a');
      final href = a?.attributes['href'] ?? '';
      final title = (a?.attributes['title'] ?? a?.text ?? '').trim();
      final img = tile.querySelector('img');
      final cover = _bestCoverUrl(img);
      final type = tile.querySelector('.typename')?.text.trim();
      // `.epxs` = latest-chapter label on listing tiles ("ตอนที่ 280",
      // drift-verified 2026-10-17) — the only chapter-count signal in
      // listings/search; used for merge primary-pick + min-chapters filter.
      final latestChapter = parseChapterNumber(
          tile.querySelector('.epxs')?.text.trim() ?? '');
      return SourceSeries(
        url: href,
        title: title,
        coverUrl: _absolutize(cover),
        chapterCountHint: latestChapter?.toInt(),
        type: _normalizeType(type),
      );
    }).where((s) => s.url.isNotEmpty && s.title.isNotEmpty).toList();
  }

  /// CLASSIC Madara rows (doujin-lc, config.classicLayout): search rows
  /// are `.row.c-tabs-item__content`; archive rows are
  /// `.page-item-detail` inside one big-thumbnail listing panel (the
  /// panel itself carries a stray `.c-tabs-item` wrapper — never select
  /// THAT, it matches the whole page). Never nested in each other;
  /// deduped by URL just in case (probed 2026-10-19).
  @visibleForTesting
  List<SourceSeries> parseClassicRows(String body) {
    final doc = html_parser.parse(body);
    final rows =
        doc.querySelectorAll('.page-item-detail, .c-tabs-item__content');
    if (rows.isEmpty) {
      if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
      return const [];
    }
    final seen = <String>{};
    final out = <SourceSeries>[];
    for (final row in rows) {
      final a = row.querySelector('.post-title a') ??
          row.querySelector('.item-thumb a[href]') ??
          row.querySelector('h3 a') ??
          row.querySelector('h5 a');
      final href = a?.attributes['href'] ?? '';
      final title = (a?.attributes['title'] ?? a?.text ?? '').trim();
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;
      final cover = _bestCoverUrl(row.querySelector('img'));
      final chap = row
          .querySelector(
              '.quick-chapter-link, .chapter-item a, .latest-chap a')
          ?.text
          .trim();
      final type = row.querySelector('.manga-title-badges')?.text.trim();
      out.add(SourceSeries(
        url: href,
        title: title,
        coverUrl: _absolutize(cover),
        chapterCountHint: parseChapterNumber(chap ?? '')?.toInt(),
        type: _normalizeType(type),
      ));
    }
    return out;
  }

  /// CLASSIC Madara detail page (doujin-lc): post-title h1,
  /// .post-content_item label/value rows, li.wp-manga-chapter chapter list.
  @visibleForTesting
  SourceSeriesDetail parseClassicDetail(String body, String sourceUrl) {
    final doc = html_parser.parse(body);
    final title =
        (doc.querySelector('.post-title h1') ?? doc.querySelector('h1'))
                ?.text
                .trim() ??
            '';
    if (title.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no post-title on $sourceUrl');
    }

    String? status;
    String? type;
    for (final item in doc.querySelectorAll('.post-content_item')) {
      final label =
          item.querySelector('.summary-heading')?.text.trim() ?? '';
      final value = item.querySelector('.summary-content')?.text.trim() ?? '';
      if (value.isEmpty) continue;
      if (label.startsWith('Status')) status = _normalizeStatus(value);
      if (label.startsWith('Type')) type = _normalizeType(value);
    }

    final tags = <String>{
      for (final a in doc.querySelectorAll('.genres-content a, .mg_genres a'))
        if (a.text.trim().isNotEmpty) a.text.trim(),
    }.toList();

    final description = (doc
                .querySelector('.description-summary .summary__content')
                ?.text ??
            doc.querySelector('.manga-excerpt')?.text ??
            '')
        .trim();

    final coverImg = doc.querySelector('.summary_image img') ??
        doc.querySelector('img.wp-post-image');
    final cover = _absolutize(_bestCoverUrl(coverImg));

    final baseUri = Uri.parse(baseUrl);
    final chapterRows = doc.querySelectorAll('li.wp-manga-chapter a[href]');
    final chapters = <SourceChapter>[];
    for (var i = 0; i < chapterRows.length; i++) {
      final a = chapterRows[i];
      final Uri url;
      try {
        final resolved = baseUri.resolve(a.attributes['href'] ?? '');
        if (!resolved.isScheme('http') && !resolved.isScheme('https')) {
          continue;
        }
        if (resolved.host != baseUri.host) continue;
        if (resolved.path.isEmpty || resolved.path == '/') continue;
        url = resolved;
      } on FormatException {
        continue;
      }
      // Classic anchors often carry the date span INSIDE them — strip it
      // from the label before number parsing.
      final dateEl = a.querySelector('.chapter-date, .chapter-format');
      var label = a.text.trim();
      if (dateEl != null) {
        label = label.replaceAll(dateEl.text.trim(), '').trim();
      }
      if (label.isEmpty) continue;
      final number =
          parseChapterNumber(label) ?? (chapterRows.length - i).toDouble();
      final dateText =
          (dateEl ?? a.parent?.querySelector('.chapter-date, .chapter-format'))
              ?.text
              .trim();
      chapters.add(SourceChapter(
        url: url.toString(),
        title: label,
        number: number,
        uploadedAt: dateText == null || dateText.isEmpty
            ? null
            : parseSiteDate(dateText),
      ));
    }
    chapters.sort((a, b) => a.number.compareTo(b.number));

    return SourceSeriesDetail(
      title: title,
      altTitles: const [],
      description: description.isEmpty ? null : description,
      tags: tags,
      type: type,
      status: status,
      coverUrl: cover,
      chapters: chapters,
    );
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final body = await _fetch(Uri.parse(sourceUrl));
    final doc = html_parser.parse(body);
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);
    if (config.classicLayout) {
      return parseClassicDetail(body, sourceUrl);
    }

    final title =
        doc.querySelector('h1.entry-title')?.text.trim() ?? '';
    if (title.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no h1.entry-title on $sourceUrl');
    }

    // Status/Type rows: `<div class="imptdt">Status <i>Ongoing</i></div>`
    String? status;
    String? type;
    for (final row in doc.querySelectorAll('.tsinfo .imptdt')) {
      final text = row.text.trim();
      final value =
          row.querySelector('i, a')?.text.trim() ?? text.split(' ').last;
      if (text.startsWith('Status')) status = _normalizeStatus(value);
      if (text.startsWith('Type')) type = _normalizeType(value);
    }

    final genres = doc
        .querySelectorAll('.mgen a')
        .map((a) => a.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final description =
        doc.querySelector('.entry-content-single')?.text.trim();
    final coverImg = doc.querySelector('.thumb img') ??
        doc.querySelector('.summary_image img') ??
        doc.querySelector('img.wp-post-image');
    final cover = _absolutize(_bestCoverUrl(coverImg));

    // Chapters: `.eph-num > a` (div or li wrapper depending on site) —
    // site order is newest-first → reversed below.
    final baseUri = Uri.parse(baseUrl);
    final chapterRows = doc.querySelectorAll('.eph-num a[href]');
    final chapters = <SourceChapter>[];
    for (var i = 0; i < chapterRows.length; i++) {
      final a = chapterRows[i];
      // Only real same-host chapter links — skip JS template placeholders
      // like `#/chapter-{{number}}` and cross-origin noise.
      final rawHref = a.attributes['href'] ?? '';
      final Uri url;
      try {
        final resolved = baseUri.resolve(rawHref);
        if (!resolved.isScheme('http') && !resolved.isScheme('https')) {
          continue;
        }
        if (resolved.host != baseUri.host) continue;
        // Fragment-only links (`#/chapter-{{number}}` JS templates) have
        // empty/root paths — real chapter pages do not.
        if (resolved.path.isEmpty || resolved.path == '/') continue;
        url = resolved;
      } on FormatException {
        continue;
      }
      final label =
          a.querySelector('.chapternum')?.text.trim() ?? a.text.trim();
      if (label.isEmpty) continue;
      final number = parseChapterNumber(label) ??
          (chapterRows.length - i).toDouble(); // fallback: list index
      final dateText =
          a.querySelector('.chapterdate')?.text.trim();
      chapters.add(SourceChapter(
        url: url.toString(),
        title: label,
        number: number,
        uploadedAt: dateText != null ? parseSiteDate(dateText) : null,
      ));
    }
    chapters.sort((a, b) => a.number.compareTo(b.number));

    return SourceSeriesDetail(
      title: title,
      altTitles: const [], // not present on ts detail pages (05 drift)
      description: (description == null || description.isEmpty)
          ? null
          : description,
      tags: genres,
      type: type,
      status: status,
      coverUrl: cover,
      chapters: chapters,
    );
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    // ts_reader.run({... "images":["...","..."] ...}) — keep given order.
    final m = RegExp(r'"images"\s*:\s*\[([^\]]*)\]').firstMatch(body);
    if (m != null) {
      final urls = m
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll('"', '').replaceAll('\\', ''))
          .where((s) => s.isNotEmpty)
          .toList();
      if (urls.isNotEmpty) return ChapterPages(imageUrls: urls);
    }
    // Fallback: content <img> tags (05 §5). Classic Madara lazy-loads with
    // a base64 svg placeholder in `src` — prefer data-src and drop data:
    // URIs either way.
    final doc = html_parser.parse(body);
    final imgs = doc
        .querySelectorAll('.reading-content img')
        .map((img) =>
            _absolutize(img.attributes['data-src'] ?? img.attributes['src']))
        .where((u) => u != null && u.isNotEmpty && !u.startsWith('data:'))
        .cast<String>()
        .toList();
    if (imgs.isEmpty) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'no ts_reader images and no .reading-content img '
              'on $chapterUrl');
    }
    return ChapterPages(imageUrls: imgs);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

  /// Genre cloud scraped from the homepage (drift 2026-10-17: the theme
  /// renders `a[href*="/genres/"]` links — both English slugs and Thai-named
  /// genres). The genre ARCHIVE pages themselves are empty JS shells; the
  /// working server-side filter is `/manga/?genres={term}` (see [browseGenre]).
  @override
  Future<List<SourceGenre>> genres() async {
    final body = await _fetch(Uri.parse('$baseUrl/'));
    final doc = html_parser.parse(body);
    final seen = <String>{};
    final genres = <SourceGenre>[];
    for (final a in doc.querySelectorAll('a[href*="/genres/"]')) {
      final href = a.attributes['href'] ?? '';
      final name = a.text.trim();
      if (href.isEmpty || name.isEmpty) continue;
      final term = _genreTermFrom(href);
      if (term == null || !seen.add(term)) continue;
      genres.add(SourceGenre(name: name, term: term));
    }
    return genres;
  }

  /// Server-side genre filter on the listing page — the ONLY working genre
  /// browse on ts themes (Plan/05 drift record). Same `.bsx` tiles as
  /// [latest], so pagination uses the same `page` query parameter.
  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) =>
      _parseTiles(Uri.parse('$baseUrl/${config.archivePath}/').replace(
        queryParameters: {
          'genres': term,
          if (page > 1) 'page': '$page',
        },
      ));

  /// `/genres/{term}/` → percent-decoded term. Sites emit occasional
  /// malformed hrefs (raw Thai, broken `%` sequences) — skip them; Uri
  /// errors here are ArgumentError/FormatException (both Exception), not
  /// parseable data loss (probed live on slow-manga, Phase 5).
  String? _genreTermFrom(String href) {
    try {
      final path = Uri.parse(baseUrl).resolve(href).pathSegments;
      if (path.length < 2 || path[0] != 'genres') return null;
      return Uri.decodeComponent(path[1]);
    } on Exception {
      return null;
    }
  }

  Future<String> _fetch(Uri uri) async {
    try {
      return await http.getHtml(uri, referer: referer);
    } on NetException catch (e) {
      if (e.statusCode == 403) {
        // Distinguish Cloudflare later via body sniff in callers; the 403
        // itself may already be a challenge page (up/dark-manga search).
        throw SourceException(id, SourceErrorKind.cloudflare,
            detail: 'HTTP 403 at $uri');
      }
      if (e.statusCode == 404) {
        throw SourceException(id, SourceErrorKind.notFound,
            detail: 'HTTP 404 at $uri');
      }
      throw SourceException(id, SourceErrorKind.network,
          detail: e.toString());
    }
  }

  bool _looksLikeCloudflare(String body) => looksLikeCloudflarePage(body);

  String? _absolutize(String? url) {
    if (url == null || url.isEmpty) return null;
    return Uri.parse(baseUrl).resolve(url).toString();
  }

  /// Best cover URL from a listing/detail <img>: lazy-loaded tiles carry a
  /// placeholder (base64 / grey gif / site logo) in `src` and the real
  /// image in `data-src`. Prefer data-src, then src, skipping data: URIs,
  /// svg placeholders and AVIF uploads — Flutter's engine can't decode
  /// AVIF so such covers can never render (slow-manga uploads, on-device
  /// QA 2026-10-18; the card/hero layer falls back to sibling sites).
  String? _bestCoverUrl(html_dom.Element? img) {
    if (img == null) return null;
    for (final raw in [
      img.attributes['data-src'],
      img.attributes['data-lazy-src'],
      img.attributes['src'],
    ]) {
      final v = raw?.trim();
      if (v == null || v.isEmpty || v.startsWith('data:')) continue;
      final lower = v.toLowerCase();
      if (lower.endsWith('.svg') || lower.endsWith('.avif')) continue;
      return v;
    }
    return null;
  }

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
      case 'publishing':
      case 'on going':
        return 'ongoing';
      case 'completed':
      case 'complete':
      case 'end':
        return 'completed';
      default:
        return null;
    }
  }
}

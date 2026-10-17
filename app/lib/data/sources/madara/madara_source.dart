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
  Future<List<SourceSeries>> latest({int page = 1}) =>
      _parseTiles(Uri.parse('$baseUrl/manga/')
          .replace(queryParameters: {'order': 'update', 'page': '$page'}));

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
      final cover =
          img?.attributes['src'] ?? img?.attributes['data-src'];
      final type = tile.querySelector('.typename')?.text.trim();
      return SourceSeries(
        url: href,
        title: title,
        coverUrl: _absolutize(cover),
        type: _normalizeType(type),
      );
    }).where((s) => s.url.isNotEmpty && s.title.isNotEmpty).toList();
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final body = await _fetch(Uri.parse(sourceUrl));
    final doc = html_parser.parse(body);
    if (_looksLikeCloudflare(body)) throw SourceException.cloudflare(id);

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
    final cover = _absolutize(
        doc.querySelector('.thumb img')?.attributes['src']);

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
    // Fallback: content <img> tags (05 §5).
    final doc = html_parser.parse(body);
    final imgs = doc
        .querySelectorAll('.reading-content img')
        .map((img) =>
            _absolutize(img.attributes['data-src'] ?? img.attributes['src']))
        .where((u) => u != null && u.isNotEmpty)
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

  bool _looksLikeCloudflare(String body) =>
      body.contains('Just a moment...') ||
      body.contains('challenge-platform') ||
      body.contains('cf-mitigated');

  String? _absolutize(String? url) {
    if (url == null || url.isEmpty) return null;
    return Uri.parse(baseUrl).resolve(url).toString();
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

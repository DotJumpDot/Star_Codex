import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/net_exception.dart';
import '../../../core/net/safe_http.dart';
import '../source_api.dart';
import 'configs.dart';

/// Adapter for the "Toonary"-platform sites (mangary.com, whytoon.com —
/// added 2026-10-28, MIX scope: normal + 18+ content side by side on the
/// same sites, so they get their own tab instead of polluting Search or
/// Search 18+). Probed structure (2026-10-28):
///
/// - Everything is a Next.js App-Router site. Listing cards + titles live
///   in the server HTML; the chapter list and reader images live ONLY in
///   the embedded RSC flight payload (`self.__next_f.push([1,"…"])`
///   chunks — string-joined then JSON-ish scanned).
/// - listing: mangary `/latest?page=N`; whytoon `/browse/page/N`. Cards
///   are anchors to `/content/<slug>` with the bilingual title in an
///   `h3`/`itemProp=name` and the cover in `img[src*=storage]`. mangary
///   cards carry genre chips ("Yaoi - มังงะวาย") — the Mix tab's yaoi
///   filter uses them before any detail fetch.
/// - detail `/content/<slug>`: title from `<title>`; description/cover
///   from og: metas; genres + episodes from the flight payload. The
///   FIRST non-empty `"episodes":[…]` array is the main series (later
///   arrays are related-series previews, whytoon); the genres array that
///   isn't the site-wide dictionary (dictionary has 30+ slugs incl.
///   sports/psychological) is the series' own.
/// - reader: mangary `/content/<slug>/episode/<no>`; whytoon
///   `/content/<slug>/<no>` (its /episode/N form 308-redirects there).
///   Images are the flight `"images":[…]` array — absolute on mangary,
///   `content/…`-relative on whytoon (resolved against gd.whytoon.com).
/// - `premium:true` episodes cost coins on the site — NO paywall bypass
///   (decision D, PLAN_NOTES 2026-10-23): premium episodes are EXCLUDED
///   from the chapter list rather than failing in the reader.
/// - search: none (404s) — the global search skips these sources.
/// - toondee.com runs the same platform but renders chapters/images
///   client-side only (no SSR flight data, RSC-header request empty) —
///   NOT addable without a session-bound API; left out 2026-10-28.
class ToonarySource implements Source {
  ToonarySource(this.config, this.http);

  final ToonaryConfig config;
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
  bool get supportsNovels => false;

  @override
  // Interface default spelled out: these sites serve permanent page URLs.
  bool get pageUrlsExpire => false;

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) =>
      _listing(config.searchUri(query, page));

  @override
  Future<List<SourceSeries>> latest({int page = 1, bool popular = false}) =>
      _listing(config.listingUri(page));

  Future<List<SourceSeries>> _listing(Uri uri) async {
    final body = await _fetch(uri);
    if (looksLikeCloudflarePage(body)) throw SourceException.cloudflare(id);
    return parseToonaryListing(
      body,
      baseUrl,
      genresInFlight: config.genresInFlight,
    );
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final body = await _fetch(Uri.parse(sourceUrl));
    if (looksLikeCloudflarePage(body)) throw SourceException.cloudflare(id);
    final detail = parseToonaryDetail(
      body,
      sourceUrl,
      genresFromHtmlLinks: config.genresFromHtmlLinks,
      episodeInPath: config.episodeInPath,
    );
    if (detail == null) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no toonary content on $sourceUrl',
      );
    }
    return detail;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    final body = await _fetch(Uri.parse(chapterUrl));
    if (looksLikeCloudflarePage(body)) throw SourceException.cloudflare(id);
    final urls = parseToonaryImages(body, cdnPrefix: config.cdnPrefix);
    if (urls.isEmpty) {
      throw SourceException(
        id,
        SourceErrorKind.parse,
        detail: 'no flight images on $chapterUrl',
      );
    }
    return ChapterPages(imageUrls: urls);
  }

  @override
  Future<String?> novelText(String chapterUrl) async => null;

  @override
  Future<List<SourceRecentStamp>> recentStamps() async => const [];

  /// Category cloud off the /categories page (mangary-style; whytoon has
  /// none — returns empty there).
  @override
  Future<List<SourceGenre>> genres() async {
    final body = await _fetch(Uri.parse('$baseUrl/categories'));
    return parseToonaryGenres(body);
  }

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) =>
      _listing(config.genreUri(term, page));

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
}

// --- pure parsers (fixture-tested, no I/O) -----------------------------------

@visibleForTesting
List<SourceSeries> parseToonaryListing(
  String body,
  String baseUrl, {
  bool genresInFlight = false,
}) {
  final doc = html_parser.parse(body);
  // whytoon (and any flight-carrying listing): per-card genres from the
  // embedded content records — slug → genre names (2026-10-28).
  final flightGenres = genresInFlight ? _listingFlightGenres(body) : const <String, List<String>>{};
  final out = <SourceSeries>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('a[href*="/content/"]')) {
    final href = a.attributes['href'] ?? '';
    final slug = toonarySlug(href);
    if (slug == null || !seen.add(slug)) continue;
    final card = _cardRoot(a);
    final title = (card.querySelector('h3') ?? card.querySelector('[itemprop="name"]'))
        ?.text
        .trim();
    if (title == null || title.isEmpty) continue;
    final img = card.querySelector('img');
    final raw = (img?.attributes['src'] ?? img?.attributes['data-src'] ?? '').trim();
    final cover = raw.startsWith('http') ? raw : null;
    // mangary cards link the newest episode separately — use it for the
    // chapter hint; the /content/ link itself has no number.
    var chapterHint = _episodeNoFromHref(href);
    if (chapterHint == null) {
      for (final e in card.querySelectorAll('a[href*="/episode/"], a[href*="/content/"]')) {
        chapterHint = _episodeNoFromHref(e.attributes['href'] ?? '');
        if (chapterHint != null) break;
      }
    }
    out.add(SourceSeries(
      url: '$baseUrl/content/$slug',
      title: title,
      coverUrl: cover,
      chapterCountHint: chapterHint,
      genres: _chipGenres(card).isNotEmpty
          ? _chipGenres(card)
          : (flightGenres[slug] ?? const []),
    ));
  }
  return out;
}

/// The enclosing card for a content anchor. mangary's anchor sits INSIDE
/// an `article` (cover link); whytoon's anchor WRAPS the whole card — so
/// the anchor's own subtree wins when it already holds a title, and the
/// walk-up only runs otherwise (never climbing past `main`/`body`, or
/// every card would inherit the first title).
html_dom.Element _cardRoot(html_dom.Element a) {
  if (a.querySelector('h3') != null) return a;
  html_dom.Element node = a;
  for (var i = 0; i < 6; i++) {
    final p = node.parent;
    if (p == null) break;
    node = p;
    if (node.localName == 'article') break;
    if (node.localName == 'main' || node.localName == 'body') {
      return a;
    }
    if (node.querySelector('h3') != null) break;
  }
  return node;
}

/// Genre chips on the card (mangary /latest renders e.g.
/// "Yaoi - มังงะวาย" as small secondary badges; whytoon cards don't).
List<String> _chipGenres(html_dom.Element card) {
  final out = <String>[];
  for (final span in card.querySelectorAll('span')) {
    final cls = span.className;
    if (!(cls.contains('bg-secondary') || cls.contains('chip__label'))) continue;
    final text = span.text.trim();
    if (text.isEmpty || text.length >= 40) continue;
    if (RegExp(r'^[0-9.]+$').hasMatch(text)) continue;
    out.add(text);
  }
  return out;
}

int? _episodeNoFromHref(String href) {
  final m = RegExp(r'/(\d+(?:\.\d+)?)\/?$').firstMatch(href);
  if (m == null) return null;
  final d = double.tryParse(m.group(1)!);
  return d?.toInt();
}

/// `/content/<slug>` (absolute or relative, optionally with an episode
/// tail) → slug. Episode tails are numeric; slugs never are.
String? toonarySlug(String href) {
  final i = href.indexOf('/content/');
  if (i < 0) return null;
  var tail = href.substring(i + '/content/'.length);
  tail = tail.split('?').first.split('#').first;
  final segs = tail.split('/')..removeWhere((s) => s.isEmpty);
  if (segs.isEmpty) return null;
  final slug = segs.first;
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(slug)) return null;
  return slug;
}

/// slug → genre display names off a listing page's flight payload.
/// Each content record looks like `{"content":{"slug":"x",…,"genres":[…]}`
/// — the genres array follows the slug inside the same record. The
/// site-wide dictionary (30+ entries) is skipped.
Map<String, List<String>> _listingFlightGenres(String body) {
  final flight = joinFlightPayload(body);
  final out = <String, List<String>>{};
  for (final m in RegExp(r'"slug":"([a-z0-9-]{4,})"').allMatches(flight)) {
    final slug = m.group(1)!;
    if (out.containsKey(slug)) continue;
    // Look ahead a bounded distance for this record's genres array.
    final window = flight.substring(
        m.end, (m.end + 4000).clamp(0, flight.length));
    final g = RegExp(r'"genres":').firstMatch(window);
    if (g == null) continue;
    final arr = _balancedArray(window, g.end);
    if (arr == null) continue;
    final names = [
      for (final n in RegExp(r'"name":"((?:[^"\\]|\\.)*)"').allMatches(arr))
        n.group(1)!,
    ];
    if (names.length >= 15) continue; // dictionary / filter list
    if (names.isNotEmpty) out[slug] = names;
  }
  return out;
}

@visibleForTesting
SourceSeriesDetail? parseToonaryDetail(
  String body,
  String sourceUrl, {
  bool genresFromHtmlLinks = false,
  bool episodeInPath = true,
}) {
  final doc = html_parser.parse(body);
  final flight = joinFlightPayload(body);

  // Title: "<bilingual series name> | Site" — keep the bilingual part.
  var title = (doc.querySelector('title')?.text ?? '').trim();
  final pipe = title.lastIndexOf(' | ');
  if (pipe > 0) title = title.substring(0, pipe).trim();
  if (title.isEmpty) title = toonarySlug(sourceUrl) ?? sourceUrl;

  String? meta(String property) =>
      doc.querySelector('meta[property="$property"]')?.attributes['content']?.trim();
  final description = meta('og:description');
  final cover = meta('og:image');

  final genres = genresFromHtmlLinks
      ? {
          for (final a in doc.querySelectorAll('a[href*="/categories/"]'))
            if (a.text.trim().isNotEmpty && a.text.trim().length < 40) a.text.trim(),
        }.toList()
      : _flightGenres(flight);

  final chapters = flightChapters(
    flight,
    sourceUrl,
    episodeInPath: episodeInPath,
  );
  if (chapters.isEmpty) return null;

  return SourceSeriesDetail(
    title: title,
    description: (description == null || description.isEmpty) ? null : description,
    tags: genres,
    // Platform truth, not a genre guess: Toonary sites host ONLY
    // vertical-scroll webtoons. Deriving the type from category names
    // misfired in the wild — mangary files Korean webtoons under its
    // "Manga - มังงะญี่ปุ่น" category, which shipped "The Night After
    // the Divorce" as type=manga → paged reader default (user report
    // 2026-11-01).
    type: 'manhwa',
    status: null,
    coverUrl: (cover == null || cover.isEmpty) ? null : cover,
    chapters: chapters,
  );
}

/// Joins the `self.__next_f.push([1,"…"])` chunks into one decoded
/// payload (each chunk body is a JSON-escaped string).
@visibleForTesting
String joinFlightPayload(String body) {
  final out = StringBuffer();
  for (final m in RegExp(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)')
      .allMatches(body)) {
    try {
      out.write(jsonDecode('"${m.group(1)!}"') as String);
    } on Exception {
      // A malformed chunk must not kill the whole payload join.
    }
  }
  return out.toString();
}

/// First genres array that is the SERIES' own (skip the site dictionary,
/// which lists 30+ genres incl. sports/psychological).
List<String> _flightGenres(String flight) {
  for (final m in RegExp(r'"genres":').allMatches(flight)) {
    final arr = _balancedArray(flight, m.end);
    if (arr == null) continue;
    final slugs =
        RegExp(r'"slug":"([a-z0-9-]+)"').allMatches(arr).map((m) => m.group(1)!);
    final names =
        RegExp(r'"name":"((?:[^"\\]|\\.)*)"').allMatches(arr).map((m) => m.group(1)!);
    final slugList = slugs.toList();
    if (slugList.length >= 15) continue; // dictionary
    final nameList = names.toList();
    if (slugList.isEmpty && nameList.isEmpty) continue;
    // Prefer display names ("Yaoi - มังงะวาย"); fall back to slugs.
    if (nameList.length >= slugList.length && nameList.isNotEmpty) {
      return nameList;
    }
    return slugList;
  }
  return const [];
}

/// Chapters off the FIRST non-empty `"episodes":[…]` array (later arrays
/// are related-series previews on whytoon). Premium (coin) episodes are
/// excluded — decision D, no paywall bypass.
@visibleForTesting
List<SourceChapter> flightChapters(
  String flight,
  String sourceUrl, {
  bool episodeInPath = true,
}) {
  for (final m in RegExp(r'"episodes":').allMatches(flight)) {
    final arr = _balancedArray(flight, m.end);
    if (arr == null) continue;
    final chapters = <SourceChapter>[];
    for (final rec in RegExp(
      r'\{"id":"(?:[^"\\]|\\.)*","name":"((?:[^"\\]|\\.)*)","no":([0-9.]+)'
      r',"publishedAt":"\$D([^"]*)"[^}]*?"premium":(true|false)[^}]*?\}',
    ).allMatches(arr)) {
      // The joined payload is already unescaped once — groups are raw.
      final name = rec.group(1)!.trim();
      final no = double.tryParse(rec.group(2)!) ?? 0;
      final iso = rec.group(3)!.trim();
      final premium = rec.group(4) == 'true';
      if (premium) continue;
      chapters.add(SourceChapter(
        url: toonaryChapterUrl(sourceUrl, no, episodeInPath: episodeInPath),
        title: 'ตอนที่ ${_fmtNo(no)}${name.isEmpty ? '' : '  $name'}',
        number: no,
        uploadedAt: iso.isEmpty ? null : DateTime.tryParse(iso)?.millisecondsSinceEpoch,
      ));
    }
    if (chapters.isEmpty) continue;
    chapters.sort((a, b) => a.number.compareTo(b.number));
    return chapters;
  }
  return const [];
}

String _fmtNo(double no) =>
    no == no.roundToDouble() ? no.toInt().toString() : no.toString();

/// Chapter URL shape differs per site (see [ToonaryConfig.episodeInPath]).
String toonaryChapterUrl(String sourceUrl, double no, {bool episodeInPath = true}) =>
    episodeInPath
        ? '$sourceUrl/episode/${_fmtNo(no)}'
        : '$sourceUrl/${_fmtNo(no)}';

/// Reader images off the episode page's flight `"images":[…]` array.
/// whytoon lists RELATIVE "content/…" paths — resolved against the CDN.
@visibleForTesting
List<String> parseToonaryImages(String body, {String? cdnPrefix}) {
  final flight = joinFlightPayload(body);
  for (final m in RegExp(r'"images":').allMatches(flight)) {
    final arr = _balancedArray(flight, m.end);
    if (arr == null) continue;
    final urls = <String>[];
    for (final e in RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(arr)) {
      var u = e.group(1)!;
      // Relative entries look like "content/<id>/<no>/<uuid>.webp"
      // (no leading slash) on whytoon.
      if (!u.contains('content/') && !u.startsWith('http')) continue;
      if (u.contains('/ads/') || u.contains('ads/')) continue;
      if (cdnPrefix != null && !u.startsWith('http')) {
        u = '$cdnPrefix$u';
      }
      if (u.startsWith('http')) urls.add(u);
    }
    if (urls.isNotEmpty) return urls;
  }
  return const [];
}

/// Genre cloud off a /categories page (mangary family).
@visibleForTesting
List<SourceGenre> parseToonaryGenres(String body) {
  final doc = html_parser.parse(body);
  final seen = <String>{};
  final out = <SourceGenre>[];
  for (final a in doc.querySelectorAll('a[href*="/categories/"], a[href*="/latest/"], a[href*="/genre/"]')) {
    final name = a.text.trim();
    final href = a.attributes['href'] ?? '';
    if (name.isEmpty || href.isEmpty || name.length >= 40) continue;
    final segs = Uri.tryParse(href.startsWith('http') ? href : 'https://x.invalid$href')
            ?.pathSegments ??
        const [];
    var i = segs.indexOf('categories');
    if (i < 0) i = segs.indexOf('genre');
    if (i < 0 || i + 1 >= segs.length) continue;
    final term = segs[i + 1];
    if (term.isEmpty || !seen.add(term)) continue;
    // Display name "Yaoi - มังงะวาย" → keep the latin part as name.
    final display = name.split(' - ').first.trim();
    out.add(SourceGenre(name: display.isEmpty ? term : display, term: term));
  }
  return out;
}

/// Scans forward from `start` (just past the opening `[`) capturing the
/// balanced array body, respecting strings and escapes. Returns as soon
/// as the array's OWN closing bracket brings the depth back to zero.
String? _balancedArray(String s, int start) {
  var depth = 0;
  var instr = false;
  var esc = false;
  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (instr) {
      if (esc) {
        esc = false;
      } else if (ch == '\\') {
        esc = true;
      } else if (ch == '"') {
        instr = false;
      }
      continue;
    }
    if (ch == '"') {
      instr = true;
    } else if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
      if (depth == 0) return s.substring(start, i + 1);
    }
  }
  return null;
}

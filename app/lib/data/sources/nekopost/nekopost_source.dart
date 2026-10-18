import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:html/parser.dart' as html_parser;

import '../../../core/net/safe_http.dart';
import '../../../core/utils/thai.dart';
import '../source_api.dart';
import 'nekopost_crypto.dart';

/// Logic ported from keiyoushi/extensions th.nekopost (Apache-2.0) and
/// live-verified against www.nekopost.net on 2026-10-17 (Plan/06 §4).
/// All endpoints are JSON POSTs; chapter payloads arrive AES-encrypted.
class NekopostSource implements Source {
  NekopostSource(this.http);

  final SafeHttp http;

  static const _base = 'https://www.nekopost.net';
  static const _api = '$_base/api/';

  /// Project ids above this are served from the fs host (site split — the
  /// wrong host answers 200 with a placeholder, Plan/06 §4).
  static const _fileHostThreshold = 17500;
  static const _wwwFiles = 'https://www.osemocphoto.com/collectManga/';
  static const _fsFiles = 'https://fs.osemocphoto.com/collectManga/';

  @override
  String get id => 'nekopost';
  @override
  String get name => 'Nekopost';
  @override
  String get baseUrl => _base;

  /// Image hosts require the site as Referer (Plan/06 §3).
  @override
  String get referer => '$_base/';

  @override
  bool get supportsNovels => true;

  String _fileHost(int pid) =>
      pid > _fileHostThreshold ? _fsFiles : _wwwFiles;

  String? _coverUrl(int pid, Object? coverVersion) {
    final v = (coverVersion as num?)?.toInt() ?? 0;
    final base = '${_fileHost(pid)}$pid/${pid}_cover.jpg';
    return v > 0 ? '$base?ver=$v' : base;
  }

  /// Nekopost "manga" (m), "comic" (c), "doujin" (d) are paged comics →
  /// type 'manga' (Plan/06 §3); translated (f) + original (n) novels →
  /// 'novel'.
  static String? _typeFor(Object? projectType) => switch (projectType) {
        'm' || 'c' || 'd' => 'manga',
        'f' || 'n' => 'novel',
        _ => null,
      };

  /// Status ints: 1 ongoing, 2 completed, 3 licensed (skipped in detail).
  static String? _statusFor(Object? raw) => switch ((raw as num?)?.toInt()) {
        1 => 'ongoing',
        2 => 'completed',
        _ => null,
      };

  Future<Object?> _post(String path, Map<String, Object?> body) async {
    final bytes = await http.postJson(Uri.parse('$_api$path'), body);
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  }

  /// cinfo lives OUTSIDE /api (verified live) and answers with an OpenSSL
  /// "Salted__" AES payload, not JSON.
  Future<Map<String, Object?>> _cinfo(int pid, int chapterId) async {
    if (kDebugMode) debugPrint('NEKO cinfo START p=$pid c=$chapterId');
    final bytes = await http.postJson(
        Uri.parse('$_base/handler/cinfo'), {'p': pid, 'c': chapterId});
    if (kDebugMode) debugPrint('NEKO cinfo BYTES ${bytes.length}');
    final decrypted =
        decryptCryptoJs(utf8.decode(bytes, allowMalformed: true));
    final decoded = jsonDecode(decrypted);
    if (kDebugMode) debugPrint('NEKO cinfo DECODED ok');
    if (decoded is! Map<String, Object?>) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'cinfo payload is not a map');
    }
    return decoded;
  }

  static Never _notMap(Object? response) {
    final text = response.toString();
    throw SourceException('nekopost', SourceErrorKind.parse,
        detail: 'API error body: '
            '${text.substring(0, text.length > 80 ? 80 : text.length)}');
  }

  @override
  Future<List<SourceSeries>> search(String query, {int page = 1}) async {
    final response = await _post('project/search', {
      'keyword': query.trim(),
      'status': 0,
      'paging': {'pageNo': page, 'pageSize': 100},
    });
    if (response is! Map<String, Object?>) _notMap(response);
    final list = response['listProject'] as List<Object?>? ?? const [];
    return [
      for (final raw in list)
        if (raw is Map<String, Object?>) _seriesFromSummary(raw),
    ];
  }

  /// Latest feed = manga (type m) + translated novels (f) interleaved
  /// (each listing is already newest-first; novels must not vanish from
  /// Browse — decision D3). Original novels (n) surface via search.
  @override
  Future<List<SourceSeries>> latest({int page = 1}) async {
    final results = await Future.wait([
      _latestType('m', page),
      _latestType('f', page),
    ]);
    final seen = <String>{};
    return [
      for (final list in results)
        for (final s in list)
          if (seen.add(s.url)) s,
    ];
  }

  Future<List<SourceSeries>> _latestType(String type, int page) async {
    final response = await _post('project/latest', {
      'type': type,
      'paging': {'pageNo': page, 'pageSize': 15},
    });
    if (response is! Map<String, Object?>) _notMap(response);
    final list = response['listChapter'] as List<Object?>? ?? const [];
    return [
      for (final raw in list)
        if (raw is Map<String, Object?>)
          SourceSeries(
            url: _projectUrl((raw['pid'] as num).toInt()),
            title: raw['projectName'] as String? ?? '',
            coverUrl:
                _coverUrl((raw['pid'] as num).toInt(), raw['coverVersion']),
            type: _typeFor(raw['projectType']),
          ),
    ];
  }

  String _projectUrl(int pid) => 'nekopost:project:$pid';

  SourceSeries _seriesFromSummary(Map<String, Object?> raw) {
    final pid = (raw['pid'] as num).toInt();
    return SourceSeries(
      url: _projectUrl(pid),
      title: raw['projectName'] as String? ?? '',
      coverUrl: _coverUrl(pid, raw['coverVersion']),
      chapterCountHint: (raw['noChapter'] as num?)?.toInt(),
      type: _typeFor(raw['projectType']),
    );
  }

  @override
  Future<SourceSeriesDetail> detail(String sourceUrl) async {
    final pid = _pidFrom(sourceUrl);
    final response = await _post('project/detail2', {'pid': pid});
    if (response is! Map<String, Object?>) {
      // Dead/deleted ids answer 200 with `"sql: no rows in result set"`.
      throw SourceException(id, SourceErrorKind.notFound,
          detail: response.toString());
    }
    final info = response['projectInfo'];
    if (info is! Map<String, Object?>) {
      throw SourceException(id, SourceErrorKind.notFound, detail: 'no info');
    }
    final project = info['Project'] as Map<String, Object?>? ?? const {};
    final statusInt = (project['status'] as num?)?.toInt();
    if (statusInt == 3) {
      throw SourceException(id, SourceErrorKind.notFound,
          detail: 'licensed — not readable (decision D5: public only)');
    }
    final title = project['projectName'] as String? ?? '';
    final alias = (project['aliasName'] as String?)?.trim() ?? '';
    final categories =
        info['ListCate'] as List<Object?>? ?? const <Object?>[];

    final chapters = [
      for (final raw in info['ListChapter'] as List<Object?>? ?? const [])
        if (raw is Map<String, Object?>) _chapterFrom(pid, raw),
    ]..sort((a, b) => a.number.compareTo(b.number));

    return SourceSeriesDetail(
      title: title,
      altTitles: [
        if (alias.isNotEmpty && alias != title) alias,
      ],
      description: (project['info'] as String?)?.trim(),
      tags: [
        for (final c in categories)
          if (c is Map)
            if (c['CateName'] is String &&
                (c['CateName'] as String).trim().isNotEmpty)
              (c['CateName'] as String).trim(),
      ],
      type: _typeFor(project['projectType']),
      status: _statusFor(statusInt),
      coverUrl: _coverUrl(pid, project['coverVersion']),
      chapters: chapters,
    );
  }

  SourceChapter _chapterFrom(int pid, Map<String, Object?> raw) {
    final chapterId = (raw['ChapterID'] as num).toInt();
    final no = raw['ChapterNo'] as String? ?? '';
    final name = raw['ChapterName'] as String? ?? no;
    final number =
        double.tryParse(no) ?? parseChapterNumber(name) ?? 0.0;
    final published =
        ((raw['PublishDate'] as Map<String, Object?>?)?['String'] as String?);
    return SourceChapter(
      url: 'nekopost:chapter:$pid:$chapterId',
      title: name,
      number: number,
      uploadedAt: published == null ? null : _isoToMs(published),
    );
  }

  static int? _isoToMs(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt?.toUtc().millisecondsSinceEpoch;
  }

  (int, int) _chapterIds(String chapterUrl) {
    final parts = chapterUrl.split(':');
    if (parts.length != 4 ||
        parts[0] != 'nekopost' ||
        parts[1] != 'chapter') {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'bad chapter url: $chapterUrl');
    }
    final pid = int.tryParse(parts[2]);
    final cid = int.tryParse(parts[3]);
    if (pid == null || cid == null) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'bad chapter ids: $chapterUrl');
    }
    return (pid, cid);
  }

  int _pidFrom(String sourceUrl) {
    final parts = sourceUrl.split(':');
    final pid = parts.length == 3 && parts[1] == 'project'
        ? int.tryParse(parts[2])
        : null;
    if (pid == null) {
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'bad project url: $sourceUrl');
    }
    return pid;
  }

  @override
  Future<ChapterPages> pages(String chapterUrl) async {
    if (kDebugMode) debugPrint('NEKO pages ENTER $chapterUrl');
    final (pid, cid) = _chapterIds(chapterUrl);
    final info = await _cinfo(pid, cid);
    final items = info['pageItem'] as List<Object?>? ?? const [];
    final sorted = [
      for (final raw in items)
        if (raw is Map<String, Object?>) raw,
    ]..sort((a, b) => _pageNo(a).compareTo(_pageNo(b)));
    final base = '${_fileHost(pid)}$pid/$cid/';
    final urls = <String>[
      for (final page in sorted)
        '$base${_fileName(page)}',
    ];
    if (kDebugMode) debugPrint('NEKO pages mapped n=${urls.length}');
    if (urls.isEmpty || urls.any((u) => u.endsWith('/'))) {
      if (kDebugMode) debugPrint('NEKO pages THROW bad names');
      throw SourceException(id, SourceErrorKind.parse,
          detail: 'pageItem missing file names');
    }
    return ChapterPages(imageUrls: urls);
  }

  /// QA on-device 2026-10-18: live payloads use INT `pageNo`
  /// ({pageNo: 1, fileName: "…_1.jpg", width, height}) — the previous
  /// `as String?` casts blew up with a TypeError, which made every
  /// image-chapter open on the nekopost source fail its candidate.
  static String _fileName(Map<String, Object?> page) {
    final fn = page['fileName'];
    if (fn is String && fn.isNotEmpty) return fn;
    final pn = page['pageName'];
    if (pn is String && pn.isNotEmpty) return pn;
    return '';
  }

  static double _pageNo(Map<String, Object?> page) =>
      double.tryParse('${page['pageNo']}') ?? 0;

  @override
  Future<String?> novelText(String chapterUrl) async {
    final (pid, cid) = _chapterIds(chapterUrl);
    final info = await _cinfo(pid, cid);
    if (kDebugMode) {
      debugPrint('NEKO novelText keys=${info.keys.toList()} '
          'pageTextLen=${(info['pageText'] as String?)?.length} '
          'novelLen=${(info['novelContent'] as String?)?.length}');
    }
    var html = (info['pageText'] as String?) ??
        (info['novelContent'] as String?) ??
        '';
    if (html.isEmpty) return null;

    // Inline-media placeholders resolve to the chapter's file directory.
    final fileBase = '${_fileHost(pid)}$pid/$cid/';
    html = html
        .replaceAll('{file_fs}', fileBase)
        .replaceAll('{file_img}', fileBase)
        .replaceAll('{file_audio}', fileBase);

    return _htmlToParagraphs(html);
  }

  /// Plan/06 §3: plain-text paragraphs separated by `\n\n`; Thai kept
  /// as-is, inline images dropped (text reader renders text only).
  static String _htmlToParagraphs(String html) {
    final fragment = html_parser.parseFragment(html);
    final paragraphs = <String>[];
    for (final node in fragment.nodes) {
      final text = (node.text ?? '')
          .replaceAll('\u00A0', ' ')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .trim();
      if (text.isNotEmpty) paragraphs.add(text);
    }
    return paragraphs.join('\n\n');
  }

  /// Nekopost has category metadata but no server-side genre filter that
  /// behaves like the ts-theme's /?genres= — browse-by-genre stays
  /// unsupported for this source (Plan/08 genre picker shows nothing).
  @override
  Future<List<SourceGenre>> genres() async => const [];

  @override
  Future<List<SourceSeries>> browseGenre(String term, {int page = 1}) async =>
      const [];
}

// Smoke-test CLI for source adapters (Plan/15 Phase 3 DoD + Plan/06 DoD).
//
// Usage (from app/):
//   dart run tool/verify_sources.dart --source slow-manga
//   dart run tool/verify_sources.dart --source nekopost
//   dart run tool/verify_sources.dart --source all
//
// Uses the SAME adapter code as the app (no copies).
// ignore_for_file: avoid_print
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/madara/configs.dart';
import 'package:star_codex/data/sources/madara/madara_source.dart';
import 'package:star_codex/data/sources/nekopost/nekopost_source.dart';
import 'package:star_codex/data/sources/source_api.dart';

Future<void> main(List<String> args) async {
  final which = args.contains('--source')
      ? args[args.indexOf('--source') + 1]
      : 'all';
  final http = SafeHttp();
  final sources = <Source>[
    for (final config in madaraConfigs)
      if (which == 'all' || which == config.id) MadaraSource(config, http),
    if (which == 'all' || which == 'nekopost') NekopostSource(http),
  ];
  if (sources.isEmpty) {
    print('unknown source: $which (expected one of: '
        '${madaraConfigs.map((c) => c.id).join(', ')}, nekopost, all)');
    return;
  }

  var failures = 0;
  for (final source in sources) {
    print('\n========== ${source.id} ==========');
    failures += await verify(source);
  }
  print('\n${failures == 0 ? 'ALL OK' : '$failures FAILURES'}');
}

Future<int> verify(Source source) async {
  var failures = 0;
  void ok(String label) => print('  OK  $label');
  void fail(String label, Object e) {
    failures++;
    print('  FAIL $label → $e');
  }

  // 1. latest: 10 series
  try {
    final latest = await source.latest();
    print('latest: ${latest.length} series');
    for (final s in latest.take(10)) {
      print('  - ${s.title}  [${s.type ?? '?'}]  ${s.url}');
    }
    ok('latest');
    if (latest.isEmpty) fail('latest', 'no series parsed');

    // 2. search (skip where blocked)
    if (latest.isNotEmpty) {
      try {
        final results = await source.search('nano machine');
        print('search "nano machine": ${results.length} results');
        for (final s in results.take(3)) {
          print('  - ${s.title}  ${s.url}');
        }
        ok('search');
      } on SourceException catch (e) {
        if (e.kind == SourceErrorKind.cloudflare) {
          print('  SKIP search (Cloudflare — searchSupported=false)');
        } else {
          fail('search', e);
        }
      }
    }

    // 3. detail + 5 chapters with parsed numbers
    final first = latest.firstWhere((s) => s.type != 'novel',
        orElse: () => latest.first);
    try {
      final detail = await source.detail(first.url);
      print('detail: "${detail.title}" '
          'type=${detail.type} status=${detail.status} '
          'tags=${detail.tags.take(4).toList()} '
          'chapters=${detail.chapters.length}');
      for (final ch in detail.chapters.take(5)) {
        print('  - #${ch.number} "${ch.title}" ${ch.uploadedAt}');
      }
      ok('detail');

      // 4. pages: image URLs for one chapter (comics only)
      if (detail.chapters.isNotEmpty && detail.type != 'novel') {
        final pages = await source.pages(detail.chapters.last.url);
        print('pages for "${detail.chapters.last.title}": '
            '${pages.imageUrls.length} images');
        for (final u in pages.imageUrls.take(3)) {
          print('  - $u');
        }
        if (pages.imageUrls.length > 3) print('  - …');
        ok('pages');
        if (pages.imageUrls.isEmpty) fail('pages', 'no images parsed');
      }
    } catch (e) {
      fail('detail', e);
    }

    // 5. novels (Plan/06 §DoD): one novel chapter's first 200 chars.
    if (source.supportsNovels) {
      try {
        final novels = await source.search('one piece');
        final novel = novels.firstWhere((s) => s.type == 'novel');
        final detail = await source.detail(novel.url);
        final chapter = detail.chapters.last;
        final text = await source.novelText(chapter.url);
        if (text == null || text.isEmpty) {
          fail('novel', 'empty novel text');
        } else {
          print('novel "${detail.title}" ch ${chapter.number}: '
              '${text.length} chars');
          final preview = text.substring(0, text.length > 200 ? 200 : text.length)
              .replaceAll('\n', ' | ');
          print('  $preview…');
          ok('novel');
        }
      } catch (e) {
        fail('novel', e);
      }
    }
  } catch (e) {
    fail('latest', e);
  }
  return failures;
}

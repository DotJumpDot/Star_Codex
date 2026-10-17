// Smoke-test CLI for source adapters (Plan/15 Phase 3 DoD).
//
// Usage (from app/):
//   dart run tool/verify_sources.dart --source slow-manga
//   dart run tool/verify_sources.dart --source all
//
// Uses the SAME adapter code as the app (no copies). Nekopost arrives in
// Phase 8.
// ignore_for_file: avoid_print
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/madara/configs.dart';
import 'package:star_codex/data/sources/madara/madara_source.dart';
import 'package:star_codex/data/sources/source_api.dart';

Future<void> main(List<String> args) async {
  final which = args.contains('--source')
      ? args[args.indexOf('--source') + 1]
      : 'all';
  final configs = which == 'all'
      ? madaraConfigs
      : madaraConfigs.where((c) => c.id == which).toList();
  if (configs.isEmpty) {
    print('unknown source: $which (expected one of: '
        '${madaraConfigs.map((c) => c.id).join(', ')}, all)');
    return;
  }

  final http = SafeHttp();
  var failures = 0;
  for (final config in configs) {
    final source = MadaraSource(config, http);
    print('\n========== ${config.id} ==========');
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
    final first = latest.first;
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

      // 4. pages: image URLs for one chapter
      if (detail.chapters.isNotEmpty) {
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
  } catch (e) {
    fail('latest', e);
  }
  return failures;
}

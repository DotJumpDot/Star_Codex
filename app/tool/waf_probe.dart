// Reachability probe (2026-10-23): every source homepage through the
// app's OWN network stack (SafeHttp, WAF ladder included) — answers
// "which sites block us right now" in one run. Not part of the test
// suite; on a desktop VM the cronet/webview tiers are unavailable, so
// ladder-escalated hosts report FAIL there (run on-device for the full
// ladder).
// Usage (from app/): dart run tool/waf_probe.dart
// ignore_for_file: avoid_print
import 'package:star_codex/core/net/safe_http.dart';

const hosts = [
  'go-manga.com',
  'slow-manga.net',
  'up-manga.com',
  'dark-manga.com',
  'fin-manga.com',
  'bully-manga.com',
  'nekopost.net',
  'ntr-manga.net',
  'hentaithai.net',
  'doujin-lc.net',
  'miku-doujin.com',
];

Future<void> main() async {
  final http = SafeHttp();
  for (final h in hosts) {
    final uri = Uri.parse('https://$h/');
    try {
      final html = await http.getHtml(uri);
      final challenged = RegExp(
        'just a moment|attention required|cf_chl|checking your browser',
        caseSensitive: false,
      ).hasMatch(html);
      final title = RegExp('<title[^>]*>([^<]{0,50})')
              .firstMatch(html)
              ?.group(1)
              ?.trim() ??
          '(no title)';
      print('$h -> OK ${html.length}b challenged=$challenged "$title"');
    } catch (e) {
      print('$h -> FAIL $e');
    }
  }
}

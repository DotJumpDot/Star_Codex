// ignore_for_file: avoid_print
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/data/sources/madara/configs.dart';
import 'package:star_codex/data/sources/madara/madara_source.dart';

Future<void> main(List<String> args) async {
  final id = args.isNotEmpty ? args[0] : 'slow-manga';
  final config = madaraConfigs.firstWhere((c) => c.id == id);
  final source = MadaraSource(config, SafeHttp(rateLimiter: RateLimiter()));
  try {
    final genres = await source.genres();
    print('OK ${genres.length} genres');
    print(genres.take(8).map((g) => '${g.name} [${g.term}]').join('\n'));
  } catch (e) {
    print('GENRES FAILED: $e');
  }
}

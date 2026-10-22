// WAF ladder tests (2026-10-23): signature detection, tier escalation,
// and the SafeHttp direct → cronet → webview handoff, all through fakes
// (a local mock server would violate the loopback rule).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/net/cronet_lane.dart';
import 'package:star_codex/core/net/net_exception.dart';
import 'package:star_codex/core/net/rate_limiter.dart';
import 'package:star_codex/core/net/safe_http.dart';
import 'package:star_codex/core/net/waf_gate.dart';
import 'package:star_codex/core/net/webview_gate.dart';

Response<List<int>> _dioResponse(Uri uri, int status, List<int> body,
        {Map<String, List<String>> headers = const {}}) =>
    Response<List<int>>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: status,
      data: body,
      headers: Headers.fromMap(headers),
    );

DioException _cfBlock(Uri uri, {int status = 403}) => DioException(
      requestOptions: RequestOptions(path: uri.toString()),
      response: _dioResponse(
        uri,
        status,
        utf8.encode('<html><title>Just a moment...</title></html>'),
        headers: {'server': ['cloudflare']},
      ),
      type: DioExceptionType.badResponse,
    );

class FakeCronet extends CronetLane {
  FakeCronet(this.handler);

  final Future<LaneResponse> Function(Uri uri, Map<String, String>? extra)
      handler;
  int calls = 0;

  @override
  bool get available => true;

  @override
  Future<LaneResponse> fetch(Uri uri,
          {Map<String, String>? extraHeaders}) =>
      handler(uri, extraHeaders).whenComplete(() => calls++);
}

class FakeWebview extends WebviewGate {
  final fetchCalls = <Uri>[];
  Object? htmlError;
  LaneResponse html = LaneResponse(
      status: 200, body: utf8.encode('<html>via-webview</html>'));

  @override
  Future<Map<String, String>> relayHeadersFor(Uri uri) async => const {};

  @override
  Future<LaneResponse> fetchHtml(Uri uri, {bool allowManualUnlock = false}) {
    fetchCalls.add(uri);
    if (htmlError != null) throw htmlError!;
    return Future.value(html);
  }
}

void main() {
  group('cloudflareSignature', () {
    test('403 + CF server + challenge body', () {
      expect(
        WafGate.cloudflareSignature(
            403, utf8.encode('Just a moment...'), {'server': 'cloudflare'}),
        isTrue,
      );
    });

    test('403 + CF server + empty body (fingerprint block)', () {
      expect(
        WafGate.cloudflareSignature(403, const [], {'server': 'Cloudflare'}),
        isTrue,
      );
    });

    test('403 + non-CF server + no markers = real 403', () {
      expect(
        WafGate.cloudflareSignature(
            403, utf8.encode('not found here'), {'server': 'nginx'}),
        isFalse,
      );
    });

    test('200 with challenge-platform marker stays healthy (probed live)', () {
      expect(
        WafGate.cloudflareSignature(
            200, utf8.encode('ok cf challenge-platform/x'), {}),
        isFalse,
      );
    });

    test('403 + marker without CF server header still matches', () {
      expect(
        WafGate.cloudflareSignature(
            403, utf8.encode('cf_chl_opt'), {'server': ' ATS'}),
        isTrue,
      );
    });
  });

  group('WafGate ladder', () {
    test('escalates direct → cronet → webview, then exhausts', () {
      final gate = WafGate(cronet: FakeCronet((_, _) => throw StateError('')),
          webview: FakeWebview());
      expect(gate.escalate('a.example.com'), WafLane.cronet);
      expect(gate.laneFor('a.example.com'), WafLane.cronet);
      expect(gate.escalate('a.example.com'), WafLane.webview);
      expect(gate.escalate('a.example.com'), isNull);
      expect(gate.recentlyExhausted('a.example.com'), isTrue);
      gate.noteSuccess('a.example.com');
      expect(gate.recentlyExhausted('a.example.com'), isFalse);
    });

    test('skips cronet when unavailable (test VM: Platform.isAndroid=false)',
        () {
      // Real CronetLane on the VM reports unavailable.
      final gate = WafGate(cronet: CronetLane(), webview: FakeWebview());
      expect(gate.hasCronet, isFalse);
      expect(gate.escalate('b.example.com'), WafLane.webview);
    });
  });

  group('SafeHttp ladder handoff', () {
    final uri = Uri.parse('https://www.example.com/manga');

    SafeHttp httpWith({
      required SafeHttpFetcher fetcher,
      required FakeCronet cronet,
      required FakeWebview webview,
    }) =>
        SafeHttp(
          rateLimiter: RateLimiter(seed: 1),
          fetcher: fetcher,
          delay: (_) async {},
          gate: WafGate(cronet: cronet, webview: webview),
        );

    test('direct 403 (CF) → retried on cronet, host lane learned', () async {
      final webview = FakeWebview();
      final cronet = FakeCronet((u, extra) async => LaneResponse(
          status: 200,
          body: utf8.encode('cronet-bytes'),
          headers: {'server': 'cloudflare'}));
      var directCalls = 0;
      final http = httpWith(
        fetcher: (u, options) async {
          directCalls++;
          throw _cfBlock(u);
        },
        cronet: cronet,
        webview: webview,
      );

      final text = await http.getHtml(uri);
      expect(text, 'cronet-bytes');
      expect(directCalls, 1);
      expect(cronet.calls, 1);
      expect(webview.fetchCalls, isEmpty);
    });

    test('cronet also blocked → webview document fetch', () async {
      final webview = FakeWebview();
      final cronet = FakeCronet((u, extra) async => LaneResponse(
          status: 403,
          body: utf8.encode('Just a moment...'),
          headers: {'server': 'cloudflare'}));
      final http = httpWith(
        fetcher: (u, options) async => throw _cfBlock(u),
        cronet: cronet,
        webview: webview,
      );

      final text = await http.getHtml(uri);
      expect(text, '<html>via-webview</html>');
      // once as the cronet tier, once as the webview tier's relay attempt
      expect(cronet.calls, 2);
      expect(webview.fetchCalls, [uri]);
    });

    test('all tiers blocked → NetException 403 + fail-fast stamp',
        () async {
      final webview = FakeWebview()
        ..htmlError = const NetException('cloudflare challenge not solved',
            statusCode: 403);
      final gate = WafGate(
          cronet: FakeCronet((u, extra) async => LaneResponse(
              status: 403,
              body: utf8.encode('attention required'),
              headers: {'server': 'cloudflare'})),
          webview: webview);
      final http = SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (u, options) async => throw _cfBlock(u),
        delay: (_) async {},
        gate: gate,
      );

      await expectLater(
        () => http.getHtml(uri),
        throwsA(
          isA<NetException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
      expect(gate.recentlyExhausted(uri.host), isTrue);
    });

    test('non-CF 403 with a gate present stays a real 403', () async {
      final gate = WafGate(
          cronet: FakeCronet((_, _) => throw StateError('unused')),
          webview: FakeWebview());
      final http = SafeHttp(
        rateLimiter: RateLimiter(seed: 1),
        fetcher: (u, options) async => throw DioException(
          requestOptions: RequestOptions(path: u.toString()),
          response: _dioResponse(u, 403, utf8.encode('forbidden')),
          type: DioExceptionType.badResponse,
        ),
        delay: (_) async {},
        gate: gate,
      );

      await expectLater(
        () => http.getHtml(uri),
        throwsA(
          isA<NetException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
      expect(gate.laneFor(uri.host), WafLane.direct);
    });
  });
}

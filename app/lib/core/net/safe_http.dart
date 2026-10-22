import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'net_exception.dart';
import 'rate_limiter.dart';
import 'waf_gate.dart';

/// Injectable transport for tests (a local mock server would violate the
/// loopback rule, so retries are tested through a fake fetcher instead).
typedef SafeHttpFetcher = Future<Response<List<int>>> Function(
    Uri uri, Options options);

/// Injectable backoff sleep for tests.
typedef SafeHttpDelay = Future<void> Function(Duration d);

/// The ONLY network door in the app (Plan/04 §2 — hard security rule).
///
/// Order of enforcement:
///  1. scheme must be http/https
///  2. host must not resolve to local/private/metadata ranges
///  3. default desktop-Chrome headers
///  4. redirects are followed manually, re-validating every hop
///  5. timeouts 15 s connect / 30 s receive; bodies capped at 50 MB
///
/// Exposes exactly `getHtml`, `getBytes` and `postJson`. Nothing else in
/// the app may construct a Dio/HttpClient (checked in the Phase 3 DoD
/// grep). `postJson` exists for the Nekopost API (Plan/06): same scheme +
/// host validation, rate limiter and retry policy as every GET.
class SafeHttp {
  SafeHttp(
      {RateLimiter? rateLimiter,
      SafeHttpFetcher? fetcher,
      SafeHttpDelay? delay,
      WafGate? gate})
      : _rateLimiter = rateLimiter ?? RateLimiter(),
        // ignore: prefer_initializing_formals — private fields
        _fetcher = fetcher,
        // ignore: prefer_initializing_formals — private field
        _gate = gate,
        _delay = delay ?? ((d) => Future<void>.delayed(d)) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false, // hops validated manually in _run
      maxRedirects: 8,
      headers: {
        'User-Agent': wafBrowserUserAgent,
        'Accept-Language': 'th,en;q=0.8',
      },
      validateStatus: (status) => status != null && status < 400,
    ));
    // Default transport: Dio with `options:` as a NAMED arg (a bare
    // `_dio.getUri` tear-off would misbind it positionally). POST bodies
    // ride in `options.extra['safe_http_body']` (Options has no data
    // field) and go out through dio.post.
    _fetch = _fetcher ??
        (uri, options) async {
          if ((options.method ?? 'GET') == 'POST') {
            return _dio.post<List<int>>(
              uri.toString(),
              data: options.extra?['safe_http_body'],
              options: Options(
                responseType: options.responseType,
                headers: options.headers,
                contentType: options.contentType,
                validateStatus: options.validateStatus,
              ),
            );
          }
          return _dio.getUri<List<int>>(uri, options: options);
        };
  }

  /// Injectable transport for tests (a local mock server would violate the
  /// loopback rule, so retries are tested through a fake fetcher instead).
  late final Dio _dio;
  final RateLimiter _rateLimiter;
  final SafeHttpFetcher? _fetcher;
  final SafeHttpDelay _delay;
  late final SafeHttpFetcher _fetch;

  /// WAF ladder (2026-10-23): null in tests → direct-lane-only behavior.
  final WafGate? _gate;

  static const maxBodyBytes = 50 * 1024 * 1024;

  Future<String> getHtml(Uri uri, {String? referer}) async {
    final bytes = await getBytes(uri, referer: referer);
    // UTF-8 — the sites are UTF-8; Latin-1 here would mojibake all Thai
    // text (titles, tags, chapter labels, dates).
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// JSON-body POST (Plan/06 nekopost API). Validated + rate-limited +
  /// retried exactly like GET; read-only endpoints, so retrying a 5xx is
  /// safe.
  Future<Uint8List> postJson(Uri uri, Map<String, Object?> body,
      {String? referer}) async {
    return _loop(uri, referer: referer, method: 'POST', data: body);
  }

  Future<Uint8List> getBytes(Uri uri, {String? referer}) async {
    return _loop(uri, referer: referer);
  }

  Future<Uint8List> _loop(Uri uri,
      {String? referer, String method = 'GET', Object? data}) async {
    var current = uri;
    for (var hop = 0; hop <= 8; hop++) {
      final response = await _run(current,
          referer: referer, method: method, data: data);
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw NetException('redirect without Location', uri: current);
        }
        current = current.resolve(location);
        continue;
      }
      final payload = response.data;
      if (payload is! List<int>) {
        throw NetException('unexpected body type', uri: current);
      }
      if (payload.length > maxBodyBytes) {
        throw NetException('body exceeds 50 MB cap', uri: current);
      }
      return Uint8List.fromList(payload);
    }
    throw NetException('too many redirects', uri: uri);
  }

  Future<Response<List<int>>> _run(Uri uri,
      {String? referer, String method = 'GET', Object? data}) async {
    await _validate(uri);
    final release = await _rateLimiter.acquire(uri.host);
    try {
      // WAF ladder: POST (nekopost API) and gate-less instances always
      // take the direct Dio lane. GETs on a lane the gate learned for
      // this host go straight there.
      final lane = _gate?.laneFor(uri.host) ?? WafLane.direct;
      if (method != 'GET' || lane == WafLane.direct) {
        try {
          return await _withRetries(uri,
              referer: referer, method: method, data: data);
        } on _CloudflareBlock catch (e) {
          final next = _gate?.laneFor(uri.host) ?? WafLane.direct;
          if (next == WafLane.direct) {
            throw NetException('HTTP ${e.statusCode}',
                uri: uri, statusCode: e.statusCode);
          }
          return await _laneFetch(uri, referer: referer);
        }
      }
      return await _laneFetch(uri, referer: referer);
    } finally {
      release();
    }
  }

  /// Fetch through a learned WAF lane (cronet or webview). 3xx responses
  /// are returned unwrapped so `_loop` follows + re-validates every hop
  /// exactly as on the direct lane. A Cloudflare-shaped failure promotes
  /// the host one tier; exhausting the ladder throws.
  Future<Response<List<int>>> _laneFetch(Uri uri, {String? referer}) async {
    final gate = _gate!;
    var lane = gate.laneFor(uri.host);
    while (true) {
      if (lane == WafLane.cronet && gate.cronet == null) {
        // The engine failed its lazy init after the lane was learned.
        final next = gate.escalate(uri.host);
        if (next == null) {
          throw NetException('cronet engine unavailable',
              uri: uri, statusCode: 403);
        }
        lane = next;
        continue;
      }
      final extra = {
        'referer': ?referer,
      };
      LaneResponse r;
      if (lane == WafLane.cronet) {
        r = await gate.cronet!.fetch(uri, extraHeaders: extra);
      } else {
        // WebView tier: byte traffic rides cronet at native speed with
        // the relayed clearance cookie + WebView UA; a Cloudflare-shaped
        // answer falls back to fetching the document inside the WebView
        // (which also re-solves an expired challenge).
        final relay = await gate.webview!.relayHeadersFor(uri);
        final cronet = gate.cronet;
        if (cronet != null) {
          r = await cronet.fetch(uri, extraHeaders: {...relay, ...extra});
        } else {
          r = await gate.webview!.fetchHtml(uri);
        }
        if (WafGate.cloudflareSignature(r.status, r.body, r.headers)) {
          try {
            r = await gate.webview!.fetchHtml(uri);
          } on NetException {
            // Top tier failed (challenge unsolved): stamp the host so
            // the next refresh fails fast instead of waiting 15 s again.
            gate.escalate(uri.host);
            rethrow;
          }
        }
      }
      if (r.status >= 200 && r.status < 400) {
        gate.noteSuccess(uri.host);
        return Response<List<int>>(
          requestOptions:
              RequestOptions(path: uri.toString(), method: 'GET'),
          statusCode: r.status,
          data: r.body is Uint8List ? r.body : Uint8List.fromList(r.body),
          headers: Headers.fromMap({
            for (final e in r.headers.entries) e.key: [e.value],
          }),
        );
      }
      if (WafGate.cloudflareSignature(r.status, r.body, r.headers)) {
        final next = gate.escalate(uri.host);
        if (next == null || next == lane) {
          throw NetException('HTTP ${r.status}',
              uri: uri, statusCode: r.status);
        }
        lane = next;
        continue;
      }
      throw NetException('HTTP ${r.status}', uri: uri, statusCode: r.status);
    }
  }

  Future<Response<List<int>>> _withRetries(Uri uri,
      {String? referer, String method = 'GET', Object? data}) async {
    var backoff = const Duration(seconds: 1);
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await _fetch(
            uri,
            Options(
              responseType: ResponseType.bytes,
              method: method,
              contentType: method == 'POST' ? 'application/json' : null,
              headers: {
                'Referer': ?referer,
              },
              extra: data == null ? null : {'safe_http_body': data},
            ));
        return response;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final retryable = e.type != DioExceptionType.badResponse ||
            status == null ||
            status >= 500 ||
            status == 429;
        if (!retryable || attempt == 3) {
          if (e.type == DioExceptionType.badResponse) {
            // WAF ladder hook: a Cloudflare-shaped 403/429/503 on a GET
            // promotes the host to the next lane before surfacing.
            if (_gate != null && method == 'GET' && status != null) {
              final body = e.response?.data;
              final headers = <String, String>{
                for (final entry
                    in e.response?.headers.map.entries ?? const <MapEntry<
                        String, List<String>>>[])
                  entry.key.toLowerCase():
                      entry.value.isNotEmpty ? entry.value.first : '',
              };
              if (WafGate.cloudflareSignature(
                  status, body is List<int> ? body : null, headers)) {
                _gate.escalate(uri.host);
                throw _CloudflareBlock(status);
              }
            }
            throw NetException('HTTP $status', uri: uri, statusCode: status);
          }
          throw NetException('network: ${e.message}', uri: uri);
        }
        final retryAfterHeader = e.response?.headers.value('retry-after');
        var wait = backoff;
        if (retryAfterHeader != null) {
          final secs = int.tryParse(retryAfterHeader);
          if (secs != null) wait = Duration(seconds: secs);
        }
        await _delay(wait);
        backoff *= 3;
      }
    }
    throw NetException('unreachable', uri: uri); // not reached
  }

  /// Steps 1–2 of the security rule: scheme check, localhost/literal-IP
  /// checks, then DNS resolution of hostnames with every resolved address
  /// validated (a public-looking name resolving into private/loopback space
  /// is rejected before connecting). Throws [NetException] on violation.
  static Future<void> _validate(Uri uri) async {
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw NetException('scheme ${uri.scheme} not allowed', uri: uri);
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost')) {
      throw NetException('localhost not allowed', uri: uri);
    }
    if (host.isEmpty) {
      throw NetException('empty host', uri: uri);
    }
    try {
      final addr = InternetAddress(host); // numeric literal?
      _validateAddress(addr, uri);
      return;
    } on ArgumentError {
      // not a literal — resolve below
    }
    List<InternetAddress> resolved;
    try {
      // Bounded lookup: an unresponsive resolver must not hang the whole
      // feed (observed on a just-booted emulator). 10 s then "DNS failed".
      resolved = await InternetAddress.lookup(host).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw const SocketException('DNS timed out'),
          );
    } on SocketException catch (e) {
      throw NetException('DNS lookup failed: ${e.message}', uri: uri);
    }
    if (resolved.isEmpty) {
      throw NetException('host did not resolve: $host', uri: uri);
    }
    for (final addr in resolved) {
      _validateAddress(addr, uri);
    }
  }

  static void _validateAddress(InternetAddress addr, Uri uri) {
    final raw = addr.address;
    if (addr.type == InternetAddressType.IPv4) {
      final p = raw.split('.').map(int.parse).toList();
      final loopback = p[0] == 127; // 127.0.0.0/8
      final unspecified = p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0;
      // private: 10/8, 172.16/12, 192.168/16; link-local: 169.254/16
      // (covers cloud metadata 169.254.169.254)
      final private = p[0] == 10 ||
          (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
          (p[0] == 192 && p[1] == 168) ||
          (p[0] == 169 && p[1] == 254);
      if (loopback || unspecified || private) {
        throw NetException('non-public address $raw not allowed', uri: uri);
      }
    } else {
      final h = raw.toLowerCase();
      final loopbackOrUnspecified = h == '::1' || h == '::';
      // link-local fe80::/10, unique-local fc00::/7
      final local = h.startsWith('fe8') || h.startsWith('fe9') ||
          h.startsWith('fea') || h.startsWith('feb') ||
          h.startsWith('fc') || h.startsWith('fd');
      if (loopbackOrUnspecified || local) {
        throw NetException('non-public address $raw not allowed', uri: uri);
      }
    }
  }
}

/// Internal: the direct lane saw a Cloudflare-shaped block and the gate
/// already promoted the host. `_run` re-dispatches onto the new lane.
class _CloudflareBlock implements Exception {
  const _CloudflareBlock(this.statusCode);
  final int statusCode;
}

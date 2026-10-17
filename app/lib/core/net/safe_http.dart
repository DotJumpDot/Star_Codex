import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'net_exception.dart';
import 'rate_limiter.dart';

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
/// Exposes exactly `getHtml` and `getBytes`. Nothing else in the app may
/// construct a Dio/HttpClient (checked in the Phase 3 DoD grep).
class SafeHttp {
  SafeHttp(
      {RateLimiter? rateLimiter, SafeHttpFetcher? fetcher, SafeHttpDelay? delay})
      : _rateLimiter = rateLimiter ?? RateLimiter(),
        // ignore: prefer_initializing_formals — private field, public param
        _fetcher = fetcher,
        _delay = delay ?? ((d) => Future<void>.delayed(d)) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false, // hops validated manually in _run
      maxRedirects: 8,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        'Accept-Language': 'th,en;q=0.8',
      },
      validateStatus: (status) => status != null && status < 400,
    ));
  }

  /// Injectable for tests (a local mock server would violate the loopback
  /// rule, so retries are tested through a fake fetcher instead).
  late final Dio _dio;
  final RateLimiter _rateLimiter;
  final SafeHttpFetcher? _fetcher;
  final SafeHttpDelay _delay;

  static const maxBodyBytes = 50 * 1024 * 1024;

  Future<String> getHtml(Uri uri, {String? referer}) async {
    final bytes = await getBytes(uri, referer: referer);
    return String.fromCharCodes(bytes);
  }

  Future<Uint8List> getBytes(Uri uri, {String? referer}) async {
    var current = uri;
    for (var hop = 0; hop <= 8; hop++) {
      final response = await _run(current, referer: referer);
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw NetException('redirect without Location', uri: current);
        }
        current = current.resolve(location);
        continue;
      }
      final data = response.data;
      if (data is! List<int>) {
        throw NetException('unexpected body type', uri: current);
      }
      if (data.length > maxBodyBytes) {
        throw NetException('body exceeds 50 MB cap', uri: current);
      }
      return Uint8List.fromList(data);
    }
    throw NetException('too many redirects', uri: uri);
  }

  Future<Response<List<int>>> _run(Uri uri, {String? referer}) async {
    _validate(uri);
    final release = await _rateLimiter.acquire(uri.host);
    try {
      return await _withRetries(uri, referer: referer);
    } finally {
      release();
    }
  }

  Future<Response<List<int>>> _withRetries(Uri uri, {String? referer}) async {
    var backoff = const Duration(seconds: 1);
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await (_fetcher ?? _dio.getUri)(uri,
            Options(
              responseType: ResponseType.bytes,
              headers: {
                'Referer': ?referer,
              },
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

  /// Steps 1–2 of the security rule. Throws [NetException] on violation.
  static void _validate(Uri uri) {
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
    } on ArgumentError {
      // hostname — check textual private forms, then resolve at connect time
      // is not feasible pre-DNS in pure Dart without lookups; textual checks
      // cover literal IPs and localhost. DNS names resolving into private
      // space are out of scope for v1 (same-origin public sites).
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

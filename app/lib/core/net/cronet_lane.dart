// Cronet lane of the WAF ladder (2026-10-23): Google's Cronet engine,
// embedded in the APK (android/app/build.gradle.kts), is Chromium's own
// network stack — requests carry a real Chrome TLS fingerprint at native
// speed. Sites that block ONLY on fingerprint (doujin-lc, miku-doujin —
// they serve 200 to anything that handshakes like Chrome) become
// reachable with no user interaction at all.
//
// Redirects are NOT followed here: the 3xx is returned to SafeHttp which
// re-validates and follows every hop itself (the same rule as the Dio
// lane — scheme + host validation before EVERY request).

import 'dart:io' show Platform;
import 'dart:typed_data' show BytesBuilder;

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

import 'net_exception.dart';
import 'waf_gate.dart';

class CronetLane {
  CronetLane();

  http.Client? _client;
  bool _initFailed = false;

  /// Android-only (the cronet-embedded .so is Android); the Dart test VM
  /// reports unavailable so unit tests exercise the ladder with fakes.
  bool get available => Platform.isAndroid && !_initFailed;

  Future<bool> ensure() async {
    if (_client != null) return true;
    if (!Platform.isAndroid) return false;
    try {
      final engine = CronetEngine.build(userAgent: wafBrowserUserAgent);
      _client = CronetClient.fromCronetEngine(engine, closeEngine: true);
      return true;
    } catch (_) {
      _initFailed = true;
      return false;
    }
  }

  /// Single GET, no redirect following. [extraHeaders] carries the
  /// WebView-relayed Cookie/User-Agent when a challenge host serves
  /// post-clearance traffic through this lane.
  Future<LaneResponse> fetch(Uri uri, {Map<String, String>? extraHeaders}) async {
    if (!await ensure()) {
      throw NetException('cronet engine unavailable', uri: uri);
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    extraHeaders?.forEach((name, value) => request.headers[name] = value);
    request.headers['accept-language'] = 'th,en;q=0.8';
    final streamed = await _client!.send(request).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw NetException('cronet timeout', uri: uri),
        );
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      if (builder.length > SafeHttpCaps.maxBodyBytes) {
        throw NetException('body exceeds 50 MB cap', uri: uri);
      }
    }
    return LaneResponse(
      status: streamed.statusCode,
      body: builder.takeBytes(),
      headers: {
        for (final e in streamed.headers.entries)
          e.key.toLowerCase(): e.value,
      },
    );
  }
}

/// Body cap shared with SafeHttp (kept here to avoid a circular import).
class SafeHttpCaps {
  static const maxBodyBytes = 50 * 1024 * 1024;
}

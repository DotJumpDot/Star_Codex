// WAF ladder (2026-10-23): some sources block the app's Dart TLS stack
// (Cloudflare fingerprinting) or sit behind an interactive "Just a
// moment..." JS challenge. Instead of one transport, each HOST climbs a
// ladder, learned at runtime from Cloudflare-shaped failures:
//
//   direct  → the normal Dio/dart:io path (fastest, 8 of 11 hosts)
//   cronet  → Chromium's own network stack: real Chrome TLS fingerprint
//             at native speed, invisible to the user. Defeats blocks that
//             ONLY fingerprint the client (doujin-lc, miku-doujin).
//   webview → a real WebView executes the JS challenge (the Android
//             equivalent of the desktop puppeteer/Playwright solvers),
//             then keeps fetching through it. Defeats interactive
//             challenge walls (dark-manga). Slower; last resort.
//
// Host state is per-app-session, monotonic (a host never demotes within
// a session) and fails fast for `retryAfter` after exhausting the ladder
// so a dead site doesn't add seconds to every feed refresh.

import 'dart:convert';

import 'cronet_lane.dart';
import 'webview_gate.dart';

/// Browser headers shared by every lane so a host sees one consistent
/// client. Kept current (Chrome 140, late 2026): a stale Chrome/126 UA
/// from 2024 is itself a bot signal.
const wafBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// A transport-level response from a non-Dio lane.
class LaneResponse {
  const LaneResponse({
    required this.status,
    required this.body,
    this.headers = const {},
  });

  final int status;
  final List<int> body;
  final Map<String, String> headers; // lowercase names
}

enum WafLane { direct, cronet, webview }

/// Coordinator for the per-host ladder. Lanes are injected; unavailable
/// tiers (non-Android, engine failure) are skipped automatically.
class WafGate {
  WafGate({CronetLane? cronet, WebviewGate? webview})
      // ignore: prefer_initializing_formals — private fields
      : _cronet = cronet,
        // ignore: prefer_initializing_formals — private field
        _webview = webview;

  final CronetLane? _cronet;
  final WebviewGate? _webview;
  final _lanes = <String, WafLane>{};
  final _exhaustedAt = <String, DateTime>{};

  /// Fail fast window after the ladder was exhausted for a host.
  static const retryAfter = Duration(minutes: 10);

  bool get hasCronet => _cronet?.available ?? false;
  bool get hasWebview => _webview != null;
  CronetLane? get cronet => hasCronet ? _cronet : null;
  WebviewGate? get webview => _webview;

  WafLane laneFor(String host) => _lanes[host] ?? WafLane.direct;

  /// Hosts whose ladder recently failed totally — callers can skip
  /// straight to the error path without re-probing every tier.
  bool recentlyExhausted(String host) {
    final at = _exhaustedAt[host];
    if (at == null) return false;
    if (DateTime.now().difference(at) > retryAfter) {
      _exhaustedAt.remove(host);
      return false;
    }
    return true;
  }

  /// Advance one tier, skipping unavailable ones. Returns the new lane,
  /// or null when the ladder is exhausted (which stamps the host).
  WafLane? escalate(String host) {
    switch (laneFor(host)) {
      case WafLane.direct:
        if (hasCronet) return _set(host, WafLane.cronet);
        if (hasWebview) return _set(host, WafLane.webview);
        return _exhaust(host);
      case WafLane.cronet:
        if (hasWebview) return _set(host, WafLane.webview);
        return _exhaust(host);
      case WafLane.webview:
        return _exhaust(host);
    }
  }

  WafLane _set(String host, WafLane lane) {
    _lanes[host] = lane;
    return lane;
  }

  WafLane? _exhaust(String host) {
    _exhaustedAt[host] = DateTime.now();
    return null;
  }

  /// A tier succeeded — clear the fail-fast stamp (the lane stays) and
  /// any pending manual-unlock marker.
  void noteSuccess(String host) {
    _exhaustedAt.remove(host);
    _webview?.clearNeedsUnlock(host);
  }

  /// True when a failure looks like a Cloudflare block/challenge rather
  /// than a genuine 403 from the site. Only consulted for 403/429/503;
  /// `challenge-platform` etc. also appear on HEALTHY Cloudflare pages,
  /// so a non-Cloudflare-served 403 without markers stays a real 403.
  static bool cloudflareSignature(
      int status, List<int>? body, Map<String, String> headers) {
    if (status != 403 && status != 429 && status != 503) return false;
    final server = (headers['server'] ?? '').toLowerCase();
    final bodyText = latin1
        .decode(body != null && body.length > 4096 ? body.sublist(0, 4096) : (body ?? const []),
            allowInvalid: true)
        .toLowerCase();
    const markers = [
      'just a moment',
      'attention required',
      'cf-chl',
      'cf_chl',
      'challenge-platform',
      'checking your browser',
      'cf-ray-id',
      'cloudflare ray id',
    ];
    final bodyMatches = markers.any(bodyText.contains);
    if (server.contains('cloudflare')) {
      // CF-served error: markers, or an error page footer, or a bare
      // body (fingerprint blocks sometimes return an empty 403).
      return bodyMatches ||
          bodyText.contains('cloudflare') ||
          (body ?? const []).isEmpty;
    }
    return bodyMatches;
  }
}

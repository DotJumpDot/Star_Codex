// WebView lane of the WAF ladder (2026-10-23): a real WebView executes
// Cloudflare's "Just a moment..." JS challenge — the Android equivalent
// of the desktop puppeteer/Playwright solvers. Research (2026-10-23): a
// cf_clearance cookie is bound to the TLS fingerprint + UA + IP that
// solved the challenge, so HTML fetches STAY inside the WebView instead
// of relaying the cookie back to Dart's stack. After the challenge is
// solved once, the cookie + the WebView's real User-Agent ARE relayed to
// the (Chrome-fingerprinted) cronet lane for byte traffic at native
// speed.
//
// Headless first: managed challenges auto-solve in a clean WebView
// within a few seconds, invisible to the user. If the challenge needs a
// human, [manualUnlock] (wired to the visible challenge dialog by the
// app shell) takes over — once per site until the cookie expires.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'net_exception.dart';
import 'waf_gate.dart';

/// Title/body markers of an uncleared Cloudflare challenge. Shared with
/// the visible challenge dialog.
const challengeMarkers = [
  'just a moment',
  'attention required',
  'checking your browser',
  'cf-chl',
];

bool looksChallenged(String? title, [String? html]) {
  final t = (title ?? '').toLowerCase();
  if (challengeMarkers.any(t.contains)) return true;
  if (html != null) {
    final h = html.toLowerCase();
    if (h.contains('cf-chl') && h.contains('challenge-platform')) return true;
  }
  return false;
}

class WebviewGate {
  WebviewGate();

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  Completer<void>? _navDone;
  String? _userAgent;
  Future<void> _tail = Future.value();

  /// Hosts whose challenge the headless WebView could NOT clear and
  /// which therefore wait for a manual unlock (settings → source row →
  /// lock icon). Reactive so the settings UI can show/hide the action.
  final ValueNotifier<List<String>> needsUnlock = ValueNotifier([]);

  /// Set by the app shell: shows the visible challenge dialog for [uri],
  /// resolves true when the challenge was cleared by the user.
  Future<bool> Function(Uri uri)? manualUnlock;

  bool get _ready => _controller != null;

  void _markNeedsUnlock(String host) {
    if (!needsUnlock.value.contains(host)) {
      needsUnlock.value = [...needsUnlock.value, host];
    }
  }

  void clearNeedsUnlock(String host) {
    if (needsUnlock.value.contains(host)) {
      needsUnlock.value =
          needsUnlock.value.where((h) => h != host).toList();
    }
  }

  /// Serializes WebView use — one page at a time through the single
  /// headless instance.
  Future<T> _serial<T>(Future<T> Function() task) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) => task()).whenComplete(done.complete);
  }

  Future<void> _boot() async {
    if (_ready) return;
    final created = Completer<void>();
    _headless = HeadlessInAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        // Cloudflare's own mobile docs: challenges fail when WebView
        // storage is restrictive or cleared between sessions.
        incognito: false,
        cacheEnabled: true,
        thirdPartyCookiesEnabled: true,
        // The DEFAULT WebView user agent stays: the clearance cookie is
        // bound to whatever UA solved the challenge, and overriding it
        // is a known way to break challenge solving.
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        created.complete();
      },
      onLoadStop: (controller, url) {
        final nav = _navDone;
        if (nav != null && !nav.isCompleted) nav.complete();
      },
    );
    await _headless!.run();
    await created.future.timeout(const Duration(seconds: 10));
  }

  /// Cookies (+ the WebView's real UA) for the cronet lane to reuse on
  /// challenge-cleared hosts. Empty until the challenge was solved once.
  Future<Map<String, String>> relayHeadersFor(Uri uri) async {
    if (!_ready) return const {};
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(uri.toString()),
      );
      if (cookies.isEmpty) return const {};
      final cookieHeader = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      return {
        'cookie': cookieHeader,
        'user-agent': ?_userAgent,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Fetch a page's HTML through the WebView, solving the challenge
  /// first when one is up. Throws [NetException] (403) when it cannot.
  Future<LaneResponse> fetchHtml(Uri uri,
      {bool allowManualUnlock = false}) async {
    await _boot();
    return _serial(() async {
      final cleared =
          await _loadUntilCleared(uri, allowManualUnlock: allowManualUnlock);
      if (!cleared) {
        throw NetException('cloudflare challenge not solved',
            uri: uri, statusCode: 403);
      }
      final html = await _controller!.evaluateJavascript(
          source: 'document.documentElement.outerHTML');
      if (html is! String || html.isEmpty) {
        throw NetException('webview returned no document', uri: uri);
      }
      return LaneResponse(
        status: 200,
        body: utf8.encode(html),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
  }

  Future<bool> _loadUntilCleared(Uri uri,
      {required bool allowManualUnlock}) async {
    final controller = _controller!;
    _userAgent ??= await _readUserAgent(controller);

    await _navigate(controller, uri);
    var cleared = await _waitCleared(const Duration(seconds: 15));
    if (cleared) {
      clearNeedsUnlock(uri.host);
      return true;
    }

    // The challenge wants a human (interactive Turnstile). Offer the
    // visible dialog once, then retry through the warm headless WebView.
    if (allowManualUnlock && manualUnlock != null) {
      final solved = await manualUnlock!(uri);
      if (solved) {
        // The visible dialog shares this app's CookieManager store, so
        // the clearance cookie is already in place.
        await _navigate(controller, uri);
        cleared = await _waitCleared(const Duration(seconds: 10));
        if (cleared) {
          clearNeedsUnlock(uri.host);
          return true;
        }
      }
    }
    _markNeedsUnlock(uri.host);
    return false;
  }

  Future<void> _navigate(InAppWebViewController controller, Uri uri) async {
    _navDone = Completer<void>();
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
    // The first onLoadStop = the challenge page (or content, if the
    // cookie is still warm). Polling titles BEFORE it would read the
    // PREVIOUS page — that stale-title false positive is why this wait
    // exists.
    try {
      await _navDone!.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // fall through to polling — some challenge reloads race the stop
    }
  }

  Future<bool> _waitCleared(Duration limit) async {
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      try {
        final title =
            await _controller!.evaluateJavascript(source: 'document.title');
        if (!looksChallenged(title is String ? title : null)) {
          return true;
        }
      } catch (_) {
        // page mid-navigation — keep polling
      }
    }
    return false;
  }

  Future<String?> _readUserAgent(InAppWebViewController controller) async {
    try {
      final ua = await controller
          .evaluateJavascript(source: 'navigator.userAgent');
      if (ua is String && ua.isNotEmpty) _userAgent = ua;
    } catch (_) {
      // relay headers stay empty — cronet then uses its engine UA
    }
    return _userAgent;
  }

  @visibleForTesting
  void debugReset() {
    _headless?.dispose();
    _headless = null;
    _controller = null;
    _userAgent = null;
  }
}

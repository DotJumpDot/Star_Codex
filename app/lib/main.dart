import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/i18n/i18n.dart';
import 'core/net/cronet_lane.dart';
import 'core/net/rate_limiter.dart';
import 'core/net/safe_http.dart';
import 'core/net/waf_gate.dart';
import 'core/net/webview_gate.dart';
import 'core/providers.dart';
import 'data/dao/settings_dao.dart';
import 'data/db.dart';
import 'data/sources/source_registry.dart';
import 'ui/webview/challenge_dialog.dart';

/// Doc 13 §A: Wi-Fi-only downloads (default ON) — mobile data keeps the
/// queue paused. Wi-Fi AND Ethernet count as unmetered.
Future<bool> isUnmeteredNow() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  } catch (_) {
    return true; // plugin unavailable → don't block downloads
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Webtoon pages decode at ~5–8 MB each (cacheWidth caps them at
  // screen resolution); the framework's 100 MiB default image cache
  // held only ~10, so scrolling back up re-decoded already-seen pages
  // (placeholder flash + jank, user report 2026-10-20). 500 MiB ≈ a
  // whole long chapter (Tyrant Dad ch.1 = 76 pages). The OS
  // memory-pressure signal still clears the whole cache
  // (PaintingBinding handles it), so a large cap is safe on
  // constrained devices.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 << 20;
  await I18nService.load();
  final db = await openDb();
  final libraryDir = await defaultLibraryDir();
  final initialSettings = await SettingsDao(db).getAll();
  // One shared limiter + http door for everything (review pass: a detached
  // RateLimiter would silently drop image-host registration). The WAF gate
  // lets Cloudflare-blocked hosts climb dio → cronet → webview
  // (PLAN_NOTES 2026-10-23); its manual-unlock tier pops the visible
  // challenge dialog through the global navigator key.
  final rateLimiter = RateLimiter();
  final wafGate = WafGate(cronet: CronetLane(), webview: WebviewGate());
  wafGate.webview!.manualUnlock = (uri) async {
    final context = appNavigatorKey.currentContext;
    if (context == null) return false;
    return showChallengeDialog(context, uri);
  };
  final http = SafeHttp(rateLimiter: rateLimiter, gate: wafGate);
  final sources = await loadSources(db, http);
  final container = ProviderContainer(overrides: [
    dbProvider.overrideWithValue(db),
    libraryDirProvider.overrideWithValue(libraryDir),
    initialSettingsProvider.overrideWithValue(initialSettings),
    rateLimiterProvider.overrideWithValue(rateLimiter),
    wafGateProvider.overrideWithValue(wafGate),
    safeHttpProvider.overrideWithValue(http),
    sourcesProvider.overrideWith((ref) => SourcesController(sources)),
    unmeteredCheckProvider.overrideWithValue(isUnmeteredNow),
  ]);
  // Cache janitor 10 s after app start (Plan/03 §LRU): startup pass includes
  // integrity (orphan/missing-file cleanup + doc-13 download demotion),
  // later runs are LRU-only.
  // Scheduled here (not in a widget) so tests never inherit a timer.
  Timer(const Duration(seconds: 10), () {
    container.read(cacheJanitorProvider).runNow(withIntegrity: true);
  });
  // Downloads worker: 1 s tick while the app runs (doc 13 §A — v1 has no
  // background service; the Offline tab says so).
  container.read(downloadsRepoProvider).start();
  // Updates check on open when stale (> 6 h, doc 13 §B) — fire and forget;
  // the bell feed refreshes itself.
  unawaited(container
      .read(updatesRepoProvider)
      .checkAll()
      .catchError((_) => 0));
  runApp(UncontrolledProviderScope(
    container: container,
    child: const StarCodexApp(),
  ));
}

import 'package:flutter/material.dart';

/// Global route observer (2026-10-28). Registered once on the root
/// navigator; screens subscribe to know when they become the top route
/// again after something above them popped.
///
/// Why: `openReader`'s future resolves at the FIRST reader→reader
/// handover (`pushReplacement` completes the original push), so the
/// detail screen's post-read `refreshProgress()` fired mid-reading and
/// never again — after a long drag-to-next session the chapter dots and
/// history came back stale until the screen was re-entered (user report
/// 2026-10-28). Detail now refreshes on didPopNext instead.
class StarRouteObserver extends NavigatorObserver {
  final _subscribers = <Route<dynamic>, Set<void Function()>>{};

  void onTopAgain(Route<dynamic> route, void Function() cb) {
    _subscribers.putIfAbsent(route, () => {}).add(cb);
  }

  void remove(Route<dynamic> route, void Function() cb) {
    _subscribers[route]?.remove(cb);
    if (_subscribers[route]?.isEmpty ?? true) _subscribers.remove(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Whatever re-emerged on top re-syncs (reader popped → detail).
    for (final cb in {...?_subscribers[previousRoute]}) {
      cb();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Covers push REPLACING after a pop-new... no-op on purpose; pops are
    // the only re-surface path that matters here.
  }
}

/// Shared instance wired into MaterialApp.navigatorObservers.
final starRouteObserver = StarRouteObserver();

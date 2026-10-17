import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// Per-host politeness queue (Plan/04 §4).
///
/// - strict (default): max 2 concurrent, 700 ms min gap between request
///   starts (+0–300 ms jitter)
/// - image-class hosts: max 4 concurrent, 200 ms gap — CDNs can take it
///
/// Hosts are classified by suffix match; new CDN domains observed in
/// ts_reader payloads are added at runtime via [registerImageHost].
class RateLimiter {
  RateLimiter({int? seed}) : _random = seed == null ? Random() : Random(seed);

  final Random _random;

  static const _strict = (concurrency: 2, minGapMs: 700);
  static const _image = (concurrency: 4, minGapMs: 200);

  /// Suffix-matched (`.flash-manga.com` matches `img3.flash-manga.com`);
  /// registered hosts also match exactly and on any subdomain.
  final Set<String> _imageHostSuffixes = {
    '.flash-manga.com',
    '.cdend.com',
  };

  final Map<String, _HostGate> _gates = {};

  void registerImageHost(String host) {
    _imageHostSuffixes.add(host.toLowerCase());
  }

  bool isImageHost(String host) {
    final h = host.toLowerCase();
    return _imageHostSuffixes.any((s) => h == s || h.endsWith(s));
  }

  /// Acquires the host slot (awaits until the request may start). Returns a
  /// release callback — always call it (use try/finally).
  Future<Future<void> Function()> acquire(String host) async {
    final gate = _gates.putIfAbsent(host.toLowerCase(), _HostGate.new);
    final rule = isImageHost(host) ? _image : _strict;
    final waiter = Completer<void>();
    gate.queue.add(waiter);
    _pump(gate, rule);

    await waiter.future;
    return () async {
      gate.inFlight--;
      _pump(gate, rule);
    };
  }

  void _pump(_HostGate gate, ({int concurrency, int minGapMs}) rule) {
    if (gate.timer?.isActive ?? false) return; // retry already scheduled
    while (gate.queue.isNotEmpty && gate.inFlight < rule.concurrency) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final wait = gate.lastStartAt + rule.minGapMs - now;
      if (wait <= 0) {
        gate.queue.removeFirst().complete();
        gate.inFlight++;
        gate.lastStartAt = now + _random.nextInt(300);
      } else {
        gate.timer = Timer(Duration(milliseconds: wait), () {
          gate.timer = null;
          _pump(gate, rule);
        });
        return;
      }
    }
  }
}

class _HostGate {
  final Queue<Completer<void>> queue = Queue();
  int inFlight = 0;
  int lastStartAt = 0;
  Timer? timer;
}

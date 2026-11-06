import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// DoH (DNS-over-HTTPS) fallback for resolver-level ISP blocks.
///
/// 2026-11-07: True Internet's resolver answers NXDOMAIN for
/// slow-manga.net — the site itself is fine (it resolves on 8.8.8.8 /
/// 1.1.1.1 and serves 200 when connected by IP). Every app transport
/// resolves through the OS, so the whole app saw "DNS lookup failed"
/// for that host. When the system resolver fails, [resolve] asks
/// cloudflare-dns.com, then dns.google, over HTTPS and caches the
/// answer; SafeHttp's connection factory then connects to that IP
/// while presenting the ORIGINAL hostname for TLS/SNI (certificates
/// still validate against the hostname).
///
/// Plan/04 §2 holds: only A records pointing at PUBLIC IPv4 addresses
/// are accepted — loopback/private/link-local answers are dropped even
/// if a DoH endpoint were tricked into returning them, and the TLS
/// handshake stays pinned to the real hostname (see PLAN_NOTES
/// 2026-11-07). This is part of the SafeHttp network door, not a
/// second one: it only runs after the system resolver already failed.
class DnsFallback {
  DnsFallback({Future<String?> Function(Uri)? fetchJson, DateTime Function()? clock})
      : _fetchJson = fetchJson ?? _defaultFetchJson,
        _now = clock ?? DateTime.now;

  /// Raw GET returning the body (null on any failure). Injectable for
  /// tests; the default speaks dart:io directly — routing it through
  /// SafeHttp would recurse back into DNS validation.
  final Future<String?> Function(Uri) _fetchJson;
  final DateTime Function() _now;

  final _cache = <String, _DohResult>{};
  final _inFlight = <String, Future<List<String>>>{};

  static const _ttl = Duration(minutes: 10);
  static const _negativeTtl = Duration(seconds: 60);

  static Future<String?> _defaultFetchJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(uri);
      req.headers.set('accept', 'application/dns-json');
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join();
    } catch (_) {
      return null; // endpoint unreachable → caller tries the next one
    } finally {
      client.close(force: true);
    }
  }

  /// Public IPv4s for [host] via DoH, cached (single-flight per host).
  /// Empty when every endpoint fails or answers nothing — the caller
  /// then surfaces its own DNS error. Only called after the SYSTEM
  /// resolver already failed.
  Future<List<String>> resolve(String host) {
    final key = host.toLowerCase();
    final cached = _freshCache(key);
    if (cached != null) return Future.value(cached);
    return _inFlight.putIfAbsent(
      key,
      () async {
        for (final uri in [
          Uri.https('cloudflare-dns.com', '/dns-query', {
            'name': key,
            'type': 'A',
          }),
          Uri.https('dns.google', '/resolve', {
            'name': key,
            'type': 'A',
          }),
        ]) {
          final body = await _fetchJson(uri);
          if (body == null) continue;
          final ips = parseDohAnswers(body);
          if (ips.isNotEmpty) {
            _cache[key] = _DohResult(ips, _now().add(_ttl));
            return ips;
          }
          // Status 0 with no usable answers = the DoH resolver itself
          // says the host is gone — try the second endpoint anyway.
        }
        _cache[key] = _DohResult(const [], _now().add(_negativeTtl));
        return const [];
      },
    ).whenComplete(() => _inFlight.remove(key));
  }

  /// Cached IP for the SafeHttp connection factory; null = the host has
  /// no live DoH answer (system DNS path, unchanged behavior).
  String? ipFor(String host) {
    final r = _freshCache(host.toLowerCase());
    return (r != null && r.isNotEmpty) ? r.first : null;
  }

  List<String>? _freshCache(String key) {
    final r = _cache[key];
    if (r == null) return null;
    if (_now().isAfter(r.expiresAt)) {
      _cache.remove(key);
      return null;
    }
    return r.ips;
  }
}

class _DohResult {
  const _DohResult(this.ips, this.expiresAt);

  final List<String> ips;
  final DateTime expiresAt;
}

/// A-record IPs out of a RFC 8484 JSON response
/// (`{"Status":0,"Answer":[{"name":…,"type":1,"data":"104.21.64.125"}…]}`),
/// keeping only PUBLIC IPv4s. Never throws: malformed bodies parse to
/// empty.
List<String> parseDohAnswers(String body) {
  Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (json is! Map<String, dynamic>) return const [];
  final answers = json['Answer'];
  if (answers is! List) return const [];
    final ips = <String>[];
    for (final a in answers) {
      if (a is! Map<String, dynamic>) continue;
      if (a['type'] != 1) continue; // A records only (no AAAA/CNAME)
      final data = a['data'];
      if (data is String && isPublicIpv4(data)) ips.add(data);
    }
    return ips;
  }

/// Same public-IPv4 rule as SafeHttp._validateAddress: rejects
/// loopback (127/8), unspecified (0.0.0.0), private (10/8, 172.16/12,
/// 192.168/16) and link-local incl. cloud-metadata (169.254/16).
bool isPublicIpv4(String raw) {
  final parts = raw.split('.');
  if (parts.length != 4) return false;
  final p = <int>[];
  for (final part in parts) {
    final v = int.tryParse(part);
    if (v == null || v < 0 || v > 255) return false;
    p.add(v);
  }
  final loopback = p[0] == 127;
  final unspecified = p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0;
  final private = p[0] == 10 ||
      (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
      (p[0] == 192 && p[1] == 168) ||
      (p[0] == 169 && p[1] == 254);
  return !loopback && !unspecified && !private;
}

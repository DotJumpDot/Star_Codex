# 04 — Source Framework (network layer + Source interface)

Everything the app knows about websites lives behind one interface. The
network layer below it enforces security, politeness, and retries.

## 1. Source interface

```dart
abstract class Source {
  String get id;            // 'slow-manga' ...
  String get name;          // display
  String get baseUrl;
  String get referer;       // sent as Referer on image/asset fetches
  bool get supportsNovels;  // only nekopost: true

  /// Search this source. Free-text, Thai or English.
  Future<List<SourceSeries>> search(String query, {int page = 1});

  /// Latest-updated series (browse home / updates).
  Future<List<SourceSeries>> latest({int page = 1});

  /// Full detail for a series URL: description, tags, type, status,
  /// alt titles, cover url, chapter list (ascending by number).
  Future<SourceSeriesDetail> detail(String sourceUrl);

  /// Ordered image URLs for one chapter URL. For novels: empty list +
  /// `novelText` instead.
  Future<ChapterPages> pages(String chapterUrl);

  /// Novel chapter body (nekopost only). Returns null for image sources.
  Future<String?> novelText(String chapterUrl);
}

class SourceSeries { String url, title; String? coverUrl; int chapterCountHint; }
class SourceSeriesDetail { title, altTitles[], description, tags[], type?, status?, coverUrl, chapters: List<SourceChapter>; }
class SourceChapter { String url, title; double number; int? uploadedAt; }
class ChapterPages { List<String> imageUrls; }
```

Adapters are dumb translators — no caching, no DB. Repos orchestrate
adapter → normalize (07) → DB.

## 2. `safe_http` — the ONLY network door (hard security rule)

All HTTP in the app goes through `core/net/safe_http.dart`. It must, in order:

1. Parse URL; **reject non-`http`/`https` schemes** immediately.
2. Resolve the host and **reject** before connecting:
   - `localhost`, any `*.localhost`
   - loopback (`127.0.0.0/8`, `::1`), unspecified (`0.0.0.0`, `::`)
   - private: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
     link-local `169.254.0.0/16`, `fe80::/10`, unique-local `fc00::/7`
   - cloud metadata `169.254.169.254` (covered by link-local, listed for clarity)
3. Default headers: desktop Chrome User-Agent, `Accept-Language: th,en;q=0.8`.
4. Follow redirects **but re-validate every redirect target** through steps 1–2.
5. Timeouts: connect 15 s, receive 30 s. Max response body 50 MB per request.

Implementation notes:
- Built on `dio`; the checks live in a `dio.Interceptor` (`onRequest` +
  `onError` for 3xx when following manually with `followRedirects: false`,
  or simply validate inside a custom `fetchBytes/fetchHtml` wrapper — the
  simpler wrapper approach is preferred; use one `Dio` instance per app).
- Expose exactly: `Future<String> getHtml(Uri, {String? referer})` and
  `Future<Uint8List> getBytes(Uri, {String? referer})`. Nothing else in the
  app creates a Dio/HttpClient. Enforce by code review + a lint grep in the
  phase DoD (`grep -r "Dio(" lib` returns only safe_http.dart).

## 3. Cookies / Cloudflare reality

These aggregator sites sometimes sit behind Cloudflare. v1 behavior:

- Dio with `CookieManager` (add `cookie_jar` + `dio_cookie_manager` packages)
  persisted to disk so session cookies survive restarts.
- If a response has status 403 **and** contains `cf-mitigated` header or the
  body contains `Just a moment...` / `challenge-platform`, throw
  `SourceException.cloudflare(sourceId)`.
- UI maps that to a card: "เว็บนี้ถูกบล็อกชั่วคราว (Cloudflare) — ลองใหม่ในภายหลัง"
  with a Retry button. A WebView-based cookie unblocker is a documented
  **future** fix, not v1 (note it in code comments, do not implement).

## 4. Rate limiting (politeness — do not hammer the sites)

`rate_limiter.dart`: per-host-name queue:

- Max **2 concurrent** requests per host.
- Min **700 ms** between request starts to the same host (+0–300 ms jitter).
- Image CDN hosts (`img*.flash-manga.com`, `image.cdend.com`, whatever
  `ts_reader`/API returns) get a relaxed rule: 4 concurrent, 200 ms gap —
  image hosts are CDNs, they can take it. Keep the rule table in one map
  `hostClass(host) -> {concurrency, minGap}`; default = strict.

## 5. Retries

- Retry on: network errors, 5xx, 429. Backoff 1s → 3s → 9s (+ jitter).
  Honor `Retry-After` if present. Max 3 attempts, then `SourceException`.
- Do NOT retry 403/404 (404 → clean "chapter not found" error).

## 6. Error model

```dart
class SourceException implements Exception {
  final String sourceId;
  final SourceErrorKind kind; // network, blocked (Cloudflare), notFound, parse, unknown
  final String? detail;
}
```

`parse` kind = the site's HTML changed → the adapter's parser failed. UI shows
"โครงสร้างเว็บเปลี่ยน (parse error)" — this is the signal to update the adapter.

## 7. Where adapters get their code

`data/sources/madara/` contains `madara_source.dart` (the shared engine) plus
`configs.dart` — a map of per-site tweaks (see 05). `data/sources/nekopost/`
contains `nekopost_source.dart` (see 06). Register all in
`data/sources/source_registry.dart` (list of `Source` instances seeded from
the `sources` table's enabled flag).

## Definition of Done

- [ ] `safe_http` unit tests: rejects `file://`, `ftp://`, `http://localhost`,
  `http://127.0.0.1`, `http://192.168.1.1`, `http://10.0.0.1`; allows public
  https. Redirect to private target is rejected.
- [ ] Rate limiter test: 5 rapid requests to one host do not exceed 2
  concurrent and observe the gap.
- [ ] Retry test: server 500 twice then 200 → succeeds on 3rd, total 3 calls.
- [ ] Only safe_http constructs Dio (grep check).

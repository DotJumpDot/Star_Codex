# HANDOFF — read this first in a new conversation

> Last updated 2026-10-24 (v1.4.3 release). Written originally 2026-10-17
> when the folder was renamed `C:\Code\Manga_Reader` → `C:\Code\StarCodex`.

## Where things stand

- **The app is built, QA'd, and released.** All 11 plan phases completed
  (2026-10-17), four user-driven UX rounds + the Doujin (18+) page
  landed (2026-10-18/19), and **v1.0.0 → v1.4.3 are live on GitHub
  Releases** (release-signed `StarCodex-<version>.apk`).
- **ALL 11 sources are live and enabled by default** (db v9): main feed
  = go-manga, slow-manga, up-manga, dark-manga, fin-manga (Madara/ts),
  bully-manga (custom engine), nekopost (API + novels); Doujin 18+ page
  = ntr-manga, hentaithai, doujin-lc, miku-doujin. The last two were
  unreachable from v1 to v1.3.1 (Cloudflare) — the **WAF ladder**
  (2026-10-23, bc469e5) unlocks them: per-host direct (Dio) → cronet
  (embedded Chromium TLS) → webview (headless challenge solver + the
  settings lock-icon manual tier). SQLite is at schema v9. 276 tests
  green, analyze clean. Invariants: PLAN_NOTES 2026-10-23 (four
  sections: WAF ladder, hentaithai /page-N, tooling note, grid-label
  generation-time anchor).
- **v1.4.3 (e02914c/a549622/20fbd53/bbda11d/d9119b6)**: the five-fix
  round from the user's phone + emulator QA. (1) MIUI bars re-show
  after reader→reader switches: readers re-assert the bars state when
  the entrance animation settles + once more ~900 ms later
  (`_reassertTimer`), the dispose wakelock disable is
  handover-guarded, successors apply their own keep-awake explicitly —
  and the post-batch review pass caught the resulting novel-reader
  wakelock leak (novel dispose now disables unconditionally). CONFIRMED on-phone
  2026-10-24 (user: "no system tab bug now"). (2) Sticky feed time anchors (db v10
  `feed_anchors` + `stickyStamp`): an unchanged chapter hint keeps the
  OLDER stamp so fin/dark stale WP-cache copies ("2 นาที" for 10+ h)
  can no longer re-freeze the label; changed/first-seen re-anchors.
  (3) Cover blob-future hash guard on history/offline/updates/detail
  (recycled rows showed another series' art). (4) up-manga +
  dark-manga search re-enabled (the WAF ladder carries the challenged
  `?s=`). (5) Reader chrome subtitle = "ตอนที่ N <name> · จาก
  <source>" (loose Flexible, source never truncates) + browse search
  ✕. Plus bbda11d: search cards show intro text (materialize class 3,
  cap 20/pass unmemoized + sibling description fallback ≤2 tries).
  Emulator black screen root-caused to a restored-snapshot GL
  corruption — boot-emu.bat always cold-boots now. 290 tests.
- **v1.4.2 (657dd74/ac98007/3ee819d/a00ef55)**: reader pull polish —
  the dot-trail indicator now sits in the space the page slide opens
  (the side the next/prev chapter enters from, LTR and RTL; it used to
  draw over the artwork on the opposite edge), and the arm threshold
  is tuned down against the shipped build: 160 px in the paged
  (side-slide) reader, 200 px in webtoon and novel (was 400/420/300 —
  friction-damped overscroll made the old values need far too much
  finger travel, and with the slide + visible trail a shallow arm is
  safe). The webtoon/novel lowering (ac98007) and the paged 160 tune
  (3ee819d) arrived in same-session follow-ups and the v1.4.2 asset
  was REPLACED in place each time (same tag/versionCode —
  uninstall-once caveat in the notes). Review pass skipped by user
  request for all batches ("u change just little if test pass that
  ok").
- **v1.4.1 (a780836/d0f4282)**: browse/search card dates froze at the
  site's cache-generation labels ("4 วินาที" for days on fin/up) — the
  ts homepages ride WP Fastest Cache behind the Cloudflare edge
  (186-day TTL, probed) and our parser re-anchored the cached labels at
  fetch time, which also dodged the 6 h stale re-check. Fix:
  `SafeHttp.getHtmlPage` returns response headers;
  `pageGenerationMs` (Last-Modified, else Date−Age) anchors the grid
  labels at the page's true generation moment. Emulator-verified: ages
  tick in real time, newest chapter holds the top slot, search filter
  accurate. Invariants: PLAN_NOTES 2026-10-23 (anchor section).
- **v1.3.1 → v1.4.0 batches**: the chapter read-state indicator +
  reader chrome carry-over (v1.3.1); the Webtoon-style pull-to-switch
  rework (slide + dot trail, bidirectional, smooth fall-back —
  c1abab3); fin-manga WPFC covers; the WAF ladder + db v9; hentaithai
  /page-N feed paging (860ceeb); the pre-release review pass
  (86f6a80: WebView boot single-flight/cleanup, error contracts,
  stale-page double-check, hentaithai genre-browse union parse).
- **Open technical item: bully-manga's feed order** still differs from
  its site — its engine is custom markup, so the grid-head treatment
  needs its own port there (the ts sites are all done).
- **The fat release APK is 109 MB** (cronet-embedded ≈ 8 MB/ABI × 4) —
  split-ABI APKs are worth doing next release (runbook change +
  README download wording).
- **Remaining work = whatever the user asks for in chat.** There is no
  open phase. The user drives batches; land them with the checklist
  commit + push discipline (AGENTS.md → Git discipline), one CHANGELOG
  line per batch, and a big-model review pass after each batch.
- The original build plan (Docs/Plan/, 16 documents) is now historical
  reference; [`Plan/00-DECISIONS.md`](./Plan/00-DECISIONS.md) still wins
  as the contract, and [`Docs/PLAN_NOTES.md`](./PLAN_NOTES.md) carries
  everything learned after the plan (source quirks, migrations, cover
  fallbacks, probe matching, the Cloudflare fingerprint blocks) — read
  its newest sections first.

## Project in 3 lines

**Star Codex** = Flutter Android app (Thai-first UI) reading from 7 live
Thai manga/novel sources in the main feed (5× WordPress-Madara/ts +
bully-manga custom engine + nekopost API incl. novels) plus a separate
Doujin 18+ page with 2 more live (ntr-manga, hentaithai) — 9 live in
total. Reading is streaming like a website; viewed
pages silently cache as WebP q80, content-hash deduplicated. Navigation:
left drawer — Browse / Doujin 18+ / Library / History / Offline /
Settings. Personal local use only — no server, no cloud, no login.

## What to tell the new conversation

Use a prompt like this (GLM 5.3 Flash or any model):

```
Read C:\Code\StarCodex\AGENTS.md, then Docs\HANDOFF.md and
Docs\PLAN_NOTES.md. Check git log + CHANGELOG.md for where things stand,
then do what I ask in chat. Land every batch with the checklist commit +
push, and keep the full test suite green.
```

## Release recipe (short)

Full runbook: [`Docs/RELEASING.md`](./RELEASING.md).

1. Version: `app/pubspec.yaml` (`x.y.z+N`) AND the About string in
   `settings_storage_sources.dart` (`AboutSection.appVersion`), CHANGELOG
   line.
2. `flutter build apk --release` → verify with `build-tools/*/apksigner.bat
   verify --print-certs` (expect CN=Star Codex, O=DotJumpDot).
3. Copy to `StarCodex-<version>.apk`, SHA-256 it, write English notes to
   a TEMP file via the Write tool (heredocs mangle; the mimosa hook
   blocks shell-written files).
4. Commit + push (the release commit is what the tag points at).
5. `GH_TOKEN=$(printf "protocol=https\nhost=github.com\n\n" |
   git credential fill | grep ^password= | cut -d= -f2)` →
   `gh release create v<version> <apk> --title … --notes-file …` —
   this CREATES the tag on the current HEAD, so no manual `git tag`,
   then DELETE the staged APK copy at the repo root (never commit it).

Debug installs must be uninstalled before a release build installs
(signature mismatch) — the release notes carry that warning.

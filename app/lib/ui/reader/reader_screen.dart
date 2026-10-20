import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ScrollCacheExtent;
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import 'reader_actions.dart';
import '../../core/settings_provider.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/reader_repo.dart';
import '../detail/detail_screen.dart';
import 'chapter_picker_sheet.dart';
import 'page_slot.dart';
import 'pull_next.dart';
import 'reader_chrome.dart';
import 'reader_drawer.dart';
import 'reader_progress.dart';
import 'reader_router.dart';
import 'reader_settings_body.dart';

/// Webtoon reader (doc 10) — vertical streaming, prefetch ahead, chrome
/// toggle, continuous progress, drag-past-the-end "pull to continue" with
/// resistance (replaced the 3 s countdown), per-page source fallback
/// (07 §5), controls in the right-hand drawer.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.chapter});

  final Chapter chapter;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  LoadedChapter? _loaded;
  bool _failed = false;
  List<double> _heights = const [];
  String? _seriesTitle;
  int _currentPage = 0;
  bool _chromeVisible = true;

  /// Scaffold key — the chrome's menu button must open the end drawer via
  /// the KEY, not Scaffold.of(): the callback's context sits ABOVE the
  /// Scaffold this screen builds, so Scaffold.of can never find it.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Drag-past-the-end state: the next chapter (or null at the very end)
  /// is resolved once, lazily, while parked at the end.
  Chapter? _next;
  bool _nextKnown = false;
  bool _nextLookup = false;
  final _pull = PullNextTracker();
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  final _scroll = ScrollController();

  /// In-flight page futures for THIS chapter. Without the memo, the
  /// seed-prefetch and the slot's own build both resolve the early pages
  /// — and the pipeline only dedups AFTER downloading, so that was 2x
  /// network for every first screen. Successes stay memoized for the
  /// screen's lifetime; failures are evicted so Retry works.
  final _inflight = <int, Future<PageFile>>{};

  /// Resolved PageFiles for this chapter session. Scrolling away
  /// DISPOSES slots; without this, rebuilding one on the way back up
  /// always started from an unresolved FutureBuilder → a spinner frame
  /// on every already-seen page (user report 2026-10-20). Passed back
  /// into the slot as `initial` so the first frame renders the image.
  final _pageFiles = <int, PageFile>{};

  /// Running average aspect of this chapter's resolved pages. First
  /// reads start every slot on the 1.9 constant — on sources whose
  /// strips run much taller (fin-manga report, 2026-10-20) the estimate
  /// error was huge and every correction visibly shifted the list.
  /// As pages resolve, estimates converge to the chapter's real shape.
  double _observedAspectSum = 0;
  int _observedAspectCount = 0;

  /// Slot REBUILDS re-fire onDimensions off the memoized resolve —
  /// without this set, a page scrolled past N times would weigh N× in
  /// the running average (review pass 2026-10-20).
  final _aspectCounted = <int>{};

  bool get _keepAwake =>
      ref.read(settingsProvider).getBool('reader_keep_awake', true);
  bool get _autoNext =>
      ref.read(settingsProvider).getBool('reader_auto_next', true);
  int get _prefetchAhead =>
      ref.read(settingsProvider).getInt('reader_prefetch_ahead', 6);

  ReaderRepo get _repo => ref.read(readerRepoProvider);

  /// Platform-channel calls are cosmetic in unit tests (no handler) —
  /// failures are swallowed so the reader still works in widget tests.
  Future<void> _setImmersive(bool on) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  Future<void> _setAwake(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _setImmersive(true);
    if (_keepAwake) _setAwake(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      final loaded = await _repo.loadChapter(widget.chapter);
      final series = await ref
          .read(seriesDaoProvider)
          .byId(loaded.chapter.seriesId);
      // Doc 10 DoD: reopen resumes at the saved page (±1). Completed
      // chapters restart from the top.
      final progress =
          await ref.read(chaptersDaoProvider).progress(loaded.chapter.id!);
      if (!mounted) return;
      setState(() {
        _failed = false;
        _loaded = loaded;
        _seriesTitle = series?.title;
        _heights = [
          for (final p in loaded.pages) _estimatedHeight(p),
        ];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (progress != null && !progress.completed && progress.pageIndex > 0) {
          final offsets = slotOffsets(_heights);
          final idx = progress.pageIndex.clamp(0, offsets.length - 1);
          _scroll.jumpTo(
              offsets[idx].clamp(0.0, _scroll.position.maxScrollExtent));
          _currentPage = idx;
        }
      });
      _seedPrefetch();
    } catch (e) {
      if (kDebugMode) debugPrint('READER open FAIL $e');
      if (!mounted) return;
      setState(() {
        _loaded = null;
        _failed = true;
      });
    }
  }

  double _estimatedHeight(ReaderPageRef p) =>
      p.hasDims
          ? _slotWidth * p.height! / p.width!
          : _slotWidth *
              (_observedAspectCount >= 3
                  ? _observedAspectSum / _observedAspectCount
                  : PageSlot.estimatedAspect);

  double get _slotWidth => MediaQuery.sizeOf(context).width;

  /// Seed pages [0..5] into the queue (doc 10 §Prefetch), then keep
  /// [ _prefetchAhead ] pages moving as the user scrolls (the setting
  /// actually drives prefetch; cacheExtent alone is fixed at ~2 screens).
  void _seedPrefetch() {
    final loaded = _loaded;
    if (loaded == null) return;
    for (var i = 0;
        i < loaded.pages.length && i <= 5;
        i++) {
      _resolvePage(i);
    }
    _prefetchFrom(0);
  }

  void _prefetchFrom(int page) {
    final loaded = _loaded;
    if (loaded == null) return;
    for (var k = 1; k <= _prefetchAhead; k++) {
      final i = page + k;
      if (i >= loaded.pages.length) break;
      _resolvePage(i); // memoized — already-fetched pages are free
    }
  }

  /// One page via the shared resolver: disk → own source → sibling
  /// sources (07 §5), badge the fallback source.
  Future<PageFile> _resolvePage(int idx) {
    final existing = _inflight[idx];
    if (existing != null) return existing;
    final loaded = _loaded!;
    final future = _repo.resolvePage(loaded, idx, onFallback: (sourceId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tFmt(
            context, 'reader.fallback_source', {'source': sourceId})),
        duration: const Duration(seconds: 2),
      ));
    }).then<PageFile>((pf) {
      _pageFiles[idx] = pf;
      return pf;
    }, onError: (Object e) {
      _inflight.remove(idx);
      throw e;
    });
    _inflight[idx] = future;
    return future;
  }

  void _onDimensions(int idx, int? w, int? h) {
    if (w == null || h == null || w <= 0 || !mounted) return;
    if (idx >= _heights.length) return;
    final aspect = h / w;
    if (_aspectCounted.add(idx)) {
      _observedAspectSum += aspect;
      _observedAspectCount++;
    }
    final exact = _slotWidth * aspect;
    if ((exact - _heights[idx]).abs() < 1) return;
    // Anchor preservation: when the corrected slot sits ABOVE the
    // viewport (the scroll-back-up case), shifting the offset by the
    // same delta keeps the visible pages under the finger — without
    // this, unmeasured pages above growing to real heights shove the
    // viewport content down: the feed feels stuck, then jumps.
    final adjust = heightAnchorDelta(
        slotOffsets(_heights), _heights, idx, exact - _heights[idx],
        _scroll.hasClients ? _scroll.offset : 0);
    if (adjust != 0 && _scroll.hasClients) {
      final raw = _scroll.offset + adjust;
      if (raw >= 0 && raw <= _scroll.position.maxScrollExtent) {
        // Shift BEFORE the relayout frame: the frame that first sees the
        // new height also sees the moved offset, so content stays pinned
        // with NO intermediate shifted frame. Doing this post-frame left
        // one rendered frame of shifted content — the "jerky shake" while
        // flinging through first-read chapters (fin-manga report,
        // 2026-10-20). Only legal when the target fits the CURRENT
        // extent; otherwise fall through to the post-frame path.
        _scroll.jumpTo(raw);
        setState(() => _heights[idx] = exact);
        return;
      }
    }
    setState(() => _heights[idx] = exact);
    if (adjust != 0 && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = (_scroll.offset + adjust)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        if ((target - _scroll.offset).abs() >= 1) _scroll.jumpTo(target);
      });
    }
  }

  bool get _atEnd {
    if (!_scroll.hasClients) return false;
    return reachedEnd(_scroll.offset, _scroll.position.maxScrollExtent,
        _scroll.position.viewportDimension);
  }

  void _onScroll() {
    final loaded = _loaded;
    if (loaded == null || !_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final offsets = slotOffsets(_heights);

    final page = currentPageIndex(
        offsets, _heights, _scroll.offset, viewport);
    if (page != _currentPage) {
      setState(() => _currentPage = page);
      _prefetchFrom(page);
    }

    // Completed: within one viewport of the end (doc 10 §5), throttled
    // DB write at 500 ms (partial positions save continuously).
    final now = DateTime.now();
    final completed = reachedEnd(
        _scroll.offset, _scroll.position.maxScrollExtent, viewport);
    if (now.difference(_lastSave) >= const Duration(milliseconds: 500)) {
      _lastSave = now;
      _saveProgress(page, completed: completed);
    }
    if (completed) {
      _ensureNext();
    } else if (_pull.dragging) {
      setState(() => _pull.cancel());
    }
  }

  /// Overscroll past the bottom edge while parked at the end = the
  /// drag-to-continue pull (ClampingScrollPhysics fires Overscroll
  /// notifications during the active drag only). Negative deltas (the
  /// finger dragging back) shrink an in-progress pull so the indicator
  /// follows both directions.
  void _onOverscroll(double overscroll) {
    if (!_autoNext || !_atEnd) return;
    if (overscroll <= 0) {
      if (_pull.dragging) setState(() => _pull.add(overscroll));
      return;
    }
    _ensureNext();
    setState(() => _pull.add(overscroll));
  }

  /// Fingers up: past the threshold → advance; otherwise the pull
  /// springs back. Also the parked-at-end completion save point.
  Future<void> _onScrollEnd() async {
    final loaded = _loaded;
    if (loaded == null || !_scroll.hasClients) return;
    if (reachedEnd(_scroll.offset, _scroll.position.maxScrollExtent,
        _scroll.position.viewportDimension)) {
      _saveProgress(_currentPage, completed: true);
    }
    if (!_pull.dragging) return;
    final go = _pull.release();
    setState(() {});
    if (!go) return;
    await _ensureNext();
    if (!mounted) return;
    final next = _next;
    if (next != null) _goTo(next);
  }

  /// Resolve the next chapter once (guarded against re-entrant lookups).
  Future<void> _ensureNext() async {
    if (_nextKnown || _nextLookup || _loaded == null) return;
    _nextLookup = true;
    final next = await _repo.adjacentChapter(_loaded!.chapter, forward: true);
    _nextLookup = false;
    if (!mounted) return;
    _next = next;
    _nextKnown = true;
    if (_pull.dragging) setState(() {});
  }

  Future<void> _saveProgress(int page, {required bool completed}) async {
    final loaded = _loaded;
    if (loaded == null) return;
    await persistReaderProgress(ref, loaded.chapter,
        pageIndex: completed ? loaded.pages.length - 1 : page,
        completed: completed);
  }

  /// Chapter switch = replace this route with the same reader, scroll
  /// reset (doc 10 §6).
  void _goTo(Chapter next) {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(chapter: next),
    ));
  }

  Future<void> _jumpTo(int idx) async {
    final offsets = slotOffsets(_heights);
    final target = (idx < offsets.length ? offsets[idx] : 0.0)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _setImmersive(false);
    _setAwake(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      endDrawerEnableOpenDragGesture: false,
      endDrawer: loaded == null ? null : _buildDrawer(loaded),
      body: Stack(
        children: [
          if (loaded == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_failed) const CircularProgressIndicator(),
                  if (!_failed) const SizedBox(height: 12),
                  Text(
                      _failed
                          ? t(context, 'common.error.title')
                          : t(context, 'common.loading'),
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(t(context, 'common.retry')),
                    onPressed: () {
                      setState(() {
                        _loaded = null;
                        _failed = false;
                      });
                      _open();
                    },
                  ),
                ],
              ),
            )
          else ...[
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification) _onScroll();
                if (n is OverscrollNotification) {
                  _onOverscroll(n.overscroll);
                }
                if (n is ScrollEndNotification) {
                  // Keep the end-state handling off the notification path
                  // (it awaits chapter lookups).
                  _onScrollEnd();
                }
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                // ~5 viewports: slots (and their height fix-ups) resolve
                // well before entering the viewport, so first-read
                // corrections shift content the user can't see yet.
                scrollCacheExtent: ScrollCacheExtent.pixels(4500),
                itemCount: loaded.pages.length,
                itemBuilder: (context, i) => PageSlot(
                  ref: loaded.pages[i],
                  screenWidth: _slotWidth,
                  resolve: () => _resolvePage(i),
                  onDimensions: _onDimensions,
                  // Session memo: a slot rebuilt on the way back up
                  // renders its image on the FIRST frame — no spinner.
                  initial: _pageFiles[i],
                  observedAspect: _observedAspectCount >= 3
                      ? _observedAspectSum / _observedAspectCount
                      : null,
                ),
              ),
            ),
            // Middle-60% tap toggles chrome (doc 10 §6).
            Positioned.fill(
              child: Row(
                children: [
                  const Expanded(flex: 2, child: SizedBox.expand()),
                  Expanded(flex: 6, child: _tapZone(() {
                    setState(() => _chromeVisible = !_chromeVisible);
                  })),
                  const Expanded(flex: 2, child: SizedBox.expand()),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ReaderChrome(
                visible: _chromeVisible,
                title: _seriesTitle ?? widget.chapter.title ?? '',
                sourceName: loaded.chapter.sourceId,
                onBack: () => Navigator.of(context).pop(),
                onTitle: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        DetailScreen(seriesId: loaded.chapter.seriesId),
                  ));
                },
                onChapters: () => _openChapterPicker(loaded),
                onMenu: () =>
                    _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ),
            if (_pull.dragging)
              Positioned(
                bottom: 90,
                left: 0,
                right: 0,
                child: Center(
                  child: PullNextIndicator(
                    progress: _pull.progress,
                    armed: _pull.armed,
                    hasNext: !_nextKnown || _next != null,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawer(LoadedChapter loaded) {
    final settings = ref.read(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final seriesId = loaded.chapter.seriesId;
    return ReaderControlDrawer(
      pageText: tFmt(context, 'reader.page', {
        'n': '${_currentPage + 1}',
        'total': '${loaded.pages.length}',
      }),
      progress: loaded.pages.length <= 1
          ? 0
          : _currentPage / (loaded.pages.length - 1),
      canPrev: true,
      canNext: true,
      onPrev: () async {
        final prev =
            await _repo.adjacentChapter(loaded.chapter, forward: false);
        if (!mounted) return;
        if (prev != null) _goTo(prev);
      },
      onNext: () async {
        final next =
            await _repo.adjacentChapter(loaded.chapter, forward: true);
        if (!mounted) return;
        if (next != null) {
          _goTo(next);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t(context, 'reader.end'))));
        }
      },
      onChapters: () => _openChapterPicker(loaded),
      onSeek: (v) {
        final total = loaded.pages.length;
        _jumpTo((v * (total - 1)).round());
      },
      settings: ReaderSettingsBody(
        prefetchAhead: settings.getInt('reader_prefetch_ahead', 6),
        keepAwake: settings.getBool('reader_keep_awake', true),
        autoNext: settings.getBool('reader_auto_next', true),
        rtl: settings.getBool('reader_rtl', false),
        mode: settings.get('reader_mode_$seriesId', 'auto'),
        onMode: (m) {
          controller.set('reader_mode_$seriesId', m);
          unawaited(_applyModeChange(loaded, chosen: m));
        },
        onChanged: (prefetch, awake, autoNext, rtl) {
          controller.set('reader_prefetch_ahead', '$prefetch');
          controller.set('reader_keep_awake', awake ? '1' : '0');
          controller.set('reader_auto_next', autoNext ? '1' : '0');
          controller.set('reader_rtl', rtl ? '1' : '0');
          _setAwake(awake);
        },
      ),
    );
  }

  Widget _tapZone(VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: const SizedBox.expand(),
      );

  /// Persist where we are, then swap this route for the freshly resolved
  /// reader when the mode actually changes screens (no-op otherwise).
  /// [chosen] is the mode JUST picked — SettingsController.set only
  /// publishes after its DB write, so re-reading the provider here can
  /// still see the old value and the swap would silently no-op.
  Future<void> _applyModeChange(LoadedChapter loaded,
      {required String chosen}) async {
    await _saveProgress(_currentPage, completed: _atEnd);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    await replaceWithResolvedReader(context,
        chapter: loaded.chapter,
        current: ReaderMode.webtoon,
        seriesDao: ref.read(seriesDaoProvider),
        modeOverride: effectiveModeOverride(
            chosen, settings.get('reader_mode_default', 'auto')));
  }

  Future<void> _openChapterPicker(LoadedChapter loaded) async {
    final vm = await ref
        .read(seriesRepoProvider)
        .load(loaded.chapter.seriesId);
    if (!mounted) return;
    await showChapterPicker(
      context,
      ref,
      vm: vm,
      current: loaded.chapter,
      onPick: (chapter, sourceId) => _goTo(chapter),
    );
  }
}

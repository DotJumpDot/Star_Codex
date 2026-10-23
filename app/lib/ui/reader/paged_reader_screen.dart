import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/reader_repo.dart';
import '../detail/detail_screen.dart';
import 'chapter_picker_sheet.dart';
import 'pull_next.dart';
import 'reader_actions.dart';
import 'reader_chrome.dart';
import 'reader_drawer.dart';
import 'reader_router.dart';
import 'reader_settings_body.dart';

/// Paged reader (doc 11 A): horizontal PageView for manga-style pages,
/// double-tap zoom + pan (ExtendedImage gesture), tap zones active only at
/// scale 1, drag past the last page (with resistance + indicator) → next
/// chapter. Controls live in the right-hand drawer.
class PagedReaderScreen extends ConsumerStatefulWidget {
  const PagedReaderScreen({
    super.key,
    required this.chapter,
    this.chromeVisible = true,
  });

  final Chapter chapter;

  /// Whether the chrome starts VISIBLE. Carried across a chapter switch
  /// so hiding it in one chapter keeps it hidden in the next (user
  /// request 2026-10-22).
  final bool chromeVisible;

  @override
  ConsumerState<PagedReaderScreen> createState() => _PagedReaderScreenState();
}

class _PagedReaderScreenState extends ConsumerState<PagedReaderScreen> {
  LoadedChapter? _loaded;
  bool _failed = false;
  String? _seriesTitle;
  int _page = 0;
  late bool _chromeVisible = widget.chromeVisible;
  bool _switching = false;

  /// Pending "on reading" marker (armed on open, fired after
  /// [kStartedMarkerDelay]); cancelled when the chapter finishes.
  Timer? _startedTimer;

  /// See the webtoon reader: pops restore the system bars at
  /// reverse-start (not dispose) so the revealed page doesn't shift.
  bool _barsHidden = false;
  Animation<double>? _routeAnimation;
  bool _routeHooked = false;

  /// True while the CURRENT page's image is zoomed in (user report
  /// 2026-10-21: while zoomed, stray drags slipped into page slides).
  /// PageView physics freeze until the image returns to 1x — the zoomed
  /// image pans inside its slot instead.
  bool _pageZoomed = false;

  /// True while TWO pointers are down (pinch intent): page slides never
  /// win then — the other failure mode from the same report (a pinch's
  /// first sideways motion let the PageView steal the gesture and flip
  /// the page). Page turns are one-finger swipes / tap zones.
  bool _pinchHold = false;
  int _activePointers = 0;

  /// See the webtoon reader: the drawer opens via the KEY (the chrome's
  /// callback context sits above this Scaffold).
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Drag-past-the-edge state (horizontal pull, rtl-aware arrow). The
  /// pull is signed: past the LAST page → next chapter, past the FIRST
  /// page → previous (user request 2026-10-23).
  // 160 (2026-10-23: user tuned 400 → 200 → 160 against the shipped
  // build — with the slide + visible trail a shallow arm is safe now,
  // unlike the pre-rework 160 that tripped blind).
  final _pull = PullChapterTracker(threshold: 160);

  /// Scroll offset sampled during an active pull — the delta between
  /// samples shrinks the pull once the finger reverses back into
  /// content (see _onPixels).
  double? _pullPixels;
  Chapter? _next;
  bool _nextKnown = false;
  bool _nextLookup = false;
  Chapter? _prev;
  bool _prevKnown = false;
  bool _prevLookup = false;

  /// Created in [_open] once the saved page is known (doc 11 DoD:
  /// progress resumes in both modes). Null while loading.
  PageController? _pageController;

  /// Per-page gesture keys (QA on-device 2026-10-18: ONE shared key was
  /// reused by every PageView child — a duplicate GlobalKey assert fired
  /// on the first page turn (2 slots alive mid-animation) and froze the
  /// whole build pipeline: taps dead, frame stuck at 1/N).
  final _slotKeys = <int, GlobalKey<ExtendedImageGestureState>>{};
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// In-flight/finished page futures for THIS chapter. PageView rebuilds
  /// slot State on every page turn (off-screen children are disposed), so
  /// without the memo every turn — including going BACK — re-resolved the
  /// page and flashed the loading spinner (user report 2026-10-19).
  /// Successes stay memoized for the screen's lifetime; failures are
  /// evicted so Retry works.
  final _inflight = <int, Future<PageFile>>{};

  int get _prefetchAhead =>
      ref.read(settingsProvider).getInt('reader_prefetch_ahead', 6);

  bool get _rtl => ref.read(settingsProvider).getBool('reader_rtl', false);
  bool get _autoNext =>
      ref.read(settingsProvider).getBool('reader_auto_next', true);
  bool get _keepAwake =>
      ref.read(settingsProvider).getBool('reader_keep_awake', true);

  ReaderRepo get _repo => ref.read(readerRepoProvider);

  Future<void> _setImmersive(bool on) async {
    _barsHidden = on;
    try {
      await SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
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
      final progress = await ref
          .read(chaptersDaoProvider)
          .progress(loaded.chapter.id!);
      final initial = progress != null && !progress.completed
          ? progress.pageIndex.clamp(0, loaded.pages.length - 1)
          : 0;
      if (!mounted) return;
      setState(() {
        _failed = false;
        _loaded = loaded;
        _seriesTitle = series?.title;
        _page = initial;
        _pageController = PageController(initialPage: initial);
      });
      _pageController!.addListener(_onPixels);
      _prefetchFrom(initial);
      // "On reading" marker — a chapter left open for a couple of
      // seconds counts as started (user request 2026-10-22).
      _startedTimer?.cancel();
      _startedTimer = armStartedMarker(
        ref,
        loaded.chapter,
        isAlive: () => mounted,
      );
    } catch (e) {
      // QA on-device 2026-10-18 (Bug #7): this catch used to swallow the
      // error into an eternal spinner — manga-type chapters route HERE,
      // so every failed open showed "กำลังโหลด…" + หน้า 1/0 forever.
      if (kDebugMode) debugPrint('PAGED open FAIL $e');
      if (!mounted) return;
      setState(() {
        _loaded = null;
        _failed = true;
      });
    }
  }

  Future<void> _saveProgress(int page, {required bool completed}) async {
    final loaded = _loaded;
    if (loaded == null) return;
    if (completed) {
      // Finished: drop the pending "on reading" marker.
      _startedTimer?.cancel();
      _startedTimer = null;
    }
    await persistReaderProgress(
      ref,
      loaded.chapter,
      pageIndex: page,
      completed: completed,
    );
  }

  /// One page via the shared resolver, memoized per index (see
  /// [_inflight]). Pages [page+1 .. page+ahead] queue right behind it so
  /// a swipe finds the file already on disk instead of a spinner.
  Future<PageFile> _resolvePage(int idx) {
    final existing = _inflight[idx];
    if (existing != null) return existing;
    final loaded = _loaded!;
    final future = _repo
        .resolvePage(loaded, idx)
        .then<PageFile>(
          (pf) => pf,
          onError: (Object e) {
            _inflight.remove(idx);
            throw e;
          },
        );
    _inflight[idx] = future;
    return future;
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

  void _onPageChanged(int page) {
    final loaded = _loaded;
    if (loaded == null) return;
    setState(() => _page = page);
    _prefetchFrom(page);
    final now = DateTime.now();
    if (now.difference(_lastSave) >= const Duration(milliseconds: 500)) {
      _lastSave = now;
      _saveProgress(page, completed: page == loaded.pages.length - 1);
    }
    if (page == loaded.pages.length - 1) _ensureNext();
  }

  /// The finger reversed back into CONTENT during a pull: overscroll
  /// notifications stop once the position re-enters range, so the
  /// in-range movement feeds `shrink` instead — the indicator FALLS
  /// BACK with the finger and only disappears when it reaches zero
  /// (user report 2026-10-23: it must not vanish on the first reversal).
  void _onPixels() {
    final c = _pageController;
    if (c == null || !c.hasClients || !_pull.dragging) {
      _pullPixels = null;
      return;
    }
    final px = c.position.pixels;
    final max = c.position.maxScrollExtent;
    final atEdge = _pull.direction > 0 ? px >= max - 1 : px <= 1;
    if (!atEdge && _pullPixels != null) {
      final moved = px - _pullPixels!;
      if (_pull.direction > 0 && moved < 0) {
        setState(() => _pull.shrink(-moved));
      } else if (_pull.direction < 0 && moved > 0) {
        setState(() => _pull.shrink(moved));
      }
    }
    _pullPixels = px;
  }

  /// Forward overscroll while ON the last page = the drag-to-next pull;
  /// backward overscroll while ON the first page = drag-to-previous
  /// (user request 2026-10-23). Positive overscroll is always the
  /// forward direction (PageView accounts for `reverse` internally). A
  /// delta AGAINST the active pull shrinks it so the indicator follows
  /// the finger in both directions.
  void _onOverscroll(double overscroll) {
    final loaded = _loaded;
    if (!_autoNext || loaded == null) return;
    final onLast = _page == loaded.pages.length - 1;
    final onFirst = _page == 0;
    if (onLast && overscroll > 0) {
      _ensureNext();
      setState(() => _pull.add(overscroll));
      return;
    }
    if (onFirst && overscroll < 0) {
      _ensurePrev();
      setState(() => _pull.add(overscroll));
      return;
    }
    if (_pull.dragging &&
        (_pull.direction > 0 ? overscroll < 0 : overscroll > 0)) {
      setState(() => _pull.add(overscroll));
    }
  }

  /// Fingers up on an edge: past the threshold → switch in the pulled
  /// direction. Also the parked-at-end completion save point.
  Future<void> _onScrollEnd() async {
    final loaded = _loaded;
    if (loaded == null) return;
    if (_page == loaded.pages.length - 1) {
      _saveProgress(_page, completed: true);
    }
    if (!_pull.dragging) return;
    final dir = _pull.release();
    setState(() {});
    if (dir == 0) return;
    if (dir > 0) {
      await _ensureNext();
      if (!mounted) return;
      if (_next != null) _goNext();
    } else {
      await _ensurePrev();
      if (!mounted) return;
      if (_prev != null) _goPrev();
    }
  }

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

  /// Same, for the previous chapter (first-page pull).
  Future<void> _ensurePrev() async {
    if (_prevKnown || _prevLookup || _loaded == null) return;
    _prevLookup = true;
    final prev = await _repo.adjacentChapter(_loaded!.chapter, forward: false);
    _prevLookup = false;
    if (!mounted) return;
    _prev = prev;
    _prevKnown = true;
    if (_pull.dragging) setState(() {});
  }

  Future<void> _goNext() async {
    final loaded = _loaded;
    if (loaded == null || _switching) return;
    final next = _nextKnown
        ? _next
        : await _repo.adjacentChapter(loaded.chapter, forward: true);
    if (next != null && mounted) {
      _switching = true;
      await _saveProgress(loaded.pages.length - 1, completed: true);
      if (mounted) {
        await replaceReaderRoute(
          context,
          (_) => PagedReaderScreen(
            chapter: next,
            // Carry the chrome state across the chapter switch.
            chromeVisible: _chromeVisible,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(context, 'reader.end'))));
    }
  }

  Future<void> _goPrev() async {
    final loaded = _loaded;
    if (loaded == null || _switching) return;
    final prev = await _repo.adjacentChapter(loaded.chapter, forward: false);
    if (prev != null && mounted) {
      _switching = true;
      // Same rule as _goNext: land the progress write before the swap.
      await _saveProgress(_page, completed: _page == loaded.pages.length - 1);
      if (mounted) {
        await replaceReaderRoute(
          context,
          (_) =>
              PagedReaderScreen(chapter: prev, chromeVisible: _chromeVisible),
        );
      }
    }
  }

  bool get _zoomed {
    final key = _slotKeys[_page];
    final details = key?.currentState?.gestureDetails;
    return details != null && (details.totalScale ?? 1.0) > 1.05;
  }

  void _tapZone(bool forward) {
    if (_zoomed) return; // page-turn taps disabled while zoomed (doc 11 A)
    final loaded = _loaded;
    final controller = _pageController;
    if (loaded == null || controller == null) {
      return;
    }
    final goForward = _rtl ? !forward : forward; // zones swap under RTL
    if (goForward) {
      if (_page < loaded.pages.length - 1) {
        controller.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _goNext();
      }
    } else {
      if (_page > 0) {
        controller.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _goPrev();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeHooked) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return;
    _routeHooked = true;
    _routeAnimation = animation;
    animation.addStatusListener(_onRouteStatus);
  }

  /// See the webtoon reader: dispose runs after the exit transition, so
  /// restoring there shifted the revealed page's insets (user report
  /// 2026-10-21). Reverse-start hides the bar change behind the outgoing
  /// route's slide.
  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse && _barsHidden) {
      _setImmersive(false);
    }
  }

  /// Sync [PageView.physics] with pointer/zoom state (see the fields
  /// above). Called from raw pointer edges only — cheap.
  void _syncPageFreeze() {
    var zoomed = false;
    final state = _slotKeys[_page]?.currentState;
    if (state is ExtendedImageGestureState) {
      zoomed = (state.gestureDetails?.totalScale ?? 1.0) > 1.01;
    }
    _pageZoomed = zoomed;
    _pinchHold = _activePointers >= 2;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _startedTimer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    // Replacement exits (chapter/mode switch) never run reverse — those
    // still restore here; pop exits already restored at reverse-start.
    // EXCEPT reader→reader handovers: the successor re-asserted
    // immersive in its initState, and this dispose fires only after the
    // new route's entrance animation, so restoring here would bring the
    // system bars BACK (user report 2026-10-23).
    if (_barsHidden && !readerHandsOverSystemBars) _setImmersive(false);
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
      // Raw pointer edges drive the slide freeze (see the fields above).
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _activePointers++;
          _syncPageFreeze();
        },
        onPointerUp: (e) {
          _activePointers = (_activePointers - 1).clamp(0, 9);
          _syncPageFreeze();
        },
        onPointerCancel: (e) {
          _activePointers = (_activePointers - 1).clamp(0, 9);
          _syncPageFreeze();
        },
        child: Stack(
          children: [
            if (loaded == null)
              // Same fail-path contract as the webtoon reader: error title +
              // retry once _open() exhausted every candidate source.
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
                      style: const TextStyle(color: Colors.white70),
                    ),
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
                  if (n is OverscrollNotification) _onOverscroll(n.overscroll);
                  if (n is ScrollEndNotification) _onScrollEnd();
                  return false;
                },
                // The pull SLIDE (user request 2026-10-23): the page
                // physically moves sideways with the finger past the
                // last/first page, opening the black space the dot trail
                // sits in; releasing springs it back. Paint-only.
                child: Builder(
                  builder: (context) {
                    // Forward = along the reading direction: LTR slides
                    // left, RTL slides right.
                    final shift =
                        (_pull.dragging ? _pull.extent * 0.55 : 0.0) *
                        (_rtl ? -1 : 1);
                    return Transform.translate(
                      offset: Offset(-shift, 0),
                      child: PageView.builder(
                        controller: _pageController!,
                        reverse: _rtl,
                        // While a pinch holds (two fingers) or the page image is
                        // zoomed in, the page must NOT slide — one finger then
                        // pans the zoomed image, and a pinch never flips the page
                        // (user report 2026-10-21).
                        physics: _pinchHold || _pageZoomed
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        // Keep the neighboring page BUILT (viewport cacheExtent):
                        // the target page of a turn is already constructed and
                        // decoded while it slides in — no black flash frame
                        // between pages (user QA 2026-10-19).
                        allowImplicitScrolling: true,
                        itemCount: loaded.pages.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, i) => _PageSlotPaged(
                          page: loaded.pages[i],
                          index: i,
                          resolve: () => _resolvePage(i),
                          register: (i, key) => _slotKeys[i] = key,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Tap zones: left 30% prev, right 30% next, middle 40% chrome
              // (swapped under RTL) — only when not zoomed.
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _tapZone(false),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () =>
                            setState(() => _chromeVisible = !_chromeVisible),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _tapZone(true),
                        child: const SizedBox.expand(),
                      ),
                    ),
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            DetailScreen(seriesId: loaded.chapter.seriesId),
                      ),
                    );
                  },
                  onChapters: () => _openChapterPicker(loaded),
                  onMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ),
              if (_pull.dragging)
                Positioned(
                  // The trail sits INSIDE the space the slide opens — the
                  // side the next/prev chapter comes FROM (LTR next = the
                  // page slides left, so the space opens on the RIGHT;
                  // flipped for RTL). Fixed 2026-10-23: it was pinned to
                  // the opposite side and drew over the artwork.
                  top: 0,
                  bottom: 0,
                  left: _pull.direction > 0
                      ? (_rtl ? 0 : null)
                      : (_rtl ? null : 0),
                  right: _pull.direction > 0
                      ? (_rtl ? null : 0)
                      : (_rtl ? 0 : null),
                  child: Center(
                    child: Opacity(
                      opacity: (_pull.progress * 1.8).clamp(0.0, 1.0),
                      child: PullNextIndicator(
                        progress: _pull.progress,
                        armed: _pull.armed,
                        horizontal: true,
                        rtl: _rtl,
                        back: _pull.direction < 0,
                        hasNext: _pull.direction < 0
                            ? (!_prevKnown || _prev != null)
                            : (!_nextKnown || _next != null),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(LoadedChapter loaded) {
    final settings = ref.read(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final seriesId = loaded.chapter.seriesId;
    return ReaderControlDrawer(
      pageText: tFmt(context, 'reader.page', {
        'n': '${_page + 1}',
        'total': '${loaded.pages.length}',
      }),
      progress: loaded.pages.length <= 1
          ? 0
          : _page / (loaded.pages.length - 1),
      canPrev: true,
      canNext: true,
      onPrev: _goPrev,
      onNext: _goNext,
      onChapters: () => _openChapterPicker(loaded),
      onSeek: (v) {
        final total = loaded.pages.length;
        final target = (v * (total - 1)).round();
        _pageController?.animateToPage(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
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

  /// Persist where we are, then swap this route for the freshly resolved
  /// reader when the mode actually changes screens (no-op otherwise).
  /// [chosen] is the mode JUST picked — SettingsController.set only
  /// publishes after its DB write, so re-reading the provider here can
  /// still see the old value and the swap would silently no-op.
  Future<void> _applyModeChange(
    LoadedChapter loaded, {
    required String chosen,
  }) async {
    await _saveProgress(_page, completed: _page == loaded.pages.length - 1);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    await replaceWithResolvedReader(
      context,
      chapter: loaded.chapter,
      current: ReaderMode.paged,
      seriesDao: ref.read(seriesDaoProvider),
      modeOverride: effectiveModeOverride(
        chosen,
        settings.get('reader_mode_default', 'auto'),
      ),
      // The mode swap is a reader swap, not a chapter swap — keep the
      // chrome where the user left it.
      chromeVisible: _chromeVisible,
    );
  }

  Future<void> _openChapterPicker(LoadedChapter loaded) async {
    final vm = await ref.read(seriesRepoProvider).load(loaded.chapter.seriesId);
    if (!mounted) return;
    await showChapterPicker(
      context,
      ref,
      vm: vm,
      current: loaded.chapter,
      onPick: (chapter, sourceId) {
        replaceReaderRoute(
          context,
          (_) => PagedReaderScreen(
            chapter: chapter,
            chromeVisible: _chromeVisible,
          ),
        );
      },
    );
  }
}

/// One page: BoxFit.contain + gesture mode (double-tap zoom + pan);
/// blurred shimmer placeholder at a 2:3 estimate while loading. Each slot
/// OWNS its gesture key (shared keys freeze the reader mid page-turn).
class _PageSlotPaged extends ConsumerStatefulWidget {
  const _PageSlotPaged({
    required this.page,
    required this.index,
    required this.resolve,
    required this.register,
  });

  final ReaderPageRef page;
  final int index;
  final Future<PageFile> Function() resolve;
  final void Function(int index, GlobalKey<ExtendedImageGestureState> key)
  register;

  @override
  ConsumerState<_PageSlotPaged> createState() => _PageSlotPagedState();
}

class _PageSlotPagedState extends ConsumerState<_PageSlotPaged> {
  late Future<PageFile?> _future;
  final _gestureKey = GlobalKey<ExtendedImageGestureState>();
  Object? _error;

  /// Decode width cap for paged pages: 2× screen pixels (portrait
  /// pages render width-limited, so native ≤1080 sources cost nothing;
  /// WIDE double-spread pages are height-limited under BoxFit.contain
  /// and zoomed — the 2× headroom keeps their detail) and never above
  /// the source's own width. Full-res decodes while PageView keeps ±1
  /// neighbors built were the swipe lag (user report 2026-10-21).
  int _cacheWidthFor(int? sourceWidth, BuildContext context) {
    final cap =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context) *
                2)
            .round();
    if (sourceWidth != null && sourceWidth > 0) {
      return sourceWidth < cap ? sourceWidth : cap;
    }
    return cap;
  }

  @override
  void initState() {
    super.initState();
    widget.register(widget.index, _gestureKey);
    _future = _load();
  }

  Future<PageFile?> _load() async {
    try {
      final pf = await widget.resolve();
      return pf;
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.white10,
        alignment: Alignment.center,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(t(context, 'common.retry')),
          onPressed: () => setState(() => _future = _load()),
        ),
      );
    }
    return FutureBuilder<PageFile?>(
      future: _future,
      builder: (context, snap) {
        final pf = snap.data;
        if (pf == null) {
          return Container(
            color: Colors.white10,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final dir = ref.read(libraryDirProvider);
        // Oversized strip (taller than the GPU texture limit): the
        // single-file gesture image would render as a black void — stack
        // the GPU-safe band slices in a scroll view instead. Zoom is not
        // offered for sliced pages (ExtendedImage gesture wraps ONE
        // image); these strips are webtoon-mode content anyway.
        final bands = pf.bands;
        if (bands != null && bands.isNotEmpty) {
          return SingleChildScrollView(
            child: Column(
              children: [
                for (final b in bands)
                  ExtendedImage.file(
                    File('${dir.path}/${b.path}'),
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    clearMemoryCacheWhenDispose: false,
                    cacheWidth: _cacheWidthFor(b.width, context),
                  ),
              ],
            ),
          );
        }
        return ExtendedImage.file(
          File('${dir.path}/${pf.path}'),
          fit: BoxFit.contain,
          mode: ExtendedImageMode.gesture,
          // Do NOT clear the memory cache on dispose: PageView disposes
          // off-screen slots on every turn, and clearing forced a
          // re-decode (a black flash frame) each time — forward AND back.
          // The framework ImageCache LRU-evicts under pressure instead.
          clearMemoryCacheWhenDispose: false,
          // Decode cap (swipe-lag fix 2026-10-21): without it every page
          // decoded at FULL source resolution while PageView keeps ±1
          // neighbors built — three big decodes racing the swipe. See
          // _cacheWidthFor for the 2× headroom rationale.
          cacheWidth: _cacheWidthFor(pf.width, context),
          extendedImageGestureKey: _gestureKey,
          loadStateChanged: (state) =>
              state.extendedImageLoadState == LoadState.loading
              ? Container(
                  color: Colors.white10,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        );
      },
    );
  }
}

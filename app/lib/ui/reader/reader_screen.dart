import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit, ScrollCacheExtent;
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
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
import 'reader_crop.dart';
import 'reader_drawer.dart';
import 'reader_progress.dart';
import 'reader_router.dart';
import 'reader_settings_body.dart';

/// Webtoon reader (doc 10) — vertical streaming, prefetch ahead, chrome
/// toggle, continuous progress, drag-past-the-end "pull to continue" with
/// resistance (replaced the 3 s countdown), per-page source fallback
/// (07 §5), controls in the right-hand drawer.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.chapter,
    this.chromeVisible = true,
  });

  final Chapter chapter;

  /// Whether the chrome starts VISIBLE. Carried across a chapter switch
  /// so hiding the chrome in one chapter and pulling to the next keeps
  /// it hidden there too (user report 2026-10-22: the header came back
  /// visible on the next chapter).
  final bool chromeVisible;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  LoadedChapter? _loaded;
  bool _failed = false;
  List<double> _heights = const [];
  String? _seriesTitle;
  int _currentPage = 0;
  late bool _chromeVisible = widget.chromeVisible;

  /// True while this screen left the system bars hidden. dispose()
  /// restores only when set — pops restore EARLIER (see [_onRouteStatus])
  /// and clear the flag, so the platform call isn't sent twice.
  bool _barsHidden = false;
  Animation<double>? _routeAnimation;
  bool _routeHooked = false;

  /// Scaffold key — the chrome's menu button must open the end drawer via
  /// the KEY, not Scaffold.of(): the callback's context sits ABOVE the
  /// Scaffold this screen builds, so Scaffold.of can never find it.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Drag-past-the-edge state: the neighbour chapters (or null at the
  /// very ends) are resolved once, lazily, while parked at that edge.
  /// The pull itself is signed: past the END pulls the NEXT chapter,
  /// past the START pulls the PREVIOUS one (user request 2026-10-23:
  /// dragging back gets the same progress treatment as dragging on).
  Chapter? _next;
  bool _nextKnown = false;
  bool _nextLookup = false;
  Chapter? _prev;
  bool _prevKnown = false;
  bool _prevLookup = false;
  final _pull = PullChapterTracker(threshold: 420);

  /// Scroll offset sampled during an active pull — the delta between
  /// samples shrinks the pull once the finger reverses back into
  /// content (see _onScroll).
  double? _pullOffset;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// Pending "on reading" marker for this chapter (armed on open, fired
  /// after [kStartedMarkerDelay]). Cancelled once the chapter is
  /// finished or the screen is disposed.
  Timer? _startedTimer;

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

  /// Height fix-ups waiting to be applied — batched into ONE relayout
  /// per frame. During a first-read fling, several pages resolve within
  /// the same frame; an immediate setState per page meant several full
  /// ListView relayouts back to back (smoothness report 2026-10-21).
  final _pendingDims = <int, double>{};
  bool _dimsFlushScheduled = false;

  /// Per-chapter screen crop (letterboxed strips — see ReaderCrop).
  /// Loaded from `reader_crop_ch<id>` on open, saved on every change.
  ReaderCrop _crop = const ReaderCrop();
  bool _cropAutoBusy = false;

  /// Raw-pointer pinch/pan state (Listener-based, so it NEVER competes
  /// with the ListView's drag recognizers — single-finger scrolling is
  /// untouched). Pinch = transient website-style VIEW zoom (ViewZoom:
  /// paint transform, focal-anchored; exits by pinching back to 1×).
  /// The CROP has no gestures at all — once set (sliders/auto-detect) it
  /// is a real lock: the window never moves during reading (user report
  /// 2026-10-21: the old drag let the window wander into the bars).
  final _pointers = <int, Offset>{};
  double? _pinchLastDist;
  Offset? _pinchFocal0;
  ViewZoom _pinchBase = const ViewZoom();
  ViewZoom _view = const ViewZoom();
  bool _scrollFrozen = false;

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
    _crop = ReaderCrop.decode(
      ref.read(settingsProvider).get('reader_crop_ch${widget.chapter.id}', ''),
    );
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
      final progress = await ref
          .read(chaptersDaoProvider)
          .progress(loaded.chapter.id!);
      if (!mounted) return;
      setState(() {
        _failed = false;
        _loaded = loaded;
        _seriesTitle = series?.title;
        _heights = [for (final p in loaded.pages) _estimatedHeight(p)];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (progress != null && !progress.completed && progress.pageIndex > 0) {
          final offsets = slotOffsets(_heights);
          final idx = progress.pageIndex.clamp(0, offsets.length - 1);
          _scroll.jumpTo(
            offsets[idx].clamp(0.0, _scroll.position.maxScrollExtent),
          );
          _currentPage = idx;
        }
      });
      _seedPrefetch();
      // "On reading" marker: a chapter left open for a couple of seconds
      // counts as started (user request 2026-10-22). The write cannot
      // regress a finished chapter, and the timer is cancelled when the
      // chapter completes or the screen goes away.
      _startedTimer?.cancel();
      _startedTimer = armStartedMarker(
        ref,
        loaded.chapter,
        isAlive: () => mounted,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('READER open FAIL $e');
      if (!mounted) return;
      setState(() {
        _loaded = null;
        _failed = true;
      });
    }
  }

  double _estimatedHeight(ReaderPageRef p) => p.hasDims
      ? _slotWidth * p.height! / p.width!
      : _slotWidth *
            (_observedAspectCount >= 3
                ? _observedAspectSum / _observedAspectCount
                : PageSlot.estimatedAspect);

  double get _screenWidth => MediaQuery.sizeOf(context).width;

  /// Slot layout width: screen width scaled by the crop zoom. Heights
  /// derive from this, so zooming rescales the whole strip uniformly.
  double get _slotWidth => _screenWidth * _crop.zoom;

  /// Seed pages [0..5] into the queue (doc 10 §Prefetch), then keep
  /// [ _prefetchAhead ] pages moving as the user scrolls (the setting
  /// actually drives prefetch; cacheExtent alone is fixed at ~2 screens).
  void _seedPrefetch() {
    final loaded = _loaded;
    if (loaded == null) return;
    for (var i = 0; i < loaded.pages.length && i <= 5; i++) {
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
    final future = _repo
        .resolvePage(
          loaded,
          idx,
          onFallback: (sourceId) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tFmt(context, 'reader.fallback_source', {'source': sourceId}),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        )
        .then<PageFile>(
          (pf) {
            _pageFiles[idx] = pf;
            return pf;
          },
          onError: (Object e) {
            _inflight.remove(idx);
            throw e;
          },
        );
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
    _pendingDims[idx] = exact;
    _scheduleDimFlush();
  }

  /// Apply every queued fix-up in one setState + ONE anchor shift.
  void _scheduleDimFlush() {
    if (_dimsFlushScheduled) return;
    _dimsFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dimsFlushScheduled = false;
      if (!mounted || _pendingDims.isEmpty) return;
      if (!_scroll.hasClients) {
        _pendingDims.clear();
        return;
      }
      var totalAdjust = 0.0;
      final offsets = slotOffsets(_heights);
      _pendingDims.removeWhere((idx, exact) {
        if (idx >= _heights.length) return true;
        final delta = exact - _heights[idx];
        if (delta.abs() < 1) return true;
        totalAdjust += heightAnchorDelta(
          offsets,
          _heights,
          idx,
          delta,
          _scroll.offset,
        );
        return false;
      });
      if (_pendingDims.isEmpty) return;
      setState(() {
        _pendingDims.forEach((idx, exact) {
          _heights[idx] = exact;
        });
      });
      _pendingDims.clear();
      if (totalAdjust == 0) return;
      final raw = _scroll.offset + totalAdjust;
      if (raw >= 0 && raw <= _scroll.position.maxScrollExtent) {
        // Shift BEFORE the relayout frame: the frame that first sees the
        // new heights also sees the moved offset, so content stays
        // pinned with NO intermediate shifted frame. forcePixels (not
        // jumpTo): jumpTo KILLS the ballistic activity — every late
        // correction during a down-fling stopped the scroll dead, which
        // read as laggy scrolling (user report 2026-10-21); forcePixels
        // moves the pixels and lets the fling continue from the new
        // position. Protected member: the framework uses it for this
        // exact purpose (pointerScroll, nested scrolling); the value is
        // pre-clamped to the current extent.
        // ignore: invalid_use_of_protected_member
        _scroll.position.forcePixels(raw);
      } else {
        // Target outside the CURRENT extent (corrections grew it): the
        // old post-frame clamp, against the relayouted extent.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final target = (_scroll.offset + totalAdjust).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          );
          if ((target - _scroll.offset).abs() >= 1) _scroll.jumpTo(target);
        });
      }
    });
  }

  bool get _atEnd {
    if (!_scroll.hasClients) return false;
    return reachedEnd(
      _scroll.offset,
      _scroll.position.maxScrollExtent,
      _scroll.position.viewportDimension,
    );
  }

  /// Parked at the very top — the previous-chapter pull edge.
  bool get _atStart => _scroll.hasClients && _scroll.offset <= 0;

  void _onScroll() {
    final loaded = _loaded;
    if (loaded == null || !_scroll.hasClients) return;

    // The finger reversed back into CONTENT during a pull: overscroll
    // notifications stop once the position re-enters range, so the
    // in-range movement feeds `shrink` instead — the indicator FALLS
    // BACK with the finger and only disappears when it reaches zero
    // (user report 2026-10-23: it must not vanish on the first
    // reversal).
    if (_pull.dragging) {
      final off = _scroll.offset;
      final max = _scroll.position.maxScrollExtent;
      final atEdge = _pull.direction > 0 ? off >= max - 1 : off <= 1;
      if (!atEdge && _pullOffset != null) {
        final moved = off - _pullOffset!;
        if (_pull.direction > 0 && moved < 0) {
          setState(() => _pull.shrink(-moved));
        } else if (_pull.direction < 0 && moved > 0) {
          setState(() => _pull.shrink(moved));
        }
      }
      _pullOffset = off;
    } else {
      _pullOffset = null;
    }

    final viewport = _scroll.position.viewportDimension;
    final offsets = slotOffsets(_heights);

    final page = currentPageIndex(offsets, _heights, _scroll.offset, viewport);
    if (page != _currentPage) {
      setState(() => _currentPage = page);
      _prefetchFrom(page);
    }

    // Completed: within one viewport of the end (doc 10 §5), throttled
    // DB write at 500 ms (partial positions save continuously).
    final now = DateTime.now();
    final completed = reachedEnd(
      _scroll.offset,
      _scroll.position.maxScrollExtent,
      viewport,
    );
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

  /// Overscroll past an edge while parked there = the drag-to-switch
  /// pull (ClampingScrollPhysics fires Overscroll notifications during
  /// the active drag only). Past the end → next chapter; past the start
  /// → previous chapter (user request 2026-10-23). A delta AGAINST the
  /// active pull (finger reversing, either direction) shrinks it so the
  /// indicator follows the finger.
  void _onOverscroll(double overscroll) {
    if (!_autoNext) return;
    if (_atEnd && overscroll > 0) {
      _ensureNext();
      setState(() => _pull.add(overscroll));
      return;
    }
    if (_atStart && overscroll < 0) {
      _ensurePrev();
      setState(() => _pull.add(overscroll));
      return;
    }
    // Opposing deltas shrink the in-progress pull; same-sign deltas on
    // the other edge do nothing.
    if (_pull.dragging &&
        (_pull.direction > 0 ? overscroll < 0 : overscroll > 0)) {
      setState(() => _pull.add(overscroll));
    }
  }

  /// Fingers up: past the threshold → switch in the pulled direction;
  /// otherwise the pull springs back. Also the parked-at-end completion
  /// save point.
  Future<void> _onScrollEnd() async {
    final loaded = _loaded;
    if (loaded == null || !_scroll.hasClients) return;
    if (reachedEnd(
      _scroll.offset,
      _scroll.position.maxScrollExtent,
      _scroll.position.viewportDimension,
    )) {
      _saveProgress(_currentPage, completed: true);
    }
    if (!_pull.dragging) return;
    final dir = _pull.release();
    setState(() {});
    if (dir == 0) return;
    if (dir > 0) {
      await _ensureNext();
      if (!mounted) return;
      final next = _next;
      if (next != null) _goTo(next);
    } else {
      await _ensurePrev();
      if (!mounted) return;
      final prev = _prev;
      if (prev != null) _goTo(prev);
    }
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

  /// Same, for the previous chapter (top-edge pull).
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

  Future<void> _saveProgress(int page, {required bool completed}) async {
    final loaded = _loaded;
    if (loaded == null) return;
    if (completed) {
      // Finished: drop the pending "on reading" marker — the chapter is
      // read, not in progress.
      _startedTimer?.cancel();
      _startedTimer = null;
    }
    await persistReaderProgress(
      ref,
      loaded.chapter,
      pageIndex: completed ? loaded.pages.length - 1 : page,
      completed: completed,
    );
  }

  /// Chapter switch = replace this route with the same reader, scroll
  /// reset (doc 10 §6). The progress save is AWAITED first: swapping
  /// the route before the completed row landed was the slider-jump bug
  /// — a fast drag to the end advanced chapters mid-write and the
  /// chapter reopened from the top (QA §12 #4, fixed 2026-10-20).
  /// Swap the crop: rescales every reserved height by the zoom ratio and
  /// re-anchors the scroll offset (multiplied by the same ratio) so the
  /// artwork under the reader stays put. Persisted per chapter — empty
  /// value when inactive.
  void _applyCrop(ReaderCrop next, {bool persist = true}) {
    if (next == _crop) return;
    final ratio = next.zoom / _crop.zoom;
    final rescale = (ratio - 1).abs() > 0.001;
    final anchor = _scroll.hasClients ? _scroll.offset : null;
    setState(() {
      _crop = next;
      if (rescale) {
        _heights = [for (final h in _heights) h * ratio];
      }
    });
    if (rescale && anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = (anchor * ratio).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        if ((target - _scroll.offset).abs() > 0.5) _scroll.jumpTo(target);
      });
    }
    if (persist) _persistCrop();
  }

  void _persistCrop() {
    final key = 'reader_crop_ch${widget.chapter.id}';
    ref
        .read(settingsProvider.notifier)
        .set(key, _crop.active ? _crop.encode() : '');
  }

  /// Drawer's auto-detect: column-luminance profile of the first page →
  /// artwork window → crop (letterbox measurement, 2026-10-21).
  Future<void> _autoDetectCrop() async {
    if (_loaded == null || _cropAutoBusy) return;
    setState(() => _cropAutoBusy = true);
    try {
      final pf = _pageFiles[0] ?? await _resolvePage(0);
      if (!mounted) return;
      final dir = ref.read(libraryDirProvider);
      final means = await columnLuminanceMeans('${dir.path}/${pf.path}');
      if (!mounted) return;
      final win = means == null ? null : detectArtworkWindow(means);
      final crop = win == null ? null : cropForWindow(win.left, win.width);
      if (crop == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'reader.crop.not_found'))),
        );
      } else {
        _applyCrop(crop);
      }
    } catch (_) {
      // Page resolve/decode failure — same contract as a miss.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'reader.crop.not_found'))),
        );
      }
    } finally {
      if (mounted) setState(() => _cropAutoBusy = false);
    }
  }

  // --- Raw-pointer gestures (see the field docs) -----------------------

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _pinchLastDist = (pts[0] - pts[1]).distance;
      _pinchFocal0 = (pts[0] + pts[1]) / 2;
      _pinchBase = _view;
      if (_pinchLastDist! > 8) {
        // Freeze scrolling for the pinch: kill the in-flight drag and
        // lock physics while the fingers (or the resulting zoom) hold.
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
        setState(() => _scrollFrozen = true);
      } else {
        _pinchLastDist = null;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2) {
      final dist0 = _pinchLastDist;
      final focal0 = _pinchFocal0;
      if (dist0 == null || focal0 == null) return;
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      if (dist >= 1 && dist0 >= 1) {
        final viewport = Size(_screenWidth, MediaQuery.sizeOf(context).height);
        final next = ViewZoom.zoomAround(
          base: _pinchBase,
          nextScale: _pinchBase.scale * dist / dist0,
          focal0: focal0,
          focal: focal,
          viewport: viewport,
        );
        if (next != _view) setState(() => _view = next);
      }
      return;
    }

    // One finger while view-zoomed: pan the zoomed content — the list's
    // physics are frozen, so this never fights scrolling.
    if (_view.active) {
      final viewport = Size(_screenWidth, MediaQuery.sizeOf(context).height);
      final next = _view.panBy(e.delta, viewport);
      if (next != _view) setState(() => _view = next);
    }
  }

  void _onPointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.length < 2 && _pinchLastDist != null) {
      _pinchLastDist = null;
      _pinchFocal0 = null;
      // View zoom is transient: back at 1x, scrolling resumes; while
      // still zoomed, one finger pans (see _onPointerMove) — stay frozen.
      if (!_view.active && _scrollFrozen) {
        setState(() => _scrollFrozen = false);
      }
    }
  }

  /// Slot wrapper for the crop window: ListView children cannot exceed
  /// the cross-axis extent (constraints clamp them), so an OverflowBox
  /// lays the oversized slot out at the zoomed width and the viewport's
  /// own clip crops it — horizontally FIXED (the lock), vertically it
  /// scrolls with the list. The OverflowBox MUST carry the slot's real
  /// height in minHeight/maxHeight: its own size derives from the min
  /// overrides, and `0` under the ListView's unbounded height collapsed
  /// every slot to zero → an all-black screen (user report 2026-10-21).
  Widget _cropBox(Widget slot, double slotHeight) {
    if (!_crop.active) return slot;
    return OverflowBox(
      // fit: deferToChild is REQUIRED here — the default
      // OverflowBoxFit.max sizes the box to constraints.biggest, and
      // under the ListView's unbounded main axis that is INFINITE → a
      // non-finite render-object size → the whole slot silently paints
      // NOTHING (the user's "all black when crop" report, verified on
      // the emulator 2026-10-21). deferToChild sizes to the child
      // clamped by the viewport width = the crop window itself.
      fit: OverflowBoxFit.deferToChild,
      minWidth: _slotWidth,
      maxWidth: _slotWidth,
      minHeight: slotHeight,
      maxHeight: slotHeight,
      alignment: Alignment(2 * _crop.cropX - 1, -1),
      child: slot,
    );
  }

  Future<void> _goTo(Chapter next) async {
    await _saveProgress(_currentPage, completed: _atEnd);
    if (!mounted) return;
    await replaceReaderRoute(
      context,
      (_) => ReaderScreen(
        chapter: next,
        // Carry the chrome state: hidden stays hidden (user request
        // 2026-10-22), visible stays visible.
        chromeVisible: _chromeVisible,
      ),
    );
  }

  Future<void> _jumpTo(int idx) async {
    final offsets = slotOffsets(_heights);
    final target = (idx < offsets.length ? offsets[idx] : 0.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
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

  /// Restore the status bar the moment THIS route starts animating OUT,
  /// not in dispose: dispose runs after the exit transition, so the page
  /// underneath was already fully revealed when its top inset came back —
  /// the whole layout visibly shifted ("warpy" pull-and-retract on back
  /// from the reader, user report 2026-10-21).
  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse && _barsHidden) {
      _setImmersive(false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
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
      // Raw-pointer pinch guard: sees every touch without entering the
      // gesture arena, so scrolling/taps behave exactly as before and
      // two-finger pinches zoom the strip.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: (e) => _onPointerUp(e.pointer),
        onPointerCancel: (e) => _onPointerUp(e.pointer),
        child: Stack(
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
              // Website-style view zoom: a PAINT transform over the list
              // (no relayout — the strip never re-flows or shakes while
              // zooming). Clipped by the Stack; chrome/tap zones above
              // are unaffected. See ViewZoom for the math.
              //
              // Layered on top: the pull slide (user request 2026-10-23
              // — the page physically moves with the finger past an
              // edge, opening the black space the dot trail sits in;
              // releasing springs it back). Paint-only, so scroll math
              // and the zoom never interact.
              Builder(
                builder: (context) {
                  final pullShift = _pull.dragging ? _pull.extent * 0.55 : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -pullShift),
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translateByDouble(_view.dx, _view.dy, 0, 1)
                        ..scaleByDouble(_view.scale, _view.scale, 1, 1),
                      alignment: Alignment.topLeft,
                      child: NotificationListener<ScrollNotification>(
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
                          // Frozen while a pinch or an active view zoom holds —
                          // one finger then PANS the zoomed view instead.
                          physics: _scrollFrozen || _view.active
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          // ~5 viewports: slots (and their height fix-ups) resolve
                          // well before entering the viewport, so first-read
                          // corrections shift content the user can't see yet.
                          scrollCacheExtent: ScrollCacheExtent.pixels(4500),
                          itemCount: loaded.pages.length,
                          itemBuilder: (context, i) => _cropBox(
                            PageSlot(
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
                            i < _heights.length
                                ? _heights[i]
                                : _screenWidth * 1.9,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Middle-60% tap toggles chrome (doc 10 §6).
              Positioned.fill(
                child: Row(
                  children: [
                    const Expanded(flex: 2, child: SizedBox.expand()),
                    Expanded(
                      flex: 6,
                      child: _tapZone(() {
                        setState(() => _chromeVisible = !_chromeVisible);
                      }),
                    ),
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
                  // The trail sits INSIDE the space the slide opens:
                  // next-pull anchors to the bottom edge, prev-pull to
                  // the top (the content slid the other way). It fades
                  // in with progress so a shallow pull doesn't overlap
                  // the artwork underneath.
                  top: _pull.direction < 0 ? 10 : null,
                  bottom: _pull.direction > 0 ? 10 : null,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: (_pull.progress * 1.8).clamp(0.0, 1.0),
                    child: Center(
                      child: PullNextIndicator(
                        progress: _pull.progress,
                        armed: _pull.armed,
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
        'n': '${_currentPage + 1}',
        'total': '${loaded.pages.length}',
      }),
      progress: loaded.pages.length <= 1
          ? 0
          : _currentPage / (loaded.pages.length - 1),
      canPrev: true,
      canNext: true,
      onPrev: () async {
        final prev = await _repo.adjacentChapter(
          loaded.chapter,
          forward: false,
        );
        if (!mounted) return;
        if (prev != null) _goTo(prev);
      },
      onNext: () async {
        final next = await _repo.adjacentChapter(loaded.chapter, forward: true);
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
        crop: _crop,
        cropAutoBusy: _cropAutoBusy,
        onCrop: (c) => _applyCrop(c),
        onCropAuto: () => unawaited(_autoDetectCrop()),
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
  Future<void> _applyModeChange(
    LoadedChapter loaded, {
    required String chosen,
  }) async {
    await _saveProgress(_currentPage, completed: _atEnd);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    await replaceWithResolvedReader(
      context,
      chapter: loaded.chapter,
      current: ReaderMode.webtoon,
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
      onPick: (chapter, sourceId) => _goTo(chapter),
    );
  }
}

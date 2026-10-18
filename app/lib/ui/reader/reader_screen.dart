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
import 'reader_chrome.dart';
import 'reader_progress.dart';
import 'reader_settings_sheet.dart';

/// Webtoon reader (doc 10) — vertical streaming, prefetch ahead, chrome
/// toggle, continuous progress, 3 s auto-next countdown, per-page source
/// fallback (07 §5).
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

  Timer? _countdown;
  int _countdownSeconds = 0;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAutoNextCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// Scroll events stop right after the clamp settles (the ballistic's
  /// final delta never re-fires) — on-device QA 2026-10-18 showed the
  /// end never reaching the auto-next check when the user STOPS at the
  /// bottom. This low-rate poller re-runs the check while parked.
  Timer? _edgePoller;

  final _scroll = ScrollController();

  /// In-flight page futures for THIS chapter. Without the memo, the
  /// seed-prefetch and the slot's own build both resolve the early pages
  /// — and the pipeline only dedups AFTER downloading, so that was 2x
  /// network for every first screen. Successes stay memoized for the
  /// screen's lifetime; failures are evicted so Retry works.
  final _inflight = <int, Future<PageFile>>{};

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
      _edgePoller?.cancel();
      _edgePoller = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (!mounted || _loaded == null || !_scroll.hasClients) return;
        _maybeAutoNext(
            slotOffsets(_heights), _scroll.position.viewportDimension,
            DateTime.now());
      });
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
          : _slotWidth * PageSlot.estimatedAspect;

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
    }).then<PageFile>((pf) => pf, onError: (Object e) {
      _inflight.remove(idx);
      throw e;
    });
    _inflight[idx] = future;
    return future;
  }

  void _onDimensions(int idx, int? w, int? h) {
    if (w == null || h == null || w <= 0 || !mounted) return;
    if (idx >= _heights.length) return;
    final exact = _slotWidth * h / w;
    if ((exact - _heights[idx]).abs() < 1) return;
    setState(() => _heights[idx] = exact);
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
    if (reachedEnd(_scroll.offset, _scroll.position.maxScrollExtent, viewport)) {
      if (now.difference(_lastSave) >= const Duration(milliseconds: 500)) {
        _lastSave = now;
        _saveProgress(page, completed: true);
      }
      _maybeAutoNext(offsets, viewport, now);
    } else if (now.difference(_lastSave) >= const Duration(milliseconds: 500)) {
      _lastSave = now;
      _saveProgress(page, completed: false);
      _maybeAutoNext(offsets, viewport, now);
    }
  }

  Future<void> _saveProgress(int page, {required bool completed}) async {
    final loaded = _loaded;
    if (loaded == null) return;
    await persistReaderProgress(ref, loaded.chapter,
        pageIndex: completed ? loaded.pages.length - 1 : page,
        completed: completed);
  }

  void _maybeAutoNext(
      List<double> offsets, double viewport, DateTime now) {
    if (!_autoNext || _countdown != null) return;
    // Check at most twice a second.
    if (now.difference(_lastAutoNextCheck) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastAutoNextCheck = now;
    if (!shouldAutoNext(offsets, _heights, _scroll.offset, viewport)) return;
    _armAutoNext();
  }

  Future<void> _armAutoNext() async {
    final loaded = _loaded!;
    final next = await _repo.adjacentChapter(loaded.chapter, forward: true);
    if (next == null || !mounted || _countdown != null) return;
    _countdownSeconds = 3;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _countdown = null;
        _goTo(next);
      }
    });
    setState(() {});
  }

  void _cancelAutoNext() {
    _countdown?.cancel();
    _countdown = null;
    if (mounted) setState(() {});
  }

  /// Chapter switch = replace this route with the same reader, scroll
  /// reset (doc 10 §6 auto-next).
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
    _countdown?.cancel();
    _edgePoller?.cancel();
    _scroll.dispose();
    _setImmersive(false);
    _setAwake(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    return Scaffold(
      backgroundColor: Colors.black,
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
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                scrollCacheExtent: ScrollCacheExtent.pixels(2500),
                itemCount: loaded.pages.length,
                itemBuilder: (context, i) => PageSlot(
                  ref: loaded.pages[i],
                  screenWidth: _slotWidth,
                  resolve: () => _resolvePage(i),
                  onDimensions: _onDimensions,
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
          ],
          ReaderChrome(
            visible: _chromeVisible,
            title: _seriesTitle ?? widget.chapter.title ?? '',
            sourceName: loaded?.chapter.sourceId ?? widget.chapter.sourceId,
            pageText: tFmt(context, 'reader.page', {
              'n': '${_currentPage + 1}',
              'total': '${loaded?.pages.length ?? 0}',
            }),
            progress: loaded == null || loaded.pages.length <= 1
                ? 0
                : _currentPage / (loaded.pages.length - 1),
            canPrev: loaded != null,
            canNext: loaded != null,
            onBack: () => Navigator.of(context).pop(),
            onTitle: () {
              if (loaded == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    DetailScreen(seriesId: loaded.chapter.seriesId),
              ));
            },
            onChapters: loaded == null
                ? () {}
                : () => _openChapterPicker(loaded),
            onPrev: () async {
              final prev = await _repo
                  .adjacentChapter(loaded!.chapter, forward: false);
              if (!mounted) return;
              if (prev != null) _goTo(prev);
            },
            onNext: () async {
              final endText = t(context, 'reader.end');
              final messenger = ScaffoldMessenger.of(context);
              final next =
                  await _repo.adjacentChapter(loaded!.chapter, forward: true);
              if (!mounted) return;
              if (next != null) {
                _goTo(next);
              } else {
                messenger.showSnackBar(SnackBar(content: Text(endText)));
              }
            },
            onSettings: () {
              final settings = ref.read(settingsProvider);
              final controller = ref.read(settingsProvider.notifier);
              final seriesId = widget.chapter.seriesId;
              showReaderSettings(
                context,
                prefetchAhead: settings.getInt('reader_prefetch_ahead', 6),
                keepAwake: settings.getBool('reader_keep_awake', true),
                autoNext: settings.getBool('reader_auto_next', true),
                rtl: settings.getBool('reader_rtl', false),
                mode: settings.get('reader_mode_$seriesId', 'auto'),
                onMode: (m) => controller.set('reader_mode_$seriesId', m),
                onChanged: (prefetch, awake, autoNext, rtl) {
                  controller.set('reader_prefetch_ahead', '$prefetch');
                  controller.set('reader_keep_awake', awake ? '1' : '0');
                  controller.set('reader_auto_next', autoNext ? '1' : '0');
                  controller.set('reader_rtl', rtl ? '1' : '0');
                  _setAwake(awake);
                },
              );
            },
            onSeek: (v) {
              final total = loaded?.pages.length ?? 1;
              _jumpTo((v * (total - 1)).round());
            },
          ),
          if (_countdown != null)
            Positioned(
              bottom: 96,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            tFmt(context, 'reader.next_toast',
                                {'n': '$_countdownSeconds'}),
                            style: const TextStyle(color: Colors.white)),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _cancelAutoNext,
                          child: Text(t(context, 'reader.cancel'),
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tapZone(VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: const SizedBox.expand(),
      );

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

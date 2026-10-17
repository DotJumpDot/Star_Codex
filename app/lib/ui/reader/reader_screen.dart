import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ScrollCacheExtent;
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
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

  final _scroll = ScrollController();

  int get _prefetchAhead =>
      ref.read(settingsProvider).getInt('reader_prefetch_ahead', 6);
  bool get _keepAwake =>
      ref.read(settingsProvider).getBool('reader_keep_awake', true);
  bool get _autoNext =>
      ref.read(settingsProvider).getBool('reader_auto_next', true);

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
      if (!mounted) return;
      setState(() {
        _failed = false;
        _loaded = loaded;
        _seriesTitle = series?.title;
        _heights = [
          for (final p in loaded.pages) _estimatedHeight(p),
        ];
      });
      _seedPrefetch();
    } catch (_) {
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

  /// Seed pages [0..5] into the queue (doc 10 §Prefetch).
  void _seedPrefetch() {
    final loaded = _loaded;
    if (loaded == null) return;
    for (var i = 0;
        i < loaded.pages.length && i <= 5;
        i++) {
      _resolvePage(i);
    }
  }

  /// One page, disk-first; on failure fall to the next sibling source's
  /// copy of the same number (07 §5) and badge it.
  Future<PageFile> _resolvePage(int idx) async {
    final loaded = _loaded!;
    final ref = loaded.pages[idx];
    final cached = await _repo.cachedFile(ref);
    if (cached != null) return cached;
    try {
      return await _repo.fetchPage(loaded.chapter.id!, ref, loaded.referer);
    } catch (e) {
      final sibs = await _repo.siblings(loaded.chapter);
      for (final sib in sibs) {
        try {
          final sibLoaded = await _repo.loadChapter(sib);
          if (idx >= sibLoaded.pages.length) continue;
          final pf = await _repo.fetchPage(
              sibLoaded.chapter.id!, sibLoaded.pages[idx], sibLoaded.referer);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tFmt(context, 'reader.fallback_source',
                  {'source': sibLoaded.chapter.sourceId})),
              duration: const Duration(seconds: 2),
            ));
          }
          return pf;
        } catch (_) {
          continue;
        }
      }
      rethrow;
    }
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
    if (page != _currentPage) setState(() => _currentPage = page);

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
    await ref
        .read(chaptersDaoProvider)
        .saveProgress(loaded.chapter.id!,
            pageIndex: completed ? loaded.pages.length - 1 : page,
            completed: completed);
    if (completed) {
      await ref.read(libraryDaoProvider).markRead(
          loaded.chapter.seriesId, loaded.chapter.id!,
          DateTime.now().millisecondsSinceEpoch);
    }
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
            onSettings: () => showReaderSettings(
              context,
              prefetchAhead: _prefetchAhead,
              keepAwake: _keepAwake,
              autoNext: _autoNext,
              onChanged: (prefetch, awake, autoNext) {
                final c = ref.read(settingsProvider.notifier);
                c.set('reader_prefetch_ahead', '$prefetch');
                c.set('reader_keep_awake', awake ? '1' : '0');
                c.set('reader_auto_next', autoNext ? '1' : '0');
                _setAwake(awake);
              },
            ),
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

import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
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
import 'reader_chrome.dart';
import 'reader_settings_sheet.dart';

/// Paged reader (doc 11 A): horizontal PageView for manga-style pages,
/// double-tap zoom + pan (ExtendedImage gesture), tap zones active only at
/// scale 1, overscroll past the last page → next chapter. Shares the
/// webtoon's chrome/progress/fallback plumbing.
class PagedReaderScreen extends ConsumerStatefulWidget {
  const PagedReaderScreen({super.key, required this.chapter});

  final Chapter chapter;

  @override
  ConsumerState<PagedReaderScreen> createState() => _PagedReaderScreenState();
}

class _PagedReaderScreenState extends ConsumerState<PagedReaderScreen> {
  LoadedChapter? _loaded;
  String? _seriesTitle;
  int _page = 0;
  bool _chromeVisible = true;
  bool _switching = false;

  /// Created in [_open] once the saved page is known (doc 11 DoD:
  /// progress resumes in both modes). Null while loading.
  PageController? _pageController;
  final _gestureKey = GlobalKey<ExtendedImageGestureState>();
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOverscroll = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _rtl =>
      ref.read(settingsProvider).getBool('reader_rtl', false);
  bool get _autoNext =>
      ref.read(settingsProvider).getBool('reader_auto_next', true);
  bool get _keepAwake =>
      ref.read(settingsProvider).getBool('reader_keep_awake', true);

  ReaderRepo get _repo => ref.read(readerRepoProvider);

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
      final series =
          await ref.read(seriesDaoProvider).byId(loaded.chapter.seriesId);
      final progress = await ref
          .read(chaptersDaoProvider)
          .progress(loaded.chapter.id!);
      final initial = progress != null && !progress.completed
          ? progress.pageIndex.clamp(0, loaded.pages.length - 1)
          : 0;
      if (!mounted) return;
      setState(() {
        _loaded = loaded;
        _seriesTitle = series?.title;
        _page = initial;
        _pageController = PageController(initialPage: initial);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = null);
    }
  }

  Future<void> _saveProgress(int page, {required bool completed}) async {
    final loaded = _loaded;
    if (loaded == null) return;
    await ref.read(chaptersDaoProvider).saveProgress(loaded.chapter.id!,
        pageIndex: page, completed: completed);
    if (completed) {
      await ref.read(libraryDaoProvider).markRead(loaded.chapter.seriesId,
          loaded.chapter.id!, DateTime.now().millisecondsSinceEpoch);
    }
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    final loaded = _loaded;
    if (loaded == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSave) >= const Duration(milliseconds: 500)) {
      _lastSave = now;
      _saveProgress(page, completed: page == loaded.pages.length - 1);
    }
  }

  /// Swipe past the last page → next chapter (doc 11 A), throttled so one
  /// fling only advances once.
  Future<void> _onOverscroll(bool atEnd) async {
    if (!atEnd || !_autoNext || _switching) return;
    final now = DateTime.now();
    if (now.difference(_lastOverscroll) < const Duration(seconds: 2)) return;
    _lastOverscroll = now;
    await _goNext();
  }

  Future<void> _goNext() async {
    final loaded = _loaded;
    if (loaded == null || _switching) return;
    final next = await _repo.adjacentChapter(loaded.chapter, forward: true);
    if (next != null && mounted) {
      _switching = true;
      await _saveProgress(loaded.pages.length - 1, completed: true);
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => PagedReaderScreen(chapter: next),
        ));
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'reader.end'))));
    }
  }

  Future<void> _goPrev() async {
    final loaded = _loaded;
    if (loaded == null || _switching) return;
    final prev = await _repo.adjacentChapter(loaded.chapter, forward: false);
    if (prev != null && mounted) {
      _switching = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => PagedReaderScreen(chapter: prev),
      ));
    }
  }

  bool get _zoomed {
    final details = _gestureKey.currentState?.gestureDetails;
    return details != null && (details.totalScale ?? 1.0) > 1.05;
  }

  void _tapZone(bool forward) {
    if (_zoomed) return; // page-turn taps disabled while zoomed (doc 11 A)
    final loaded = _loaded;
    final controller = _pageController;
    if (loaded == null || controller == null) return;
    final goForward = _rtl ? !forward : forward; // zones swap under RTL
    if (goForward) {
      if (_page < loaded.pages.length - 1) {
        controller.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      } else {
        _goNext();
      }
    } else {
      if (_page > 0) {
        controller.previousPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      } else {
        _goPrev();
      }
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
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
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(t(context, 'common.loading'),
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else ...[
            NotificationListener<OverscrollNotification>(
              onNotification: (n) {
                _onOverscroll(n.overscroll > 0);
                return false;
              },
              child: PageView.builder(
                controller: _pageController!,
                reverse: _rtl,
                itemCount: loaded.pages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, i) => _PageSlotPaged(
                  page: loaded.pages[i],
                  resolve: () => _repo.resolvePage(loaded, i),
                  gestureKey: _gestureKey,
                ),
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
                        child: const SizedBox.expand()),
                  ),
                  Expanded(
                    flex: 4,
                    child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(
                            () => _chromeVisible = !_chromeVisible),
                        child: const SizedBox.expand()),
                  ),
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _tapZone(true),
                        child: const SizedBox.expand()),
                  ),
                ],
              ),
            ),
          ],
          ReaderChrome(
            visible: _chromeVisible,
            title: _seriesTitle ?? widget.chapter.title ?? '',
            sourceName: loaded?.chapter.sourceId ?? widget.chapter.sourceId,
            pageText: tFmt(context, 'reader.page', {
              'n': '${_page + 1}',
              'total': '${loaded?.pages.length ?? 0}',
            }),
            progress: loaded == null || loaded.pages.length <= 1
                ? 0
                : _page / (loaded.pages.length - 1),
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
            onPrev: _goPrev,
            onNext: _goNext,
            onSettings: () => _openSettings(),
            onSeek: (v) {
              final total = loaded?.pages.length ?? 1;
              final target = (v * (total - 1)).round();
              _pageController?.animateToPage(target,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openChapterPicker(LoadedChapter loaded) async {
    final vm =
        await ref.read(seriesRepoProvider).load(loaded.chapter.seriesId);
    if (!mounted) return;
    await showChapterPicker(
      context,
      ref,
      vm: vm,
      current: loaded.chapter,
      onPick: (chapter, sourceId) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => PagedReaderScreen(chapter: chapter),
        ));
      },
    );
  }

  void _openSettings() {
    final settings = ref.read(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    showReaderSettings(
      context,
      prefetchAhead: settings.getInt('reader_prefetch_ahead', 6),
      keepAwake: settings.getBool('reader_keep_awake', true),
      autoNext: settings.getBool('reader_auto_next', true),
      rtl: settings.getBool('reader_rtl', false),
      mode: settings.get('reader_mode_${widget.chapter.seriesId}', 'auto'),
      onMode: (m) => controller.set(
          'reader_mode_${widget.chapter.seriesId}', m),
      onChanged: (prefetch, awake, autoNext, rtl) {
        controller.set('reader_prefetch_ahead', '$prefetch');
        controller.set('reader_keep_awake', awake ? '1' : '0');
        controller.set('reader_auto_next', autoNext ? '1' : '0');
        controller.set('reader_rtl', rtl ? '1' : '0');
        _setAwake(awake);
      },
    );
  }
}

/// One page: BoxFit.contain + gesture mode (double-tap zoom + pan);
/// blurred shimmer placeholder at a 2:3 estimate while loading.
class _PageSlotPaged extends ConsumerStatefulWidget {
  const _PageSlotPaged({
    required this.page,
    required this.resolve,
    required this.gestureKey,
  });

  final ReaderPageRef page;
  final Future<PageFile> Function() resolve;
  final GlobalKey<ExtendedImageGestureState> gestureKey;

  @override
  ConsumerState<_PageSlotPaged> createState() => _PageSlotPagedState();
}

class _PageSlotPagedState extends ConsumerState<_PageSlotPaged> {
  late Future<PageFile?> _future;
  Object? _error;

  @override
  void initState() {
    super.initState();
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
        return ExtendedImage.file(
          File('${dir.path}/${pf.path}'),
          fit: BoxFit.contain,
          mode: ExtendedImageMode.gesture,
          clearMemoryCacheWhenDispose: true,
          extendedImageGestureKey: widget.gestureKey,
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

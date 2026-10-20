import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/reader_repo.dart';
import '../detail/detail_screen.dart';
import 'chapter_picker_sheet.dart';
import 'pull_next.dart';
import 'reader_actions.dart';
import 'reader_drawer.dart';
import 'reader_router.dart';
import 'reader_settings_body.dart';

/// Novel reader (doc 11 B): scrollable Thai text (selected UI font),
/// adjustable size/leading/theme/background opacity, scroll-fraction
/// progress (page_index = percent), ≥97% completes, drag-past-the-end
/// "pull to continue" + explicit next-chapter button (the 1.5 s dwell
/// auto-next is gone), controls in the right-hand drawer.
class NovelReaderScreen extends ConsumerStatefulWidget {
  const NovelReaderScreen({super.key, required this.chapter});

  final Chapter chapter;

  @override
  ConsumerState<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends ConsumerState<NovelReaderScreen> {
  String? _text;
  String? _seriesTitle;
  Object? _error;
  bool _chromeVisible = true;
  bool _switching = false;
  int _percent = 0;
  bool _endVisible = false;

  /// See the webtoon reader: the drawer opens via the KEY (the chrome's
  /// callback context sits above this Scaffold).
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _pull = PullNextTracker(threshold: 120);
  Chapter? _next;
  bool _nextKnown = false;
  bool _nextLookup = false;

  final _scroll = ScrollController();
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  ReaderRepo get _repo => ref.read(readerRepoProvider);

  int get _fontSize =>
      ref.read(settingsProvider).getInt('novel_font_size', 18);
  double get _lineHeight =>
      ref.read(settingsProvider).getDouble('novel_line_height', 1.7);
  String get _theme => ref.read(settingsProvider).get('novel_theme', 'dark');
  double get _bgOpacity =>
      ref.read(settingsProvider).getDouble('novel_bg_opacity', 1.0);
  bool get _autoNext =>
      ref.read(settingsProvider).getBool('reader_auto_next', true);
  String get _uiFontFamily =>
      fontById(ref.read(settingsProvider).get('ui_font', 'sarabun')).family;

  ({Color bg, Color fg}) get _colors =>
      novelThemes[_theme] ?? novelThemes['dark']!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    _scroll.addListener(_onScroll);
  }

  Future<void> _open() async {
    try {
      final text = await _repo.loadNovelText(widget.chapter);
      final series =
          await ref.read(seriesDaoProvider).byId(widget.chapter.seriesId);
      // page_index stores the scroll PERCENT for novels (doc 11 B).
      final progress =
          await ref.read(chaptersDaoProvider).progress(widget.chapter.id!);
      if (!mounted) return;
      setState(() {
        _text = text;
        _seriesTitle = series?.title;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        if (max <= 0) {
          // Whole chapter fits: no scroll events will ever fire, so the
          // end-of-chapter state must be evaluated once here.
          setState(() => _endVisible = true);
          return;
        }
        if (progress != null && !progress.completed && progress.pageIndex > 0) {
          _scroll
              .jumpTo((max * progress.pageIndex / 100).clamp(0.0, max));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final pct = max <= 0 ? 100 : ((_scroll.offset / max) * 100).round();
    if (pct != _percent) setState(() => _percent = pct.clamp(0, 100));

    final now = DateTime.now();
    if (now.difference(_lastSave) >= const Duration(milliseconds: 500)) {
      _lastSave = now;
      _saveProgress(pct.clamp(0, 100), completed: pct >= 97);
    }

    final atEnd = pct >= 97 || max <= 0;
    if (atEnd != _endVisible) setState(() => _endVisible = atEnd);
    if (atEnd) {
      _ensureNext();
    } else if (_pull.dragging) {
      setState(() => _pull.cancel());
    }
  }

  /// Overscroll past the bottom while at the end = pull-to-continue.
  void _onOverscroll(double overscroll) {
    if (!_autoNext || !_endVisible) return;
    // Dragging back shrinks an in-progress pull (indicator follows both
    // directions, user QA 2026-10-19).
    if (overscroll <= 0) {
      if (_pull.dragging) setState(() => _pull.add(overscroll));
      return;
    }
    _ensureNext();
    setState(() => _pull.add(overscroll));
  }

  Future<void> _onScrollEnd() async {
    if (_endVisible) _saveProgress(100, completed: true);
    if (!_pull.dragging) return;
    final go = _pull.release();
    setState(() {});
    if (!go) return;
    await _ensureNext();
    if (!mounted) return;
    if (_next != null) _goNext();
  }

  Future<void> _ensureNext() async {
    if (_nextKnown || _nextLookup) return;
    _nextLookup = true;
    final next = await _repo.adjacentChapter(widget.chapter, forward: true);
    _nextLookup = false;
    if (!mounted) return;
    _next = next;
    _nextKnown = true;
    if (_pull.dragging) setState(() {});
  }

  Future<void> _saveProgress(int percent, {required bool completed}) async {
    await persistReaderProgress(ref, widget.chapter,
        pageIndex: percent, completed: completed);
  }

  Future<void> _goNext() async {
    if (_switching) return;
    final next =
        _nextKnown ? _next : await _repo.adjacentChapter(widget.chapter, forward: true);
    if (next != null && mounted) {
      _switching = true;
      await _saveProgress(100, completed: true);
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => NovelReaderScreen(chapter: next),
        ));
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'reader.end'))));
    }
  }

  Future<void> _goPrev() async {
    if (_switching) return;
    final prev = await _repo.adjacentChapter(widget.chapter, forward: false);
    if (prev != null && mounted) {
      _switching = true;
      // Same rule as _goNext: land the progress write before the swap.
      await _saveProgress(_percent, completed: _percent >= 97);
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => NovelReaderScreen(chapter: prev),
        ));
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final text = _text;
    final paragraphs = text?.split('\n\n') ?? const <String>[];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      endDrawerEnableOpenDragGesture: false,
      endDrawer: _buildDrawer(),
      body: Stack(
        children: [
          if (text == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error == null)
                    const CircularProgressIndicator()
                  else
                    Icon(Icons.cloud_off, color: colors.fg.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                      _error == null
                          ? t(context, 'common.loading')
                          : t(context, 'common.error.title'),
                      style: TextStyle(color: colors.fg.withValues(alpha: 0.7))),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(t(context, 'common.retry')),
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _text = null;
                      });
                      _open();
                    },
                  ),
                ],
              ),
            )
          else
            // Reading surface carries the selected opacity; what shows
            // through is the app scaffold behind it.
            Positioned.fill(
              child: Container(
                color: colors.bg.withValues(alpha: _bgOpacity),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is OverscrollNotification) {
                      _onOverscroll(n.overscroll);
                    }
                    if (n is ScrollEndNotification) _onScrollEnd();
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final para in paragraphs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              para.trim().isEmpty ? '' : '\u2003${para.trim()}',
                              style: GoogleFonts.getFont(
                                _uiFontFamily,
                                fontSize: _fontSize.toDouble(),
                                height: _lineHeight,
                                color: colors.fg,
                              ),
                            ),
                          ),
                        if (_endVisible)
                          Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: FilledButton.icon(
                                icon: const Icon(Icons.skip_next),
                                label: Text(
                                    t(context, 'reader.next_chapter')),
                                onPressed: _goNext,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Tap toggles chrome (novels have no zoom — whole surface taps).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _chromeVisible = !_chromeVisible),
              child: const SizedBox.expand(),
            ),
          ),
          _NovelTopBar(
            visible: _chromeVisible,
            fg: colors.fg,
            title: _seriesTitle ?? widget.chapter.title ?? '',
            subtitle: tFmt(context, 'detail.chapter_number',
                {'n': formatChapterNumber(widget.chapter.number)}),
            onBack: () => Navigator.of(context).pop(),
            onTitle: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DetailScreen(seriesId: widget.chapter.seriesId),
            )),
            onChapters: () => _openChapterPicker(),
            onMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
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
      ),
    );
  }

  Widget _buildDrawer() {
    final settings = ref.read(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final seriesId = widget.chapter.seriesId;
    return ReaderControlDrawer(
      pageText: '$_percent%',
      progress: _percent / 100,
      canPrev: true,
      canNext: true,
      onPrev: _goPrev,
      onNext: _goNext,
      onChapters: () => _openChapterPicker(),
      onSeek: (v) {
        final max = _scroll.hasClients
            ? _scroll.position.maxScrollExtent
            : 0.0;
        _scroll.animateTo(max * v,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      },
      settings: ReaderSettingsBody(
        prefetchAhead: settings.getInt('reader_prefetch_ahead', 6),
        keepAwake: settings.getBool('reader_keep_awake', true),
        autoNext: settings.getBool('reader_auto_next', true),
        rtl: settings.getBool('reader_rtl', false),
        mode: settings.get('reader_mode_$seriesId', 'auto'),
        onMode: (m) {
          controller.set('reader_mode_$seriesId', m);
          unawaited(_applyModeChange(chosen: m));
        },
        novel: true,
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        novelTheme: _theme,
        bgOpacity: _bgOpacity,
        onNovelChanged: (font, line, theme, opacity) {
          controller.set('novel_font_size', '$font');
          controller.set('novel_line_height', line.toString());
          controller.set('novel_theme', theme);
          controller.set('novel_bg_opacity', opacity.toString());
          setState(() {});
        },
        onChanged: (prefetch, awake, autoNext, rtl) {
          controller.set('reader_prefetch_ahead', '$prefetch');
          controller.set('reader_keep_awake', awake ? '1' : '0');
          controller.set('reader_auto_next', autoNext ? '1' : '0');
          controller.set('reader_rtl', rtl ? '1' : '0');
        },
      ),
    );
  }

  /// Persist where we are, then swap this route for the freshly resolved
  /// reader when the mode actually changes screens (no-op otherwise).
  /// [chosen] is the mode JUST picked — SettingsController.set only
  /// publishes after its DB write, so re-reading the provider here can
  /// still see the old value and the swap would silently no-op.
  Future<void> _applyModeChange({required String chosen}) async {
    await _saveProgress(_percent, completed: _percent >= 97);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    await replaceWithResolvedReader(context,
        chapter: widget.chapter,
        current: ReaderMode.novel,
        seriesDao: ref.read(seriesDaoProvider),
        modeOverride: effectiveModeOverride(
            chosen, settings.get('reader_mode_default', 'auto')));
  }

  Future<void> _openChapterPicker() async {
    final vm =
        await ref.read(seriesRepoProvider).load(widget.chapter.seriesId);
    if (!mounted) return;
    final current = widget.chapter;
    await showChapterPicker(
      context,
      ref,
      vm: vm,
      current: current,
      onPick: (chapter, sourceId) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => NovelReaderScreen(chapter: chapter),
        ));
      },
    );
  }
}

/// Novel top bar on a transparent surface tinted toward the theme fg.
class _NovelTopBar extends StatelessWidget {
  const _NovelTopBar({
    required this.visible,
    required this.fg,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onTitle,
    required this.onChapters,
    required this.onMenu,
  });

  final bool visible;
  final Color fg;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onTitle;
  final VoidCallback onChapters;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        offset: visible ? Offset.zero : const Offset(0, -1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: visible ? 1 : 0,
          child: Container(
            color: fg.withValues(alpha: 0.08),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  BackButton(color: fg, onPressed: onBack),
                  Expanded(
                    child: GestureDetector(
                      onTap: onTitle,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: fg, fontWeight: FontWeight.w600)),
                          Text(subtitle,
                              style: TextStyle(
                                  color: fg.withValues(alpha: 0.7),
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.menu_book, color: fg),
                    tooltip: t(context, 'reader.chapter_picker'),
                    onPressed: onChapters,
                  ),
                  IconButton(
                    icon: Icon(Icons.menu, color: fg),
                    tooltip: t(context, 'reader.controls'),
                    onPressed: onMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

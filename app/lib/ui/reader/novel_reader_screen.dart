import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/reader_repo.dart';
import '../detail/detail_screen.dart';
import 'chapter_picker_sheet.dart';
import 'reader_actions.dart';
import 'reader_settings_sheet.dart';

/// Novel reader (doc 11 B): scrollable Thai text (Sarabun), adjustable
/// size/leading/theme, scroll-fraction progress (page_index = percent),
/// ≥97% or next-chapter completes, end-of-chapter button + 1.5 s dwell
/// auto-next.
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

  Timer? _dwellTimer;
  final _scroll = ScrollController();
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDwellCheck = DateTime.fromMillisecondsSinceEpoch(0);

  ReaderRepo get _repo => ref.read(readerRepoProvider);

  int get _fontSize =>
      ref.read(settingsProvider).getInt('novel_font_size', 18);
  double get _lineHeight =>
      ref.read(settingsProvider).getDouble('novel_line_height', 1.7);
  String get _theme => ref.read(settingsProvider).get('novel_theme', 'dark');
  bool get _autoNext =>
      ref.read(settingsProvider).getBool('reader_auto_next', true);

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

    // End-of-chapter visibility + 1.5 s dwell auto-next (doc 11 B).
    final atEnd = pct >= 97 || max <= 0;
    if (atEnd != _endVisible) setState(() => _endVisible = atEnd);
    if (atEnd && _autoNext && _dwellTimer == null && !_switching) {
      if (now.difference(_lastDwellCheck) >= const Duration(seconds: 2)) {
        _armDwell();
      } else if (_dwellTimer == null) {
        _lastDwellCheck = now;
      }
    }
  }

  void _armDwell() {
    _dwellTimer = Timer(const Duration(milliseconds: 1500), () {
      _dwellTimer = null;
      if (mounted && _endVisible && _autoNext) _goNext();
    });
  }

  Future<void> _saveProgress(int percent, {required bool completed}) async {
    await persistReaderProgress(ref, widget.chapter,
        pageIndex: percent, completed: completed);
  }

  Future<void> _goNext() async {
    if (_switching) return;
    final next = await _repo.adjacentChapter(widget.chapter, forward: true);
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
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => NovelReaderScreen(chapter: prev),
      ));
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final text = _text;
    final paragraphs = text?.split('\n\n') ?? const <String>[];

    return Scaffold(
      backgroundColor: colors.bg,
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
            SingleChildScrollView(
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
                        style: GoogleFonts.sarabun(
                          fontSize: _fontSize.toDouble(),
                          height: _lineHeight,
                          color: colors.fg,
                        ),
                      ),
                    ),
                  if (_endVisible)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.skip_next),
                          label: Text(t(context, 'reader.next_chapter')),
                          onPressed: _goNext,
                        ),
                      ),
                    ),
                ],
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
          _NovelChrome(
            visible: _chromeVisible,
            fg: colors.fg,
            title: _seriesTitle ?? widget.chapter.title ?? '',
            subtitle: tFmt(context, 'detail.chapter_number',
                {'n': formatChapterNumber(widget.chapter.number)}),
            percentText: '$_percent%',
            progress: _percent / 100,
            onBack: () => Navigator.of(context).pop(),
            onTitle: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DetailScreen(seriesId: widget.chapter.seriesId),
            )),
            onChapters: () => _openChapterPicker(),
            onPrev: _goPrev,
            onNext: _goNext,
            onSettings: () => _openSettings(),
            onSeek: (v) {
              final max = _scroll.hasClients
                  ? _scroll.position.maxScrollExtent
                  : 0.0;
              _scroll.animateTo(max * v,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut);
            },
          ),
        ],
      ),
    );
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
      onMode: (m) =>
          controller.set('reader_mode_${widget.chapter.seriesId}', m),
      novel: true,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      novelTheme: _theme,
      onNovelChanged: (font, line, theme) {
        controller.set('novel_font_size', '$font');
        controller.set('novel_line_height', line.toString());
        controller.set('novel_theme', theme);
        setState(() {});
      },
      onChanged: (prefetch, awake, autoNext, rtl) {
        controller.set('reader_prefetch_ahead', '$prefetch');
        controller.set('reader_keep_awake', awake ? '1' : '0');
        controller.set('reader_auto_next', autoNext ? '1' : '0');
        controller.set('reader_rtl', rtl ? '1' : '0');
      },
    );
  }
}

/// Novel chrome on a transparent surface tinted toward the theme fg.
class _NovelChrome extends StatelessWidget {
  const _NovelChrome({
    required this.visible,
    required this.fg,
    required this.title,
    required this.subtitle,
    required this.percentText,
    required this.progress,
    required this.onBack,
    required this.onTitle,
    required this.onChapters,
    required this.onPrev,
    required this.onNext,
    required this.onSettings,
    required this.onSeek,
  });

  final bool visible;
  final Color fg;
  final String title;
  final String subtitle;
  final String percentText;
  final double progress;
  final VoidCallback onBack;
  final VoidCallback onTitle;
  final VoidCallback onChapters;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSettings;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: Column(
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset: visible ? Offset.zero : const Offset(0, -1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: visible ? 1 : 0,
              child: Container(
                color: fg.withValues(alpha: 0.08),
                child: SafeArea(
                  bottom: false,
                  child: ListTile(
                    leading: BackButton(color: fg, onPressed: onBack),
                    title: GestureDetector(
                      onTap: onTitle,
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: fg, fontWeight: FontWeight.w600)),
                    ),
                    subtitle: Text(subtitle,
                        style: TextStyle(
                            color: fg.withValues(alpha: 0.7), fontSize: 11)),
                    trailing: IconButton(
                      icon: Icon(Icons.menu_book, color: fg),
                      onPressed: onChapters,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset: visible ? Offset.zero : const Offset(0, 1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: visible ? 1 : 0,
              child: Container(
                color: fg.withValues(alpha: 0.08),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          activeColor: fg,
                          inactiveColor: fg.withValues(alpha: 0.3),
                          value: progress.clamp(0.0, 1.0),
                          onChanged: onSeek,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                              icon: Icon(Icons.skip_previous, color: fg),
                              onPressed: onPrev),
                          Expanded(
                              child: Center(
                                  child: Text(percentText,
                                      style: TextStyle(
                                          color: fg,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ])))),
                          IconButton(
                              icon: Icon(Icons.skip_next, color: fg),
                              onPressed: onNext),
                          IconButton(
                              icon: Icon(Icons.settings, color: fg),
                              onPressed: onSettings),
                        ],
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
}

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Reader chrome (doc 10 §6): tap anywhere in the middle 60% toggles the
/// top/bottom bars with a 300 ms animation.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.title,
    required this.sourceName,
    required this.pageText,
    required this.progress,
    required this.canPrev,
    required this.canNext,
    required this.onBack,
    required this.onTitle,
    required this.onChapters,
    required this.onPrev,
    required this.onNext,
    required this.onSettings,
    required this.onSeek,
  });

  final bool visible;
  final String title;
  final String sourceName;
  final String pageText;

  /// 0..1 slider position (NaN-safe: pass 0 when total is 1).
  final double progress;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onBack;
  final VoidCallback onTitle;
  final VoidCallback onChapters;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSettings;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final foreground = Colors.white;
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
                color: Colors.black87,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      BackButton(color: foreground, onPressed: onBack),
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
                                      color: foreground,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  '${t(context, 'reader.from_source')} $sourceName',
                                  style: TextStyle(
                                      color: foreground.withValues(alpha: 0.7),
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.menu_book, color: foreground),
                        tooltip: t(context, 'reader.chapter_picker'),
                        onPressed: onChapters,
                      ),
                    ],
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
                color: Colors.black87,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: progress.clamp(0.0, 1.0),
                          onChanged: onSeek,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.skip_previous, color: foreground),
                            tooltip: t(context, 'reader.prev_chapter'),
                            onPressed: canPrev ? onPrev : null,
                          ),
                          Expanded(
                            child: Center(
                              child: Text(pageText,
                                  style: TextStyle(
                                      color: foreground,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_next, color: foreground),
                            tooltip: t(context, 'reader.next_chapter'),
                            onPressed: canNext ? onNext : null,
                          ),
                          IconButton(
                            icon: Icon(Icons.settings, color: foreground),
                            tooltip: t(context, 'reader.settings'),
                            onPressed: onSettings,
                          ),
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

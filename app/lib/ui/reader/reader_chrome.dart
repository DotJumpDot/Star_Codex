import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Reader top chrome (doc 10 §6): tap anywhere in the middle 60% toggles
/// the bar with a 300 ms animation. Everything that used to live in the
/// bottom bar (position slider, prev/next, settings) moved to the
/// right-hand control drawer; [onMenu] opens it.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.title,
    required this.sourceName,
    required this.onBack,
    required this.onTitle,
    required this.onChapters,
    required this.onMenu,
  });

  final bool visible;
  final String title;
  final String sourceName;
  final VoidCallback onBack;
  final VoidCallback onTitle;
  final VoidCallback onChapters;

  /// Hamburger → right-hand control drawer (never a swipe).
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final foreground = Colors.white;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
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
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${t(context, 'reader.from_source')} $sourceName',
                            style: TextStyle(
                              color: foreground.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.menu_book, color: foreground),
                    tooltip: t(context, 'reader.chapter_picker'),
                    onPressed: onChapters,
                  ),
                  IconButton(
                    icon: Icon(Icons.menu, color: foreground),
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

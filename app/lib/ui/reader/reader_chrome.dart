import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';

/// The chrome subtitle's chapter part: "ตอนที่ 69" plus the chapter's own
/// name when it has one (user request 2026-10-24: the reader bar only
/// said "จาก `<source>`" — after a drag-to-continue switch there was no
/// telling WHICH chapter you landed on). Number-only when the title is
/// empty or repeats the number.
String readerChapterLabel(BuildContext context, Chapter chapter) {
  final number = tFmt(context, 'detail.chapter_number', {
    'n': formatChapterNumber(chapter.number),
  });
  final extra = stripChapterNumberPrefix(chapter.title);
  return extra == null ? number : '$number  $extra';
}

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
    this.chapterLabel,
    required this.onBack,
    required this.onTitle,
    required this.onChapters,
    required this.onMenu,
  });

  final bool visible;
  final String title;
  final String sourceName;

  /// "ตอนที่ …  `<name>`" leading the subtitle line (see
  /// [readerChapterLabel]); null falls back to the source-only line.
  final String? chapterLabel;
  final VoidCallback onBack;
  final VoidCallback onTitle;
  final VoidCallback onChapters;

  /// Hamburger → right-hand control drawer (never a swipe).
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final foreground = Colors.white;
    final sourceLine = TextStyle(
      color: foreground.withValues(alpha: 0.7),
      fontSize: 11,
    );
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
                          // The chapter label ellipsizes FIRST; the
                          // source tail always stays visible (user
                          // request 2026-10-24).
                          if (chapterLabel == null)
                            Text(
                              '${t(context, 'reader.from_source')} $sourceName',
                              style: sourceLine,
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Expanded(
                                  child: Text(
                                    chapterLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sourceLine,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${t(context, 'reader.from_source')} $sourceName',
                                  style: sourceLine,
                                ),
                              ],
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

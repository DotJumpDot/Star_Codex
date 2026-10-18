import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'reader_settings_body.dart';

/// Right-hand control drawer for every reader mode (webtoon / paged /
/// novel): position slider + page counter, prev/next chapter, chapter
/// list, and the full settings panel. Opened from the hamburger in the
/// reader's top bar only — never by swiping, so reading gestures stay
/// unmolested.
class ReaderControlDrawer extends StatelessWidget {
  const ReaderControlDrawer({
    super.key,
    required this.pageText,
    required this.progress,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onChapters,
    required this.onSeek,
    required this.settings,
  });

  final String pageText;

  /// 0..1 position for the slider (NaN-safe: pass 0 when total is 1).
  final double progress;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onChapters;
  final ValueChanged<double> onSeek;

  /// Prebuilt [ReaderSettingsBody] with the reader's current values.
  final Widget settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      width: 320,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(t(context, 'reader.controls'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(pageText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ),
            Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: onSeek,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.skip_previous, size: 18),
                      label: Text(t(context, 'reader.prev_chapter')),
                      onPressed: canPrev ? onPrev : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: Text(t(context, 'reader.next_chapter')),
                      onPressed: canNext ? onNext : null,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.menu_book, size: 18),
                label: Text(t(context, 'reader.chapter_picker')),
                onPressed: onChapters,
              ),
            ),
            const Divider(height: 24),
            settings,
          ],
        ),
      ),
    );
  }
}

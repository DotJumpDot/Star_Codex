import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Novel reader themes (doc 11 B): ขาว / น้ำตาลเหลือง (sepia) / ดำ.
const novelThemes = <String, ({Color bg, Color fg})>{
  'light': (bg: Colors.white, fg: Color(0xFF1A1B1F)),
  'sepia': (bg: Color(0xFFF5EDDC), fg: Color(0xFF5B4636)),
  'dark': (bg: Colors.black, fg: Color(0xFFE4E2E6)),
};

/// Reader settings sheet (doc 10 §6 + doc 11):
/// - shared: reader-mode override (persisted per series), prefetch ahead,
///   keep-screen-on, auto-next, RTL (paged only)
/// - novel only: font size, line height, theme
Future<void> showReaderSettings(
  BuildContext context, {
  required int prefetchAhead,
  required bool keepAwake,
  required bool autoNext,
  required bool rtl,
  required void Function(
          int prefetch, bool awake, bool autoNext, bool rtl)
      onChanged,
  String? mode, // current override: auto|webtoon|paged|novel
  ValueChanged<String>? onMode,
  bool novel = false,
  int fontSize = 18,
  double lineHeight = 1.7,
  String novelTheme = 'dark',
  void Function(int font, double line, String theme)? onNovelChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      var prefetch = prefetchAhead;
      var awake = keepAwake;
      var next = autoNext;
      var rtlValue = rtl;
      var font = fontSize;
      var leading = lineHeight;
      var theme = novelTheme;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onMode != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(t(sheetContext, 'reader.mode'),
                          style: Theme.of(sheetContext).textTheme.labelLarge),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: RadioGroup<String>(
                      groupValue: mode,
                      onChanged: (v) {
                        if (v != null) onMode(v);
                        setSheetState(() => mode = v);
                      },
                      child: Wrap(
                        children: [
                          for (final m in const [
                            'auto',
                            'webtoon',
                            'paged',
                            'novel'
                          ])
                            RadioListTile<String>(
                              dense: true,
                              title: Text(t(sheetContext, 'reader.mode.$m')),
                              value: m,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                ],
                SwitchListTile(
                  title: Text(t(sheetContext, 'reader.keep_awake')),
                  value: awake,
                  onChanged: (v) {
                    setSheetState(() => awake = v);
                    onChanged(prefetch, awake, next, rtlValue);
                  },
                ),
                SwitchListTile(
                  title: Text(t(sheetContext, 'reader.auto_next')),
                  value: next,
                  onChanged: (v) {
                    setSheetState(() => next = v);
                    onChanged(prefetch, awake, next, rtlValue);
                  },
                ),
                SwitchListTile(
                  title: Text(t(sheetContext, 'reader.rtl')),
                  value: rtlValue,
                  onChanged: (v) {
                    setSheetState(() => rtlValue = v);
                    onChanged(prefetch, awake, next, rtlValue);
                  },
                ),
                ListTile(
                  title: Text(t(sheetContext, 'reader.prefetch_ahead')),
                  subtitle: Slider(
                    min: 3,
                    max: 12,
                    divisions: 9,
                    label: '$prefetch',
                    value: prefetch.toDouble(),
                    onChanged: (v) {
                      setSheetState(() => prefetch = v.round());
                      onChanged(prefetch, awake, next, rtlValue);
                    },
                  ),
                  trailing: Text('$prefetch'),
                ),
                if (novel) ...[
                  const Divider(),
                  ListTile(
                    title: Text(t(sheetContext, 'reader.novel.font')),
                    subtitle: Slider(
                      min: 14,
                      max: 30,
                      divisions: 16,
                      label: '$font',
                      value: font.toDouble(),
                      onChanged: (v) {
                        setSheetState(() => font = v.round());
                        onNovelChanged?.call(font, leading, theme);
                      },
                    ),
                    trailing: Text('$font'),
                  ),
                  ListTile(
                    title: Text(t(sheetContext, 'reader.novel.line_height')),
                    subtitle: Slider(
                      min: 1.4,
                      max: 2.2,
                      divisions: 8,
                      label: leading.toStringAsFixed(1),
                      value: leading,
                      onChanged: (v) {
                        setSheetState(
                            () => leading = double.parse(v.toStringAsFixed(1)));
                        onNovelChanged?.call(font, leading, theme);
                      },
                    ),
                    trailing: Text(leading.toStringAsFixed(1)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Text(t(sheetContext, 'reader.novel.theme'),
                            style:
                                Theme.of(sheetContext).textTheme.labelLarge),
                        const Spacer(),
                        SegmentedButton<String>(
                          segments: [
                            for (final tKey in const ['light', 'sepia', 'dark'])
                              ButtonSegment(
                                  value: tKey,
                                  label: Text(
                                      t(sheetContext, 'reader.novel.$tKey'))),
                          ],
                          selected: {theme},
                          onSelectionChanged: (v) {
                            setSheetState(() => theme = v.first);
                            onNovelChanged?.call(font, leading, theme);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

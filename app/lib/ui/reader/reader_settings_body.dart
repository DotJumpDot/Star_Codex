import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Novel reader themes (doc 11 B): ขาว / น้ำตาลเหลือง (sepia) / ดำ. The
/// background color is further scaled by the `novel_bg_opacity` setting.
const novelThemes = <String, ({Color bg, Color fg})>{
  'light': (bg: Colors.white, fg: Color(0xFF1A1B1F)),
  'sepia': (bg: Color(0xFFF5EDDC), fg: Color(0xFF5B4636)),
  'dark': (bg: Colors.black, fg: Color(0xFFE4E2E6)),
};

/// Reader settings panel (doc 10 §6 + doc 11), rendered inside the
/// right-hand control drawer:
/// - shared: reader-mode override (persisted per series), prefetch ahead,
///   keep-screen-on, auto-next (gates the drag-to-continue pull), RTL
/// - novel only: font size, line height, theme, background opacity
class ReaderSettingsBody extends StatefulWidget {
  const ReaderSettingsBody({
    super.key,
    required this.prefetchAhead,
    required this.keepAwake,
    required this.autoNext,
    required this.rtl,
    required this.onChanged,
    this.mode,
    this.onMode,
    this.novel = false,
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.novelTheme = 'dark',
    this.bgOpacity = 1.0,
    this.onNovelChanged,
  });

  final int prefetchAhead;
  final bool keepAwake;
  final bool autoNext;
  final bool rtl;
  final void Function(int prefetch, bool awake, bool autoNext, bool rtl)
      onChanged;

  /// Current override: auto|webtoon|paged|novel (null hides the section).
  final String? mode;
  final ValueChanged<String>? onMode;

  final bool novel;
  final int fontSize;
  final double lineHeight;
  final String novelTheme;
  final double bgOpacity;
  final void Function(int font, double line, String theme, double opacity)?
      onNovelChanged;

  @override
  State<ReaderSettingsBody> createState() => _ReaderSettingsBodyState();
}

class _ReaderSettingsBodyState extends State<ReaderSettingsBody> {
  late int prefetch = widget.prefetchAhead;
  late bool awake = widget.keepAwake;
  late bool next = widget.autoNext;
  late bool rtlValue = widget.rtl;
  late int font = widget.fontSize;
  late double leading = widget.lineHeight;
  late String theme = widget.novelTheme;
  late double opacity = widget.bgOpacity;
  String? mode;

  @override
  void initState() {
    super.initState();
    mode = widget.mode;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onMode != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(t(context, 'reader.mode'),
                style: Theme.of(context).textTheme.labelLarge),
          ),
          RadioGroup<String>(
            groupValue: mode,
            onChanged: (v) {
              if (v != null) widget.onMode!(v);
              setState(() => mode = v);
            },
            child: Column(
              children: [
                for (final m in const ['auto', 'webtoon', 'paged', 'novel'])
                  RadioListTile<String>(
                    dense: true,
                    title: Text(t(context, 'reader.mode.$m')),
                    value: m,
                  ),
              ],
            ),
          ),
          const Divider(),
        ],
        SwitchListTile(
          dense: true,
          title: Text(t(context, 'reader.keep_awake')),
          value: awake,
          onChanged: (v) {
            setState(() => awake = v);
            widget.onChanged(prefetch, awake, next, rtlValue);
          },
        ),
        SwitchListTile(
          dense: true,
          title: Text(t(context, 'reader.auto_next')),
          subtitle: Text(t(context, 'reader.auto_next_hint'),
              style: Theme.of(context).textTheme.labelSmall),
          value: next,
          onChanged: (v) {
            setState(() => next = v);
            widget.onChanged(prefetch, awake, next, rtlValue);
          },
        ),
        SwitchListTile(
          dense: true,
          title: Text(t(context, 'reader.rtl')),
          value: rtlValue,
          onChanged: (v) {
            setState(() => rtlValue = v);
            widget.onChanged(prefetch, awake, next, rtlValue);
          },
        ),
        ListTile(
          dense: true,
          title: Text(t(context, 'reader.prefetch_ahead')),
          subtitle: Slider(
            min: 3,
            max: 12,
            divisions: 9,
            label: '$prefetch',
            value: prefetch.toDouble(),
            onChanged: (v) {
              setState(() => prefetch = v.round());
              widget.onChanged(prefetch, awake, next, rtlValue);
            },
          ),
          trailing: Text('$prefetch'),
        ),
        if (widget.novel) ...[
          const Divider(),
          ListTile(
            dense: true,
            title: Text(t(context, 'reader.novel.font')),
            subtitle: Slider(
              min: 14,
              max: 30,
              divisions: 16,
              label: '$font',
              value: font.toDouble(),
              onChanged: (v) {
                setState(() => font = v.round());
                _novelChanged();
              },
            ),
            trailing: Text('$font'),
          ),
          ListTile(
            dense: true,
            title: Text(t(context, 'reader.novel.line_height')),
            subtitle: Slider(
              min: 1.4,
              max: 2.2,
              divisions: 8,
              label: leading.toStringAsFixed(1),
              value: leading,
              onChanged: (v) {
                setState(() => leading = double.parse(v.toStringAsFixed(1)));
                _novelChanged();
              },
            ),
            trailing: Text(leading.toStringAsFixed(1)),
          ),
          ListTile(
            dense: true,
            title: Text(t(context, 'reader.novel.bg_opacity')),
            subtitle: Slider(
              min: 0.3,
              max: 1.0,
              divisions: 14,
              label: '${(opacity * 100).round()}%',
              value: opacity,
              onChanged: (v) {
                setState(() => opacity = v);
                _novelChanged();
              },
            ),
            trailing: Text('${(opacity * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Text(t(context, 'reader.novel.theme'),
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                SegmentedButton<String>(
                  segments: [
                    for (final tKey in const ['light', 'sepia', 'dark'])
                      ButtonSegment(
                          value: tKey,
                          label: Text(t(context, 'reader.novel.$tKey'))),
                  ],
                  selected: {theme},
                  onSelectionChanged: (v) {
                    setState(() => theme = v.first);
                    _novelChanged();
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _novelChanged() =>
      widget.onNovelChanged?.call(font, leading, theme, opacity);
}

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'reader_crop.dart';

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
    this.crop,
    this.onCrop,
    this.onCropAuto,
    this.cropAutoBusy = false,
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

  /// Webtoon-only screen-crop controls (letterboxed chapters). Non-null
  /// [crop] shows the section.
  final ReaderCrop? crop;
  final ValueChanged<ReaderCrop>? onCrop;
  final VoidCallback? onCropAuto;
  final bool cropAutoBusy;

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
        if (widget.crop != null && widget.onCrop != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(t(context, 'reader.crop.title'),
                style: Theme.of(context).textTheme.labelLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(t(context, 'reader.crop.position_hint'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ListTile(
            dense: true,
            title: Text(t(context, 'reader.crop.zoom')),
            subtitle: Slider(
              min: 1.0,
              max: 3.0,
              divisions: 20,
              label: '${widget.crop!.zoom.toStringAsFixed(1)}×',
              value: widget.crop!.zoom.clamp(1.0, 3.0),
              onChanged: (v) => widget.onCrop!(
                  ReaderCrop(zoom: v, cropX: widget.crop!.cropX)),
            ),
            trailing: Text('${widget.crop!.zoom.toStringAsFixed(1)}×'),
          ),
          ListTile(
            dense: true,
            title: Text(t(context, 'reader.crop.position')),
            subtitle: Slider(
              min: 0.0,
              max: 1.0,
              divisions: 20,
              value: widget.crop!.cropX,
              label: widget.crop!.cropX < 0.33
                  ? t(context, 'reader.crop.position_left')
                  : widget.crop!.cropX > 0.67
                      ? t(context, 'reader.crop.position_right')
                      : t(context, 'reader.crop.position_center'),
              onChanged: widget.crop!.zoom > 1.01
                  ? (v) => widget.onCrop!(
                      ReaderCrop(zoom: widget.crop!.zoom, cropX: v))
                  : null,
            ),
            trailing: const Icon(Icons.swap_horiz, size: 18),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: widget.cropAutoBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.crop_free, size: 18),
                    label: Text(t(context, 'reader.crop.auto')),
                    onPressed:
                        widget.cropAutoBusy ? null : widget.onCropAuto,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: widget.crop!.active
                        ? () =>
                            widget.onCrop!(const ReaderCrop())
                        : null,
                    child: Text(t(context, 'reader.crop.reset')),
                  ),
                ),
              ],
            ),
          ),
        ],
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

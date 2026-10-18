import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/settings_provider.dart';
import '../shell/star_app_bar.dart';
import 'appearance_section.dart';
import 'settings_storage_sources.dart';

/// Settings tab (Plan/14, reworked): Language / Appearance / Reading /
/// Novel / Navigation / Library sections + storage, sources, about. EVERY
/// control writes through settings_dao immediately (no Save button) and
/// hot-applies where the consuming side is reactive (theme, font,
/// language, sources).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final lang = ref.watch(languageProvider);

    return Scaffold(
      appBar: starAppBar(context, ref: ref,
          title: Text(t(context, 'tab.settings'))),
      body: ListView(
        children: [
          _SectionHeader(t(context, 'settings.language')),
          RadioGroup<String>(
            groupValue: lang,
            onChanged: (v) =>
                v == null ? null : ref.read(languageProvider.notifier).set(v),
            child: Column(children: [
              for (final (code, label) in const [
                ('th', 'settings.lang_th'),
                ('en', 'settings.lang_en'),
              ])
                RadioListTile<String>(
                  value: code,
                  title: Text(t(context, label)),
                ),
            ]),
          ),

          const AppearanceSection(),

          _SectionHeader(t(context, 'settings.reading')),
          RadioGroup<String>(
            groupValue: settings.get('reader_mode_default', 'auto'),
            onChanged: (v) => _set(ref, 'reader_mode_default', v),
            child: Column(children: [
              for (final (code, label) in const [
                ('auto', 'reader.mode.auto'),
                ('webtoon', 'reader.mode.webtoon'),
                ('paged', 'reader.mode.paged'),
              ])
                RadioListTile<String>(
                  value: code,
                  title: Text(t(context, label)),
                ),
            ]),
          ),
          _SliderTile(
            label: t(context, 'reader.prefetch_ahead'),
            value: settings.getInt('reader_prefetch_ahead', 6).toDouble(),
            min: 2,
            max: 12,
            divisions: 10,
            format: (v) => '${v.round()}',
            onChanged: (v) =>
                _set(ref, 'reader_prefetch_ahead', '${v.round()}'),
          ),
          SwitchListTile(
            title: Text(t(context, 'reader.keep_awake')),
            value: settings.getBool('reader_keep_awake', true),
            onChanged: (v) => _set(ref, 'reader_keep_awake', v ? '1' : '0'),
          ),
          SwitchListTile(
            title: Text(t(context, 'reader.auto_next')),
            subtitle: Text(t(context, 'reader.auto_next_hint'),
                style: Theme.of(context).textTheme.labelSmall),
            value: settings.getBool('reader_auto_next', true),
            onChanged: (v) => _set(ref, 'reader_auto_next', v ? '1' : '0'),
          ),
          SwitchListTile(
            title: Text(t(context, 'reader.rtl')),
            value: settings.getBool('reader_rtl', false),
            onChanged: (v) => _set(ref, 'reader_rtl', v ? '1' : '0'),
          ),

          _SectionHeader(t(context, 'settings.novel')),
          _SliderTile(
            label: t(context, 'reader.novel.font'),
            value: settings.getInt('novel_font_size', 18).toDouble(),
            min: 14,
            max: 30,
            divisions: 16,
            format: (v) => '${v.round()}',
            onChanged: (v) => _set(ref, 'novel_font_size', '${v.round()}'),
          ),
          _SliderTile(
            label: t(context, 'reader.novel.line_height'),
            value: settings.getDouble('novel_line_height', 1.7),
            min: 1.4,
            max: 2.2,
            divisions: 8,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v) =>
                _set(ref, 'novel_line_height', v.toStringAsFixed(1)),
          ),
          _SliderTile(
            label: t(context, 'reader.novel.bg_opacity'),
            value: settings.getDouble('novel_bg_opacity', 1.0),
            min: 0.3,
            max: 1.0,
            divisions: 14,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) =>
                _set(ref, 'novel_bg_opacity', v.toStringAsFixed(2)),
          ),
          RadioGroup<String>(
            groupValue: settings.get('novel_theme', 'dark'),
            onChanged: (v) => _set(ref, 'novel_theme', v),
            child: Column(children: [
              for (final (code, label) in const [
                ('dark', 'reader.novel.dark'),
                ('sepia', 'reader.novel.sepia'),
                ('light', 'reader.novel.light'),
              ])
                RadioListTile<String>(
                  value: code,
                  title: Text(t(context, label)),
                ),
            ]),
          ),

          _SectionHeader(t(context, 'settings.navigation')),
          SwitchListTile(
            title: Text(t(context, 'settings.edge_swipe')),
            subtitle: Text(t(context, 'settings.edge_swipe_hint'),
                style: Theme.of(context).textTheme.labelSmall),
            value: settings.getBool('nav_edge_swipe', false),
            onChanged: (v) => _set(ref, 'nav_edge_swipe', v ? '1' : '0'),
          ),

          _SectionHeader(t(context, 'settings.library')),
          SwitchListTile(
            title: Text(t(context, 'settings.hide_merge')),
            subtitle: Text(t(context, 'settings.hide_merge_hint'),
                style: Theme.of(context).textTheme.labelSmall),
            value: settings.getBool('hide_merge_split', true),
            onChanged: (v) => _set(ref, 'hide_merge_split', v ? '1' : '0'),
          ),
          SwitchListTile(
            title: Text(t(context, 'settings.history_group')),
            subtitle: Text(t(context, 'settings.history_group_hint'),
                style: Theme.of(context).textTheme.labelSmall),
            value: settings.getBool('history_group_series', true),
            onChanged: (v) => _set(ref, 'history_group_series', v ? '1' : '0'),
          ),

          const StorageSection(),
          const SourcesSection(),
          const AboutSection(),
        ],
      ),
    );
  }

  void _set(WidgetRef ref, String key, String? value) {
    if (value == null) return;
    ref.read(settingsProvider.notifier).set(key, value);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Numeric slider row (prefetch / novel font / line height) — shows the
/// live value, writes through on change.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
        ],
      ),
      trailing: Text(format(value), style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

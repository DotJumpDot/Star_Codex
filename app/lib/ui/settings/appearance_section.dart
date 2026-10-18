import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show appearanceProvider;
import '../../core/i18n/i18n.dart';
import '../../core/settings_provider.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_themes.dart';

/// Appearance section (Plan/14, reworked): language radio moved to its own
/// section; theme + font pickers live here. Both pickers preview each
/// option in its own palette/typeface.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(appearanceProvider);
    final font =
        fontById(ref.watch(settingsProvider).get('ui_font', 'sarabun'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, t(context, 'settings.theme')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openThemePicker(context, ref, spec),
            child: _ThemePreviewTile(spec: spec),
          ),
        ),
        _header(context, t(context, 'settings.font')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openFontPicker(context, ref, font),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t(context, 'settings.font_preview'),
                    style: fontPreviewStyle(
                        font, Theme.of(context).textTheme.titleMedium!),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
      );

  Future<void> _openThemePicker(
      BuildContext context, WidgetRef ref, StarThemeSpec current) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t(dialogContext, 'settings.theme')),
        children: [
          for (final spec in starThemes)
            SimpleDialogOption(
              onPressed: () {
                ref.read(appearanceProvider.notifier).set(spec.id);
                Navigator.pop(dialogContext);
              },
              child: Row(
                children: [
                  _ThemeSwatch(spec: spec, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text(spec.name)),
                  if (spec.id == current.id)
                    Icon(Icons.check,
                        color: Theme.of(dialogContext).colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openFontPicker(
      BuildContext context, WidgetRef ref, StarFontSpec current) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t(dialogContext, 'settings.font')),
        children: [
          for (final font in starFonts)
            SimpleDialogOption(
              onPressed: () {
                ref
                    .read(settingsProvider.notifier)
                    .set('ui_font', font.id);
                Navigator.pop(dialogContext);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          font.name,
                          style: fontPreviewStyle(
                              font,
                              Theme.of(dialogContext)
                                  .textTheme
                                  .titleMedium!),
                        ),
                        Text(
                          font.thai
                              ? t(dialogContext, 'settings.font_thai_ok')
                              : t(dialogContext, 'settings.font_latin_only'),
                          style:
                              Theme.of(dialogContext).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (font.id == current.id)
                    Icon(Icons.check,
                        color: Theme.of(dialogContext).colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Mini palette preview: background + accent bar + a secondary dot.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.spec, this.size = 34});

  final StarThemeSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Center(
        child: Container(
          width: size * 0.45,
          height: size * 0.45,
          decoration: BoxDecoration(
            color: spec.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// The settings row: swatch + theme name + brightness icon.
class _ThemePreviewTile extends StatelessWidget {
  const _ThemePreviewTile({required this.spec});

  final StarThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _ThemeSwatch(spec: spec),
          const SizedBox(width: 12),
          Expanded(
            child: Text(spec.name,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Icon(
            spec.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

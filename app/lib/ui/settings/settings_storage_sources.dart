import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../data/dao/series_dao.dart';
import '../../data/sources/source_registry.dart';

/// ดาวน์โหลด & พื้นที่ (doc 14): Wi-Fi-only, cache budget, quota,
/// storage readout, clear-unpinned-cache, delete search history.
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  int _cacheBytes = 0;
  int _pinnedBytes = 0;
  int _dbBytes = 0;

  @override
  void initState() {
    super.initState();
    _readout();
  }

  Future<void> _readout() async {
    final dbPath = ref.read(dbProvider).path;
    var dbBytes = 0;
    try {
      dbBytes = (await File(dbPath).stat()).size;
    } catch (_) {
      dbBytes = 0;
    }
    final blobs = ref.read(blobsDaoProvider);
    final cache = await blobs.unpinnedBytes();
    final pinned = await blobs.pinnedBytes();
    if (!mounted) return;
    setState(() {
      _cacheBytes = cache;
      _pinnedBytes = pinned;
      _dbBytes = dbBytes;
    });
  }

  Future<void> _refreshNumbers() async {
    final blobs = ref.read(blobsDaoProvider);
    final cache = await blobs.unpinnedBytes();
    final pinned = await blobs.pinnedBytes();
    if (!mounted) return;
    setState(() {
      _cacheBytes = cache;
      _pinnedBytes = pinned;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    return Column(
      children: [
        _header(context, t(context, 'settings.storage')),
        SwitchListTile(
          title: Text(t(context, 'settings.wifi_only')),
          value: settings.getBool('downloads_wifi_only', true),
          onChanged: (v) =>
              controller.set('downloads_wifi_only', v ? '1' : '0'),
        ),
        _GbInputTile(
          label: t(context, 'settings.cache_budget_gb'),
          bytes: settings.getInt('cache_limit_bytes', 5368709120),
          minGb: 1,
          maxGb: 50,
          onChanged: (bytes) => controller.set('cache_limit_bytes', '$bytes'),
        ),
        _GbInputTile(
          label: t(context, 'settings.quota_gb'),
          bytes: settings.getInt('total_quota_bytes', 21474836480),
          minGb: 1,
          maxGb: 500,
          onChanged: (bytes) => controller.set('total_quota_bytes', '$bytes'),
        ),
        ListTile(
          title: Text(t(context, 'settings.usage_now')),
          subtitle: Text(
            tFmt(context, 'settings.usage_breakdown', {
              'cache': _gb(_cacheBytes),
              'pinned': _gb(_pinnedBytes),
              'db': (_dbBytes / 1048576).toStringAsFixed(1),
            }),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        ListTile(
          title: Text(t(context, 'settings.clear_cache')),
          onTap: () => _clearCache(context, ref),
        ),
        ListTile(
          title: Text(t(context, 'settings.clear_searches')),
          onTap: () async {
            final n = await _searchCount(ref);
            await ref.read(settingsDaoProvider).clearSearches();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tFmt(
                  context, 'settings.searches_cleared', {'n': '$n'})),
            ));
          },
        ),
      ],
    );
  }

  Future<int> _searchCount(WidgetRef ref) async =>
      (await ref.read(settingsDaoProvider).recentSearches()).length;

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, 'settings.clear_cache')),
        content: Text(t(context, 'settings.clear_cache_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, 'common.ok')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final freed = await ref.read(cacheJanitorProvider).clearUnpinned();
    await _refreshNumbers();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tFmt(context, 'settings.cache_cleared',
          {'mb': (freed / 1048576).round().toString()})),
    ));
  }
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

String _gb(int bytes) => (bytes / 1073741824).toStringAsFixed(1);

/// Free-number GB input (cache budget / download quota): a small numeric
/// field with − / + steppers, written through on submit or step. Typed
/// values clamp to [minGb]..[maxGb].
class _GbInputTile extends StatefulWidget {
  const _GbInputTile({
    required this.label,
    required this.bytes,
    required this.minGb,
    required this.maxGb,
    required this.onChanged,
  });

  final String label;
  final int bytes;
  final int minGb;
  final int maxGb;
  final ValueChanged<int> onChanged;

  @override
  State<_GbInputTile> createState() => _GbInputTileState();
}

class _GbInputTileState extends State<_GbInputTile> {
  late final TextEditingController _text =
      TextEditingController(text: '${(widget.bytes / 1073741824).round()}');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply(int gb) {
    final clamped = gb.clamp(widget.minGb, widget.maxGb);
    _text.text = '$clamped';
    widget.onChanged(clamped * 1073741824);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(widget.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 20),
            onPressed: () =>
                _apply((int.tryParse(_text.text) ?? widget.minGb) - 1),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _text,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'GB',
              ),
              onSubmitted: (v) => _apply(int.tryParse(v) ?? widget.minGb),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 20),
            onPressed: () =>
                _apply((int.tryParse(_text.text) ?? widget.minGb) + 1),
          ),
        ],
      ),
    );
  }
}

/// แหล่งอ่าน (doc 14): per-source switch + connection test + up/down
/// reorder. Changes re-emit [SourcesController] so browse/search/fallback
/// react immediately.
class SourcesSection extends ConsumerStatefulWidget {
  const SourcesSection({super.key});

  @override
  ConsumerState<SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends ConsumerState<SourcesSection> {
  List<SourceInfo>? _all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await ref.read(seriesDaoProvider).allSources();
    if (!mounted) return;
    setState(() => _all = all);
  }

  Future<void> _reemit() async {
    final db = ref.read(dbProvider);
    final http = ref.read(safeHttpProvider);
    ref
        .read(sourcesProvider.notifier)
        .replace(await loadSources(db, http));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Column(
      children: [
        _header(context, t(context, 'settings.sources')),
        if (all == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          )
        else
          for (var i = 0; i < all.length; i++)
            _SourceTile(
              info: all[i],
              isFirst: i == 0,
              isLast: i == all.length - 1,
              onChanged: _reemit,
            ),
      ],
    );
  }
}

class _SourceTile extends ConsumerStatefulWidget {
  const _SourceTile({
    required this.info,
    required this.isFirst,
    required this.isLast,
    required this.onChanged,
  });

  final SourceInfo info;
  final bool isFirst;
  final bool isLast;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends ConsumerState<_SourceTile> {
  String? _testResult; // null = untested; "1234 ms" / "error"

  Future<void> _testConnection() async {
    final http = ref.read(safeHttpProvider);
    final db = ref.read(dbProvider);
    final sources =
        await loadSources(db, http, onlyEnabled: false);
    final source = sources.where((s) => s.id == widget.info.id).firstOrNull;
    if (source == null) return;
    final watch = Stopwatch()..start();
    try {
      await source.latest(page: 1);
      watch.stop();
      if (!mounted) return;
      setState(() =>
          _testResult = tFmt(context, 'settings.source_ok',
              {'ms': '${watch.elapsedMilliseconds}'}));
    } catch (_) {
      watch.stop();
      if (!mounted) return;
      setState(() =>
          _testResult = t(context, 'settings.source_err'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    // Switch on the row, action icons below it — a single trailing Row
    // with three icons + a switch overflows on narrow screens.
    return Column(
      children: [
        ListTile(
          dense: true,
          title: Text(info.name),
          subtitle: _testResult == null
              ? Text(info.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall)
              : Text(_testResult!,
                  style: Theme.of(context).textTheme.labelSmall),
          trailing: Switch(
            value: info.enabled,
            onChanged: (v) async {
              await ref
                  .read(seriesDaoProvider)
                  .setSourceEnabled(info.id, v);
              await widget.onChanged();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: t(context, 'settings.source_test'),
                icon: const Icon(Icons.network_check, size: 20),
                onPressed: _testConnection,
              ),
              IconButton(
                tooltip: t(context, 'settings.source_up'),
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: widget.isFirst
                    ? null
                    : () async {
                        await ref
                            .read(seriesDaoProvider)
                            .moveSource(info.id, up: true);
                        await widget.onChanged();
                      },
              ),
              IconButton(
                tooltip: t(context, 'settings.source_down'),
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: widget.isLast
                    ? null
                    : () async {
                        await ref
                            .read(seriesDaoProvider)
                            .moveSource(info.id, up: false);
                        await widget.onChanged();
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// เกี่ยวกับ (doc 14): version + GitHub link + licenses.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const appVersion = '1.3.0';
  static const githubUrl = 'https://github.com/DotJumpDot/Star_Codex';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(context, t(context, 'settings.about')),
        ListTile(
          title: const Text('Star Codex'),
          subtitle: Text('v$appVersion · 2026-10-22'),
        ),
        ListTile(
          title: Text(t(context, 'settings.personal_use')),
          subtitle: Text(t(context, 'settings.personal_use_body'),
              style: Theme.of(context).textTheme.labelSmall),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(t(context, 'settings.github')),
          subtitle: const Text('DotJumpDot/Star_Codex',
              style: TextStyle(fontFamily: 'monospace')),
          onTap: () =>
              launchUrl(Uri.parse(githubUrl), mode: LaunchMode.externalApplication),
        ),
        ListTile(
          title: Text(t(context, 'settings.licenses')),
          onTap: () => showLicensePage(
              context: context,
              applicationName: 'Star Codex',
              applicationVersion: appVersion),
        ),
      ],
    );
  }
}

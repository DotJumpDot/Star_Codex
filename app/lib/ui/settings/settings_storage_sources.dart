import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        RadioGroup<String>(
          groupValue: settings.get('cache_limit_bytes', '${5 * 1073741824}'),
          onChanged: (v) =>
              v == null ? null : controller.set('cache_limit_bytes', v),
          child: Column(
            children: [
              for (final gb in const [2, 5, 10])
                RadioListTile<String>(
                  dense: true,
                  value: '${gb * 1073741824}',
                  title: Text(
                      tFmt(context, 'settings.cache_budget', {'gb': '$gb'})),
                ),
            ],
          ),
        ),
        RadioGroup<String>(
          groupValue:
              settings.get('total_quota_bytes', '${100 * 1073741824}'),
          onChanged: (v) =>
              v == null ? null : controller.set('total_quota_bytes', v),
          child: Column(
            children: [
              for (final gb in const [20, 50, 100, 200])
                RadioListTile<String>(
                  dense: true,
                  value: '${gb * 1073741824}',
                  title: Text(tFmt(context, 'settings.quota', {'gb': '$gb'})),
                ),
            ],
          ),
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
    return ListTile(
      title: Text(info.name),
      subtitle: _testResult == null
          ? Text(info.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall)
          : Text(_testResult!,
              style: Theme.of(context).textTheme.labelSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
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
          Switch(
            value: info.enabled,
            onChanged: (v) async {
              await ref
                  .read(seriesDaoProvider)
                  .setSourceEnabled(info.id, v);
              await widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}

/// เกี่ยวกับ (doc 14).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const appVersion = '1.0.0 (v1)';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(context, t(context, 'settings.about')),
        const ListTile(
          title: Text('Star Codex'),
          subtitle: Text('v$appVersion · สร้าง 2026-10-17'),
        ),
        ListTile(
          title: Text(t(context, 'settings.personal_use')),
          subtitle: Text(t(context, 'settings.personal_use_body'),
              style: Theme.of(context).textTheme.labelSmall),
        ),
        ListTile(
          title: Text(t(context, 'settings.plan_note')),
          subtitle: Text(t(context, 'settings.plan_note_body'),
              style: Theme.of(context).textTheme.labelSmall),
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

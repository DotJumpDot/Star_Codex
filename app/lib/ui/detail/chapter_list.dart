import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/utils/relative_time.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/series_repo.dart';
import '../browse/source_palette.dart';
import '../reader/reader_router.dart';
import 'chapter_indicator.dart';
import 'chapter_sheet.dart';
import 'detail_controller.dart';

/// Chapter list for ONE selected source (the old per-source tab bar was
/// replaced by the site switcher in the action row). The search field and
/// sort toggle moved UP to the detail body (they share the row the intro
/// toggle vacated) — this widget is the bare list.
class ChapterList extends ConsumerWidget {
  const ChapterList({
    super.key,
    required this.vm,
    required this.controllerKey,
    required this.sourceId,
    required this.query,
  });

  final SeriesDetailVm vm;

  /// The screen's provider-family key (-1 when opened from browse) — NOT
  /// vm.series.id, which resolves to a different controller there.
  final DetailKey controllerKey;

  final String sourceId;

  /// Live text from the detail body's chapter search field.
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var chapters = [
      ...(vm.chaptersBySource[sourceId] ?? const <Chapter>[]),
    ];
    chapters.sort(
      (a, b) => vm.sortOldestFirst
          ? a.number.compareTo(b.number)
          : b.number.compareTo(a.number),
    );
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      bool hit(Chapter c) =>
          c.title?.toLowerCase().contains(q) == true ||
          formatChapterNumber(c.number).contains(q);
      chapters = chapters.where(hit).toList(growable: false);
    }
    if (chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            q.isEmpty
                ? t(context, 'detail.chapters_empty')
                : t(context, 'common.empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final sources = ref.watch(sourcesProvider);
    int registryIndex(String id) {
      for (var i = 0; i < sources.length; i++) {
        if (sources[i].id == id) return i;
      }
      return 0;
    }

    return ListView.builder(
      itemCount: chapters.length,
      itemBuilder: (context, i) => _ChapterRow(
        vm: vm,
        chapter: chapters[i],
        sourceId: sourceId,
        controllerKey: controllerKey,
        registryIndex: registryIndex,
      ),
    );
  }
}

class _ChapterRow extends ConsumerWidget {
  const _ChapterRow({
    required this.vm,
    required this.chapter,
    required this.sourceId,
    required this.controllerKey,
    required this.registryIndex,
  });

  final SeriesDetailVm vm;
  final Chapter chapter;
  final String sourceId;
  final DetailKey controllerKey;

  /// Source → index in the registry sort order (same colors as browse).
  final int Function(String) registryIndex;

  /// Sources carrying this exact chapter number (epsilon), in link order —
  /// the colored chips of the doc 09 addendum.
  List<String> get _carrying {
    final copies = vm.chaptersByNumber[chapter.number] ?? <Chapter>[chapter];
    return [
      for (final l in vm.links)
        if (copies.any((c) => c.sourceId == l.sourceId)) l.sourceId,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = vm.progress[chapter.id];
    final readState = _readState(progress);
    final downloaded = vm.downloadedChapterIds.contains(chapter.id);
    final carrying = _carrying;
    final extra = _stripNumberPrefix(chapter.title);

    final uploadedAt = chapter.uploadedAt;
    String? dateText;
    if (uploadedAt != null) {
      final parts = relativeParts(
        uploadedAt,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      dateText = tFmt(context, parts.key, parts.params);
    }
    return ListTile(
      dense: true,
      // The read-state circle sits in FRONT of the chapter title (user
      // request 2026-10-22) — it used to be on the right, next to the
      // source dots.
      //
      // `minLeadingWidth: 0` + a small `horizontalTitleGap` pull the
      // title right up against the dot: the default 40 px leading slot
      // left a wide gap and the dot looked detached (user feedback
      // 2026-10-22). The extra left padding keeps the dot off the
      // screen edge.
      minLeadingWidth: 0,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.only(left: 16, right: 16),
      leading: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: ChapterStateDot(state: readState),
      ),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: tFmt(context, 'detail.chapter_number', {
                'n': formatChapterNumber(chapter.number),
              }),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (extra != null)
              TextSpan(
                text: '  $extra',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        dateText ?? t(context, 'detail.no_date'),
        style: TextStyle(color: _dateColor(context, uploadedAt)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sid in carrying)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: SourceDot(color: sourceDotColor(registryIndex(sid))),
            ),
          if (downloaded) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.download,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
      onTap: () async {
        final settings = ref.read(settingsProvider);
        await openReader(
          context,
          chapter: chapter,
          sourceId: sourceId,
          seriesDao: ref.read(seriesDaoProvider),
          modeOverride: effectiveModeOverride(
            settings.get('reader_mode_${chapter.seriesId}', 'auto'),
            settings.get('reader_mode_default', 'auto'),
          ),
        );
        // The reader wrote the chapter's state — show it (user request
        // 2026-10-22: "on reading" / "read" must update on return).
        if (!context.mounted) return;
        await ref
            .read(detailControllerProvider(controllerKey).notifier)
            .refreshProgress();
      },
      onLongPress: () => showChapterActions(
        context,
        ref,
        vm: vm,
        chapter: chapter,
        carryingSourceIds: carrying,
        controllerKey: controllerKey,
      ),
    );
  }

  /// Three states (user request 2026-10-22):
  ///
  /// - no progress row → never opened → empty ring.
  /// - a row with completed=0 → opened and read for a while → solid
  ///   "on reading" dot.
  /// - completed=1 → finished → solid dot with a check.
  static ChapterReadState _readState(ChapterProgress? progress) {
    if (progress == null) return ChapterReadState.unread;
    return progress.completed ? ChapterReadState.read : ChapterReadState.reading;
  }

  /// Chapter titles repeat the number (`ตอนที่ 155`) — strip it so the row
  /// doesn't read "ตอนที่ 155  ตอนที่ 155" (shared with the reader chrome).
  String? _stripNumberPrefix(String? title) => stripChapterNumberPrefix(title);

  /// Age-coded date color (user request 2026-10-24: "old to new need
  /// unique color") — fresh chapters pop with the theme accent, the
  /// current week gets the tertiary tone, then the default muted text,
  /// and old chapters fade to outline. Buckets mirror the relative
  /// labels (hours / days / weeks / months+). The no-date placeholder
  /// shares the oldest bucket.
  Color _dateColor(BuildContext context, int? uploadedAtMs) {
    final scheme = Theme.of(context).colorScheme;
    if (uploadedAtMs == null) return scheme.outline;
    final ageMs = DateTime.now().millisecondsSinceEpoch - uploadedAtMs;
    if (ageMs < const Duration(hours: 24).inMilliseconds) {
      return scheme.primary;
    }
    if (ageMs < const Duration(days: 7).inMilliseconds) {
      return scheme.tertiary;
    }
    if (ageMs < const Duration(days: 30).inMilliseconds) {
      return scheme.onSurfaceVariant;
    }
    return scheme.outline;
  }
}

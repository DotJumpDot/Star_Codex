import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../data/dao/blobs_dao.dart';
import '../../data/repo/library_cards.dart';
import '../browse/cover_thumb.dart';

/// Library grid card (Plan/12 §3): cover, 1-line Thai title, green
/// "N ตอนใหม่" badge (visit-reset, db v4), progress hairline, downloaded
/// pin. New-chipped series sort to the top of every view.
class LibraryCardView extends ConsumerWidget {
  const LibraryCardView({
    super.key,
    required this.card,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryCard card;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CardCover(card: card),
                  if (selectionMode)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: selected
                            ? scheme.primary
                            : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  if (card.doneDownloads > 0)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Icon(Icons.download_done,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.95)),
                    ),
                  if (card.newCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _newBadge(context),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: card.readFraction,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tFmt(context, 'library.unread_count',
                        {'n': '${card.unreadCount}'}),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newBadge(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          // Green reads as "fresh update" at thumbnail scale (user QA
          // 2026-10-18); red was being read as an error.
          color: const Color(0xFF22A45D),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          tFmt(context, 'library.badge_new', {'n': '${card.newCount}'}),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );
}

/// Library list row (denser, Plan/12 §3): unread count in the trailing.
class LibraryRowView extends ConsumerWidget {
  const LibraryRowView({
    super.key,
    required this.card,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryCard card;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: SizedBox(
        width: 48,
        height: 68,
        child: _CardCover(card: card, width: 48, height: 68),
      ),
      title: Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: card.originalTitle == null
          ? null
          : Text(card.originalTitle!,
              maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (card.doneDownloads > 0)
            Icon(Icons.download_done, size: 18, color: scheme.primary),
          if (card.newCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22A45D),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tFmt(context, 'library.badge_new', {'n': '${card.newCount}'}),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            )
          else
            Text(
                tFmt(context, 'library.unread_count',
                    {'n': '${card.unreadCount}'}),
                style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Cover from `series.cover_hash` blob; evicted → CoverThumb through the
/// pipeline (first link's URL); nothing → placeholder. The blob-row future
/// is cached per state like the detail screen's _Cover (a DB read per
/// rebuild otherwise).
class _CardCover extends ConsumerStatefulWidget {
  const _CardCover({required this.card, this.width = 120, this.height = 170});

  final LibraryCard card;
  final double width;
  final double height;

  @override
  ConsumerState<_CardCover> createState() => _CardCoverState();
}

class _CardCoverState extends ConsumerState<_CardCover> {
  Future<BlobRow?>? _future;
  String? _futureHash;

  @override
  Widget build(BuildContext context) {
    final hash = widget.card.coverHash;
    if (hash == null) return _fallback(context);
    if (_future == null || _futureHash != hash) {
      _futureHash = hash;
      _future = ref.read(blobStoreProvider).blobRow(hash);
    }
    final dir = ref.watch(libraryDirProvider);
    return FutureBuilder<BlobRow?>(
      future: _future,
      builder: (context, snap) {
        final path = snap.data?.path;
        if (path == null) return _fallback(context);
        return Image.file(
          File('${dir.path}/$path'),
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(context),
        );
      },
    );
  }

  Widget _fallback(BuildContext context) {
    final card = widget.card;
    if (card.coverUrl != null && card.coverReferer != null) {
      return CoverThumb(
        url: card.coverUrl!,
        referer: card.coverReferer!,
        width: widget.width,
        height: widget.height,
      );
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined,
          size: 28, color: Theme.of(context).colorScheme.outline),
    );
  }
}

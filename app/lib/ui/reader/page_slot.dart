import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/i18n/i18n.dart';
import '../../data/repo/reader_repo.dart';

/// One vertical slot (doc 10 §Widget tree): cached file renders instantly,
/// known dims reserve the EXACT height (no jump on re-read), unknown dims
/// reserve the observed-average estimate (720:1360 probe), errors get a
/// retry + fallback path handled by the screen's resolver.
class PageSlot extends ConsumerStatefulWidget {
  const PageSlot({
    super.key,
    required this.ref,
    required this.screenWidth,
    required this.resolve,
    required this.onDimensions,
    this.errorBadge,
  });

  final ReaderPageRef ref;

  /// Logical screen width — slots span the full width (fitWidth).
  final double screenWidth;

  /// Screen-provided resolver: cache check → queue fetch → per-page source
  /// fallback (07 §5). Throws → this slot's error UI.
  final Future<PageFile> Function() resolve;

  /// Reports REAL (w, h) once known so the screen can fix up slot heights.
  final void Function(int idx, int? width, int? height) onDimensions;

  /// "จาก go-manga" style chip shown when this slot came from a fallback.
  final String? errorBadge;

  static const estimatedAspect = 1.9; // height = width * 1.9 (doc 10)

  @override
  ConsumerState<PageSlot> createState() => _PageSlotState();
}

class _PageSlotState extends ConsumerState<PageSlot> {
  late Future<PageFile?> _future;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PageFile?> _load() async {
    try {
      final pf = await widget.resolve();
      if (mounted) {
        widget.onDimensions(widget.ref.idx, pf.width, pf.height);
      }
      if (mounted) setState(() => _error = null);
      return pf;
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return null;
    }
  }

  double get _reservedHeight {
    final ref = widget.ref;
    if (ref.hasDims) {
      return widget.screenWidth * ref.height! / ref.width!;
    }
    return widget.screenWidth * PageSlot.estimatedAspect;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _errorSlot(context);
    }
    return FutureBuilder<PageFile?>(
      future: _future,
      builder: (context, snap) {
        final pf = snap.data;
        if (pf == null) {
          return _placeholder(context);
        }
        final dir = ref.read(libraryDirProvider);
        final file = File('${dir.path}/${pf.path}');
        final w = pf.width ?? widget.ref.width;
        final h = pf.height ?? widget.ref.height;
        final height = (w != null && h != null && w > 0)
            ? widget.screenWidth * h / w
            : _reservedHeight;
        return Stack(
          children: [
            ExtendedImage.file(
              file,
              width: widget.screenWidth,
              height: height,
              fit: BoxFit.fitWidth,
              clearMemoryCacheWhenDispose: true,
              cacheWidth:
                  (widget.screenWidth * MediaQuery.devicePixelRatioOf(context))
                      .round(),
              loadStateChanged: (state) {
                if (state.extendedImageLoadState == LoadState.loading) {
                  return _placeholderBox(context, height);
                }
                return null;
              },
            ),
            if (widget.errorBadge != null)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(widget.errorBadge!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) => _placeholderBox(
      context,
      widget.ref.hasDims
          ? _reservedHeight
          : widget.screenWidth * PageSlot.estimatedAspect);

  Widget _placeholderBox(BuildContext context, double height) => Container(
        width: widget.screenWidth,
        height: height,
        color: Colors.white10,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );

  Widget _errorSlot(BuildContext context) => Container(
        width: widget.screenWidth,
        height: _reservedHeight,
        color: Colors.white10,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, color: Colors.white54, size: 28),
            const SizedBox(height: 8),
            Text(t(context, 'reader.error_page'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(t(context, 'common.retry')),
              onPressed: () => setState(() {
                _future = _load();
              }),
            ),
          ],
        ),
      );
}

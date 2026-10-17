import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import 'reader_router.dart';

/// Placeholder destination for chapter taps (doc 15 Phase 6: "open stub
/// screens for now"). Phase 7 replaces webtoon, Phase 8 paged + novel.
class ReaderStubScreen extends StatelessWidget {
  const ReaderStubScreen({
    super.key,
    required this.chapter,
    required this.sourceId,
    required this.mode,
  });

  final Chapter chapter;
  final String sourceId;
  final ReaderMode mode;

  String get _modeKey => switch (mode) {
        ReaderMode.paged => 'reader.mode.paged',
        ReaderMode.novel => 'reader.mode.novel',
        ReaderMode.webtoon => 'reader.mode.webtoon',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tFmt(context, 'detail.chapter_number',
              {'n': formatChapterNumber(chapter.number)}),
        ),
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              t(context, _modeKey),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              '${tFmt(context, 'detail.chapter_number', {'n': formatChapterNumber(chapter.number)})}'
              ' · $sourceId',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                t(context, 'reader.soon'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

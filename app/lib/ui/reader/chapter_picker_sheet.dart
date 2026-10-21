import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/providers.dart';
import '../../core/utils/thai.dart';
import '../../data/dao/chapters_dao.dart';
import '../../data/repo/series_repo.dart';
import '../browse/source_palette.dart';

/// Chapter selector bottom sheet (doc 10 §6): merged number list with the
/// current chapter highlighted and the doc 09 source dots; search filters
/// by number. Picking pushes the reader route via [onPick].
Future<void> showChapterPicker(
  BuildContext context,
  WidgetRef ref, {
  required SeriesDetailVm vm,
  required Chapter current,
  required void Function(Chapter chapter, String sourceId) onPick,
}) {
  // Registry-order source colors (consistent with browse + detail).
  final sources = ref.read(sourcesProvider);
  int registryIndex(String id) {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id == id) return i;
    }
    return 0;
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      var query = '';
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final numbers = vm.chaptersByNumber.keys.toList()..sort();
          final q = query.trim();
          final filtered = q.isEmpty
              ? numbers
              : numbers
                    .where(
                      (n) =>
                          formatChapterNumber(n).contains(q) ||
                          (vm.chaptersByNumber[n]!.first.title ?? '')
                              .toLowerCase()
                              .contains(q.toLowerCase()),
                    )
                    .toList(growable: false);
          return SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setSheetState(() => query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: t(sheetContext, 'detail.search_chapters'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final number = filtered[i];
                      final copies = vm.chaptersByNumber[number]!;
                      final isCurrent = copies.any(
                        (c) =>
                            c.sourceId == current.sourceId &&
                            (c.id == current.id),
                      );
                      return ListTile(
                        dense: true,
                        selected: isCurrent,
                        leading: isCurrent
                            ? Icon(
                                Icons.play_arrow,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        title: Text(
                          tFmt(sheetContext, 'detail.chapter_number', {
                            'n': formatChapterNumber(number),
                          }),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final link in vm.links)
                              if (copies.any(
                                (c) => c.sourceId == link.sourceId,
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(left: 3),
                                  child: SourceDot(
                                    color: sourceDotColor(
                                      registryIndex(link.sourceId),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                        onTap: () {
                          // Prefer the current source's copy, else any.
                          Chapter pick = copies.first;
                          for (final c in copies) {
                            if (c.sourceId == current.sourceId) pick = c;
                          }
                          Navigator.pop(sheetContext);
                          onPick(pick, pick.sourceId);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

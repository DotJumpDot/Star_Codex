import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';

/// Reader settings sheet (doc 10 §6 bottom bar): prefetch count,
/// keep-screen-on, auto-next-chapter. Values write through to the settings
/// table via [onChanged].
Future<void> showReaderSettings(
  BuildContext context, {
  required int prefetchAhead,
  required bool keepAwake,
  required bool autoNext,
  required void Function(int prefetch, bool awake, bool autoNext) onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      var prefetch = prefetchAhead;
      var awake = keepAwake;
      var next = autoNext;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(t(sheetContext, 'reader.keep_awake')),
                value: awake,
                onChanged: (v) {
                  setSheetState(() => awake = v);
                  onChanged(prefetch, awake, next);
                },
              ),
              SwitchListTile(
                title: Text(t(sheetContext, 'reader.auto_next')),
                value: next,
                onChanged: (v) {
                  setSheetState(() => next = v);
                  onChanged(prefetch, awake, next);
                },
              ),
              ListTile(
                title: Text(t(sheetContext, 'reader.prefetch_ahead')),
                subtitle: Slider(
                  min: 3,
                  max: 12,
                  divisions: 9,
                  label: '$prefetch',
                  value: prefetch.toDouble(),
                  onChanged: (v) {
                    setSheetState(() => prefetch = v.round());
                    onChanged(prefetch, awake, next);
                  },
                ),
                trailing: Text('$prefetch'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

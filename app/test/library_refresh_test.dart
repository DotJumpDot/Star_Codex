import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/providers.dart';
import 'package:star_codex/core/utils/title_norm.dart';
import 'package:star_codex/data/dao/library_dao.dart';
import 'package:star_codex/data/dao/series_dao.dart';
import 'package:star_codex/ui/detail/detail_controller.dart';
import 'package:star_codex/ui/library/library_controller.dart';

import 'helpers.dart';

/// QA on-device 2026-10-18: the shell keeps the library tab mounted, so a
/// detail-screen add/remove that only wrote the DB never reached the tab —
/// the card appeared only after an app restart. The detail controller now
/// pings [LibraryController.load] via `onLibraryChanged`; this locks it in.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detail toggleLibrary refreshes the kept-alive library tab',
      () async {
    final db = await openTestDb();
    final tmp =
        await io.Directory.systemTemp.createTemp('starcodex_lib_ping');
    final now = DateTime.now().millisecondsSinceEpoch;

    final inLib = await SeriesDao(db).upsertByTitleNorm(Series(
      title: 'อยู่ในคลัง',
      titleNorm: normalizeTitle('อยู่ในคลัง'),
      type: 'manga',
      createdAt: now,
      updatedAt: now,
    ));
    final outside = await SeriesDao(db).upsertByTitleNorm(Series(
      title: 'ยังไม่อยู่ในคลัง',
      titleNorm: normalizeTitle('ยังไม่อยู่ในคลัง'),
      type: 'manga',
      createdAt: now,
      updatedAt: now,
    ));
    final libraryDao = LibraryDao(db);
    await libraryDao.add(inLib, now);

    final container = ProviderContainer(overrides: [
      dbProvider.overrideWithValue(db),
      initialSettingsProvider.overrideWithValue(const {}),
      libraryDirProvider.overrideWithValue(tmp),
      sourcesProvider.overrideWith((ref) => SourcesController(const [])),
    ]);
    addTearDown(container.dispose);

    final lib = container.read(libraryControllerProvider.notifier);
    await lib.load();
    expect(lib.state.cards.map((c) => c.seriesId), [inLib]);

    final detail = container
        .read(detailControllerProvider(DetailKey.id(outside)).notifier);
    await detail.load();
    await detail.toggleLibrary(); // add — must refresh the library controller
    expect(lib.state.cards.map((c) => c.seriesId), contains(outside));

    await detail.toggleLibrary(); // remove — must refresh again
    expect(lib.state.cards.map((c) => c.seriesId), isNot(contains(outside)));
    expect(lib.state.cards.map((c) => c.seriesId), [inLib]);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/data/repo/browse_repo.dart';
import 'package:star_codex/ui/browse/result_card.dart';

import 'fake_source.dart';

/// Browse card: the series intro fills the space under the chip row
/// (user request 2026-10-22 — short-title cards showed a dead gap next
/// to the cover) and is truncated to the lines that fit.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await I18nService.load();

  // No cover URL on purpose: CoverThumb would hit the network (a widget
  // test must not), so the card falls back to its placeholder.
  SearchGroup card(String title) => SearchGroup([
    BrowseCandidate(
      sourceId: 'slow-manga',
      referer: 'https://r/',
      url: 'https://s/${title.hashCode}/',
      title: title,
      chapterCountHint: 920,
    ),
  ]);

  testWidgets('result card shows the description under the chips, truncated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final withDesc = card('Nano Machine');
    withDesc.dbDescription = 'A lone mechanic rebuilds machines and quietly outgrows the academy that discarded him.';
    final withoutDesc = card('Other Series');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ResultCard(
                group: withDesc,
                allGroups: [withDesc, withoutDesc],
                sources: [FakeSource('slow-manga')],
                onTap: () {},
                onLongPress: () {},
              ),
              ResultCard(
                group: withoutDesc,
                allGroups: [withDesc, withoutDesc],
                sources: [FakeSource('slow-manga')],
                onTap: () {},
                onLongPress: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // The intro shows on the card that has one — and only there.
    expect(find.textContaining('A lone mechanic'), findsOneWidget);
    final text = tester.widget<Text>(find.textContaining('A lone mechanic'));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);

    // The second card has no description → no empty paragraph block.
    expect(find.textContaining('A lone mechanic'), findsOneWidget);
  });
}

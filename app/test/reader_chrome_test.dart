import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/i18n/i18n.dart';
import 'package:star_codex/data/dao/chapters_dao.dart';
import 'package:star_codex/ui/reader/reader_chrome.dart';

Chapter _chapter(String? title) => Chapter(
      seriesId: 1,
      sourceId: 'go-manga',
      number: 69,
      title: title,
      url: 'https://www.go-manga.com/x/69',
      fetchedAt: 0,
    );

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await I18nService.load();

  // tFmt ignores its context (static bundles) — any live element works.
  Future<BuildContext> pumpEmpty(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        },
      ),
    ));
    return ctx;
  }

  Future<void> pumpChrome(WidgetTester tester, String label) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderChrome(
          visible: true,
          title: 'The Academy Weapon Replicator',
          sourceName: 'go-manga',
          chapterLabel: label,
          onBack: () {},
          onTitle: () {},
          onChapters: () {},
          onMenu: () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('chrome subtitle: chapter label leads, source stays visible',
      (tester) async {
    final ctx = await pumpEmpty(tester);
    final label = readerChapterLabel(ctx, _chapter('ตอนที่ 69 ดาบปลอม'));
    expect(label, contains('69'));
    expect(label, contains('ดาบปลอม'),
        reason: 'the number prefix is stripped, the name kept');
    await pumpChrome(tester, label);
    // The chapter part renders its own Text…
    expect(find.textContaining('ตอนที่ 69'), findsOneWidget);
    // …and the source line is a SEPARATE Text — an ellipsized chapter
    // label can never eat it (user request 2026-10-24: "จาก go-manga"
    // must stay visible no matter how long the chapter name is).
    final src = tester.widget<Text>(find.textContaining('จาก'));
    expect(src.data, contains('go-manga'));
    expect(src.maxLines, isNull,
        reason: 'the source Text is the non-ellipsizing side of the Row');
  });

  testWidgets('chrome subtitle: number-only when the title repeats it',
      (tester) async {
    final ctx = await pumpEmpty(tester);
    final label = readerChapterLabel(ctx, _chapter('ตอนที่ 69'));
    expect(label, isNot(contains('ตอนที่ 69 ตอนที่ 69')));
    await pumpChrome(tester, label);
    expect(find.textContaining('จาก'), findsOneWidget);
  });

  testWidgets('chrome subtitle: null title keeps just the number',
      (tester) async {
    final ctx = await pumpEmpty(tester);
    final label = readerChapterLabel(ctx, _chapter(null));
    expect(label, contains('69'));
    expect(label, isNot(contains('null')));
  });

  testWidgets('chrome subtitle: null label falls back to source-only line',
      (tester) async {
    await pumpChrome(
      tester,
      // The null-label branch is a constructor default; pump it directly.
      '',
    );
    // An empty label still rides the Row branch — pump the true fallback:
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderChrome(
          visible: true,
          title: 'T',
          sourceName: 'go-manga',
          onBack: () {},
          onTitle: () {},
          onChapters: () {},
          onMenu: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('ตอนที่'), findsNothing);
    expect(find.textContaining('จาก'), findsOneWidget);
  });
}

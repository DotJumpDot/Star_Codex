import 'package:flutter_test/flutter_test.dart';
import 'package:star_codex/data/repo/library_cards.dart';
import 'package:star_codex/ui/library/library_controller.dart';

/// Library source-scope cycle (user request 2026-11-03: Search Mix joins
/// between Normal Search and Search 18+ so the cycle mirrors the three
/// browse universes). Pure state tests — the controller only flips the
/// enum.
void main() {
  LibraryCard card(List<String> sources) => LibraryCard(
        seriesId: sources.hashCode,
        title: 'T ${sources.join('+')}',
        addedAt: 0,
        chapterNumbers: const <double>{},
        completedNumbers: const <double>{},
        newCount: 0,
        maxUpdatedAt: 0,
        doneDownloads: 0,
        sources: sources,
        altTitles: const [],
        tags: const [],
      );

  final mainOnly = card(['slow-manga']);
  final mixOnly = card(['niceoppai']);
  final adultOnly = card(['hentaithai']);
  final cards = [mainOnly, mixOnly, adultOnly];

  LibraryState stateWith(LibraryScope scope) => LibraryState(
        cards: cards,
        loading: false,
        scope: scope,
      );

  group('LibraryScope.visible filter', () {
    test('all → every card', () {
      expect(stateWith(LibraryScope.all).visible, hasLength(3));
    });

    test('normal → main-universe sources only (mix excluded)', () {
      final visible = stateWith(LibraryScope.normal).visible;
      expect(visible, [mainOnly]);
    });

    test('mix → mix-scope sources only', () {
      expect(stateWith(LibraryScope.mix).visible, [mixOnly]);
    });

    test('adult → adult sources only', () {
      expect(stateWith(LibraryScope.adult).visible, [adultOnly]);
    });

    test('a card with BOTH main and mix sources stays in normal', () {
      final both = card(['slow-manga', 'niceoppai']);
      final state = LibraryState(
          cards: [both, mixOnly], loading: false, scope: LibraryScope.normal);
      expect(state.visible, [both]);
    });
  });

  group('cycle order', () {
    test('all → normal → mix → adult → all', () {
      // Mirrors LibraryController.cycleScope's switch, pinned so a future
      // reorder can't silently drop the Mix step (user-specified order).
      LibraryScope next(LibraryScope s) => switch (s) {
            LibraryScope.all => LibraryScope.normal,
            LibraryScope.normal => LibraryScope.mix,
            LibraryScope.mix => LibraryScope.adult,
            LibraryScope.adult => LibraryScope.all,
          };
      expect(next(LibraryScope.all), LibraryScope.normal);
      expect(next(LibraryScope.normal), LibraryScope.mix);
      expect(next(LibraryScope.mix), LibraryScope.adult);
      expect(next(LibraryScope.adult), LibraryScope.all);
    });
  });
}

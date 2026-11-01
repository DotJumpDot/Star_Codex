import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/data/sources/source_registry.dart';
import 'package:star_codex/ui/shell/search_overlay.dart';

/// The search overlay routes by the tab it was opened from. The mapping
/// MUST mirror shell._pages — inserting the Mix tab at index 1 (v1.5.0)
/// without updating the old hardcoded `adultTab = 1` sent Mix searches
/// to the hidden 18+ controller and bounced 18+ searches to main
/// (user reports 2026-11-01).
void main() {
  test('browseScopeForTab mirrors shell page order', () {
    expect(browseScopeForTab(0), BrowseScope.main);
    expect(browseScopeForTab(1), BrowseScope.mix);
    expect(browseScopeForTab(2), BrowseScope.adult);
    // Non-browse tabs (library/history/offline/settings) never host the
    // overlay's scope — they fall back to the main browse.
    expect(browseScopeForTab(3), BrowseScope.main);
    expect(browseScopeForTab(6), BrowseScope.main);
  });
}

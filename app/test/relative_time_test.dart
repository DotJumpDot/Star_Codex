import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/core/utils/relative_time.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 12, 0, 0).millisecondsSinceEpoch;
  int ago(Duration d) => now - d.inMilliseconds;

  test('relativeParts boundaries', () {
    // Records containing maps don't compare by value (Map == is identity),
    // so assert fields individually.
    void check(int atMs, String key, Map<String, String> params) {
      final parts = relativeParts(atMs, nowMs: now);
      expect(parts.key, key);
      expect(parts.params, params);
    }

    check(ago(const Duration(seconds: 30)), 'relative.now', const {});
    // Future timestamps (site clock ahead) read as "just now".
    check(now + 90000, 'relative.now', const {});
    check(ago(const Duration(minutes: 5)), 'relative.minutes', {'n': '5'});
    check(ago(const Duration(hours: 3)), 'relative.hours', {'n': '3'});
    check(ago(const Duration(days: 2)), 'relative.days', {'n': '2'});
    check(ago(const Duration(days: 12)), 'relative.weeks', {'n': '1'});
    check(ago(const Duration(days: 70)), 'relative.months', {'n': '2'});
    check(ago(const Duration(days: 800)), 'relative.years', {'n': '2'});
  });
}

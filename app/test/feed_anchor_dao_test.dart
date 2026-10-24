import 'package:flutter_test/flutter_test.dart';

import 'package:star_codex/data/dao/feed_anchor_dao.dart';

import 'helpers.dart';

void main() {
  late FeedAnchorDao dao;

  setUp(() async {
    final db = await openTestDb();
    dao = FeedAnchorDao(db);
  });

  group('stickyStamp (db v10 — sticky feed time anchors)', () {
    const hour = 3600 * 1000;
    // A chapter really posted 10 hours ago; the clock reads "now".
    final trueStamp = DateTime.now().millisecondsSinceEpoch - 10 * hour;

    test('first sighting adopts the new stamp', () {
      expect(
        stickyStamp(
          storedHint: null,
          storedStampMs: null,
          newHint: 69,
          newStampMs: trueStamp + 5 * 60 * 1000,
        ),
        trueStamp + 5 * 60 * 1000,
      );
    });

    test(
        'unchanged chapter: a stale copy re-anchoring "2 นาที" hours later '
        'keeps the stored (older, truer) stamp', () {
      final staleReanchor = DateTime.now().millisecondsSinceEpoch -
          2 * 60 * 1000; // site says "2 นาที" 10h late
      expect(
        stickyStamp(
          storedHint: 69,
          storedStampMs: trueStamp,
          newHint: 69,
          newStampMs: staleReanchor,
        ),
        trueStamp,
        reason: 'the label must keep aging from the first-seen moment, '
            'not snap back to "just updated"',
      );
    });

    test(
        'unchanged chapter: a fresh page converging on the true moment '
        'heals an inflated first-seen stamp', () {
      final inflated = DateTime.now().millisecondsSinceEpoch -
          5 * 60 * 1000; // first fetch caught a stale copy
      final fresh = trueStamp - hour; // later page admits 11 hours
      expect(
        stickyStamp(
          storedHint: 69,
          storedStampMs: inflated,
          newHint: 69,
          newStampMs: fresh,
        ),
        fresh,
      );
    });

    test('changed chapter hint re-anchors (the real update arrived)', () {
      final now = DateTime.now().millisecondsSinceEpoch - 2 * 60 * 1000;
      expect(
        stickyStamp(
          storedHint: 68,
          storedStampMs: trueStamp,
          newHint: 69,
          newStampMs: now,
        ),
        now,
      );
    });

    test('missing identity on either side falls back to the new stamp', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(
        stickyStamp(
          storedHint: 69,
          storedStampMs: trueStamp,
          newHint: null,
          newStampMs: now,
        ),
        now,
        reason: 'a tile that lost its pill cannot claim stickiness',
      );
      expect(
        stickyStamp(
          storedHint: null,
          storedStampMs: trueStamp,
          newHint: 69,
          newStampMs: now,
        ),
        now,
      );
    });
  });

  group('FeedAnchorDao', () {
    test('upsert replaces by (source, url) and round-trips', () async {
      await dao.upsert(
        'fin-manga',
        'https://www.fin-manga.com/a/',
        chapterHint: 69,
        stampMs: 1000,
        atMs: 5000,
      );
      await dao.upsert(
        'fin-manga',
        'https://www.fin-manga.com/a/',
        chapterHint: 70,
        stampMs: 2000,
        atMs: 6000,
      );
      await dao.upsert(
        'fin-manga',
        'https://www.fin-manga.com/b/',
        chapterHint: 12,
        stampMs: 3000,
        atMs: 6000,
      );
      final a = await dao.get('fin-manga', 'https://www.fin-manga.com/a/');
      expect(a?.chapterHint, 70);
      expect(a?.stampMs, 2000);
      expect(a?.updatedAtMs, 6000);
      expect(
        await dao.get('go-manga', 'https://www.fin-manga.com/a/'),
        isNull,
        reason: 'keys are per-source',
      );
    });

    test('rows older than the prune window vanish on write', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await dao.upsert(
        'fin-manga',
        'https://www.fin-manga.com/old/',
        chapterHint: 1,
        stampMs: 1,
        atMs: now - FeedAnchorDao.pruneAfterMs - 1,
      );
      await dao.upsert(
        'fin-manga',
        'https://www.fin-manga.com/new/',
        chapterHint: 2,
        stampMs: 2,
        atMs: now,
      );
      expect(
        await dao.get('fin-manga', 'https://www.fin-manga.com/old/'),
        isNull,
      );
      expect(
        await dao.get('fin-manga', 'https://www.fin-manga.com/new/'),
        isNotNull,
      );
    });
  });
}

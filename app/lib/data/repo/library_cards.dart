import '../../core/utils/thai.dart';

/// One Library grid/list card (Plan/12). All counters are computed in one
/// load pass — see [LibraryRepo.load].
class LibraryCard {
  const LibraryCard({
    required this.seriesId,
    required this.title,
    required this.addedAt,
    this.originalTitle,
    this.coverHash,
    this.coverUrl,
    this.coverReferer,
    this.type,
    this.lastReadAt,
    required this.chapterNumbers,
    required this.completedNumbers,
    required this.newCount,
    required this.maxUpdatedAt,
    required this.doneDownloads,
    required this.sources,
    required this.altTitles,
    required this.tags,
  });

  final int seriesId;
  final String title;
  final String? originalTitle;
  final String? coverHash;

  /// First link's cover URL — the fallback when the cover blob was
  /// evicted (same policy as the detail screen).
  final String? coverUrl;
  final String? coverReferer;
  final String? type;
  final int? lastReadAt;
  final int addedAt;

  /// DISTINCT chapter numbers (multi-source copies count once).
  final Set<double> chapterNumbers;
  final Set<double> completedNumbers;

  /// Doc 13 badge rule: chapters with uploaded_at > library.last_read_at.
  final int newCount;
  final int? maxUpdatedAt;
  final int doneDownloads;
  final List<String> sources;
  final List<String> altTitles;
  final List<String> tags;

  int get unreadCount => chapterNumbers.difference(completedNumbers).length;
  double get readFraction => chapterNumbers.isEmpty
      ? 0
      : completedNumbers.length / chapterNumbers.length;
}

/// Sort dropdown (Plan/12 sort table). Persisted as settings `library_sort`.
enum LibrarySort { lastRead, updated, added, titleAz, unread }

LibrarySort parseLibrarySort(String? raw) => switch (raw) {
      'updated' => LibrarySort.updated,
      'added' => LibrarySort.added,
      'title_az' => LibrarySort.titleAz,
      'unread' => LibrarySort.unread,
      _ => LibrarySort.lastRead,
    };

/// Toolbar quick filters (Plan/12): AND-combined with the active tab.
class LibraryFilters {
  const LibraryFilters({
    this.hasNew = false,
    this.downloaded = false,
    this.types = const {},
    this.sources = const {},
  });

  final bool hasNew;
  final bool downloaded;
  final Set<String> types;
  final Set<String> sources;

  bool get isEmpty =>
      !hasNew && !downloaded && types.isEmpty && sources.isEmpty;

  LibraryFilters copyWith({
    bool? hasNew,
    bool? downloaded,
    Set<String>? types,
    Set<String>? sources,
  }) =>
      LibraryFilters(
        hasNew: hasNew ?? this.hasNew,
        downloaded: downloaded ?? this.downloaded,
        types: types ?? this.types,
        sources: sources ?? this.sources,
      );
}

/// Which tab is active: a built-in smart kind or a user category id.
sealed class LibraryTab {
  const LibraryTab();
}

class AllTab extends LibraryTab {
  const AllTab();
}

/// กำลังอ่าน (last_read_at within 14 d) / ตอนใหม่ / นิยาย / ดาวน์โหลดไว้.
class SmartTab extends LibraryTab {
  const SmartTab(this.kind);
  final SmartKind kind;
}

enum SmartKind { reading, hasNew, novel, downloaded }

class CategoryTab extends LibraryTab {
  const CategoryTab(this.categoryId);
  final int categoryId;
}

/// Applies the active tab + quick filters + search to the card list —
/// pure so the widget-testable rules live outside the widget.
List<LibraryCard> filterAndSortCards(
  List<LibraryCard> cards, {
  required LibraryTab tab,
  required LibraryFilters filters,
  required String search,
  required LibrarySort sort,
  Map<int, Set<int>> categoryMembers = const {},
}) {
  final q = search.trim().toLowerCase();
  Iterable<LibraryCard> out = cards.where((c) {
    switch (tab) {
      case AllTab():
        break;
      case SmartTab(:final kind):
        switch (kind) {
          case SmartKind.reading:
            final within =
                DateTime.now().millisecondsSinceEpoch - 14 * 86400000;
            if ((c.lastReadAt ?? 0) < within) return false;
          case SmartKind.hasNew:
            if (c.newCount == 0) return false;
          case SmartKind.novel:
            if (c.type != 'novel') return false;
          case SmartKind.downloaded:
            if (c.doneDownloads == 0) return false;
        }
      case CategoryTab(:final categoryId):
        if (!(categoryMembers[categoryId]?.contains(c.seriesId) ?? false)) {
          return false;
        }
    }
    if (filters.hasNew && c.newCount == 0) return false;
    if (filters.downloaded && c.doneDownloads == 0) return false;
    if (filters.types.isNotEmpty && !filters.types.contains(c.type)) {
      return false;
    }
    if (filters.sources.isNotEmpty &&
        !c.sources.any(filters.sources.contains)) {
      return false;
    }
    if (q.isNotEmpty) {
      final hit = c.title.toLowerCase().contains(q) ||
          (c.originalTitle?.toLowerCase().contains(q) ?? false) ||
          c.altTitles.any((a) => a.toLowerCase().contains(q)) ||
          c.tags.any((tg) => tg.toLowerCase().contains(q));
      if (!hit) return false;
    }
    return true;
  });
  final list = out.toList();
  switch (sort) {
    case LibrarySort.lastRead:
      list.sort((a, b) => (b.lastReadAt ?? 0).compareTo(a.lastReadAt ?? 0));
    case LibrarySort.updated:
      list.sort((a, b) => (b.maxUpdatedAt ?? 0).compareTo(a.maxUpdatedAt ?? 0));
    case LibrarySort.added:
      list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case LibrarySort.titleAz:
      list.sort((a, b) => compareTitlesThai(a.title, b.title));
    case LibrarySort.unread:
      list.sort((a, b) {
        final byUnread = b.unreadCount.compareTo(a.unreadCount);
        return byUnread != 0 ? byUnread : compareTitlesThai(a.title, b.title);
      });
  }
  return list;
}


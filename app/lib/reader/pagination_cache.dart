import 'package:flutter/widgets.dart';

import 'book_pagination.dart';

/// Session-only, bounded LRU. Exact source JSON avoids content-hash collisions.
/// The estimate is a retention budget, not a measurement of VM heap bytes.
typedef PaginationCacheKey = ({
  String book,
  String content,
  String? document,
  Object geometry,
});

class PaginationCache with WidgetsBindingObserver {
  final int maxEntries, maxCost;
  final _entries =
      <({PaginationCacheKey key, BookPagination layout, int cost})>[];
  int generation = 0;
  int get retainedCost => _entries.fold(0, (sum, e) => sum + e.cost);
  int get length => _entries.length;
  PaginationCache({this.maxEntries = 3, this.maxCost = 16 * 1024 * 1024});

  BookPagination? get(PaginationCacheKey key) {
    final index = _entries.indexWhere((e) => e.key == key);
    if (index < 0) return null;
    final entry = _entries.removeAt(index);
    _entries.add(entry);
    return entry.layout;
  }

  void put(PaginationCacheKey key, BookPagination layout) {
    var cost = key.content.length * 2 + layout.pages.length * 128;
    for (final page in layout.pages) {
      for (final fragment in page.fragments) {
        // Do not retain a transient failed image load across reader sessions.
        if (fragment is PageImageFragment && fragment.unavailable) return;
        cost += 512;
        if (fragment is PageTableRowFragment) {
          for (final cell in fragment.cells) {
            cost += 128 + cell.text.length * 2;
          }
        }
      }
    }
    _entries.removeWhere((e) => e.key == key);
    if (maxEntries <= 0 || cost > maxCost) return;
    while (_entries.isNotEmpty &&
        (_entries.length >= maxEntries || retainedCost + cost > maxCost)) {
      _entries.removeAt(0);
    }
    _entries.add((key: key, layout: layout, cost: cost));
  }

  void removeBook(String id) {
    generation++;
    _entries.removeWhere((e) => e.key.book == id);
  }

  void clear() {
    generation++;
    _entries.clear();
  }

  @override
  void didHaveMemoryPressure() => clear();
}

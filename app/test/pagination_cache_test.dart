import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/pagination_cache.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  const content = BookContent([
    BookBlock('First paragraph.'),
    BookBlock('Second paragraph.'),
  ]);
  final layout = const BookPaginator().paginate(
    content,
    viewport: const Size(400, 700),
    platform: TargetPlatform.android,
  );
  PaginationCacheKey key(
    String book, {
    String source = 'source',
    String? document,
    Object geometry = 1,
  }) => (book: book, content: source, document: document, geometry: geometry);

  test('exact source, document and geometry isolate cache entries', () {
    final cache = PaginationCache();
    cache.put(key('a'), layout);
    expect(cache.get(key('a')), same(layout));
    expect(cache.get(key('b')), isNull);
    expect(cache.get(key('a', source: 'changed')), isNull);
    expect(cache.get(key('a', document: 'notes')), isNull);
    expect(cache.get(key('a', geometry: 2)), isNull);
  });
  test('LRU, retention budget, deletion and memory pressure', () {
    final cache = PaginationCache(maxEntries: 2);
    cache.put(key('a'), layout);
    final cost = cache.retainedCost;
    cache.put(key('b'), layout);
    cache.get(key('a'));
    cache.put(key('c'), layout);
    expect(cache.get(key('b')), isNull);
    expect(cache.get(key('a')), same(layout));
    cache.removeBook('a');
    expect(cache.get(key('a')), isNull);
    expect(cache.get(key('c')), same(layout));
    final generation = cache.generation;
    cache.didHaveMemoryPressure();
    expect(cache.length, 0);
    expect(cache.generation, greaterThan(generation));
    final tiny = PaginationCache(maxCost: cost - 1);
    tiny.put(key('a'), layout);
    expect(tiny.length, 0);
    final bounded = PaginationCache(maxCost: cost, maxEntries: 3);
    bounded.put(key('a'), layout);
    bounded.put(key('b'), layout);
    expect(bounded.length, 1);
    expect(bounded.retainedCost, lessThanOrEqualTo(cost));
  });
  test('missing image dimensions do not become a persistent cache hit', () {
    final cache = PaginationCache();
    final missing = const BookPaginator().paginate(
      const BookContent([BookBlock('', image: 'missing.png')]),
      viewport: const Size(400, 700),
      platform: TargetPlatform.android,
    );
    cache.put(key('a'), missing);
    expect(cache.length, 0);
  });
  test('only typography affects style pagination identity', () {
    const style = ReaderStyle();
    expect(
      style.paginationKey,
      const ReaderStyle(
        theme: ReaderTheme.night,
        glossLanguage: GlossLanguage.enEn,
        bubbleSize: 22,
        tier: GlossTier.full,
        followSystem: false,
      ).paginationKey,
    );
    expect(
      style.paginationKey,
      isNot(const ReaderStyle(size: 22).paginationKey),
    );
    expect(
      style.paginationKey,
      isNot(const ReaderStyle(margin: 30).paginationKey),
    );
  });
  testWidgets(
    'reopen uses layout immediately with current anchor; style and source invalidate',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = PaginationCache();
      final source = BookContent(
        List.generate(45, (i) => BookBlock('Paragraph $i. ' * 12)),
      ).encode();
      var state = GlobalKey<PagedReaderState>();
      Widget build({
        String? raw,
        ReaderStyle style = const ReaderStyle(),
        int block = 0,
      }) => MaterialApp(
        home: Scaffold(
          body: PagedReader(
            key: state,
            cache: cache,
            cacheBookId: 'book',
            cacheContent: raw ?? source,
            content: BookContent.decode(raw ?? source),
            style: style,
            initialAnchor: PageAnchor(BookPosition(block)),
            loadImage: (_) async => null,
            onPosition: (_, page, count) {},
            onWord: (_, word, rect, cell) {},
            onSentence: (_, offset) {},
            onLink: (_) {},
            onBlank: () {},
            onTurn: () {},
            onScrollFallback: () {},
          ),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final original = state.currentState!.layout!;
      await tester.pumpWidget(const SizedBox());
      state = GlobalKey<PagedReaderState>();
      await tester.pumpWidget(build(block: 20));
      expect(state.currentState!.layout, same(original));
      expect(find.text('正在分页…'), findsNothing);
      expect(state.currentState!.anchor.position.block, 20);
      await tester.pumpWidget(
        build(block: 20, style: const ReaderStyle(theme: ReaderTheme.night)),
      );
      expect(state.currentState!.layout, same(original));
      tester.view.physicalSize = const Size(1194, 834);
      await tester.pumpAndSettle();
      expect(state.currentState!.columns, 2);
      expect(state.currentState!.layout, isNot(same(original)));
      tester.view.physicalSize = const Size(400, 800);
      await tester.pump();
      expect(state.currentState!.layout, same(original));
      await tester.pumpWidget(build(style: const ReaderStyle(size: 25)));
      await tester.pumpAndSettle();
      expect(state.currentState!.layout, isNot(same(original)));
      await tester.pumpWidget(
        build(raw: const BookContent([BookBlock('Replacement book')]).encode()),
      );
      await tester.pumpAndSettle();
      expect(state.currentState!.layout!.pages, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

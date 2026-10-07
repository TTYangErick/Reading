import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/bookmarks/bookmark.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/search/book_search.dart';
import 'package:reading_app/search/search_page.dart';
import 'package:reading_app/vocab/vocabulary.dart';

import 'vocabulary_test.dart' show draft;
import 'reader_links_test.dart' show tapText;

class DelayedSearch extends BookSearch {
  final calls =
      <({Completer<BookSearchResult?> done, bool Function()? cancelled})>[];
  @override
  Future<BookSearchResult?> find(
    BookContent content,
    String query, {
    bool caseSensitive = false,
    bool Function()? cancelled,
  }) {
    final done = Completer<BookSearchResult?>();
    calls.add((done: done, cancelled: cancelled));
    return done.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('literal search preserves UTF16 and flexible whitespace without ASCII word assumptions', () async {
    const text =
        '😀 İ abc Target\r\n   Phrase, target phrase. [a.*] naïve. aaaa';
    const content = BookContent([
      BookBlock(text),
      BookBlock('target'),
      BookBlock('phrase'),
    ]);
    final result = (await const BookSearch().find(content, 'TARGET phrase'))!;
    expect(result.hits.map((h) => h.match), [
      'Target\r\n   Phrase',
      'target phrase',
    ]);
    for (final h in result.hits) {
      expect(h.position.offset, text.indexOf(h.match));
      expect(h.valid(content), isTrue);
    }
    expect(
      (await const BookSearch().find(
        content,
        'TARGET phrase',
        caseSensitive: true,
      ))!.hits,
      isEmpty,
    );
    expect(
      (await const BookSearch().find(content, '[a.*]'))!.hits.single.match,
      '[a.*]',
    );
    expect(
      (await const BookSearch().find(content, 'NAÏVE'))!.hits.single.match,
      'naïve',
    );
    expect(
      (await const BookSearch().find(
        content,
        'İ',
      ))!.hits.single.position.offset,
      3,
    );
    expect((await const BookSearch().find(content, '😀'))!.hits.single.end, 2);
    expect((await const BookSearch().find(content, 'aaa'))!.hits, hasLength(2));
    expect((await const BookSearch().find(content, '   '))!.hits, isEmpty);
    await expectLater(
      const BookSearch().find(content, 'a' * 201),
      throwsArgumentError,
    );
  });
  test(
    'all source kinds, chunk boundaries, result cap and scan cap are explicit',
    () async {
      final prefix = 'x' * 8191;
      final content = BookContent(
        [
          BookBlock('${prefix}Target'),
          const BookBlock('Target', image: 'image'),
          const BookBlock(
            '',
            rows: [
              ['Target', 'Target'],
              ['not', 'joined'],
            ],
          ),
        ],
        supplementaryDocuments: const {
          'note': [BookBlock('Target')],
        },
      );
      final found = (await const BookSearch().find(content, 'target'))!;
      expect(found.hits, hasLength(5));
      expect(found.limit, isNull);
      expect(found.hits.first.position.offset, 8191);
      expect(found.hits[1].anchor.part, PagePart.caption);
      expect(found.hits[2].cell, '0-0');
      expect(found.hits[3].cell, '0-1');
      expect(found.hits[4].position.document, 'note');
      for (final h in found.hits) {
        expect(h.valid(content), isTrue);
      }
      expect(
        found.hits.first.valid(const BookContent([BookBlock('changed')])),
        isFalse,
      );
      expect(
        (await const BookSearch().find(content, 'not joined'))!.hits,
        isEmpty,
      );
      final limited = (await const BookSearch(maxResults: 2)
          .find(content, 'Target'))!;
      expect(limited.hits, hasLength(2));
      expect(limited.limit, SearchLimit.results);
      final partial = (await const BookSearch(maxUnits: 20)
          .find(content, 'Target'))!;
      expect(partial.limit, SearchLimit.text);
      final exactly = (await const BookSearch(maxResults: 5)
          .find(content, 'Target'))!;
      expect(exactly.limit, isNull);
      final emptySegments = await const BookSearch().find(
        BookContent(List.filled(100001, const BookBlock('', rows: []))),
        'nothing',
      );
      expect(emptySegments!.limit, SearchLimit.text);
      final spaces = ' ' * 10000;
      final wideMatch = (await const BookSearch().find(
        BookContent([BookBlock('a${spaces}b')]),
        'a b',
      ))!.hits.single;
      expect(wideMatch.end, 10002);
      expect(wideMatch.previewMatch.length, lessThanOrEqualTo(203));
    },
  );
  test(
    'long blocks yield and cancel rather than publish stale results',
    () async {
      var cancelled = false, ticks = 0;
      Timer.run(() {
        ticks++;
        cancelled = true;
      });
      final found = await const BookSearch().find(
        BookContent([BookBlock('abcdef ' * 20000)]),
        'not found',
        cancelled: () => cancelled,
      );
      expect(ticks, 1);
      expect(found, isNull);
    },
  );

  testWidgets(
    'typing, case option, clear, limits, error retry and late completion are isolated',
    (tester) async {
      final engine = DelayedSearch();
      await tester.pumpWidget(
        MaterialApp(
          home: BookSearchPage(
            content: const BookContent([]),
            search: engine,
            onOpen: (_, _) async {},
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('book-search-input')),
        'first',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(
        find.byKey(const ValueKey('book-search-input')),
        'second',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(engine.calls.first.cancelled!(), isTrue);
      engine.calls.first.done.complete(
        const BookSearchResult([], limit: SearchLimit.text),
      );
      engine.calls.last.done.complete(const BookSearchResult([]));
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配内容'), findsOneWidget);
      expect(find.textContaining('未覆盖'), findsNothing);
      await tester.tap(find.text('区分大小写'));
      await tester.pump();
      engine.calls.last.done.completeError(StateError('failure'));
      await tester.pumpAndSettle();
      expect(find.text('搜索暂时失败'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      engine.calls.last.done.complete(
        const BookSearchResult([], limit: SearchLimit.text),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('搜索未覆盖全部内容'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('book-search-input')),
        'third',
      );
      await tester.pump(const Duration(milliseconds: 350));
      final pending = engine.calls.last;
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(pending.cancelled!(), isTrue);
      pending.done.complete(
        const BookSearchResult([], limit: SearchLimit.results),
      );
      await tester.pumpAndSettle();
      expect(find.text('输入关键词，查找书中的位置'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('book-search-input')),
        'last',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(const SizedBox.shrink());
      engine.calls.last.done.completeError(StateError('late'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, paged) in [
    (const Size(320, 740), true),
    (const Size(402, 874), true),
    (const Size(1194, 834), true),
    (const Size(320, 740), false),
  ]) {
    testWidgets(
      'search results highlight real text and return without data changes $size paged=$paged',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
        final db = ReadingDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final prefix = 'Earlier words. ' * 100;
        final content = BookContent(
          [
            const BookBlock('Original position'),
            BookBlock('${prefix}Body Target.'),
            BookBlock('${prefix}Caption Target.', image: 'missing'),
            BookBlock(
              '',
              rows: List.generate(
                35,
                (r) => List.generate(
                  5,
                  (c) => r == 30 && c == 4
                      ? '${prefix}Table Target.'
                      : 'Cell $r $c',
                ),
              ),
            ),
          ],
          chapters: const [
            BookChapter('Original', 0),
            BookChapter('Destinations', 1),
          ],
          supplementaryDocuments: {
            'note': [BookBlock('${prefix}Note Target.')],
          },
        );
        final id = await db.addBook('Search book', content),
            book = (await db.book(id))!;
        await db.addBookmark(id, const PageAnchor(BookPosition(0)));
        await db.addVocabulary(draft(book: id));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: ThemeData(
                platform: size.width == 320
                    ? TargetPlatform.android
                    : TargetPlatform.iOS,
              ),
              home: ReaderPage(
                book: book,
                defaultStyle: ReaderStyle(paged: paged, landscapePaged: paged),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> actions() async {
          if (paged) {
            await tester.tap(find.byKey(const ValueKey('page-label')));
            await tester.pumpAndSettle();
          }
        }

        Future<Map<String, List<Map<String, Object?>>>> data() async => {
          for (final t in [
            'books',
            'book_assets',
            'settings',
            'translations',
            'vocabulary',
            'bookmarks',
          ])
            t: (await db.customSelect('SELECT * FROM $t ORDER BY rowid').get())
                .map((r) => r.data)
                .toList(),
        };
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        final before = await data();
        await actions();
        await tester.tap(find.byKey(const ValueKey('reader-search')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('book-search-input')),
          'target',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('找到 4 处'), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          final tile = find.byKey(ValueKey('search-result-$i'));
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          await tester.tap(tile);
          await tester.pumpAndSettle();
          final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
          final hit = reader.searchHit!;
          expect(hit.match, 'Target');
          if (paged) {
            expect(
              tester
                  .state<PagedReaderState>(find.byType(PagedReader))
                  .anchor
                  .encode(),
              hit.anchor.encode(),
            );
          }
          final points = <Offset>[];
          for (final e
              in find
                  .byWidgetPredicate(
                    (w) => w is ReaderParagraph && w.text == hit.text,
                  )
                  .evaluate()) {
            final p = e.widget as ReaderParagraph;
            expect(p.selection?.start, hit.position.offset);
            expect(p.selection?.end, hit.end);
            final r = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byWidget(e.widget),
                matching: find.byType(RichText),
              ),
            );
            final boxes = r.getBoxesForSelection(
              TextSelection(
                baseOffset: hit.position.offset,
                extentOffset: hit.end,
              ),
            );
            if (boxes.isNotEmpty) {
              points.add(r.localToGlobal(boxes.first.toRect().center));
            }
          }
          expect(
            points.any(
              (p) =>
                  p.dx > 0 &&
                  p.dx < size.width &&
                  p.dy > 55 &&
                  p.dy < size.height - 40,
            ),
            isTrue,
            reason: 'target visible: $points',
          );
          await actions();
          expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
          expect(find.byTooltip('目录'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('back-link')));
          await tester.pumpAndSettle();
          expect(find.byType(BookSearchPage), findsOneWidget);
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
            'target',
          );
          expect(await data(), before);
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('search-result-0')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-result-0')));
        await tester.pumpAndSettle();
        await actions();
        await tester.tap(find.byKey(const ValueKey('close-links')));
        await tester.pumpAndSettle();
        expect(find.byType(BookSearchPage), findsNothing);
        expect(
          tester.widget<ReaderPage>(find.byType(ReaderPage)).linkTarget,
          isNull,
        );
        expect(await data(), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'true backlink skips intervening search page; directory and leave use original controls',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final content = BookContent(
        [BookBlock('Original ' * 300), BookBlock('Second ' * 300)],
        chapters: const [
          BookChapter('Original chapter', 0),
          BookChapter('Second chapter', 1),
        ],
        supplementaryDocuments: const {
          'note': [BookBlock('Target Return')],
        },
        links: const [
          BookLink(
            block: 0,
            start: 7,
            end: 13,
            document: 'note',
            href: 'body',
            kind: BookLinkKind.backlink,
            status: BookLinkStatus.resolved,
            target: BookPosition(0),
          ),
        ],
      );
      final id = await db.addBook('Book', content);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final book = (await db.book(id))!;
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderPage(
                            book: book,
                            defaultStyle: const ReaderStyle(
                              paged: false,
                              landscapePaged: false,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Future<void> search() async {
        await tester.tap(find.byKey(const ValueKey('reader-search')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('book-search-input')),
          'Target',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-result-0')));
        await tester.pumpAndSettle();
      }

      await search();
      await tapText(tester, 0, 'Return');
      expect(find.byType(BookSearchPage), findsNothing);
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).linkTarget,
        isNull,
      );
      await search();
      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second chapter'));
      await tester.pumpAndSettle();
      expect(find.byType(BookSearchPage), findsNothing);
      expect((await db.book(id))!.position, 1);
      await search();
      await tester.tap(find.byKey(const ValueKey('back-library')));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.byType(BookSearchPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

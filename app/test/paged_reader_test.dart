import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:reading_app/book/book.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/settings.dart';
import 'package:reading_app/reader/style.dart';

import 'epub_links_test.dart' show supplementaryBook, notePage;

class _Dictionary implements DictionaryProvider {
  final words = <String>[];
  @override
  DictionaryEntry? lookup(String word) {
    words.add(word);
    return null;
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
  });
  const pagedStyle = ReaderStyle(font: 'Literata', paged: true);

  test(
    'version 2 migration preserves content, assets, settings and old progress',
    () async {
      final temp = Directory.systemTemp.createTempSync('reading-pages-');
      final file = File('${temp.path}/reading.sqlite');
      final old = sqlite.sqlite3.open(file.path);
      final content = const BookContent([
        BookBlock('First'),
        BookBlock('Second'),
      ]).encode();
      old.execute(
        'CREATE TABLE books(id TEXT PRIMARY KEY,title TEXT NOT NULL,content TEXT NOT NULL,position INTEGER NOT NULL DEFAULT 0,style TEXT,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,last_read_at INTEGER NOT NULL DEFAULT 0)',
      );
      old.execute(
        'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
      );
      old.execute(
        'CREATE TABLE book_assets(book_id TEXT NOT NULL,path TEXT NOT NULL,data BLOB NOT NULL,PRIMARY KEY(book_id,path))',
      );
      old.execute("INSERT INTO books VALUES('old','Old',?,1,NULL,1,2,3)", [
        content,
      ]);
      old.execute("INSERT INTO settings VALUES('readerStyle','{}')");
      old.execute("INSERT INTO book_assets VALUES('old','p',X'010203')");
      old.execute('PRAGMA user_version=2');
      old.close();
      var db = ReadingDatabase(NativeDatabase(file));
      try {
        final book = (await db.book('old'))!;
        expect(book.content.encode(), content);
        expect(book.position, 1);
        expect(book.location, isNull);
        expect(await db.asset('old', 'p'), [1, 2, 3]);
        expect(await db.setting('readerStyle'), '{}');
        final location = const PageAnchor(BookPosition(1, offset: 3)).encode();
        await db.savePosition('old', 1, location: location);
        await db.close();
        db = ReadingDatabase(NativeDatabase(file));
        expect((await db.book('old'))!.location, location);
        await db.savePosition('old', 0);
        expect((await db.book('old'))!.location, isNull);
      } finally {
        await db.close();
        temp.deleteSync(recursive: true);
      }
    },
  );

  test('anchors are versioned and invalid saved values fall back safely', () {
    for (final anchor in [
      const PageAnchor(BookPosition(3, offset: 7)),
      const PageAnchor(BookPosition(1), part: PagePart.image),
      const PageAnchor(BookPosition(2, offset: 5), part: PagePart.caption),
      const PageAnchor(BookPosition(4), part: PagePart.tableRow, row: 9),
    ]) {
      expect(PageAnchor.decode(anchor.encode())!.encode(), anchor.encode());
    }
    for (final invalid in [
      null,
      '',
      '{}',
      '{bad',
      '{"version":2}',
      '{"version":1,"position":{"block":-1},"part":"text"}',
      '{"version":1,"position":{"block":0},"part":"tableRow","row":-1}',
    ]) {
      expect(PageAnchor.decode(invalid), isNull);
    }
    expect(ReaderStyle.decode('{}').paged, isFalse);
    expect(const ReaderStyle().paged, isTrue);
    expect(ReaderStyle.decode(null).paged, isTrue);
    expect(ReaderStyle.decode('{"paged":false}').paged, isFalse);
    expect(ReaderStyle.decode('{}').landscapePaged, isTrue);
    expect(
      ReaderStyle.decode('{"landscapePaged":false}').landscapePaged,
      isFalse,
    );
    expect(ReaderStyle.isWideLandscape(const Size(932, 430)), isFalse);
    expect(ReaderStyle.isWideLandscape(const Size(834, 1194)), isFalse);
    expect(ReaderStyle.isWideLandscape(const Size(1194, 834)), isTrue);
    expect(ReaderStyle.decode(pagedStyle.encode()).paged, isTrue);
  });

  test('cooperative pagination matches synchronous pages and supports cancellation and limits', () async {
    final content = BookContent(
      List.generate(
        150,
        (i) => BookBlock('Paragraph $i. Tomorrow is another day.'),
      ),
    );
    final sync = const BookPaginator().paginate(
      content,
      viewport: const Size(380, 500),
      platform: TargetPlatform.android,
      style: pagedStyle,
    );
    var serviced = false;
    Future<void>.delayed(Duration.zero, () => serviced = true);
    final async = (await const BookPaginator().paginateAsync(
      content,
      viewport: const Size(380, 500),
      platform: TargetPlatform.android,
      style: pagedStyle,
    ))!;
    expect(serviced, isTrue);
    expect(
      async.pages.map((p) => p.start.encode()),
      sync.pages.map((p) => p.start.encode()),
    );
    expect(
      await const BookPaginator().paginateAsync(
        content,
        viewport: const Size(380, 500),
        platform: TargetPlatform.android,
        cancelled: () => true,
      ),
      isNull,
    );
    expect(
      () => const BookPaginator().paginateAsync(
        BookContent([BookBlock('a' * 40001)]),
        viewport: const Size(380, 500),
        platform: TargetPlatform.android,
      ),
      throwsA(isA<PaginationTooLargeException>()),
    );
  });

  group('reader', () {
    late ReadingDatabase db;
    late _Dictionary dictionary;
    late String id;
    setUp(() {
      db = ReadingDatabase(NativeDatabase.memory());
      dictionary = _Dictionary();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
            'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
            (_) async => const StandardMessageCodec().encodeMessage([null]),
          );
    });
    tearDown(() async => db.close());

    Future<void> mount(
      WidgetTester tester,
      BookContent content, {
      int position = 0,
      String? location,
      ReaderStyle style = pagedStyle,
      bool images = false,
      Size size = const Size(402, 874),
      FakeViewPadding safePadding = const FakeViewPadding(),
      TargetPlatform platform = TargetPlatform.android,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = safePadding;
      tester.view.viewPadding = safePadding;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.runAsync(() async {
        id = await db.addBook('Paged book', content);
        await db.savePosition(id, position, location: location);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryProvider.overrideWith((_) async => dictionary),
          ],
          child: MaterialApp(
            theme: const ReadingApp()
                .theme(Brightness.light)
                .copyWith(platform: platform),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    final book = (await db.book(id))!;
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ReaderPage(book: book, defaultStyle: style),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      if (images) {
        // ImageDescriptor/ImageCodec complete on the engine's real clock.
        await tester.runAsync(() async {
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
      }
      await tester.pumpAndSettle();
    }

    Future<void> tapControl(WidgetTester tester, Finder control) async {
      if (control.evaluate().isEmpty) {
        final page = find.byKey(const ValueKey('page-label'));
        await tester.tap(page.evaluate().isNotEmpty ? page : find.text('阅读操作'));
        await tester.pumpAndSettle();
      }
      await tester.tap(control);
      await tester.pumpAndSettle();
    }

    PagedReaderState state(WidgetTester tester) =>
        tester.state<PagedReaderState>(find.byType(PagedReader).last);
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    Offset wordPoint(
      WidgetTester tester,
      PagedReaderState view,
      String text, {
      int? offset,
    }) {
      final block = view.anchor.position.block;
      final rich = find.descendant(
        of: find.byKey(ValueKey('page-text-${view.page}-$block-text')),
        matching: find.byType(RichText),
      );
      final render = tester.renderObject<RenderParagraph>(rich);
      final start =
          offset ??
          render.text.toPlainText().indexOf(text, view.anchor.position.offset);
      expect(start, greaterThanOrEqualTo(0));
      final box = render
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + text.length),
          )
          .first;
      return render.localToGlobal(box.toRect().center);
    }

    for (final (platform, size) in [
      (TargetPlatform.android, const Size(402, 874)),
      (TargetPlatform.iOS, const Size(402, 874)),
      (TargetPlatform.iOS, const Size(1194, 834)),
    ]) {
      testWidgets(
        'chapters start on the next physical page for $platform at $size',
        (tester) async {
          const content = BookContent(
            [
              BookBlock('Chapter one', heading: true),
              BookBlock('First paragraph.'),
              BookBlock('Chapter two', heading: true),
              BookBlock('Second paragraph.'),
              BookBlock('Chapter three', heading: true),
              BookBlock('Last paragraph.'),
            ],
            chapters: [
              BookChapter('One', 0),
              BookChapter('Two', 2),
              BookChapter('Three', 4),
            ],
          );
          await mount(tester, content, platform: platform, size: size);
          final view = state(tester);
          expect(view.layout!.pages.map((p) => p.start.position.block), [
            0,
            2,
            4,
          ]);
          if (size.width > 900) {
            expect(view.visiblePages, [0, 1]);
            // Chapter two uses the right page, without padding to the next spread.
            expect(
              find.byKey(const ValueKey('visible-page-1')),
              findsOneWidget,
            );
          }
          view.jump(const BookPosition(3, offset: 7));
          await tester.pumpAndSettle();
          final saved = view.anchor.encode();
          expect(view.page, 1);
          tester.view.physicalSize = const Size(600, 900);
          await tester.pumpAndSettle();
          expect(state(tester).anchor.encode(), saved);
          expect(state(tester).page, 1);
          await tapControl(tester, find.byKey(const ValueKey('back-library')));
          await tester.pumpAndSettle();
          final stored = (await tester.runAsync(() => db.book(id)))!;
          expect(stored.location, saved);
          expect(stored.content.encode(), content.encode());
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(state(tester).anchor.encode(), saved);
          expect(state(tester).page, 1);
          await unmount(tester);
        },
      );
    }

    for (final size in [const Size(402, 874), const Size(1194, 834)]) {
      testWidgets('outside word tap dismisses without lookup at $size', (
        tester,
      ) async {
        await mount(
          tester,
          BookContent([
            BookBlock(
              'Tomorrow is another day. Reading is a quiet pleasure. ' * 180,
            ),
          ]),
          size: size,
        );
        final view = state(tester);
        final anchor = view.anchor.encode();
        final tomorrow = wordPoint(tester, view, 'Tomorrow');
        final another = wordPoint(tester, view, 'another');
        await tester.tapAt(tomorrow);
        await tester.pumpAndSettle();
        expect(dictionary.words, ['Tomorrow']);
        expect(find.byType(WordBubble), findsOneWidget);
        expect(
          tester.getRect(find.byType(WordBubble)).contains(another),
          isFalse,
        );
        await tester.tapAt(another);
        await tester.pumpAndSettle();
        expect(find.byType(WordBubble), findsNothing);
        expect(dictionary.words, ['Tomorrow']);
        expect(view.anchor.encode(), anchor);
        expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
        await tester.tapAt(another);
        await tester.pumpAndSettle();
        expect(dictionary.words, ['Tomorrow', 'another']);
        // The same word and the otherwise empty top margin also dismiss.
        await tester.tapAt(another);
        await tester.pumpAndSettle();
        expect(find.byType(WordBubble), findsNothing);
        await tester.tapAt(tomorrow);
        await tester.pumpAndSettle();
        await tester.tapAt(Offset(size.width / 2, 5));
        await tester.pumpAndSettle();
        expect(find.byType(WordBubble), findsNothing);
        expect(view.anchor.encode(), anchor);
        if (size.width > 900) {
          // The divider and both edges of its 44px gutter are blank space.
          for (final dx in [-21.0, 0.0, 21.0]) {
            await tester.tapAt(tomorrow);
            await tester.pumpAndSettle();
            final lookups = dictionary.words.length;
            await tester.tapAt(Offset(size.width / 2 + dx, size.height / 2));
            await tester.pumpAndSettle();
            expect(find.byType(WordBubble), findsNothing);
            expect(dictionary.words.length, lookups);
            expect(view.anchor.encode(), anchor);
            expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
          }
        }
        // Swiping with a bubble open still turns the page and dismisses it.
        await tester.tapAt(tomorrow);
        await tester.pumpAndSettle();
        await tester.dragFrom(
          Offset(size.width - 50, size.height / 2),
          Offset(-size.width * .8, 0),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WordBubble), findsNothing);
        expect(view.page, greaterThan(0));
        await unmount(tester);
      });
    }

    testWidgets(
      'swipe, lookup, long press, reflow and reopen preserve a nonzero text offset',
      (tester) async {
        final text = List.filled(
          160,
          'Tomorrow is another day. Reading is a quiet pleasure. ',
        ).join();
        await mount(tester, BookContent([BookBlock(text)]));
        expect(find.text('正在分页…'), findsNothing);
        await tester.drag(find.byType(PageView), const Offset(-320, 0));
        await tester.pumpAndSettle();
        final view = state(tester);
        expect(view.page, 1);
        expect(view.anchor.position.offset, greaterThan(0));
        final saved = view.anchor.encode();
        await tester.tapAt(wordPoint(tester, view, 'Tomorrow'));
        await tester.pumpAndSettle();
        expect(dictionary.words.last.toLowerCase(), 'tomorrow');
        await tester.tap(find.byKey(const ValueKey('word-bubble')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭释义'));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          wordPoint(tester, view, 'Tomorrow'),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('选中的句子'), findsNothing);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.text('选中的句子'), findsOneWidget);
        await tester.tap(find.text('复制句子'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(500, 874);
        await tester.pumpAndSettle();
        expect(state(tester).anchor.encode(), saved);
        await tapControl(tester, find.byKey(const ValueKey('reader-settings')));
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('size'))) +
              const Offset(35, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pumpAndSettle();
        expect(state(tester).anchor.encode(), saved);
        await tapControl(tester, find.byKey(const ValueKey('back-library')));
        await tester.pumpAndSettle();
        final book = await tester.runAsync(() => db.book(id));
        expect(book!.location, saved);
        expect(book.position, 0);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(state(tester).anchor.encode(), saved);
        await unmount(tester);
      },
    );

    for (final (platform, size) in [
      (TargetPlatform.android, const Size(320, 740)),
      (TargetPlatform.iOS, const Size(402, 874)),
      (TargetPlatform.iOS, const Size(1194, 834)),
    ]) {
      testWidgets(
        'linked controls retain settings, progress and contents for $platform $size',
        (tester) async {
          final parsed = EpubParser().parse(
            supplementaryBook(
              '<h1>Chapter one</h1><p><a href="a.xhtml#n">Start</a></p><h1>Chapter two</h1><p>Last body.</p>',
              {
                'a.xhtml': notePage(
                  '<p id="n"><a href="b.xhtml#n">Next</a></p>',
                ),
                'b.xhtml': notePage(
                  '<p id="n">${'Long note text. ' * 180}</p>',
                ),
              },
            ),
          );
          final content = BookContent(
            parsed.blocks,
            chapters: const [
              BookChapter('Chapter one', 0),
              BookChapter('Chapter two', 2),
            ],
            links: parsed.links,
            supplementaryDocuments: parsed.supplementaryDocuments,
          );
          await mount(tester, content, size: size, platform: platform);
          final ref = content.links.first;
          state(tester).jump(BookPosition(ref.block, offset: ref.start));
          await tester.pumpAndSettle();
          final source = state(tester).anchor.encode();
          await tester.tapAt(wordPoint(tester, state(tester), 'Start'));
          await tester.pumpAndSettle();
          await tester.tapAt(wordPoint(tester, state(tester), 'Next'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('page-label')));
          await tester.pumpAndSettle();
          for (final key in [
            'back-library',
            'back-link',
            'close-links',
            'reader-settings',
            'reading-progress',
            'previous-page',
            'next-page',
          ]) {
            expect(find.byKey(ValueKey(key)), findsOneWidget);
          }
          expect(find.text('目录'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('reader-settings')));
          await tester.pumpAndSettle();
          tester.widget<Slider>(find.byKey(const ValueKey('size'))).onChanged!(
            26,
          );
          await tester.pumpAndSettle();
          tester.widget<ReaderSettings>(find.byType(ReaderSettings)).onPerBook!(
            true,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('关闭设置'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<PagedReader>(
                  find.byType(PagedReader, skipOffstage: false),
                )
                .map((w) => w.style.size),
            everyElement(26),
          );
          expect(
            ReaderStyle.decode(
              (await tester.runAsync(() => db.book(id)))!.style,
            ).size,
            26,
          );
          await tester.tap(find.byKey(const ValueKey('page-label')));
          await tester.pumpAndSettle();
          tester
              .widget<Slider>(find.byKey(const ValueKey('reading-progress')))
              .onChanged!(1);
          await tester.pumpAndSettle();
          expect(state(tester).page, greaterThan(0));
          expect((await tester.runAsync(() => db.book(id)))!.location, source);
          await tester.tap(find.byKey(const ValueKey('back-link')));
          await tester.pumpAndSettle();
          expect(
            find.byType(ReaderPage, skipOffstage: false),
            findsNWidgets(2),
          );
          await tapControl(tester, find.byKey(const ValueKey('close-links')));
          expect(state(tester).anchor.encode(), source);
          expect(state(tester).widget.style.size, 26);
          // A chapter chosen inside a supplementary document belongs to the body.
          await tester.tapAt(wordPoint(tester, state(tester), 'Start'));
          await tester.pumpAndSettle();
          await tapControl(tester, find.text('目录'));
          await tester.tap(find.text('Chapter two'));
          await tester.pumpAndSettle();
          expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
          expect(state(tester).anchor.position.document, isNull);
          expect(
            state(tester).anchor.position.block,
            content.contents.firstWhere((c) => c.title == 'Chapter two').block,
          );
          state(tester).jump(BookPosition(ref.block, offset: ref.start));
          await tester.pumpAndSettle();
          await tester.tapAt(wordPoint(tester, state(tester), 'Start'));
          await tester.pumpAndSettle();
          await tapControl(tester, find.byKey(const ValueKey('back-library')));
          expect(find.text('Open'), findsOneWidget);
          expect(find.byType(ReaderPage, skipOffstage: false), findsNothing);
          expect(tester.takeException(), isNull);
          await unmount(tester);
        },
      );
    }

    testWidgets(
      'paged footnotes use original glyph hit positions and preserve body on backlink',
      (tester) async {
        final content = EpubParser().parse(
          supplementaryBook(
            '<p>${'Reading words. ' * 180}<a id="ref" href="notes.xhtml#n">[1]</a> End.</p>',
            {
              'notes.xhtml': notePage(
                '<h1 id="n">A note</h1><p>Tomorrow is another day.</p><p><a href="first.xhtml#ref">Back</a></p>',
              ),
            },
          ),
        );
        final reference = content.links.firstWhere((l) => l.document == null);
        final back = content.links.firstWhere((l) => l.document != null);
        expect(back.status, BookLinkStatus.resolved);
        await mount(tester, content);
        state(tester)
            .jump(BookPosition(reference.block, offset: reference.start));
        await tester.pumpAndSettle();
        final source = state(tester).anchor.encode();
        await tester.tapAt(
          wordPoint(tester, state(tester), '[1]', offset: reference.start),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2));
        final note = state(tester);
        note.jump(
          BookPosition(back.block, offset: back.start, document: back.document),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(wordPoint(tester, note, 'Back', offset: back.start));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('back-link')), findsNothing);
        expect(state(tester).anchor.encode(), source);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect((await tester.runAsync(() => db.book(id)))!.location, source);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'table continuation persists row, wide and tall content remains accessible',
      (tester) async {
        final rows = List.generate(
          18,
          (r) => [
            'Row $r. ${r == 4 ? 'Very long content. ' * 100 : 'Hello'}',
            'Meaning',
            'Third',
          ],
        );
        await mount(
          tester,
          BookContent([
            const BookBlock('Before'),
            BookBlock('', rows: rows, tableHeader: true),
            const BookBlock('After'),
          ]),
        );
        final view = state(tester);
        final tall = view.layout!.pageForAnchor(
          const PageAnchor(BookPosition(1), part: PagePart.tableRow, row: 4),
        )!;
        view.jumpPage(tall);
        await tester.pumpAndSettle();
        final vertical = find
            .descendant(
              of: find.byKey(ValueKey('page-scroll-$tall')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.drag(vertical, const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(
          tester.state<ScrollableState>(vertical).position.pixels,
          greaterThan(0),
        );
        final target = view.layout!.pageForAnchor(
          const PageAnchor(BookPosition(1), part: PagePart.tableRow, row: 8),
        )!;
        view.jumpPage(target);
        await tester.pumpAndSettle();
        final saved = view.anchor.encode();
        expect(view.anchor.part, PagePart.tableRow);
        expect(view.anchor.row, greaterThan(0));
        final horizontal = find
            .descendant(
              of: find.byKey(ValueKey('page-table-$target-1')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.drag(horizontal, const Offset(-160, 0));
        await tester.pumpAndSettle();
        expect(
          tester.state<ScrollableState>(horizontal).position.pixels,
          greaterThan(0),
        );
        expect(view.page, target);
        expect(view.hasOverflow, isTrue);
        await tapControl(tester, find.byTooltip('展开本页内容'));
        await tester.pumpAndSettle();
        expect(find.text('本页完整内容'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭完整内容'));
        await tester.pumpAndSettle();
        await tapControl(tester, find.byKey(const ValueKey('back-library')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(state(tester).anchor.encode(), saved);
        await unmount(tester);
      },
    );

    testWidgets(
      'images load from stored assets and captions remain selectable across pages',
      (tester) async {
        final parsed = EpubParser().parse(
          File('test/fixtures/epub/lesson-epub3.epub').readAsBytesSync(),
        );
        final path = parsed.assets.keys.first;
        final caption = 'Tomorrow describes this picture. ' * 120;
        await mount(
          tester,
          BookContent([
            BookBlock(caption, image: path),
            const BookBlock('Missing picture', image: 'missing'),
          ], assets: parsed.assets),
          images: true,
        );
        expect(find.byType(Image), findsOneWidget);
        final view = state(tester);
        final target = view.layout!.pages.indexWhere(
          (p) =>
              p.start.part == PagePart.caption && p.start.position.offset > 0,
        );
        expect(target, greaterThan(0));
        view.jumpPage(target);
        await tester.pumpAndSettle();
        final rich = find.descendant(
          of: find.byKey(ValueKey('page-text-$target-0-caption')),
          matching: find.byType(RichText),
        );
        final render = tester.renderObject<RenderParagraph>(rich);
        final start = caption.indexOf('Tomorrow', view.anchor.position.offset);
        final box = render
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: start + 8),
            )
            .first;
        await tester.tapAt(render.localToGlobal(box.toRect().center));
        await tester.pumpAndSettle();
        expect(dictionary.words.last.toLowerCase(), 'tomorrow');
        final saved = view.anchor.encode();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        // Image decoding mounted this route on the real clock; let its
        // serialized database writes finish on that clock too.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        expect((await tester.runAsync(() => db.book(id)))!.location, saved);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        view.jump(const BookPosition(1));
        await tester.pumpAndSettle();
        expect(find.text('图片无法读取'), findsOneWidget);
        await unmount(tester);
      },
    );

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        'phone $platform uses safe area once and gives reserved chrome height back to text',
        (tester) async {
          final insets = platform == TargetPlatform.iOS
              ? const FakeViewPadding(top: 62, bottom: 34)
              : const FakeViewPadding(top: 24, bottom: 24);
          final content = BookContent(
            [
              BookBlock(
                'Tomorrow is another day. Reading is a quiet pleasure. ' * 180,
              ),
            ],
            chapters: const [BookChapter('Chapter 1', 0)],
          );
          const initial = PageAnchor(BookPosition(0, offset: 500));
          await mount(
            tester,
            content,
            safePadding: insets,
            platform: platform,
            location: initial.encode(),
          );
          final view = state(tester);
          final height = 874 - insets.top - insets.bottom - 20 - 40;
          expect(view.columns, 1);
          expect(view.layout!.contentSize.height, height);
          expect(view.anchor.encode(), initial.encode());
          final oldLayout = const BookPaginator().paginate(
            content,
            viewport: Size(402, height - 166),
            platform: platform,
            style: pagedStyle,
          );
          expect(view.layout!.pages.length, lessThan(oldLayout.pages.length));
          final pageBounds = tester.getRect(find.byType(PageView));
          expect(pageBounds.top, insets.top + 20);
          expect(pageBounds.bottom, 874 - insets.bottom - 40);
          final label = tester.getRect(
            find.byKey(const ValueKey('page-label')),
          );
          expect(label.top, greaterThanOrEqualTo(pageBounds.bottom));
          expect(label.bottom, lessThanOrEqualTo(874 - insets.bottom));
          expect(find.byKey(const ValueKey('previous-page')), findsNothing);
          expect(find.byKey(const ValueKey('next-page')), findsNothing);
          expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
          expect(find.byKey(const ValueKey('reading-progress')), findsNothing);
          // Opening/closing the temporary controls must not repaginate the text.
          await tester.tap(find.byKey(const ValueKey('page-label')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('reading-progress')),
            findsOneWidget,
          );
          expect(view.layout!.contentSize.height, height);
          await tester.tap(find.byTooltip('关闭阅读操作'));
          await tester.pumpAndSettle();
          expect(view.anchor.encode(), initial.encode());
          await tester.drag(find.byType(PageView), const Offset(-320, 0));
          await tester.pumpAndSettle();
          final saved = view.anchor.encode();
          expect(saved, isNot(initial.encode()));
          await tester.tapAt(wordPoint(tester, view, 'Tomorrow'));
          await tester.pumpAndSettle();
          final bubble = tester.getRect(
            find.byKey(const ValueKey('word-bubble')),
          );
          final word = wordPoint(tester, view, 'Tomorrow');
          expect(bubble.contains(word), isFalse);
          expect(bubble.top, greaterThanOrEqualTo(insets.top));
          expect(bubble.bottom, lessThanOrEqualTo(874 - insets.bottom));
          await tester.tap(find.byKey(const ValueKey('word-bubble')));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('关闭释义'));
          await tester.pumpAndSettle();
          await tapControl(tester, find.byKey(const ValueKey('back-library')));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(state(tester).anchor.encode(), saved);
          expect(state(tester).layout!.contentSize.height, height);
          expect(tester.takeException(), isNull);
          await unmount(tester);
        },
      );
    }

    testWidgets(
      'wide landscape shows consecutive pages and turns by spread; right page survives reflow and reopen',
      (tester) async {
        await mount(
          tester,
          BookContent(
            [
              BookBlock(
                'Tomorrow is another day. Reading is a quiet pleasure. ' * 180,
              ),
            ],
            chapters: const [BookChapter('Chapter 1', 0)],
          ),
          size: const Size(1194, 834),
        );
        final view = state(tester);
        expect(view.columns, 2);
        expect(view.visiblePages, [0, 1]);
        expect(view.layout!.contentSize.height, 762);
        final oldLayout = const BookPaginator().paginate(
          view.widget.content,
          viewport: const Size(575, 608),
          platform: TargetPlatform.android,
          style: pagedStyle,
        );
        expect(view.layout!.pages.length, lessThan(oldLayout.pages.length));
        expect(find.text('Chapter 1'), findsOneWidget);
        expect(find.text('Paged book'), findsNothing);
        expect(find.byKey(const ValueKey('back-library')), findsNothing);
        expect(find.byKey(const ValueKey('previous-page')), findsNothing);
        expect(find.byKey(const ValueKey('next-page')), findsNothing);
        expect(find.byKey(const ValueKey('reading-progress')), findsNothing);
        final left = tester.getRect(
          find.byKey(const ValueKey('visible-page-0')),
        );
        final right = tester.getRect(
          find.byKey(const ValueKey('visible-page-1')),
        );
        expect(right.left - left.right, 44);
        expect(left.width, right.width);
        await tester.drag(find.byType(PageView), const Offset(-850, 0));
        await tester.pumpAndSettle();
        expect(view.visiblePages, [2, 3]);
        await tapControl(tester, find.byKey(const ValueKey('previous-page')));
        await tester.pumpAndSettle();
        expect(view.visiblePages, [0, 1]);
        // Jumping directly to the right page must not be overwritten by the
        // PageView callback for the containing spread.
        view.jumpPage(1);
        await tester.pumpAndSettle();
        final saved = view.anchor.encode();
        final point = wordPoint(tester, view, 'Tomorrow');
        expect(point.dx, greaterThan(right.left));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(dictionary.words.last.toLowerCase(), 'tomorrow');
        final bubble = tester.getRect(
          find.byKey(const ValueKey('word-bubble')),
        );
        expect(bubble.left, greaterThanOrEqualTo(0));
        expect(bubble.right, lessThanOrEqualTo(1194));
        tester.view.physicalSize = const Size(834, 1194);
        await tester.pumpAndSettle();
        expect(state(tester).columns, 1);
        expect(state(tester).anchor.encode(), saved);
        tester.view.physicalSize = const Size(600, 834);
        await tester.pumpAndSettle();
        expect(state(tester).columns, 1);
        expect(state(tester).anchor.encode(), saved);
        tester.view.physicalSize = const Size(1194, 834);
        await tester.pumpAndSettle();
        expect(state(tester).columns, 2);
        expect(state(tester).anchor.encode(), saved);
        expect(state(tester).page, 1);
        await tapControl(tester, find.byKey(const ValueKey('back-library')));
        await tester.pumpAndSettle();
        expect((await tester.runAsync(() => db.book(id)))!.location, saved);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(state(tester).page, 1);
        expect(state(tester).anchor.encode(), saved);
        await unmount(tester);
      },
    );

    testWidgets(
      'right-page footnote and backlink keep the exact source and body progress',
      (tester) async {
        final content = EpubParser().parse(
          supplementaryBook(
            '<p>${'Reading words. ' * 120}<a id="ref" href="notes.xhtml#n">[1]</a> End.</p>',
            {
              'notes.xhtml': notePage(
                '<p id="n">Tomorrow <a href="first.xhtml#ref">Back</a></p>',
              ),
            },
          ),
        );
        final reference = content.links.firstWhere((l) => l.document == null);
        final back = content.links.firstWhere((l) => l.document != null);
        await mount(tester, content, size: const Size(1194, 834));
        final body = state(tester);
        body.jump(BookPosition(reference.block, offset: reference.start));
        await tester.pumpAndSettle();
        expect(body.page.isOdd, isTrue);
        final saved = body.anchor.encode();
        await tester.tapAt(
          wordPoint(tester, body, '[1]', offset: reference.start),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2));
        expect(state(tester).columns, 2);
        await tester.tapAt(
          wordPoint(tester, state(tester), 'Back', offset: back.start),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
        expect(state(tester).anchor.encode(), saved);
        expect(state(tester).page.isOdd, isTrue);
        await tapControl(tester, find.byKey(const ValueKey('back-library')));
        await tester.pumpAndSettle();
        expect((await tester.runAsync(() => db.book(id)))!.location, saved);
        await unmount(tester);
      },
    );

    testWidgets(
      'odd final spread leaves a blank right page and expands overflow from either page',
      (tester) async {
        await mount(
          tester,
          BookContent([
            for (var row = 0; row < 3; row++)
              BookBlock(
                '',
                rows: [
                  ['Row $row. ${'Very long table text. ' * 200}', 'Meaning'],
                ],
              ),
          ]),
          size: const Size(1194, 834),
        );
        final view = state(tester);
        expect(view.layout!.pages.length, 3);
        expect(view.visiblePages, [0, 1]);
        await tapControl(tester, find.byTooltip('展开本页内容'));
        await tester.pumpAndSettle();
        final rightText = find.byWidgetPredicate(
          (w) => w is SelectableText && (w.data?.startsWith('Row 1.') ?? false),
        );
        await tester.scrollUntilVisible(
          rightText,
          400,
          scrollable: find
              .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(rightText, findsOneWidget);
        // Return to the close control after checking the second page's text.
        await tester.scrollUntilVisible(
          find.byTooltip('关闭完整内容'),
          -400,
          scrollable: find
              .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.byTooltip('关闭完整内容'));
        await tester.pumpAndSettle();
        await tapControl(tester, find.byKey(const ValueKey('next-page')));
        await tester.pumpAndSettle();
        expect(view.visiblePages, [2]);
        expect(find.byKey(const ValueKey('empty-page')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('page-label'))).data,
          '3 / 3',
        );
        await tester.tap(find.byKey(const ValueKey('page-label')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('next-page')))
              .onPressed,
          isNull,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'wide landscape and portrait remember separate modes and preserve existing scroll preference',
      (tester) async {
        await mount(
          tester,
          BookContent([BookBlock('Tomorrow is another day. ' * 100)]),
          style: const ReaderStyle(font: 'Literata', paged: false),
          size: const Size(1194, 834),
        );
        expect(state(tester).columns, 2);
        state(tester).jumpPage(1);
        await tester.pumpAndSettle();
        final saved = state(tester).anchor.encode();
        tester.view.physicalSize = const Size(834, 1194);
        await tester.pumpAndSettle();
        expect(find.byType(PagedReader), findsNothing);
        tester.view.physicalSize = const Size(1194, 834);
        await tester.pumpAndSettle();
        expect(state(tester).anchor.encode(), saved);
        await tapControl(tester, find.byKey(const ValueKey('reader-settings')));
        await tester.pumpAndSettle();
        expect(find.text('双页翻阅'), findsOneWidget);
        await tester.tap(find.text('上下滚动'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pumpAndSettle();
        expect(find.byType(PagedReader), findsNothing);
        tester.view.physicalSize = const Size(834, 1194);
        await tester.pumpAndSettle();
        await tapControl(tester, find.byKey(const ValueKey('reader-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('左右翻页'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pumpAndSettle();
        expect(state(tester).columns, 1);
        tester.view.physicalSize = const Size(1194, 834);
        await tester.pumpAndSettle();
        expect(find.byType(PagedReader), findsNothing);
        await tapControl(tester, find.byKey(const ValueKey('back-library')));
        await tester.pumpAndSettle();
        final style = ReaderStyle.decode(
          await tester.runAsync(() async => (await db.setting('readerStyle'))!),
        );
        expect(style.paged, isTrue);
        expect(style.landscapePaged, isFalse);
        await unmount(tester);
      },
    );

    testWidgets(
      'old progress and malformed location restore, long block offers scroll fallback',
      (tester) async {
        await mount(
          tester,
          const BookContent([BookBlock('First'), BookBlock('Tomorrow')]),
          position: 1,
          location: '{bad',
        );
        expect(state(tester).anchor.position.block, 1);
        await unmount(tester);
        await mount(tester, BookContent([BookBlock('Word ' * 8100)]));
        expect(find.text('改用滚动阅读'), findsOneWidget);
        await tester.tap(find.text('改用滚动阅读'));
        await tester.pumpAndSettle();
        expect(find.byType(PagedReader), findsNothing);
        expect(find.byKey(const ValueKey('reader-text')), findsOneWidget);
        await unmount(tester);
      },
    );
  });
}

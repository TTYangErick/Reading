import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await font.load();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  BookContent content({bool table = false}) => BookContent(
    List.generate(
      80,
      (i) => table && i == 4
          ? BookBlock(
              '',
              rows: List.generate(
                40,
                (r) => ['Row $r', 'Description of this row.'],
              ),
            )
          : BookBlock(
              'Paragraph $i. ${'Readers enjoy a quiet morning with this story. ' * 8}',
            ),
    ),
    chapters: const [
      BookChapter('Chapter one', 0),
      BookChapter('Chapter two', 30),
      BookChapter('Chapter three', 60),
    ],
    supplementaryDocuments: const {
      'note': [BookBlock('A note.')],
    },
  );
  Future<void> flush(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await t.pump();
  }

  late ReadingDatabase db;
  late String id;
  Future<void> mount(
    WidgetTester t,
    Size size, {
    bool paged = true,
    bool table = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    db = ReadingDatabase(NativeDatabase.memory());
    id = (await t.runAsync(() async {
      final id = await db.addBook('Return test', content(table: table));
      await db.savePosition(
        id,
        4,
        location: const PageAnchor(BookPosition(4, offset: 13)).encode(),
      );
      return id;
    }))!;
    await t.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: const ReadingApp().theme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final book = (await db.book(id))!;
                  if (context.mounted) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ReaderPage(
                          book: book,
                          defaultStyle: ReaderStyle(
                            font: 'Literata',
                            paged: paged,
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
    await t.tap(find.text('Open'));
    await flush(t);
  }

  Future<void> control(WidgetTester t, Finder target) async {
    if (target.evaluate().isEmpty) {
      await t.tap(find.byKey(const ValueKey('page-label')));
      await t.pumpAndSettle();
    }
    await t.tap(target);
    await flush(t);
  }

  Future<void> chapter(WidgetTester t, String name) async {
    await control(t, find.byTooltip('目录'));
    await t.tap(find.widgetWithText(ListTile, name));
    await flush(t);
  }

  PagedReaderState state(WidgetTester t) => t.state(find.byType(PagedReader));
  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await t.runAsync(db.close);
  }

  for (final size in [
    const Size(320, 740),
    const Size(402, 874),
    const Size(1194, 834),
  ]) {
    testWidgets(
      'chapter jumps keep first origin, original controls and current saved progress at $size',
      (t) async {
        await mount(t, size);
        final original = state(t).anchor.encode();
        final bodyHeight = t.getSize(find.byType(PagedReader)).height;
        await chapter(t, 'Chapter two');
        expect(state(t).anchor.position.block, 30);
        expect((await t.runAsync(() => db.book(id)))!.position, 30);
        await chapter(t, 'Chapter three');
        expect(state(t).anchor.position.block, 60);
        await t.tap(find.byKey(const ValueKey('page-label')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
        expect(find.byKey(const ValueKey('reader-bookmarks')), findsOneWidget);
        expect(find.byKey(const ValueKey('reader-search')), findsOneWidget);
        expect(find.byKey(const ValueKey('reading-progress')), findsOneWidget);
        await control(t, find.byKey(const ValueKey('return-chapter')));
        expect(state(t).anchor.encode(), original);
        expect((await t.runAsync(() => db.book(id)))!.location, original);
        expect(t.getSize(find.byType(PagedReader)).height, bodyHeight);
        await t.tap(find.byKey(const ValueKey('page-label')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('return-chapter')), findsNothing);
        await t.tap(find.byTooltip('关闭阅读操作'));
        await t.pumpAndSettle();
        await chapter(t, 'Chapter two');
        await control(t, find.byKey(const ValueKey('back-library')));
        expect(find.text('Open'), findsOneWidget);
        await t.tap(find.text('Open'));
        await flush(t);
        expect(
          state(t).anchor.position.block,
          30,
        ); // A normal jump is saved, not a temporary footnote.
        await t.tap(find.byKey(const ValueKey('page-label')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('return-chapter')), findsNothing);
        expect(t.takeException(), isNull);
        await dispose(t);
      },
    );
  }

  testWidgets(
    'scrolling restores partially visible paragraph and keeps toolbar settings',
    (t) async {
      await mount(t, const Size(402, 874), paged: false);
      await t.drag(
        find.byKey(const ValueKey('reader-text')),
        const Offset(0, -173),
      );
      await flush(t);
      final dynamic reader = t.state(find.byType(ReaderPage));
      final positions = reader.positions as ItemPositionsListener;
      final visible =
          positions.itemPositions.value
              .where((p) => p.itemTrailingEdge > .02 && p.itemLeadingEdge < 1)
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
      final originalIndex = visible.first.index;
      final originalY = t
          .getTopLeft(find.byKey(ValueKey('paragraph-$originalIndex')))
          .dy;
      await chapter(t, 'Chapter three');
      expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
      await control(t, find.byKey(const ValueKey('return-chapter')));
      expect(
        t.getTopLeft(find.byKey(ValueKey('paragraph-$originalIndex'))).dy,
        closeTo(originalY, 2),
      );
      expect((await t.runAsync(() => db.book(id)))!.position, originalIndex);
      expect(find.byKey(const ValueKey('return-chapter')), findsNothing);
      expect(t.takeException(), isNull);
      await dispose(t);
    },
  );

  testWidgets(
    'full table anchor survives directory return and font/viewport reflow',
    (t) async {
      await mount(t, const Size(1194, 834), table: true);
      const original = PageAnchor(
        BookPosition(4),
        part: PagePart.tableRow,
        row: 18,
      );
      state(t).jumpAnchor(original);
      await flush(t);
      await chapter(t, 'Chapter two');
      final dynamic reader = t.state(find.byType(ReaderPage));
      reader.changeStyle(const ReaderStyle(font: 'Literata', size: 23), false);
      await flush(t);
      t.view.physicalSize = const Size(834, 1194);
      await flush(t);
      await control(t, find.byKey(const ValueKey('return-chapter')));
      expect(state(t).anchor.encode(), original.encode());
      expect(
        (await t.runAsync(() => db.book(id)))!.location,
        original.encode(),
      );
      expect(t.takeException(), isNull);
      await dispose(t);
    },
  );

  testWidgets(
    'changing between scrolling and paging keeps return source block',
    (t) async {
      await mount(t, const Size(402, 874));
      final originalBlock = state(t).anchor.position.block;
      await chapter(t, 'Chapter two');
      final dynamic reader = t.state(find.byType(ReaderPage));
      reader.changeStyle(
        const ReaderStyle(font: 'Literata', paged: false),
        false,
      );
      await flush(t);
      await control(t, find.byKey(const ValueKey('return-chapter')));
      expect((await t.runAsync(() => db.book(id)))!.position, originalBlock);
      expect(find.byType(PagedReader), findsNothing);
      await chapter(t, 'Chapter three');
      reader.changeStyle(
        const ReaderStyle(font: 'Literata', paged: true),
        false,
      );
      await flush(t);
      await control(t, find.byKey(const ValueKey('return-chapter')));
      expect(state(t).anchor.position.block, originalBlock);
      expect(t.takeException(), isNull);
      await dispose(t);
    },
  );

  testWidgets(
    'chapter chosen in a note captures body origin; source roots stay temporary',
    (t) async {
      await mount(t, const Size(402, 874));
      final original = state(t).anchor.encode();
      final dynamic reader = t.state(find.byType(ReaderPage));
      unawaitedLink(reader);
      await flush(t);
      expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2));
      await chapter(t, 'Chapter two');
      expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
      await control(t, find.byKey(const ValueKey('return-chapter')));
      expect(state(t).anchor.encode(), original);
      final book = (await t.runAsync(() => db.book(id)))!;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await t.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: ReaderPage.source(
              book: book,
              defaultStyle: const ReaderStyle(font: 'Literata'),
              target: const BookPosition(4),
              anchor: const PageAnchor(BookPosition(4)),
            ),
          ),
        ),
      );
      await flush(t);
      await chapter(t, 'Chapter three');
      expect(state(t).anchor.position.block, 60);
      expect((await t.runAsync(() => db.book(id)))!.location, original);
      await t.tap(find.byKey(const ValueKey('page-label')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('return-chapter')), findsNothing);
      expect(find.byKey(const ValueKey('back-link')), findsOneWidget);
      expect(t.takeException(), isNull);
      await dispose(t);
    },
  );
}

void unawaitedLink(dynamic reader) {
  reader.openLink(
    const BookLink(
      block: 4,
      start: 0,
      end: 1,
      href: 'note',
      kind: BookLinkKind.noteref,
      status: BookLinkStatus.resolved,
      target: BookPosition(0, document: 'note'),
    ),
  );
}

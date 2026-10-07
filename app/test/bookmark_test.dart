import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:reading_app/book/book.dart';
import 'package:reading_app/bookmarks/bookmark.dart';
import 'package:reading_app/bookmarks/bookmark_sheet.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/reader/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('schema 5 migration keeps all five tables; reopen, dedup and deletion are isolated', () async {
    final dir = Directory.systemTemp.createTempSync('bookmarks-');
    final file = File('${dir.path}/reading.sqlite');
    final old = sqlite.sqlite3.open(file.path);
    old.execute(
      'CREATE TABLE books(id TEXT PRIMARY KEY,title TEXT NOT NULL,content TEXT NOT NULL,position INTEGER NOT NULL DEFAULT 0,style TEXT,location TEXT,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,last_read_at INTEGER NOT NULL DEFAULT 0)',
    );
    old.execute(
      'CREATE TABLE book_assets(book_id TEXT NOT NULL,path TEXT NOT NULL,data BLOB NOT NULL,PRIMARY KEY(book_id,path))',
    );
    old.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
    old.execute(
      'CREATE TABLE translations(engine TEXT NOT NULL,source_language TEXT NOT NULL,target_language TEXT NOT NULL,source TEXT NOT NULL,result TEXT NOT NULL,PRIMARY KEY(engine,source_language,target_language,source))',
    );
    old.execute(
      'CREATE TABLE vocabulary(id TEXT PRIMARY KEY,lang TEXT NOT NULL,dict_id TEXT NOT NULL,word TEXT NOT NULL,lemma TEXT NOT NULL,gloss TEXT NOT NULL,source TEXT NOT NULL,source_url TEXT NOT NULL,license TEXT NOT NULL,book_id TEXT NOT NULL,book_title TEXT NOT NULL,sentence TEXT NOT NULL,location TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,UNIQUE(lang,dict_id,book_id,location))',
    );
    old.execute(
      "INSERT INTO books VALUES('old','Book',?,1,'style','location',1,2,3)",
      [
        const BookContent([BookBlock('one'), BookBlock('two')]).encode(),
      ],
    );
    old.execute("INSERT INTO book_assets VALUES('old','p',X'010203')");
    old.execute("INSERT INTO settings VALUES('readerStyle','{}')");
    old.execute(
      "INSERT INTO translations VALUES('native','en','zh','source','译文')",
    );
    old.execute(
      "INSERT INTO vocabulary VALUES('v','en','ecdict','one','one','一','ECDICT','url','MIT','old','Book','one','source',1,2)",
    );
    old.execute('PRAGMA user_version=5');
    final tables = [
      'books',
      'book_assets',
      'settings',
      'translations',
      'vocabulary',
    ];
    final before = {
      for (final t in tables)
        t: old
            .select('SELECT * FROM $t')
            .map((r) => r.values.toList())
            .toList(),
    };
    old.close();
    var db = ReadingDatabase(NativeDatabase(file));
    try {
      const anchor = PageAnchor(BookPosition(1));
      final ids = await Future.wait([
        db.addBookmark('old', anchor),
        db.addBookmark('old', anchor),
      ]);
      expect(ids.toSet(), hasLength(1));
      await db.addBookmark('old', const PageAnchor(BookPosition(0)));
      for (final t in tables) {
        expect(
          (await db.customSelect('SELECT * FROM $t').get())
              .map((r) => r.data.values.toList())
              .toList(),
          before[t],
        );
      }
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        7,
      );
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      expect(await db.bookmarks('old'), hasLength(2));
      final other = await db.addBook(
        'Other',
        const BookContent([BookBlock('one')]),
      );
      final otherMark = await db.addBookmark(
        other,
        const PageAnchor(BookPosition(0)),
      );
      await db.deleteBookmark(other, ids.first);
      expect(await db.bookmarks('old'), hasLength(2));
      await db.rename('old', 'Renamed');
      expect(await db.addBookmark('old', anchor), ids.first);
      await db.deleteBookmark('old', ids.first);
      expect(await db.bookmarks('old'), hasLength(1));
      await db.deleteBook('old');
      expect(await db.bookmarks('old'), isEmpty);
      expect((await db.bookmarks(other)).single.id, otherMark);
      expect(
        (await db.customSelect('SELECT * FROM vocabulary').get()),
        hasLength(1),
      );
      await expectLater(db.addBookmark('old', anchor), throwsArgumentError);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });

  test(
    'anchor validation covers all namespaces, media and malformed locations',
    () async {
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await db.addBook(
        'B',
        const BookContent(
          [
            BookBlock('text'),
            BookBlock('caption', image: 'p'),
            BookBlock(
              '',
              rows: [
                ['cell'],
              ],
            ),
            BookBlock('', rows: []),
          ],
          supplementaryDocuments: {
            'note': [BookBlock('note')],
          },
        ),
      );
      final book = (await db.book(id))!;
      final good = [
        const PageAnchor(BookPosition(0, offset: 2)),
        const PageAnchor(BookPosition(0, document: 'note')),
        const PageAnchor(BookPosition(1), part: PagePart.image),
        const PageAnchor(BookPosition(1, offset: 2), part: PagePart.caption),
        const PageAnchor(BookPosition(2), part: PagePart.tableRow, row: 0),
        const PageAnchor(BookPosition(3), part: PagePart.tableRow, row: 0),
      ];
      for (final a in good) {
        await db.addBookmark(id, a);
        expect(
          Bookmark('', id, a.encode(), '', 0).resolve(book)?.encode(),
          a.encode(),
        );
      }
      for (final a in [
        const PageAnchor(BookPosition(-1)),
        const PageAnchor(BookPosition(50)),
        const PageAnchor(BookPosition(0, offset: 99)),
        const PageAnchor(BookPosition(0, document: 'missing')),
        const PageAnchor(BookPosition(0), part: PagePart.image),
        const PageAnchor(BookPosition(1)),
        const PageAnchor(BookPosition(2), part: PagePart.tableRow, row: 2),
        const PageAnchor(BookPosition(3), part: PagePart.tableRow, row: 1),
        const PageAnchor(
          BookPosition(2, offset: 1),
          part: PagePart.tableRow,
          row: 0,
        ),
      ]) {
        expect(Bookmark('', id, a.encode(), '', 0).resolve(book), isNull);
        await expectLater(db.addBookmark(id, a), throwsArgumentError);
      }
      for (final raw in ['bad', '{}', '{"version":99}', 'x' * 16385]) {
        expect(Bookmark('', id, raw, '', 0).resolve(book), isNull);
      }
      expect(
        Bookmark('', 'other', good.first.encode(), '', 0).resolve(book),
        isNull,
      );
    },
  );

  for (final (size, paged) in [
    (const Size(320, 740), true),
    (const Size(402, 874), true),
    (const Size(1194, 834), true),
    (const Size(402, 874), false),
  ]) {
    testWidgets(
      'reader bookmarks add, media jump, return and settings at $size paged=$paged',
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
        final long = 'Earlier words. ' * 100;
        final content = BookContent(
          [
            const BookBlock('Original reading position'),
            BookBlock('${long}Body target.'),
            BookBlock('${long}Caption target.', image: 'missing'),
            BookBlock(
              '',
              rows: List.generate(35, (r) => ['Row $r target.', 'Other cell']),
            ),
          ],
          chapters: const [
            BookChapter('Original', 0),
            BookChapter('Sources', 1),
          ],
          supplementaryDocuments: {
            'note': [BookBlock('${long}Note target.')],
          },
        );
        final id = await db.addBook('Bookmarks', content),
            book = (await db.book(id))!;
        final targets = [
          PageAnchor(BookPosition(1, offset: long.length)),
          PageAnchor(
            BookPosition(2, offset: long.length),
            part: PagePart.caption,
          ),
          const PageAnchor(BookPosition(3), part: PagePart.tableRow, row: 30),
          PageAnchor(BookPosition(0, offset: long.length, document: 'note')),
        ];
        final ids = <String>[];
        for (final a in targets) {
          ids.add(await db.addBookmark(id, a));
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: ReaderPage(
                book: book,
                defaultStyle: ReaderStyle(paged: paged, landscapePaged: paged),
              ),
              theme: ThemeData(
                platform: size.width == 320
                    ? TargetPlatform.android
                    : TargetPlatform.iOS,
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

        Future<void> marks() async {
          await actions();
          await tester.tap(find.byKey(const ValueKey('reader-bookmarks')));
          await tester.pumpAndSettle();
        }

        await marks();
        await tester.tap(find.byKey(const ValueKey('add-bookmark')));
        await tester.pumpAndSettle();
        expect(find.text('此位置已添加书签'), findsOneWidget);
        expect(await db.bookmarks(id), hasLength(5));
        await tester.tap(find.byTooltip('关闭书签'));
        await tester.pumpAndSettle();
        final before =
            (await db.customSelect('SELECT * FROM books').getSingle()).data;
        for (var i = 0; i < targets.length; i++) {
          await marks();
          await tester.ensureVisible(
            find.byKey(ValueKey('bookmark-${ids[i]}')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('bookmark-${ids[i]}')));
          await tester.pumpAndSettle();
          final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
          expect(reader.linkAnchor?.encode(), targets[i].encode());
          if (paged) {
            final view = tester.state<PagedReaderState>(
              find.byType(PagedReader),
            );
            expect(view.anchor.encode(), targets[i].encode());
          }
          final targetText = i == 0
              ? 'Body target.'
              : i == 1
              ? 'Caption target.'
              : i == 2
              ? 'Row 30 target.'
              : 'Note target.';
          final points = <Offset>[];
          for (final e
              in find
                  .byWidgetPredicate(
                    (w) => w is ReaderParagraph && w.text.contains(targetText),
                  )
                  .evaluate()) {
            final r = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byWidget(e.widget),
                matching: find.byType(RichText),
              ),
            );
            final offset = r.text.toPlainText().indexOf(targetText);
            final boxes = r.getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: offset + 4),
            );
            if (boxes.isNotEmpty) {
              points.add(r.localToGlobal(boxes.first.toRect().center));
            }
          }
          expect(
            points.any(
              (p) =>
                  p.dy > 55 &&
                  p.dy < size.height - 40 &&
                  p.dx > 0 &&
                  p.dx < size.width,
            ),
            isTrue,
            reason: 'target visible: $points',
          );
          await actions();
          expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
          expect(find.byTooltip('目录'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('back-link')));
          await tester.pumpAndSettle();
          expect(
            tester.widget<ReaderPage>(find.byType(ReaderPage)).linkTarget,
            isNull,
          );
          expect(
            (await db.customSelect('SELECT * FROM books').getSingle()).data,
            before,
          );
        }
        await marks();
        await tester.tap(find.byTooltip('删除书签').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await db.bookmarks(id), hasLength(5));
        await tester.tap(find.byTooltip('删除书签').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(await db.bookmarks(id), hasLength(4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'dual-page left bookmark, reflow, nested return and reopen keep anchors',
    (tester) async {
      tester.view.physicalSize = const Size(1194, 834);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await db.addBook(
        'Book',
        BookContent(
          [BookBlock('Long text for bookmarks. ' * 200)],
          supplementaryDocuments: const {
            'note': [BookBlock('Footnote source')],
          },
        ),
      );
      final note = await db.addBookmark(
        id,
        const PageAnchor(BookPosition(0, document: 'note')),
      );
      Future<void> mount() async {
        final book = (await db.book(id))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: ReaderPage(
                book: book,
                defaultStyle: ReaderStyle.decode(
                  await db.setting('readerStyle'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await db.setSetting(
        'readerStyle',
        const ReaderStyle(paged: true, landscapePaged: true).encode(),
      );
      await mount();
      Future<void> actions() async {
        await tester.tap(find.byKey(const ValueKey('page-label')));
        await tester.pumpAndSettle();
      }

      Future<void> marks() async {
        await actions();
        await tester.tap(find.byKey(const ValueKey('reader-bookmarks')));
        await tester.pumpAndSettle();
      }

      final view = tester.state<PagedReaderState>(find.byType(PagedReader));
      view.jumpPage(3);
      await tester.pumpAndSettle();
      expect(view.columns, 2);
      final left = view.layout!.pages[2].start;
      await marks();
      await tester.tap(find.byKey(const ValueKey('add-bookmark')));
      await tester.pumpAndSettle();
      final body = (await db.bookmarks(id)).firstWhere((i) => i.id != note);
      expect(body.location, left.encode());
      await tester.tap(find.byKey(ValueKey('bookmark-$note')));
      await tester.pumpAndSettle();
      await marks();
      await tester.tap(find.byKey(ValueKey('bookmark-${body.id}')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).linkAnchor?.encode(),
        left.encode(),
      );
      await actions();
      await tester.tap(find.byKey(const ValueKey('reader-settings')));
      await tester.pumpAndSettle();
      final settings = tester.widget<ReaderSettings>(
        find.byType(ReaderSettings),
      );
      settings.onChanged(settings.style.withValue('size', 26.0));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(834, 1194);
      await tester.pumpAndSettle();
      final reflow = tester.state<PagedReaderState>(find.byType(PagedReader));
      expect(reflow.anchor.encode(), left.encode());
      expect(reflow.columns, 1);
      await actions();
      await tester.tap(find.byKey(const ValueKey('back-link')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).linkTarget?.document,
        'note',
      );
      await actions();
      await tester.tap(find.byKey(const ValueKey('close-links')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).linkTarget,
        isNull,
      );
      expect(ReaderStyle.decode(await db.setting('readerStyle')).size, 26);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount();
      await marks();
      await tester.tap(find.byKey(ValueKey('bookmark-${body.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<PagedReaderState>(find.byType(PagedReader))
            .anchor
            .encode(),
        left.encode(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('bookmark failures retry without losing or duplicating data', (
    tester,
  ) async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.addBook('Book', const BookContent([BookBlock('text')]));
    await db.customStatement(
      "CREATE TRIGGER fail_add BEFORE INSERT ON bookmarks BEGIN SELECT RAISE(FAIL,'test'); END",
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: BookmarkSheet(
              bookId: id,
              current: const PageAnchor(BookPosition(0)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有书签'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-bookmark')));
    await tester.pumpAndSettle();
    expect(find.text('添加书签失败，请重试。'), findsOneWidget);
    expect(await db.bookmarks(id), isEmpty);
    await db.customStatement('DROP TRIGGER fail_add');
    await tester.tap(find.byKey(const ValueKey('add-bookmark')));
    await tester.pumpAndSettle();
    expect(await db.bookmarks(id), hasLength(1));
    await db.customStatement(
      "CREATE TRIGGER fail_delete BEFORE DELETE ON bookmarks BEGIN SELECT RAISE(FAIL,'test'); END",
    );
    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除书签失败，请重试。'), findsOneWidget);
    expect(await db.bookmarks(id), hasLength(1));
    await db.customStatement('DROP TRIGGER fail_delete');
    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await db.bookmarks(id), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.customStatement(
      'ALTER TABLE bookmarks RENAME TO temporarily_unavailable',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: BookmarkSheet(
              bookId: id,
              current: const PageAnchor(BookPosition(0)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('书签暂时无法读取'), findsOneWidget);
    await db.customStatement(
      'ALTER TABLE temporarily_unavailable RENAME TO bookmarks',
    );
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('还没有书签'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

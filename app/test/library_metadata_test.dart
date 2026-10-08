import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/backup/backup.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/library/book_cover.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/reader.dart';

final png = Uint8List.fromList(
  ZipDecoder()
      .decodeBytes(
        File('test/fixtures/epub/lesson-epub3.epub').readAsBytesSync(),
      )
      .find('OPS/images/lesson image.png')!
      .content,
);

BookContent content({bool corrupt = false}) => BookContent(
  List.generate(
    20,
    (i) => BookBlock(
      'Paragraph $i. ${'A quiet reader follows every word. ' * 16}',
    ),
  ),
  authors: const ['Jane Austen', 'Coauthor'],
  cover: 'OPS/cover.png',
  assets: {
    'OPS/cover.png': corrupt ? Uint8List.fromList([1, 2, 3]) : png,
  },
);

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), true);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cover-only asset, manual title and precise location survive backup/reopen/delete', () async {
    final directory = await Directory.systemTemp.createTemp('reading-cover-');
    final path = File('${directory.path}/reading.sqlite');
    var database = ReadingDatabase(NativeDatabase(path));
    final restored = ReadingDatabase(NativeDatabase.memory());
    try {
      final id = await database.addBook('Imported title', content());
      final anchor = const PageAnchor(BookPosition(10, offset: 20)).encode();
      await database.savePosition(id, 10, location: anchor);
      await database.rename(id, 'My title');
      final original = (await database.book(id))!;
      final snapshot = original.contentSnapshot;
      await database.close();
      database = ReadingDatabase(NativeDatabase(path));
      final reopened = (await database.book(id))!;
      expect(reopened.title, 'My title');
      expect(reopened.position, 10);
      expect(reopened.location, anchor);
      expect(reopened.content.authors, ['Jane Austen', 'Coauthor']);
      expect(reopened.content.cover, 'OPS/cover.png');
      expect(reopened.contentSnapshot, snapshot);
      expect(await database.asset(id, reopened.content.cover!), png);
      final backup = ReadingBackup.decode(await BackupStore(database).export());
      await BackupStore(restored).restore(backup);
      final copy = (await restored.book(id))!;
      expect(copy.contentSnapshot, snapshot);
      expect(copy.title, 'My title');
      expect(copy.location, anchor);
      expect(copy.position, 10);
      expect(await restored.asset(id, copy.content.cover!), png);
      // Missing cover resources must fail preflight even with no body image.
      await database.customStatement(
        'DELETE FROM book_assets WHERE book_id=?',
        [id],
      );
      await expectLater(BackupStore(database).export(), throwsFormatException);
      await restored.deleteBook(id);
      expect(await restored.asset(id, 'OPS/cover.png'), isNull);
    } finally {
      await database.close();
      await restored.close();
      await directory.delete(recursive: true);
    }
  });

  for (final size in [const Size(430, 1000), const Size(1180, 820)]) {
    testWidgets('shelf metadata, old fallback and opening at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = ReadingDatabase(NativeDatabase.memory());
      final id = await database.addBook('A quiet reader', content());
      await database.addBook(
        'Old text',
        const BookContent([BookBlock('Legacy text')]),
      );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      final boundary = GlobalKey();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
            'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
            (_) async => const StandardMessageCodec().encodeMessage([null]),
          );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(key: boundary, child: const ReadingApp()),
          ),
        );
        await until(
          tester,
          () => find.byType(BookCover).evaluate().length == 2,
        );
        await until(
          tester,
          () => find.byKey(ValueKey('cover-image-$id')).evaluate().isNotEmpty,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Jane Austen · Coauthor'), findsOneWidget);
        expect(find.text('READING LIBRARY'), findsOneWidget);
        final image = tester.widget<Image>(
          find.byKey(ValueKey('cover-image-$id')),
        );
        final resize = image.image as ResizeImage;
        expect(resize.policy, ResizeImagePolicy.fit);
        expect(resize.width! * resize.height!, lessThanOrEqualTo(512 * 768));
        expect(tester.takeException(), isNull);
        if (Platform.environment['READING_SHELF_CAPTURE'] == '1') {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final frame = await render.toImage();
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/reading-shelf-${size.width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            frame.dispose();
          });
        }
        final cover = find.byWidgetPredicate(
          (w) => w is BookCover && w.book.id == id,
        );
        await tester.tap(cover);
        await tester.pumpAndSettle();
        expect(find.byType(ReaderPage), findsOneWidget);
        final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
        expect(reader.book.id, id);
        expect(reader.book.content.authors, ['Jane Austen', 'Coauthor']);
        expect(
          reader.book.content.blocks.first.text,
          startsWith('Paragraph 0.'),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        await database.close();
      }
    });
  }

  testWidgets(
    'corrupt cover falls back; refreshing same ID and path reloads bytes',
    (tester) async {
      final database = ReadingDatabase(NativeDatabase.memory());
      final id = await database.addBook('Book', content(corrupt: true));
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      Future<void> mount() async {
        final book = (await database.book(id))!;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 180,
                  height: 260,
                  child: BookCover(book: book),
                ),
              ),
            ),
          ),
        );
        await until(
          tester,
          () => find.byKey(ValueKey('cover-image-$id')).evaluate().isNotEmpty,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      try {
        await mount();
        expect(find.text('READING LIBRARY'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await database.customStatement(
          'UPDATE book_assets SET data=? WHERE book_id=?',
          [png, id],
        );
        await mount();
        expect(find.text('READING LIBRARY'), findsNothing);
        expect(tester.takeException(), isNull);
        final image = tester.widget<Image>(
          find.byKey(ValueKey('cover-image-$id')),
        );
        final key = await image.image.obtainKey(ImageConfiguration.empty);
        final cache = PaintingBinding.instance.imageCache;
        expect(cache.statusForKey(key).keepAlive, true);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final released = cache.statusForKey(key);
        expect(released.keepAlive || released.pending || released.live, false);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await database.close();
      }
    },
  );
}

import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/reader/image_viewer.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';

class _Dictionary implements DictionaryProvider {
  @override
  DictionaryEntry? lookup(String word) => DictionaryEntry(
    word: word,
    phonetic: '',
    fullGloss: '图片',
    definition: '',
    meanings: const ['图片'],
  );
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 400, 220),
      Paint()..color = Colors.amber,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 220);
    png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  test(
    'decode dimensions bounded without upscaling; invalid bytes rejected',
    () async {
      for (final size in [
        const Size(50000, 50000),
        const Size(100, 50000),
        const Size(100000, 20),
      ]) {
        final target = boundedImageDecodeSize(size);
        expect(target.width, lessThanOrEqualTo(4096));
        expect(target.height, lessThanOrEqualTo(4096));
        expect(
          target.width * target.height,
          lessThanOrEqualTo(8 * 1024 * 1024),
        );
      }
      expect(await imageDecodeSize(png), const Size(400, 220));
      expect(await imageDecodeSize(Uint8List(0)), isNull);
      expect(await imageDecodeSize(Uint8List.fromList([1, 2, 3])), isNull);
      expect(await imageDecodeSize(Uint8List(20 * 1024 * 1024 + 1)), isNull);
    },
  );
  for (final setup in [
    (size: const Size(320, 740), paged: true, source: false),
    (size: const Size(402, 874), paged: true, source: false),
    (size: const Size(1194, 834), paged: true, source: false),
    (size: const Size(402, 874), paged: false, source: false),
    (size: const Size(402, 874), paged: true, source: true),
  ]) {
    testWidgets('image opens, zooms, returns without moving reader $setup', (
      t,
    ) async {
      t.view.physicalSize = setup.size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      final db = ReadingDatabase(NativeDatabase.memory());
      final book = (await t.runAsync(() async {
        final id = await db.addBook(
          'Image book',
          BookContent(
            [
              const BookBlock('Picture caption.', image: 'picture.png'),
              const BookBlock('A paragraph after the picture.'),
            ],
            assets: {'picture.png': png},
            supplementaryDocuments: const {
              'notes': [BookBlock('Picture caption.', image: 'picture.png')],
            },
          ),
        );
        return db.book(id);
      }))!;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryProvider.overrideWith((_) async => _Dictionary()),
          ],
          child: MaterialApp(
            home: setup.source
                ? ReaderPage.source(
                    book: book,
                    defaultStyle: ReaderStyle(paged: setup.paged),
                    target: const BookPosition(0, document: 'notes'),
                    anchor: const PageAnchor(
                      BookPosition(0, document: 'notes'),
                      part: PagePart.image,
                    ),
                  )
                : ReaderPage(
                    book: book,
                    defaultStyle: ReaderStyle(paged: setup.paged),
                  ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pumpAndSettle();
      }

      await settle();
      final before = (await t.runAsync(() => db.book(book.id)))!;
      final anchor = setup.paged
          ? t.state<PagedReaderState>(find.byType(PagedReader)).anchor.encode()
          : null;
      final caption = find.byWidgetPredicate(
        (w) => w is ReaderParagraph && w.text == 'Picture caption.',
      );
      final rich = find
          .descendant(of: caption.first, matching: find.byType(RichText))
          .first;
      final render = t.renderObject<RenderParagraph>(rich);
      final box = render
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 7),
          )
          .first
          .toRect();
      await t.tapAt(render.localToGlobal(box.center));
      await settle();
      expect(find.byType(WordBubble), findsOneWidget);
      final imagePoint =
          t.getTopLeft(find.byKey(const ValueKey('reader-image-0'))) +
          const Offset(5, 5);
      await t.tapAt(imagePoint);
      await settle();
      expect(find.byType(WordBubble), findsNothing);
      expect(find.byType(ReaderImageViewer), findsNothing);
      await t.tap(find.byKey(const ValueKey('reader-image-0')));
      await settle();
      expect(find.byType(ReaderImageViewer), findsOneWidget);
      final interactive = t.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      await t.tap(find.byTooltip('放大'));
      await t.pump();
      expect(
        interactive.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await t.drag(find.byType(InteractiveViewer), const Offset(-30, 20));
      await t.pump();
      await t.tap(find.byTooltip('还原图片'));
      await t.pump();
      expect(
        interactive.transformationController!.value.getMaxScaleOnAxis(),
        1,
      );
      final center = t.getCenter(find.byType(InteractiveViewer));
      await t.tapAt(center);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(center);
      await t.pumpAndSettle();
      expect(
        interactive.transformationController!.value.getMaxScaleOnAxis(),
        closeTo(2.5, .01),
      );
      await t.tap(find.byTooltip('还原图片'));
      await t.pump();
      final left = await t.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final right = await t.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await t.pump();
      await left.moveTo(center - const Offset(80, 0));
      await right.moveTo(center + const Offset(80, 0));
      await t.pump();
      await left.moveTo(center - const Offset(100, 0));
      await right.moveTo(center + const Offset(100, 0));
      await t.pump();
      expect(
        interactive.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await left.up();
      await right.up();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('close-image')));
      await settle();
      expect(find.byType(ReaderImageViewer), findsNothing);
      if (setup.paged) {
        expect(
          t.state<PagedReaderState>(find.byType(PagedReader)).anchor.encode(),
          anchor,
        );
      }
      final after = (await t.runAsync(() => db.book(book.id)))!;
      expect(after.position, before.position);
      expect(after.location, before.location);
      // System Back closes only the viewer, including rapid repeated taps.
      final point = t.getCenter(find.byKey(const ValueKey('reader-image-0')));
      await t.tapAt(point);
      await t.tapAt(point);
      await settle();
      await t.binding.handlePopRoute();
      await settle();
      expect(find.byType(ReaderImageViewer), findsNothing);
      expect(find.byType(ReaderPage), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(db.close);
    });
  }
  testWidgets('invalid image has a dismissible error state', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReaderImageViewer(
                  bytes: Uint8List(0),
                  description: '',
                  palette: ReaderPalette.palettes[ReaderTheme.white]!,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(find.text('图片无法显示'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('close-image')));
    await t.pumpAndSettle();
    expect(find.byType(ReaderImageViewer), findsNothing);
  });
}

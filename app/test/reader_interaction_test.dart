import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  testWidgets(
    'blank reader margins toggle immersive controls before and after settings',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      final database = ReadingDatabase(NativeDatabase.memory());
      final dictionary = SqliteDictionary.open(
        'assets/dictionaries/ecdict.sqlite',
      );
      addTearDown(dictionary.close);
      final book = Book(
        id: 'test',
        title: 'Gesture test',
        content: TxtParser().parseText(
          'Chapter 1\n${List.filled(30, 'Tomorrow is another day. Reading is a quiet pleasure.').join('\n')}',
        ),
        createdAt: 0,
        updatedAt: 0,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            dictionaryProvider.overrideWith((_) async => dictionary),
          ],
          child: MaterialApp(
            theme: const ReadingApp().theme(Brightness.light),
            home: ReaderPage(book: book, defaultStyle: const ReaderStyle()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rich = find.descendant(
        of: find.byKey(const ValueKey('paragraph-1')),
        matching: find.byType(RichText),
      );
      final render = tester.renderObject<RenderParagraph>(rich);
      final wordBox = render
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 8),
          )
          .first
          .toRect();
      await tester.tapAt(render.localToGlobal(wordBox.center));
      await tester.pumpAndSettle();
      expect(find.text('明天；未来'), findsOneWidget);
      await tester.tap(find.byType(WordBubble));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭释义'));
      await tester.pumpAndSettle();
      final press = await tester.startGesture(
        render.localToGlobal(wordBox.center),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('选中的句子'), findsNothing);
      await press.up();
      await tester.pumpAndSettle();
      expect(find.text('选中的句子'), findsOneWidget);
      await tester.tap(find.text('复制句子'));
      await tester.pumpAndSettle();
      final area = tester.getRect(find.byKey(const ValueKey('reader-text')));
      final margin = Offset(area.right - 12, area.center.dy);
      await tester.tapAt(margin);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
      await tester.tapAt(margin);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reader-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粗体'));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('size'));
      await tester.tapAt(tester.getCenter(slider) + const Offset(35, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
      await tester.tapAt(margin);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(database.close);
    },
  );
}

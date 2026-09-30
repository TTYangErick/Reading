import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'paste → real offline lookup → live settings → progress → restart → shelf management',
    (tester) async {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/reading-integration-${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      var database = ReadingDatabase(NativeDatabase(file));
      var container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      Future<void> pump() async {
        await tester.pumpAndSettle(const Duration(milliseconds: 150));
      }

      Future<void> tap(Finder finder) async {
        await tester.tap(finder);
        await pump();
      }

      Future<void> mount() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ReadingApp(),
          ),
        );
        for (
          int i = 0;
          i < 100 && find.byKey(const ValueKey('add-book')).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pump();
      }

      await mount();
      final dictionary = await container.read(dictionaryProvider.future);
      final times = <int>[];
      for (int i = 0; i < 1000; i++) {
        final clock = Stopwatch()..start();
        dictionary.lookup(
          ['went', 'tomorrow', 'reading', 'studies', 'children'][i % 5],
        );
        times.add(clock.elapsedMicroseconds);
      }
      times.sort();
      debugPrint(
        'ECDICT ${Platform.operatingSystem} simulator lookup p50=${times[500]}µs p95=${times[950]}µs max=${times.last}µs',
      );
      await tap(find.byKey(const ValueKey('add-book')));
      await tap(find.text('粘贴文本'));
      await tester.enterText(find.byKey(const ValueKey('paste-title')), '验收文本');
      final paragraphs = [
        'Chapter 1',
        'Tomorrow is another day. The children went to school.',
        ...List.generate(
          50,
          (i) =>
              'This is paragraph ${i + 1}. Reading a good book brings a little more light into the world. Take your time, and enjoy every word.',
        ),
        'Chapter 2',
        'A new beginning.',
      ];
      await tester.enterText(
        find.byKey(const ValueKey('paste-body')),
        paragraphs.join('\n\n'),
      );
      await tap(find.byKey(const ValueKey('save-paste')));
      expect(find.byType(ReaderPage), findsOneWidget);
      final id = (await database.books()).single.id;
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
      await pump();
      expect(find.byType(WordBubble), findsOneWidget);
      expect(find.text('明天；未来'), findsOneWidget);
      await tap(find.byType(WordBubble));
      expect(find.text('ECDICT · 离线'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      await tap(find.byTooltip('关闭释义'));
      await tester.longPressAt(render.localToGlobal(wordBox.center));
      await pump();
      expect(find.text('选中的句子'), findsOneWidget);
      expect(find.text('Tomorrow is another day.'), findsOneWidget);
      await tap(find.text('复制句子'));
      await tap(find.byKey(const ValueKey('reader-settings')));
      await tap(find.text('仅应用于这本书'));
      await tap(find.text('粗体'));
      final slider = find.byKey(const ValueKey('size'));
      await tester.tapAt(tester.getCenter(slider) + const Offset(35, 0));
      await pump();
      await tap(find.byTooltip('关闭设置'));
      expect(ReaderStyle.decode((await database.book(id))!.style).bold, isTrue);
      expect(
        ReaderStyle.decode((await database.book(id))!.style).size,
        isNot(19),
      );
      // Blank margins toggle both the reading toolbar and platform immersive mode.
      final readerArea = tester.getRect(
        find.byKey(const ValueKey('reader-text')),
      );
      final margin = Offset(readerArea.right - 12, readerArea.center.dy);
      debugPrint('Reader area $readerArea, tap $margin, bubble=${find.byType(WordBubble).evaluate().length}');
      await tester.tapAt(margin);
      await pump();
      expect(find.byKey(const ValueKey('reader-settings')), findsNothing);
      await tester.tapAt(margin);
      await pump();
      expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
      final progressSlider = find.byKey(const ValueKey('reading-progress'));
      await tester.tapAt(tester.getCenter(progressSlider));
      await pump();
      await tester.pump(const Duration(milliseconds: 600));
      debugPrint(
        'Progress UI: ${tester.widget<Text>(find.byKey(const ValueKey('progress-label'))).data}',
      );
      for (int i = 0; i < 20 && (await database.book(id))!.position == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      final savedPosition = (await database.book(id))!.position;
      expect(savedPosition, greaterThan(15));
      await tap(find.byKey(const ValueKey('back-library')));
      expect(find.text('书架'), findsOneWidget);
      // Dispose the complete app and SQLite connection, then recreate both from disk.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump();
      container.dispose();
      await database.close();
      database = ReadingDatabase(NativeDatabase(file));
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      await mount();
      expect((await database.book(id))!.position, savedPosition);
      await tap(find.textContaining('继续阅读 ·'));
      expect(
        find.text('$savedPosition / ${paragraphs.length} 段'),
        findsNothing,
      );
      expect(
        find.text('${savedPosition + 1} / ${paragraphs.length} 段'),
        findsOneWidget,
      );
      final paragraphWidget = tester.widget<ReaderParagraph>(
        find.byType(ReaderParagraph).first,
      );
      expect(paragraphWidget.style.fontWeight, FontWeight.w700);
      await tap(find.byKey(const ValueKey('back-library')));
      await tap(find.byTooltip('管理 验收文本'));
      await tap(find.text('修改书名'));
      await tester.enterText(
        find.byKey(const ValueKey('rename-title')),
        'Reading 验收通过',
      );
      await tap(find.text('保存'));
      await tester.enterText(
        find.byKey(const ValueKey('search-books')),
        '找不到的书',
      );
      await pump();
      expect(find.text('没有找到这本书'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('search-books')),
        'Reading',
      );
      await pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await pump();
      await tester.ensureVisible(find.byTooltip('管理 Reading 验收通过'));
      await pump();
      await tap(find.byTooltip('管理 Reading 验收通过'));
      await tap(find.text('删除'));
      await tap(find.widgetWithText(TextButton, '删除'));
      expect(await database.books(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await pump();
      container.dispose();
      await database.close();
      await file.delete();
      expect(tester.takeException(), isNull);
    },
  );
}

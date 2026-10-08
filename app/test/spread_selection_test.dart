import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/selection.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/text/language.dart';
import 'package:reading_app/translate/sentence_sheet.dart';
import 'package:reading_app/translate/translator.dart';

import 'selection_test.dart'
    show begin, point, renderFor, highlight, RecordingTranslator;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Literata',
    )..addFont(rootBundle.load('assets/fonts/Literata.ttf'))).load();
  });

  Widget paragraph(
    int block,
    String text, {
    int start = 0,
    int? end,
    bool local = false,
    ValueChanged<WordRange>? onLocal,
    ValueChanged<int>? onSentence,
  }) => ReaderParagraph(
    key: ValueKey('text-$block'),
    sourceBlock: local ? null : block,
    text: text,
    visibleStart: start,
    visibleEnd: end,
    language: EnglishLanguage(),
    style: const TextStyle(fontFamily: 'Literata', fontSize: 22),
    align: TextAlign.start,
    selection: null,
    onWord: (_, _) {},
    onSentence: onSentence ?? (_) {},
    onSelection: onLocal ?? (_) {},
    onBlank: () {},
  );

  Future<void> mount(
    WidgetTester t,
    List<BookBlock> blocks,
    List<Widget> children,
    List<String> results,
  ) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReadingSelectionScope(
          blocks: blocks,
          onSelected: results.add,
          child: Center(
            child: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: child,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'forward/backward across three paragraphs preserves Unicode and source order',
    (t) async {
      const texts = [
        'One quiet morning.',
        'A café and e\u0301 👩‍👩‍👦.',
        'Readers enjoy beautiful books.',
      ];
      final results = <String>[];
      await mount(t, texts.map(BookBlock.new).toList(), [
        for (var i = 0; i < texts.length; i++) paragraph(i, texts[i]),
      ], results);
      final first = renderFor(t, find.byKey(const ValueKey('text-0'))),
          middle = renderFor(t, find.byKey(const ValueKey('text-1'))),
          last = renderFor(t, find.byKey(const ValueKey('text-2')));
      final from = point(first, texts[0], 'quiet'),
          to = point(last, texts[2], 'beautiful');
      var press = await begin(t, from);
      await press.moveTo(to);
      await t.pump();
      expect(highlight(first), 'quiet morning.');
      expect(highlight(middle), texts[1]);
      expect(highlight(last), 'Readers enjoy beautiful');
      expect(results, isEmpty);
      await press.up();
      await t.pump();
      const expected =
          'quiet morning.\n\nA café and e\u0301 👩‍👩‍👦.\n\nReaders enjoy beautiful';
      expect(results, [expected]);
      expect(highlight(middle), isEmpty);
      press = await begin(t, to);
      await press.moveTo(from);
      await t.pump();
      await press.up();
      await t.pump();
      expect(results, [expected, expected]);
    },
  );

  testWidgets(
    'cancel, resize and removing a selected region never submit stale text',
    (t) async {
      const texts = ['One quiet morning.', 'Readers enjoy beautiful books.'];
      final results = <String>[];
      Future<void> show({bool remove = false}) => mount(
        t,
        texts.map(BookBlock.new).toList(),
        [paragraph(0, texts[0]), if (!remove) paragraph(1, texts[1])],
        results,
      );
      await show();
      for (final action in ['cancel', 'resize', 'remove']) {
        final first = renderFor(t, find.byKey(const ValueKey('text-0'))),
            last = renderFor(t, find.byKey(const ValueKey('text-1')));
        final press = await begin(t, point(first, texts[0], 'quiet'));
        await press.moveTo(point(last, texts[1], 'beautiful'));
        await t.pump();
        if (action == 'cancel') {
          await press.cancel();
        } else {
          if (action == 'resize') {
            t.view.physicalSize = const Size(780, 600);
            addTearDown(t.view.resetPhysicalSize);
            await t.pump();
          } else {
            await show(remove: true);
          }
          await press.up();
        }
        await t.pumpAndSettle();
        expect(results, isEmpty);
        expect(highlight(first), isEmpty);
      }
    },
  );

  for (final media in [
    const BookBlock('Caption alpha beta.', image: 'pic'),
    const BookBlock(
      '',
      rows: [
        ['Cell alpha beta.'],
      ],
    ),
  ]) {
    testWidgets(
      'media barrier and local text selection remain separate ${media.image}',
      (t) async {
        const firstText = 'One quiet morning.',
            lastText = 'Readers enjoy beautiful books.';
        final results = <String>[], locals = <WordRange>[];
        final local = media.image != null
            ? media.text
            : media.rows!.first.first;
        await mount(
          t,
          [const BookBlock(firstText), media, const BookBlock(lastText)],
          [
            paragraph(0, firstText),
            paragraph(1, local, local: true, onLocal: locals.add),
            paragraph(2, lastText),
          ],
          results,
        );
        final first = renderFor(t, find.byKey(const ValueKey('text-0'))),
            last = renderFor(t, find.byKey(const ValueKey('text-2')));
        final press = await begin(t, point(first, firstText, 'quiet'));
        await press.moveTo(point(first, firstText, 'morning'));
        await t.pump();
        await press.moveTo(point(last, lastText, 'beautiful'));
        await t.pump();
        await press.up();
        await t.pump();
        expect(results, ['quiet morning']);
        final localRender = renderFor(t, find.byKey(const ValueKey('text-1')));
        final localPress = await begin(t, point(localRender, local, 'alpha'));
        await localPress.moveTo(point(localRender, local, 'beta'));
        await t.pump();
        await localPress.up();
        await t.pump();
        expect(locals.single.text, 'alpha beta');
        expect(results, hasLength(1));
      },
    );
  }

  testWidgets(
    'unrendered source gap and another document cannot expand selection',
    (t) async {
      const text = 'Alpha beta hidden words gamma delta.';
      final results = <String>[], other = <String>[];
      await mount(
        t,
        const [BookBlock(text)],
        [
          paragraph(0, text, end: 10),
          // Distinct key for a second clipped fragment of the same source block.
          KeyedSubtree(
            key: const ValueKey('second'),
            child: paragraph(0, text, start: text.indexOf('gamma')),
          ),
          ReadingSelectionScope(
            blocks: const [BookBlock('Other text.')],
            onSelected: other.add,
            child: paragraph(0, 'Other text.'),
          ),
        ],
        results,
      );
      final all = find.byType(ReaderParagraph);
      final first = renderFor(t, all.at(0)),
          last = renderFor(t, all.at(1)),
          isolated = renderFor(t, all.at(2));
      final press = await begin(t, point(first, text, 'Alpha'));
      await press.moveTo(point(first, text, 'beta'));
      await t.pump();
      await press.moveTo(point(last, text, 'gamma'));
      await t.pump();
      await press.moveTo(point(isolated, 'Other text.', 'Other'));
      await t.pump();
      await press.up();
      await t.pump();
      expect(results, ['Alpha beta']);
      expect(other, isEmpty);
    },
  );

  testWidgets(
    'one long paragraph spans both visible pages without duplicates, hidden text or turning',
    (t) async {
      t.view.physicalSize = const Size(1194, 834);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final text = List.filled(
        150,
        'Alpha beta gamma delta epsilon.',
      ).join('\n');
      final blocks = [BookBlock(text)],
          results = <String>[],
          positions = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadingSelectionScope(
              blocks: blocks,
              onSelected: results.add,
              child: PagedReader(
                content: BookContent(blocks),
                style: const ReaderStyle(font: 'Literata'),
                initialAnchor: const PageAnchor(BookPosition(0)),
                loadImage: (_) async => null,
                onPosition: (a, _, _) => positions.add(a.encode()),
                onWord: (_, _, _, _) {},
                onSentence: (_, _) {},
                onLink: (_) {},
                onBlank: () {},
                onTurn: () {},
                onScrollFallback: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final paras = find.byType(ReaderParagraph);
      expect(paras, findsNWidgets(2));
      final left = renderFor(t, paras.first),
          right = renderFor(t, paras.last),
          region = t.widget<ReaderParagraph>(paras.last);
      final word = right.getWordBoundary(
        TextPosition(offset: region.visibleStart),
      );
      final box = right
          .getBoxesForSelection(
            TextSelection(baseOffset: word.start, extentOffset: word.end),
          )
          .first;
      final from = point(left, text, 'Alpha'),
          to = right.localToGlobal(box.toRect().center),
          before = List.of(positions);
      for (final backwards in [false, true]) {
        final press = await begin(t, backwards ? to : from);
        await press.moveTo(backwards ? from : to);
        await t.pump();
        expect(highlight(left), isNotEmpty);
        expect(highlight(right), isNotEmpty);
        await press.moveTo(const Offset(597, 200));
        await t.pump();
        await press.up();
        await t.pump();
        expect(results.last, text.substring(0, word.end));
        expect(positions, before);
      }
    },
  );

  testWidgets('scroll update cancels a held cross-paragraph selection', (
    t,
  ) async {
    const texts = ['One quiet morning.', 'Readers enjoy beautiful books.'];
    final results = <String>[], controller = ScrollController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingSelectionScope(
            blocks: texts.map(BookBlock.new).toList(),
            onSelected: results.add,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  paragraph(0, texts[0]),
                  paragraph(1, texts[1]),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final first = renderFor(t, find.byKey(const ValueKey('text-0'))),
        last = renderFor(t, find.byKey(const ValueKey('text-1')));
    final press = await begin(t, point(first, texts[0], 'quiet'));
    await press.moveTo(point(last, texts[1], 'beautiful'));
    await t.pump();
    expect(highlight(last), isNotEmpty);
    controller.jumpTo(24);
    await t.pump();
    await press.up();
    await t.pump();
    expect(results, isEmpty);
    expect(highlight(last), isEmpty);
  });

  for (final mode in [
    (paged: false, note: false),
    (paged: true, note: false),
    (paged: true, note: true),
  ]) {
    final paged = mode.paged;
    testWidgets(
      'reader translates/copies cross-paragraph text and retains progress $mode',
      (t) async {
        t.view.physicalSize = const Size(402, 874);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        t.binding.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
        String? copied;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final db = ReadingDatabase(NativeDatabase.memory()),
            native = RecordingTranslator();
        addTearDown(db.close);
        const first = 'One quiet morning.',
            second = 'Readers enjoy beautiful books.';
        final id = await db.addBook(
          'Cross selection',
          mode.note
              ? const BookContent(
                  [BookBlock('Body must remain unchanged.')],
                  supplementaryDocuments: {
                    'notes': [BookBlock(first), BookBlock(second)],
                  },
                )
              : const BookContent([BookBlock(first), BookBlock(second)]),
        );
        final book = (await db.book(id))!;
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              translatorProvider.overrideWithValue(
                CachedTranslator(native, db),
              ),
            ],
            child: MaterialApp(
              theme: const ReadingApp().theme(Brightness.light),
              home: mode.note
                  ? ReaderPage.source(
                      book: book,
                      defaultStyle: const ReaderStyle(
                        font: 'Literata',
                        size: 20,
                      ),
                      target: const BookPosition(0, document: 'notes'),
                      anchor: const PageAnchor(
                        BookPosition(0, document: 'notes'),
                      ),
                    )
                  : ReaderPage(
                      book: book,
                      defaultStyle: ReaderStyle(
                        font: 'Literata',
                        paged: paged,
                        size: 20,
                      ),
                    ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.pump(const Duration(seconds: 1));
        final before =
            (await db.customSelect('SELECT * FROM books').getSingle()).data;
        final paras = find.byType(ReaderParagraph);
        final press = await begin(
          t,
          point(renderFor(t, paras.first), first, 'quiet'),
        );
        await press.moveTo(
          point(renderFor(t, paras.last), second, 'beautiful'),
        );
        await t.pump();
        expect(native.calls, isEmpty);
        await press.up();
        await t.pumpAndSettle();
        const expected = 'quiet morning.\n\nReaders enjoy beautiful';
        expect(
          t.widget<SentenceSheet>(find.byType(SentenceSheet)).sentence,
          expected,
        );
        expect(native.calls, [expected]);
        await t.tap(find.text('复制文字'));
        await t.pumpAndSettle();
        expect(copied, expected);
        expect(
          (await db.customSelect('SELECT * FROM books').getSingle()).data,
          before,
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(
        paged ? TargetPlatform.android : TargetPlatform.iOS,
      ),
    );
  }
}

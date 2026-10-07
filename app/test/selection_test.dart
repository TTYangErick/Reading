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
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/text/language.dart';
import 'package:reading_app/translate/sentence_sheet.dart';
import 'package:reading_app/translate/translator.dart';

class RecordingTranslator implements Translator {
  final calls = <String>[];
  @override
  String get engine => 'test-selection';
  @override
  Future<void> prepare(String from, String to) async {}
  @override
  Future<TranslationStatus> status(String from, String to) async =>
      TranslationStatus.ready;
  @override
  Future<String> translate(String text, String from, String to) async {
    calls.add(text);
    return '译文：$text';
  }
}

RenderParagraph renderFor(WidgetTester t, Finder paragraph) =>
    t.renderObject<RenderParagraph>(
      find.descendant(of: paragraph, matching: find.byType(RichText)).first,
    );
Offset point(RenderParagraph r, String text, String word) {
  final at = text.indexOf(word);
  return r.localToGlobal(
    r
        .getBoxesForSelection(
          TextSelection(baseOffset: at, extentOffset: at + word.length),
        )
        .first
        .toRect()
        .center,
  );
}

String highlight(RenderParagraph r) {
  final s = r.text as TextSpan;
  return (s.children ?? [])
      .whereType<TextSpan>()
      .where((s) => s.style?.backgroundColor != null)
      .map((s) => s.text ?? '')
      .join();
}

Future<TestGesture> begin(WidgetTester t, Offset at) async {
  final p = await t.startGesture(at);
  await t.pump(const Duration(milliseconds: 600));
  return p;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
  });
  testWidgets(
    'live forward/backward multiline selection, no-drag sentence and pointer cancel',
    (t) async {
      const text =
          'One quiet morning, readers enjoy a beautiful book. Another sentence.';
      final results = <WordRange>[], sentences = <int>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: ReaderParagraph(
                  text: text,
                  language: EnglishLanguage(),
                  style: const TextStyle(fontFamily: 'Literata', fontSize: 22),
                  align: TextAlign.start,
                  selection: null,
                  onWord: (_, _) {},
                  onSentence: sentences.add,
                  onSelection: results.add,
                  onBlank: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final r = renderFor(t, find.byType(ReaderParagraph));
      var p = await begin(t, point(r, text, 'quiet'));
      expect(highlight(r), contains('One quiet morning'));
      expect(results, isEmpty);
      await p.moveTo(point(r, text, 'beautiful'));
      await t.pump();
      expect(highlight(r), 'quiet morning, readers enjoy a beautiful');
      expect(results, isEmpty);
      await p.up();
      await t.pump();
      expect(results.single.text, 'quiet morning, readers enjoy a beautiful');
      expect(highlight(r), '');
      p = await begin(t, point(r, text, 'beautiful'));
      await p.moveTo(point(r, text, 'quiet'));
      await t.pump();
      await p.up();
      await t.pump();
      expect(results.last.text, results.first.text);
      p = await begin(t, point(r, text, 'quiet'));
      await p.up();
      await t.pump();
      expect(sentences, hasLength(1));
      p = await begin(t, point(r, text, 'quiet'));
      await p.moveTo(point(r, text, 'beautiful'));
      await t.pump();
      await p.cancel();
      await t.pump();
      expect(results, hasLength(2));
      expect(highlight(r), '');
    },
  );
  testWidgets(
    'Unicode source offsets, clipped range, outside target and resize cancellation',
    (t) async {
      const text =
          'Hidden text. café e\u0301 👩‍👩‍👦 alpha beta. Hidden ending.';
      final result = <WordRange>[];
      final start = text.indexOf('café'), end = text.indexOf('. Hidden');
      Future<void> show(double size) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: ReaderParagraph(
                  text: text,
                  language: EnglishLanguage(),
                  style: TextStyle(fontFamily: 'Literata', fontSize: size),
                  align: TextAlign.start,
                  selection: null,
                  visibleStart: start,
                  visibleEnd: end,
                  onWord: (_, _) {},
                  onSentence: (_) {},
                  onSelection: result.add,
                  onBlank: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await show(18);
      await t.pump();
      var r = renderFor(t, find.byType(ReaderParagraph));
      var p = await begin(t, point(r, text, 'café'));
      await p.moveTo(point(r, text, 'alpha'));
      await t.pump();
      expect(highlight(r), 'café e\u0301 👩‍👩‍👦 alpha');
      await p.moveTo(const Offset(799, 590));
      await t.pump();
      await p.up();
      await t.pump();
      expect(result.single.text, 'café e\u0301 👩‍👩‍👦 alpha');
      expect(result.single.start, start);
      expect(
        text.substring(result.single.start, result.single.end),
        result.single.text,
      );
      p = await begin(t, point(r, text, 'alpha'));
      await p.moveTo(point(r, text, 'Hidden'));
      await t.pump();
      await p.up();
      await t.pump();
      expect(result.last.start, start);
      p = await begin(t, point(r, text, 'café'));
      await p.moveTo(point(r, text, 'alpha'));
      await t.pump();
      await show(20);
      await t.pump();
      await p.up();
      await t.pump();
      expect(result, hasLength(2));
    },
  );

  testWidgets(
    'double-page clipping and gutter never select hidden text or turn a page',
    (t) async {
      t.view.physicalSize = const Size(1194, 834);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final text = List.filled(
        150,
        'Alpha beta gamma delta epsilon.',
      ).join('\n');
      final results = <WordRange>[];
      final positions = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedReader(
              content: BookContent([BookBlock(text)]),
              style: const ReaderStyle(font: 'Literata'),
              initialAnchor: const PageAnchor(BookPosition(0)),
              loadImage: (_) async => null,
              onPosition: (a, p, c) => positions.add(a.encode()),
              onWord: (_, _, _, _) {},
              onSentence: (_, _) {},
              onLink: (_) {},
              onSelection: results.add,
              onBlank: () {},
              onTurn: () {},
              onScrollFallback: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final paragraphs = find.byType(ReaderParagraph);
      expect(paragraphs, findsNWidgets(2));
      final left = renderFor(t, paragraphs.first),
          right = renderFor(t, paragraphs.last);
      final first = t.widget<ReaderParagraph>(paragraphs.first),
          second = t.widget<ReaderParagraph>(paragraphs.last);
      expect(first.visibleEnd!, lessThan(text.length));
      final before = List.of(positions);
      final press = await begin(t, point(left, text, 'Alpha'));
      await press.moveTo(point(left, text, 'gamma'));
      await t.pump();
      expect(highlight(left), 'Alpha beta gamma');
      final rightBox = right
          .getBoxesForSelection(
            TextSelection(
              baseOffset: second.visibleStart,
              extentOffset: second.visibleStart + 4,
            ),
          )
          .first
          .toRect();
      await press.moveTo(right.localToGlobal(rightBox.center));
      await t.pump();
      expect(highlight(left), 'Alpha beta gamma');
      await press.moveTo(const Offset(597, 200));
      await t.pump();
      await press.up();
      await t.pump();
      expect(results.single.text, 'Alpha beta gamma');
      expect(results.single.end, lessThan(first.visibleEnd!));
      expect(positions, before);
    },
  );

  testWidgets(
    'supplementary note, caption and table cell keep their own source ranges',
    (t) async {
      t.view.physicalSize = const Size(1194, 834);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final results = <WordRange>[];
      const texts = [
        'Note alpha beta gamma.',
        'Caption alpha beta gamma.',
        'Cell alpha beta gamma.',
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedReader(
              content: const BookContent(
                [BookBlock('Body unchanged.')],
                supplementaryDocuments: {
                  'notes': [
                    BookBlock('Note alpha beta gamma.'),
                    BookBlock('Caption alpha beta gamma.', image: 'pic'),
                    BookBlock(
                      '',
                      rows: [
                        [
                          'Cell alpha beta gamma.',
                          'Other cell remains unchanged.',
                        ],
                      ],
                    ),
                  ],
                },
              ),
              document: 'notes',
              style: const ReaderStyle(font: 'Literata'),
              initialAnchor: const PageAnchor(
                BookPosition(0, document: 'notes'),
              ),
              loadImage: (_) async => null,
              onPosition: (_, _, _) {},
              onWord: (_, _, _, _) {},
              onSentence: (_, _) {},
              onLink: (_) {},
              onSelection: results.add,
              onBlank: () {},
              onTurn: () {},
              onScrollFallback: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final text in texts) {
        final finder = find.byWidgetPredicate(
          (w) => w is ReaderParagraph && w.text == text,
        );
        expect(finder, findsOneWidget);
        final r = renderFor(t, finder),
            press = await begin(t, point(renderFor(t, finder), text, 'alpha'));
        await press.moveTo(point(r, text, 'gamma'));
        await t.pump();
        await press.up();
        await t.pump();
        expect(results.last.text, 'alpha beta gamma');
        expect(
          text.substring(results.last.start, results.last.end),
          results.last.text,
        );
      }
      expect(results, hasLength(3));
    },
  );

  for (final setting in [
    (const Size(320, 740), true),
    (const Size(402, 874), true),
    (const Size(1194, 834), true),
    (const Size(402, 874), false),
  ]) {
    testWidgets(
      'reader translates and copies actual phrase, retains progress ${setting.$1} paged=${setting.$2}',
      (t) async {
        t.view.physicalSize = setting.$1;
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
        const text =
            'One quiet morning, readers enjoy a beautiful book. Another sentence.';
        final id = await db.addBook(
          'Selection',
          BookContent(List.generate(30, (_) => const BookBlock(text))),
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
              home: ReaderPage(
                book: book,
                defaultStyle: ReaderStyle(
                  font: 'Literata',
                  paged: setting.$2,
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
        final para = find.byType(ReaderParagraph).first, r = renderFor(t, para);
        final p = await begin(t, point(r, text, 'quiet'));
        await p.moveTo(point(r, text, 'beautiful'));
        await t.pump();
        expect(native.calls, isEmpty);
        expect(find.byType(SentenceSheet), findsNothing);
        await p.up();
        await t.pumpAndSettle();
        final sheet = t.widget<SentenceSheet>(find.byType(SentenceSheet));
        expect(sheet.adjusted, true);
        expect(sheet.sentence, 'quiet morning, readers enjoy a beautiful');
        expect(native.calls, [sheet.sentence]);
        expect(find.text('复制文字'), findsOneWidget);
        await t.tap(find.text('复制文字'));
        await t.pumpAndSettle();
        expect(copied, sheet.sentence);
        expect(find.byType(SentenceSheet), findsNothing);
        expect(
          (await db.customSelect('SELECT * FROM books').getSingle()).data,
          before,
        );
        final next = await begin(t, point(r, text, 'quiet'));
        await next.up();
        await t.pumpAndSettle();
        expect(
          t.widget<SentenceSheet>(find.byType(SentenceSheet)).adjusted,
          false,
        );
        expect(find.text('复制句子'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(
        setting.$1.width == 320 ? TargetPlatform.android : TargetPlatform.iOS,
      ),
    );
  }
}

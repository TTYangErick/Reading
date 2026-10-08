import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/orientation/orientation.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/settings.dart';
import 'package:reading_app/reader/style.dart';

import 'epub_links_test.dart' show linkedBook, supplementaryBook, notePage;

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

RenderParagraph paragraph(WidgetTester tester, int block) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(ValueKey('paragraph-$block')),
        matching: find.byType(RichText),
      ),
    );

Offset textPoint(WidgetTester tester, int block, String text) {
  final render = paragraph(tester, block);
  final start = render.text.toPlainText().indexOf(text);
  expect(start, greaterThanOrEqualTo(0));
  final box = render
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + text.length),
      )
      .first;
  return render.localToGlobal(box.toRect().center);
}

Future<void> tapText(WidgetTester tester, int block, String text) async {
  await tester.tapAt(textPoint(tester, block, text));
  await tester.pumpAndSettle();
}

void main() {
  late ReadingDatabase database;
  late _Dictionary dictionary;
  late String bookId;
  var wakeCalls = 0;

  setUp(() {
    database = ReadingDatabase(NativeDatabase.memory());
    dictionary = _Dictionary();
    wakeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (message) async {
            wakeCalls++;
            return const StandardMessageCodec().encodeMessage([null]);
          },
        );
  });
  tearDown(() async => database.close());

  Future<void> mount(
    WidgetTester tester,
    BookContent content, {
    int position = 0,
    ReaderStyle style = const ReaderStyle(paged: false),
    ReadingOrientationSession? orientation,
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      bookId = await database.addBook('Link test', content);
      await database.savePosition(bookId, position);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          if (orientation != null)
            readingOrientationSessionProvider.overrideWithValue(orientation),
          dictionaryProvider.overrideWith((_) async => dictionary),
        ],
        child: MaterialApp(
          theme: const ReadingApp().theme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final book = (await database.book(bookId))!;
                  if (!context.mounted) return;
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ReaderPage(book: book, defaultStyle: style),
                    ),
                  );
                },
                child: const Text('Open book'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open book'));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  for (final version in [2, 3]) {
    testWidgets(
      'EPUB $version note tap, lookup, backlink, lifecycle and reopen preserve body',
      (tester) async {
        final content = EpubParser().parse(
          linkedBook(
            '${'<p>Opening</p>' * 8}<p>Tomorrow <a id="ref" epub:type="noteref" href="second.xhtml#n">[1]</a> after.</p>${'<p>Body text to scroll.</p>' * 40}',
            '<p id="n">Explanation <a href="first.xhtml#ref">Back</a></p>${'<p>Supplementary text.</p>' * 40}',
            version: version,
            nonLinear: true,
          ),
        );
        await mount(tester, content, position: 5);
        // Move the body a fraction of a paragraph, then record the exact viewport.
        await tester.drag(
          find.byKey(const ValueKey('reader-text')),
          const Offset(0, -25),
        );
        await tester.pumpAndSettle();
        final before = textPoint(tester, 8, '[1]');
        final savedBefore = (await database.book(bookId))!.position;
        expect(savedBefore, greaterThan(0));
        await tapText(tester, 8, 'Tomorrow');
        expect(dictionary.words, ['Tomorrow']);
        expect(find.byType(WordBubble), findsOneWidget);
        await tester.tap(find.byType(WordBubble));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭释义'));
        await tester.pumpAndSettle();
        await tapText(tester, 8, '[1]');
        expect(find.text('脚注'), findsOneWidget);
        expect(find.byType(WordBubble), findsNothing);
        expect(find.byKey(const ValueKey('reading-progress')), findsOneWidget);
        expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
        expect(find.byTooltip('目录'), findsOneWidget);
        expect(dictionary.words, ['Tomorrow']);
        final noteBeforeScope = textPoint(tester, 0, 'Explanation');
        await tester.tap(find.byKey(const ValueKey('reader-settings')));
        await tester.pumpAndSettle();
        tester.widget<ReaderSettings>(find.byType(ReaderSettings)).onPerBook!(
          true,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pumpAndSettle();
        expect(
          textPoint(tester, 0, 'Explanation').dy,
          closeTo(noteBeforeScope.dy, .1),
        );
        await tapText(tester, 0, 'Explanation');
        expect(dictionary.words.last, 'Explanation');
        await tester.tap(find.byType(WordBubble));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭释义'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('reader-text')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect((await database.book(bookId))!.position, savedBefore);
        await tester.tap(find.byTooltip('返回上一处'));
        await tester.pumpAndSettle();
        expect(textPoint(tester, 8, '[1]').dy, closeTo(before.dy, .1));
        // Unmarked EPUB 2 backlinks resolve to the source, not another stacked view.
        await tapText(tester, 8, '[1]');
        await tapText(tester, 0, 'Back');
        expect(find.byKey(const ValueKey('back-link')), findsNothing);
        expect(textPoint(tester, 8, '[1]').dy, closeTo(before.dy, .1));
        expect(wakeCalls, 1);
        await tester.tap(find.byTooltip('返回书架'));
        await tester.pumpAndSettle();
        expect((await database.book(bookId))!.position, savedBefore);
        await tester.tap(find.text('Open book'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('back-link')), findsNothing);
        expect(find.byKey(ValueKey('paragraph-$savedBefore')), findsOneWidget);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'body targets honor inline UTF-16 offsets and system back restores the source',
    (tester) async {
      final prefix = '😀 long paragraph before the target. ' * 80;
      final content = EpubParser().parse(
        linkedBook(
          '<p><a href="second.xhtml#inside">Target</a></p><p>After source</p>',
          '<p>$prefix<span id="inside">Destination</span> after target.</p>',
        ),
      );
      await mount(tester, content);
      final source = textPoint(tester, 0, 'Target');
      await tapText(tester, 0, 'Target');
      final destination = textPoint(tester, 2, 'Destination');
      expect(destination.dy, greaterThan(60));
      // Near the document end the scroll extent clamps; the target must still
      // be inside the visible viewport, not thousands of pixels below it.
      expect(destination.dy, lessThan(780));
      expect((await database.book(bookId))!.position, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(textPoint(tester, 0, 'Target').dy, closeTo(source.dy, .1));
      await unmount(tester);
    },
  );

  testWidgets(
    'nested notes return one level or close all, and retain theme and media',
    (tester) async {
      tester.view.display.size = const Size(402, 874);
      tester.view.display.devicePixelRatio = 1;
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.display.resetDevicePixelRatio);
      final orientations = <List<DeviceOrientation>>[];
      final orientation = ReadingOrientationSession(
        (value) async => orientations.add(value),
      );
      addTearDown(() async {
        orientation.dispose();
        await tester.pump();
      });
      await tester.runAsync(
        () => database.setSetting(readingOrientationKey, 'portrait'),
      );
      final content = EpubParser().parse(
        supplementaryBook('<p><a href="a.xhtml#n">Start</a></p>', {
          'a.xhtml': notePage(
            '<p id="n">First <a href="b.xhtml#n">Next</a></p><img src="../images/lesson%20image.png"/><table><tr><td>Cell</td></tr></table>',
          ),
          'b.xhtml': notePage(
            '<p id="n">Second <a href="a.xhtml#n">Cycle</a></p>',
          ),
        }),
      );
      const style = ReaderStyle(
        paged: false,
        theme: ReaderTheme.night,
        followSystem: false,
        size: 25,
      );
      await mount(tester, content, style: style, orientation: orientation);
      await tester.runAsync(
        () =>
            ProviderScope.containerOf(tester.element(find.byType(ReaderPage)))
                .read(readingOrientationProvider.future),
      );
      await tester.pumpAndSettle();
      expect(orientations.last, ReadingOrientation.portrait.orientations);
      await tapText(tester, 0, 'Start');
      expect(
        tester
            .widget<ReaderParagraph>(find.byKey(const ValueKey('paragraph-0')))
            .style
            .fontSize,
        25,
      );
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFF0F0F10),
      );
      for (var i = 0; i < 10 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      final notePoint = textPoint(tester, 0, 'Next');
      await tapText(tester, 0, 'Next');
      expect(paragraph(tester, 0).text.toPlainText(), 'Second Cycle');
      await tester.tap(find.byTooltip('返回上一处'));
      await tester.pumpAndSettle();
      expect(textPoint(tester, 0, 'Next').dy, closeTo(notePoint.dy, .1));
      expect(orientations.last, ReadingOrientation.portrait.orientations);
      await tapText(tester, 0, 'Next');
      await tester.tap(find.byTooltip('回到原阅读处'));
      await tester.pumpAndSettle();
      expect(paragraph(tester, 0).text.toPlainText(), 'Start');
      expect(wakeCalls, 1);
      expect((await database.book(bookId))!.position, 0);
      expect(orientations.last, ReadingOrientation.portrait.orientations);
      await unmount(tester);
      await orientation.pending;
      expect(orientations.last, isEmpty);
    },
  );

  testWidgets(
    'deep backlink returns to the matching source and rapid taps open once',
    (tester) async {
      final content = EpubParser().parse(
        supplementaryBook('<p><a id="root" href="a.xhtml#n">Start</a></p>', {
          'a.xhtml': notePage('<p id="n"><a href="b.xhtml#n">Next</a></p>'),
          'b.xhtml': notePage(
            '<p id="n"><a role="doc-backlink" href="first.xhtml#root">Return</a></p>',
          ),
        }),
      );
      await mount(tester, content);
      final source = textPoint(tester, 0, 'Start');
      await tester.tapAt(source);
      await tester.tapAt(source);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2));
      await tapText(tester, 0, 'Next');
      expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(3));
      await tapText(tester, 0, 'Return');
      expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
      expect(textPoint(tester, 0, 'Start').dy, closeTo(source.dy, .1));
      await unmount(tester);
    },
  );

  testWidgets('cyclic navigation is capped and close always reaches the body', (
    tester,
  ) async {
    const note = 'notes.xhtml';
    final content = BookContent(
      const [BookBlock('Start')],
      supplementaryDocuments: const {
        note: [BookBlock('Loop')],
      },
      links: const [
        BookLink(
          block: 0,
          start: 0,
          end: 5,
          href: note,
          kind: BookLinkKind.link,
          status: BookLinkStatus.resolved,
          target: BookPosition(0, document: note),
        ),
        BookLink(
          document: note,
          block: 0,
          start: 0,
          end: 4,
          href: '#inside',
          kind: BookLinkKind.link,
          status: BookLinkStatus.resolved,
          target: BookPosition(0, offset: 1, document: note),
        ),
      ],
    );
    await mount(tester, content);
    await tapText(tester, 0, 'Start');
    for (var i = 0; i < 16; i++) {
      await tapText(tester, 0, 'Loop');
    }
    expect(find.text('打开的链接较多，请先返回再继续。'), findsOneWidget);
    expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(17));
    await tester.tap(find.byTooltip('回到原阅读处'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
    expect(paragraph(tester, 0).text.toPlainText(), 'Start');
    expect((await database.book(bookId))!.position, 0);
    await unmount(tester);
  });

  testWidgets(
    'missing, unavailable, invalid, external and stale targets never navigate or look up words',
    (tester) async {
      const statuses = [
        BookLinkStatus.missingTarget,
        BookLinkStatus.unavailableDocument,
        BookLinkStatus.invalid,
        BookLinkStatus.external,
        BookLinkStatus.resolved,
      ];
      final content = BookContent(
        [for (var i = 0; i < statuses.length; i++) BookBlock('Link$i')],
        links: [
          for (var i = 0; i < statuses.length; i++)
            BookLink(
              block: i,
              start: 0,
              end: 5,
              href: 'javascript:alert(1)',
              kind: BookLinkKind.link,
              status: statuses[i],
              target: i == 4
                  ? const BookPosition(99, document: 'missing.xhtml')
                  : null,
            ),
        ],
      );
      await mount(tester, content);
      const messages = [
        '找不到这处引用的内容。',
        '这处引用的内容尚未载入。',
        '这处链接格式不受支持。',
        '这是书外链接，暂不打开。',
        '找不到这处引用的内容。',
      ];
      for (var i = 0; i < statuses.length; i++) {
        await tapText(tester, i, 'Link$i');
        expect(find.text(messages[i]), findsOneWidget);
        expect(find.byKey(const ValueKey('back-link')), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect(dictionary.words, isEmpty);
      expect((await database.book(bookId))!.position, 0);
      await unmount(tester);
    },
  );

  testWidgets(
    'wrapped links, punctuation, margins and long press keep distinct gestures',
    (tester) async {
      const label =
          'Very long linked text wrapping over several lines with a final marker [2]';
      final content = EpubParser().parse(
        linkedBook(
          '<p><a href="second.xhtml#n">$label</a> Ordinary.</p>',
          '<p id="n">Note</p>',
          nonLinear: true,
        ),
      );
      await mount(tester, content);
      final render = paragraph(tester, 0);
      expect(
        (render.text as TextSpan).children!
            .whereType<TextSpan>()
            .first
            .style!
            .decoration,
        TextDecoration.underline,
      );
      final press = await tester.startGesture(textPoint(tester, 0, 'Very'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('选中的句子'), findsNothing);
      await press.up();
      await tester.pumpAndSettle();
      expect(find.text('选中的句子'), findsOneWidget);
      expect(find.byKey(const ValueKey('back-link')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // The second/last line of a link must still hit its actual range.
      await tapText(tester, 0, '[2]');
      expect(find.byKey(const ValueKey('back-link')), findsOneWidget);
      await tester.tap(find.byTooltip('返回上一处'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('paragraph-0')));
      await tester.tapAt(Offset(rect.right - 2, rect.bottom - 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('back-link')), findsNothing);
      expect(dictionary.words, isEmpty);
      await unmount(tester);
    },
  );
}

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
import 'package:reading_app/reader/selection_paging.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/translate/sentence_sheet.dart';
import 'package:reading_app/translate/translator.dart';

import 'selection_test.dart' show begin, point, renderFor, RecordingTranslator;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Literata',
    )..addFont(rootBundle.load('assets/fonts/Literata.ttf'))).load();
  });
  for (final note in [false, true]) {
    testWidgets(
      'cross-page translation/copy is exact, ${note ? 'footnote' : 'body'} progress survives reopening',
      (t) async {
        t.view.physicalSize = const Size(402, 800);
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
        addTearDown(() {
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          t.binding.defaultBinaryMessenger.setMockMessageHandler(
            'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
            null,
          );
        });
        final db = ReadingDatabase(NativeDatabase.memory()),
            native = RecordingTranslator();
        addTearDown(db.close);
        final text = List.filled(
          100,
          'Alpha café e\u0301 👩‍👩‍👦 gamma delta.',
        ).join('\n');
        final content = note
            ? BookContent(
                const [BookBlock('Unchanged body.')],
                supplementaryDocuments: {
                  'notes': [BookBlock(text)],
                },
              )
            : BookContent([BookBlock(text)]);
        final id = await db.addBook('Cross-page selection', content);
        final book = (await db.book(id))!;
        Widget app() => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            translatorProvider.overrideWithValue(CachedTranslator(native, db)),
          ],
          child: MaterialApp(
            theme: const ReadingApp().theme(Brightness.light),
            home: note
                ? ReaderPage.source(
                    book: book,
                    defaultStyle: const ReaderStyle(font: 'Literata'),
                    target: const BookPosition(0, document: 'notes'),
                    anchor: const PageAnchor(
                      BookPosition(0, document: 'notes'),
                    ),
                  )
                : ReaderPage(
                    book: book,
                    defaultStyle: const ReaderStyle(font: 'Literata'),
                  ),
          ),
        );
        await t.pumpWidget(app());
        await t.pumpAndSettle();
        await t.pump(const Duration(seconds: 1));
        final before =
            (await db.customSelect('SELECT * FROM books').getSingle()).data;
        final state = t.state<PagedReaderState>(find.byType(PagedReader)),
            anchor = state.anchor.encode();
        final first = find.byType(ReaderParagraph).first;
        final press = await begin(t, point(renderFor(t, first), text, 'Alpha'));
        final rect = t.getRect(find.byKey(state.selectionViewportKey));
        await press.moveTo(Offset(rect.right - 2, rect.top + 80));
        await t.pump(SelectionPageTurner.dwell);
        await t.pump();
        expect(state.page, 1);
        expect(native.calls, isEmpty);
        final next = find
            .descendant(
              of: find.byKey(const ValueKey('visible-page-1')),
              matching: find.byType(ReaderParagraph),
            )
            .first;
        final paragraph = t.widget<ReaderParagraph>(next),
            render = renderFor(t, next);
        final at = text.indexOf('gamma', paragraph.visibleStart);
        final word = render.getWordBoundary(TextPosition(offset: at));
        final box = render
            .getBoxesForSelection(
              TextSelection(baseOffset: word.start, extentOffset: word.end),
            )
            .first;
        await press.moveTo(render.localToGlobal(box.toRect().center));
        await t.pump();
        await press.up();
        await t.pumpAndSettle();
        final expected = text.substring(0, word.end);
        expect(expected.length, lessThan(4000));
        expect(
          t.widget<SentenceSheet>(find.byType(SentenceSheet)).sentence,
          expected,
        );
        expect(native.calls, [expected]);
        expect(state.page, 0);
        expect(state.anchor.encode(), anchor);
        await t.ensureVisible(find.text('复制文字'));
        await t.pumpAndSettle();
        await t.tap(find.text('复制文字'));
        await t.pumpAndSettle();
        expect(copied, expected);
        expect(
          (await db.customSelect('SELECT * FROM books').getSingle()).data,
          before,
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        final reopened = (await db.book(id))!;
        expect(reopened.position, book.position);
        expect(reopened.location, before['location']);
        expect(reopened.content.encode(), content.encode());
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}

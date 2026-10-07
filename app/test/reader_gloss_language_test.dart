import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/settings.dart';
import 'package:reading_app/reader/style.dart';

import 'gloss_language_test.dart' show glossEntry;
import 'reader_links_test.dart' show textPoint, tapText;

class _Dictionary implements DictionaryProvider {
  @override
  DictionaryEntry? lookup(String word) => glossEntry;
  @override
  void close() {}
}

void main() {
  testWidgets(
    'reader saves global and per-book languages; lookup, footnotes and return preserve body',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      final db = ReadingDatabase(NativeDatabase.memory());
      final content = BookContent(
        [
          ...List.generate(8, (_) => const BookBlock('Opening')),
          const BookBlock('Tomorrow [1]'),
          const BookBlock('Tomorrow again.'),
          ...List.generate(40, (_) => const BookBlock('Body text to scroll.')),
        ],
        supplementaryDocuments: const {
          'note': [BookBlock('Tomorrow Back')],
        },
        links: const [
          BookLink(
            block: 8,
            start: 9,
            end: 12,
            href: 'note',
            kind: BookLinkKind.noteref,
            status: BookLinkStatus.resolved,
            target: BookPosition(0, document: 'note'),
          ),
          BookLink(
            document: 'note',
            block: 0,
            start: 9,
            end: 13,
            href: 'body',
            kind: BookLinkKind.backlink,
            status: BookLinkStatus.resolved,
            target: BookPosition(8, offset: 9),
          ),
        ],
      );
      final id = (await tester.runAsync(() async {
        final id = await db.addBook('Language test', content);
        await db.setSetting(
          'readerStyle',
          const ReaderStyle(paged: false).encode(),
        );
        await db.savePosition(id, 5);
        return id;
      }))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            dictionaryProvider.overrideWith((_) async => _Dictionary()),
          ],
          child: MaterialApp(
            theme: const ReadingApp().theme(Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final book = (await db.book(id))!;
                    final style = ReaderStyle.decode(
                      await db.setting('readerStyle'),
                    );
                    if (context.mounted) {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              ReaderPage(book: book, defaultStyle: style),
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
      Future<void> open() async {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      Future<void> configure({
        required bool perBook,
        required String language,
      }) async {
        await tester.tap(find.byKey(const ValueKey('reader-settings')));
        await tester.pumpAndSettle();
        if (perBook) {
          await tester.tap(find.text('仅应用于这本书'));
          await tester.pumpAndSettle();
        }
        final scrollable = find.descendant(
          of: find.byType(ReaderSettings),
          matching: find.byType(Scrollable),
        );
        final setting = find.byKey(const ValueKey('gloss-language-setting'));
        await tester.scrollUntilVisible(setting, 250, scrollable: scrollable);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(setting), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: setting, matching: find.text(language)),
        );
        await tester.pumpAndSettle();
        final other = find.byKey(
          const ValueKey('gloss-expansion-otherLanguage'),
        );
        await tester.scrollUntilVisible(other, 150, scrollable: scrollable);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(other), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(other);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      Future<void> leave() async {
        await tester.tap(find.byKey(const ValueKey('back-library')));
        await tester.pumpAndSettle();
      }

      await open();
      await configure(perBook: false, language: '英英');
      await tapText(tester, 8, 'Tomorrow');
      expect(find.text('The next day.\nThe future.'), findsOneWidget);
      final point = textPoint(tester, 8, 'Tomorrow');
      final bubble = tester.getRect(find.byType(WordBubble));
      expect(bubble.contains(point), isFalse);
      expect(bubble.left, greaterThanOrEqualTo(12));
      expect(bubble.right, lessThanOrEqualTo(390));
      await tester.tap(find.byType(WordBubble));
      await tester.pumpAndSettle();
      expect(find.text('n. 明天；未来'), findsOneWidget);
      await tester.tap(find.text('英英'));
      await tester.pumpAndSettle();
      // Selecting the same spelling in another paragraph must clear card state.
      await tester.tap(find.byTooltip('关闭释义'));
      await tester.pumpAndSettle();
      await tapText(tester, 9, 'Tomorrow');
      expect(find.text('The next day.\nThe future.'), findsOneWidget);
      await tester.tapAt(const Offset(390, 720));
      await tester.pumpAndSettle();
      expect(find.byType(WordBubble), findsNothing);
      final before = (await tester.runAsync(() => db.book(id)))!;
      await tapText(tester, 8, 'Tomorrow');
      await tapText(tester, 8, '[1]');
      expect(find.byType(WordBubble), findsNothing);
      expect(find.byType(ReaderPage), findsOneWidget);
      // A second deliberate tap follows the footnote after dismissing.
      await tapText(tester, 8, '[1]');
      await tapText(tester, 0, 'Tomorrow');
      expect(find.text('The next day.\nThe future.'), findsOneWidget);
      await tester.tap(find.byType(WordBubble));
      await tester.pumpAndSettle();
      expect(find.text('n. 明天；未来'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭释义'));
      await tester.pumpAndSettle();
      await tapText(tester, 0, 'Back');
      expect(find.byKey(const ValueKey('back-link')), findsNothing);
      final after = (await tester.runAsync(() => db.book(id)))!;
      expect(after.position, before.position);
      expect(after.location, before.location);
      expect(after.content.encode(), before.content.encode());
      await leave();
      final global = ReaderStyle.decode(
        await tester.runAsync<String?>(() => db.setting('readerStyle')),
      );
      expect(global.glossLanguage, GlossLanguage.enEn);
      expect(global.glossExpansion, GlossExpansion.otherLanguage);
      expect((await tester.runAsync(() => db.book(id)))!.style, isNull);
      await open();
      await tapText(tester, 8, 'Tomorrow');
      expect(find.text('The next day.\nThe future.'), findsOneWidget);
      await tester.tapAt(const Offset(390, 720));
      await tester.pumpAndSettle();
      await configure(perBook: true, language: '英汉');
      await leave();
      final own = ReaderStyle.decode(
        (await tester.runAsync(() => db.book(id)))!.style,
      );
      expect(own.glossLanguage, GlossLanguage.enZh);
      expect(own.glossExpansion, GlossExpansion.otherLanguage);
      expect(
        ReaderStyle.decode(
          await tester.runAsync<String?>(() => db.setting('readerStyle')),
        ).glossLanguage,
        GlossLanguage.enEn,
      );
      await open();
      await tapText(tester, 8, 'Tomorrow');
      expect(find.text('明天；未来'), findsOneWidget);
      await tester.tap(find.byType(WordBubble));
      await tester.pumpAndSettle();
      expect(find.text('The next day.'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭释义'));
      await tester.pumpAndSettle();
      await leave();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(db.close);
    },
  );
}

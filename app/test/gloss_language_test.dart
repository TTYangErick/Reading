import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/settings.dart';
import 'package:reading_app/reader/style.dart';

const glossEntry = DictionaryEntry(
  word: 'tomorrow',
  phonetic: 'Chinese IPA',
  fullGloss: 'n. 明天；未来',
  definition: 'ECDICT English definition',
  meanings: ['明天', '未来'],
  englishWord: 'morrow',
  englishPhonetic: '/English IPA/',
  englishSenses: [
    EnglishSense(
      pos: 'noun',
      gloss: 'The next day.',
      examples: ['Tomorrow is another day.'],
    ),
    EnglishSense(pos: 'noun', gloss: 'The future.'),
  ],
);

Future<void> showBubble(
  WidgetTester tester,
  ReaderStyle style, {
  DictionaryEntry? entry = glossEntry,
  String word = 'tomorrow',
  bool expanded = false,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
              child: WordBubble(
                word: word,
                entry: entry,
                style: style,
                palette: ReaderPalette.palettes[ReaderTheme.white]!,
                expanded: expanded,
                onExpand: () => update(() => expanded = true),
                onClose: onClose ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('old and unknown styles retain Chinese defaults; options persist globally and per book', () async {
    for (final raw in [
      '{}',
      '{"glossLanguage":"unknown","glossExpansion":9,"size":22}',
    ]) {
      final style = ReaderStyle.decode(raw);
      expect(style.glossLanguage, GlossLanguage.enZh);
      expect(style.glossExpansion, GlossExpansion.current);
      expect(style.paged, isFalse);
      if (raw.contains('size')) expect(style.size, 22);
    }
    final dir = Directory.systemTemp.createTempSync('gloss-settings-');
    final file = File('${dir.path}/reading.sqlite');
    var db = ReadingDatabase(NativeDatabase(file));
    const global = ReaderStyle(
      glossLanguage: GlossLanguage.enEn,
      glossExpansion: GlossExpansion.otherLanguage,
    );
    const own = ReaderStyle(
      glossLanguage: GlossLanguage.enZh,
      glossExpansion: GlossExpansion.otherLanguage,
      size: 23,
    );
    try {
      final id = await db.addBook(
        'Test',
        TxtParser().parseText('First\nSecond'),
      );
      await db.setSetting('readerStyle', global.encode());
      await db.saveStyle(id, own.encode());
      await db.savePosition(id, 1);
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      expect(
        ReaderStyle.decode(await db.setting('readerStyle')).toJson(),
        global.toJson(),
      );
      final book = (await db.book(id))!;
      expect(ReaderStyle.decode(book.style).toJson(), own.toJson());
      expect(book.position, 1);
      expect(book.content.blocks.last.text, 'Second');
      await db.saveStyle(id, null);
      expect((await db.book(id))!.style, isNull);
      expect(
        ReaderStyle.decode(await db.setting('readerStyle')).glossLanguage,
        GlossLanguage.enEn,
      );
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });

  for (final language in GlossLanguage.values) {
    for (final expansion in GlossExpansion.values) {
      for (final tier in GlossTier.values) {
        testWidgets(
          '${language.name} ${expansion.name} ${tier.name} entry and expansion',
          (tester) async {
            final style = ReaderStyle(
              glossLanguage: language,
              glossExpansion: expansion,
              tier: tier,
              senses: 1,
            );
            final legacy =
                language == GlossLanguage.enZh &&
                expansion == GlossExpansion.current;
            await showBubble(tester, style);
            if (tier != GlossTier.full) {
              expect(
                find.byKey(const ValueKey('card-gloss-language')),
                findsNothing,
              );
              expect(
                find.text(
                  language == GlossLanguage.enZh
                      ? tier == GlossTier.minimal
                            ? '明天'
                            : '明天；未来'
                      : tier == GlossTier.minimal
                      ? 'The next day.'
                      : 'The next day.\nThe future.',
                ),
                findsOneWidget,
              );
              expect(find.text('Tomorrow is another day.'), findsNothing);
              await tester.tap(find.byType(WordBubble));
              await tester.pumpAndSettle();
            }
            final english =
                tier == GlossTier.full || expansion == GlossExpansion.current
                ? language == GlossLanguage.enEn
                : language == GlossLanguage.enZh;
            expect(
              find.byKey(const ValueKey('card-gloss-language')),
              legacy ? findsNothing : findsOneWidget,
            );
            expect(
              find.text('n. 明天；未来'),
              legacy || !english ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('The next day.'),
              legacy || english ? findsOneWidget : findsNothing,
            );
            expect(find.text('ECDICT English definition'), findsNothing);
            if (!legacy) {
              expect(
                find.text('/English IPA/'),
                english ? findsOneWidget : findsNothing,
              );
              expect(
                find.text('/Chinese IPA/'),
                english ? findsNothing : findsOneWidget,
              );
              expect(
                find.text('原形 morrow'),
                english ? findsOneWidget : findsNothing,
              );
              await tester.tap(find.text(english ? '英汉' : '英英'));
              await tester.pumpAndSettle();
              expect(
                find.text('n. 明天；未来'),
                english ? findsOneWidget : findsNothing,
              );
              expect(
                find.text('The next day.'),
                english ? findsNothing : findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('temporary choice resets on new word and changed preferences', (
    tester,
  ) async {
    const style = ReaderStyle(
      glossLanguage: GlossLanguage.enEn,
      tier: GlossTier.full,
    );
    await showBubble(tester, style);
    await tester.tap(find.text('英汉'));
    await tester.pumpAndSettle();
    expect(find.text('n. 明天；未来'), findsOneWidget);
    await showBubble(tester, style, word: 'next');
    expect(find.text('The next day.'), findsOneWidget);
    expect(find.text('n. 明天；未来'), findsNothing);
    await tester.tap(find.text('英汉'));
    await tester.pumpAndSettle();
    await showBubble(tester, style.withValue('tier', 'brief'), word: 'next');
    expect(find.text('The next day.\nThe future.'), findsOneWidget);
  });

  testWidgets(
    'missing English and unavailable English are explicit and offer Chinese',
    (tester) async {
      for (final notice in [null, '英英词典暂时无法打开，请重开应用后重试。']) {
        final entry = DictionaryEntry(
          word: 'tomorrow',
          phonetic: '',
          fullGloss: 'n. 明天；未来',
          definition: '',
          meanings: ['明天'],
          englishNotice: notice,
        );
        await showBubble(
          tester,
          const ReaderStyle(glossLanguage: GlossLanguage.enEn),
          entry: entry,
          word: notice ?? 'tomorrow',
        );
        expect(find.textContaining(notice ?? '英英词典未收录这个词'), findsOneWidget);
        expect(find.textContaining('点此查看英汉'), findsOneWidget);
        expect(find.text('n. 明天；未来'), findsNothing);
        await tester.tap(find.byType(WordBubble));
        await tester.pumpAndSettle();
        expect(find.text('n. 明天；未来'), findsOneWidget);
      }
      const onlyEnglish = DictionaryEntry(
        word: 'morrow',
        phonetic: '',
        fullGloss: '',
        definition: '',
        meanings: [],
        hasChineseSource: false,
        englishWord: 'morrow',
        englishSenses: [EnglishSense(pos: 'noun', gloss: 'The next day.')],
      );
      await showBubble(
        tester,
        const ReaderStyle(glossExpansion: GlossExpansion.otherLanguage),
        entry: onlyEnglish,
      );
      expect(find.textContaining('英汉词典未收录'), findsOneWidget);
      await tester.tap(find.byType(WordBubble));
      await tester.pumpAndSettle();
      expect(find.text('The next day.'), findsOneWidget);
      await showBubble(
        tester,
        const ReaderStyle(glossLanguage: GlossLanguage.enEn),
        entry: null,
        word: 'unknown',
      );
      expect(find.text('未收录这个词'), findsOneWidget);
    },
  );

  testWidgets(
    'long English is bounded and scrollable, retains source, copy and close',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entry = DictionaryEntry(
        word: 'word',
        phonetic: '',
        fullGloss: '',
        definition: '',
        meanings: [],
        hasChineseSource: false,
        englishWord: 'word',
        englishSenses: List.generate(
          30,
          (i) => EnglishSense(
            pos: 'noun',
            gloss:
                'Meaning $i with enough English text to wrap over several lines in a narrow bubble.',
            examples: ['Example $i'],
          ),
        ),
      );
      var closed = false;
      await showBubble(
        tester,
        const ReaderStyle(
          glossLanguage: GlossLanguage.enEn,
          tier: GlossTier.brief,
        ),
        entry: entry,
        word: 'word',
        onClose: () => closed = true,
      );
      expect(
        tester.getSize(find.byType(WordBubble)).width,
        lessThanOrEqualTo(320),
      );
      expect(
        tester.getSize(find.byType(WordBubble)).height,
        lessThanOrEqualTo(420),
      );
      expect(find.textContaining('Meaning 24'), findsNothing);
      await tester.tapAt(
        tester.getTopLeft(find.byType(WordBubble)) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('词条来源与许可'));
      await tester.tap(find.text('词条来源与许可'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('https://en.wiktionary.org/wiki/word#English'),
        findsOneWidget,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.ensureVisible(find.text('复制'));
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(copied, 'word');
      await tester.ensureVisible(find.byTooltip('关闭释义'));
      await tester.tap(find.byTooltip('关闭释义'));
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'settings update language and disable expansion only while full tier is active',
    (tester) async {
      var style = const ReaderStyle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderSettings(
              style: style,
              onChanged: (value) => style = value,
            ),
          ),
        ),
      );
      Future<void> reveal(Finder finder, double delta) async {
        await tester.scrollUntilVisible(finder, delta);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
        await tester.pumpAndSettle();
      }

      final language = find.byKey(const ValueKey('gloss-language-setting'));
      await reveal(language, 250);
      await tester.tap(
        find.descendant(of: language, matching: find.text('英英')),
      );
      await tester.pumpAndSettle();
      expect(style.glossLanguage, GlossLanguage.enEn);
      final other = find.byKey(const ValueKey('gloss-expansion-otherLanguage'));
      await reveal(other, 180);
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(style.glossExpansion, GlossExpansion.otherLanguage);
      await reveal(find.text('完整'), -180);
      await tester.tap(find.text('完整'));
      await tester.pumpAndSettle();
      await reveal(other, 180);
      expect(
        tester.widget<RadioListTile<GlossExpansion>>(other).enabled,
        isFalse,
      );
      expect(style.glossExpansion, GlossExpansion.otherLanguage);
      await reveal(find.text('简洁'), -180);
      await tester.tap(find.text('简洁'));
      await tester.pumpAndSettle();
      await reveal(other, 180);
      expect(
        tester.widget<RadioListTile<GlossExpansion>>(other).enabled,
        isTrue,
      );
      expect(style.glossExpansion, GlossExpansion.otherLanguage);
      expect(tester.takeException(), isNull);
    },
  );
}

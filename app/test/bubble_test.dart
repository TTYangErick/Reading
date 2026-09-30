import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  const entry = DictionaryEntry(
    word: 'tomorrow',
    phonetic: 'təˈmɒrəʊ',
    fullGloss: 'n. 明天, 未来\nadv. 明天, 未来地',
    definition: 'The day after today.',
    meanings: ['明天', '未来', '未来地'],
  );
  testWidgets('three tiers, 1–3 minimal senses, missing word, and expansion', (
    tester,
  ) async {
    Future<void> render(
      ReaderStyle style, {
      DictionaryEntry? value = entry,
      bool expanded = false,
      VoidCallback? onExpand,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 296, maxHeight: 380),
              child: WordBubble(
                word: 'tomorrow',
                entry: value,
                style: style,
                palette: ReaderPalette.palettes[ReaderTheme.white]!,
                expanded: expanded,
                onExpand: onExpand ?? () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await render(const ReaderStyle(senses: 1));
    expect(find.text('明天'), findsOneWidget);
    await render(const ReaderStyle(senses: 2));
    expect(find.text('明天；未来'), findsOneWidget);
    await render(const ReaderStyle(senses: 3));
    expect(find.text('明天；未来；未来地'), findsOneWidget);
    await render(const ReaderStyle(tier: GlossTier.brief));
    expect(find.text('明天；未来；未来地'), findsOneWidget);
    expect(find.text(entry.fullGloss), findsNothing);
    await render(const ReaderStyle(tier: GlossTier.full));
    expect(find.text(entry.fullGloss), findsOneWidget);
    expect(find.text('/təˈmɒrəʊ/'), findsOneWidget);
    await render(const ReaderStyle(), value: null);
    expect(find.text('未收录这个词'), findsOneWidget);
    bool expanded = false;
    await render(const ReaderStyle(), onExpand: () => expanded = true);
    await tester.tap(find.byType(WordBubble));
    expect(expanded, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('large full entry stays scrollable in a narrow edge bubble', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomSingleChildLayout(
            delegate: const BubbleLayout(
              Rect.fromLTWH(270, 450, 40, 30),
              safeTop: 68,
              safeBottom: 60,
            ),
            child: WordBubble(
              word: 'tomorrow',
              entry: DictionaryEntry(
                word: entry.word,
                phonetic: entry.phonetic,
                fullGloss: List.filled(50, entry.fullGloss).join('\n'),
                definition: entry.definition,
                meanings: entry.meanings,
              ),
              style: const ReaderStyle(tier: GlossTier.full, bubbleSize: 24),
              palette: ReaderPalette.palettes[ReaderTheme.night]!,
              expanded: true,
              onExpand: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byType(WordBubble)).right,
      lessThanOrEqualTo(308),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

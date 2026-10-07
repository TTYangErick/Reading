import 'dart:convert';

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
import 'package:reading_app/reader/settings.dart';

import 'reader_links_test.dart' show tapText;

import 'package:reading_app/text/language.dart';
import 'package:reading_app/vocab/source.dart';
import 'package:reading_app/vocab/vocabulary.dart';
import 'package:reading_app/vocab/vocabulary_page.dart';

import 'gloss_language_test.dart' show glossEntry;

VocabularyDraft withLocation(VocabularyDraft d, String raw) => VocabularyDraft(
  word: d.word,
  lemma: d.lemma,
  gloss: d.gloss,
  lang: d.lang,
  dictId: d.dictId,
  source: d.source,
  sourceUrl: d.sourceUrl,
  license: d.license,
  bookId: d.bookId,
  bookTitle: d.bookTitle,
  sentence: d.sentence,
  location: raw,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReadingDatabase db;
  setUp(() {
    db = ReadingDatabase(NativeDatabase.memory());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  tearDown(() => db.close());

  test('source resolution rejects stale or malformed positions instead of clamping', () async {
    final id = await db.addBook(
      'Book',
      const BookContent(
        [
          BookBlock('Tomorrow here.'),
          BookBlock('Tomorrow caption.', image: 'p'),
          BookBlock(
            'table',
            rows: [
              ['Tomorrow cell.'],
            ],
          ),
        ],
        supplementaryDocuments: {
          'note': [BookBlock('Tomorrow note.')],
        },
      ),
    );
    final book = (await db.book(id))!;
    for (final (p, cell, part) in [
      (const BookPosition(0), null, PagePart.text),
      (const BookPosition(1), 'caption', PagePart.caption),
      (const BookPosition(2), '0-0', PagePart.tableRow),
      (const BookPosition(0, document: 'note'), null, PagePart.text),
    ]) {
      final d = VocabularyDraft.capture(
        book: book,
        position: p,
        cell: cell,
        word: const WordRange(0, 8, 'Tomorrow'),
        entry: glossEntry,
        english: false,
      );
      final source = VocabularySource.resolve(book, d)!;
      expect(source.anchor.part, part);
      expect(source.cell, cell);
      expect(source.position.document, p.document);
      for (final raw in [
        'bad',
        '{}',
        jsonEncode({'version': 2, 'position': p.toJson()}),
        jsonEncode({
          'version': 1,
          'position': {'block': -1},
        }),
        jsonEncode({
          'version': 1,
          'position': {'block': 999},
        }),
        jsonEncode({
          'version': 1,
          'position': {'block': 0, 'offset': 999},
        }),
        jsonEncode({
          'version': 1,
          'position': {'block': 0, 'document': 'missing'},
        }),
        jsonEncode({'version': 1, 'position': p.toJson(), 'cell': '-1-0'}),
        jsonEncode({'version': 1, 'position': p.toJson(), 'cell': '999-999'}),
      ]) {
        expect(VocabularySource.resolve(book, withLocation(d, raw)), isNull);
      }
    }
    final d = VocabularyDraft.capture(
      book: book,
      position: const BookPosition(0),
      word: const WordRange(0, 8, 'Tomorrow'),
      entry: glossEntry,
      english: false,
    );
    await db.customStatement('UPDATE books SET content=? WHERE id=?', [
      const BookContent([BookBlock('Tomorrow changed.')]).encode(),
      id,
    ]);
    expect(VocabularySource.resolve((await db.book(id))!, d), isNull);
  });

  for (final (size, platform, paged) in [
    (const Size(402, 874), TargetPlatform.android, true),
    (const Size(402, 874), TargetPlatform.iOS, true),
    (const Size(1194, 834), TargetPlatform.iOS, true),
    (const Size(402, 874), TargetPlatform.iOS, false),
  ]) {
    for (final kind in ['body', 'note', 'caption', 'table']) {
      testWidgets(
        '$kind source opens accurately and preserves saved progress for $platform $size paged=$paged',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final text = '${'Earlier words. ' * 100}Tomorrow is another day.';
          final content = BookContent(
            [
              const BookBlock('Saved position.'),
              BookBlock(text),
              BookBlock(
                'Table',
                rows: List.generate(
                  40,
                  (r) => List.generate(
                    5,
                    (c) => r == 35 && c == 4 ? text : 'Row $r column $c.',
                  ),
                ),
              ),
              BookBlock(text, image: 'missing-image'),
            ],
            chapters: const [
              BookChapter('Saved chapter', 0),
              BookChapter('Source chapter', 1),
            ],
            supplementaryDocuments: {
              'note': [BookBlock(text)],
            },
            links: const [
              BookLink(
                block: 1,
                start: 0,
                end: 7,
                href: 'note',
                kind: BookLinkKind.link,
                status: BookLinkStatus.resolved,
                target: BookPosition(0, document: 'note'),
              ),
            ],
          );
          final id = await db.addBook('Source book', content);
          const saved = PageAnchor(BookPosition(0));
          await db.savePosition(id, 0, location: saved.encode());
          await db.setSetting(
            'readerStyle',
            ReaderStyle(paged: paged, landscapePaged: paged).encode(),
          );
          final book = (await db.book(id))!;
          final p = switch (kind) {
            'body' => const BookPosition(1),
            'note' => const BookPosition(0, document: 'note'),
            'caption' => const BookPosition(3),
            _ => const BookPosition(2),
          };
          final cell = kind == 'table'
              ? '35-4'
              : kind == 'caption'
              ? 'caption'
              : null;
          final offset = text.indexOf('Tomorrow');
          final d = VocabularyDraft.capture(
            book: book,
            position: p,
            cell: cell,
            word: WordRange(offset, offset + 8, 'Tomorrow'),
            entry: glossEntry,
            english: false,
          );
          await db.addVocabulary(d);
          final before =
              (await db.customSelect('SELECT * FROM books').getSingle()).data;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [databaseProvider.overrideWithValue(db)],
              child: MaterialApp(
                theme: const ReadingApp()
                    .theme(Brightness.light)
                    .copyWith(platform: platform),
                home: const VocabularyPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('vocabulary-search')),
            'Tomorrow',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('在书中查看原句'));
          await tester.pumpAndSettle();
          expect(find.byType(ReaderPage), findsOneWidget);
          if (paged) {
            final state = tester.state<PagedReaderState>(
              find.byType(PagedReader),
            );
            expect(state.anchor.position.document, p.document);
            expect(state.anchor.position.block, p.block);
            if (kind == 'table') expect(state.anchor.row, 35);
            if (kind == 'caption') expect(state.anchor.part, PagePart.caption);
          }
          final candidates = find
              .byWidgetPredicate((w) => w is ReaderParagraph && w.text == text)
              .evaluate()
              .map((e) => e.widget)
              .toList();
          final points = <Offset>[];
          for (final w in candidates) {
            final rich = find.descendant(
              of: find.byWidget(w),
              matching: find.byType(RichText),
            );
            final render = tester.renderObject<RenderParagraph>(rich);
            final boxes = render.getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: offset + 8),
            );
            points.add(render.localToGlobal(boxes.first.toRect().center));
          }
          expect(
            points.any(
              (p) =>
                  p.dx > 0 &&
                  p.dx < size.width &&
                  p.dy > 55 &&
                  p.dy < size.height - 40,
            ),
            isTrue,
            reason: 'word must be visible: $points',
          );
          if (paged) {
            await tester.tap(find.byKey(const ValueKey('page-label')));
            await tester.pumpAndSettle();
          }
          expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
          expect(find.byTooltip('目录'), findsOneWidget);
          if (paged) {
            await tester.tap(find.byTooltip('关闭阅读操作'));
            await tester.pumpAndSettle();
            await tester.drag(find.byType(PageView), const Offset(-320, 0));
            await tester.pumpAndSettle();
          }
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pumpAndSettle();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(VocabularyPage), findsOneWidget);
          expect(
            tester
                    .widget<TextField>(
                      find.byKey(const ValueKey('vocabulary-search')),
                    )
                    .controller
                    ?.text ??
                tester
                    .widget<EditableText>(find.byType(EditableText))
                    .controller
                    .text,
            'Tomorrow',
          );
          expect(
            (await db.customSelect('SELECT * FROM books').getSingle()).data,
            before,
          );
          expect(await db.vocabulary(), hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'source root supports nested links, settings, contents and returning to vocabulary',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = await db.addBook(
        'Source',
        const BookContent(
          [BookBlock('Saved'), BookBlock('Tomorrow Next')],
          chapters: [
            BookChapter('Saved chapter', 0),
            BookChapter('Source chapter', 1),
          ],
          supplementaryDocuments: {
            'note': [BookBlock('Nested note')],
          },
          links: [
            BookLink(
              block: 1,
              start: 9,
              end: 13,
              href: 'note',
              kind: BookLinkKind.link,
              status: BookLinkStatus.resolved,
              target: BookPosition(0, document: 'note'),
            ),
          ],
        ),
      );
      const saved = PageAnchor(BookPosition(0));
      await db.savePosition(id, 0, location: saved.encode());
      await db.setSetting(
        'readerStyle',
        const ReaderStyle(paged: false, landscapePaged: false).encode(),
      );
      final book = (await db.book(id))!;
      await db.addVocabulary(
        VocabularyDraft.capture(
          book: book,
          position: const BookPosition(1),
          word: const WordRange(0, 8, 'Tomorrow'),
          entry: glossEntry,
          english: false,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: const ReadingApp().theme(Brightness.light),
            home: const VocabularyPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('在书中查看原句'));
      await tester.tap(find.text('在书中查看原句'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
      await tapText(tester, 1, 'Next');
      expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2));
      expect(find.byTooltip('返回生词本'), findsOneWidget);
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      final settings = tester.widget<ReaderSettings>(
        find.byType(ReaderSettings),
      );
      settings.onChanged(settings.style.withValue('size', 26.0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('回到原句'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget);
      expect(
        tester
            .widget<ReaderParagraph>(find.byKey(const ValueKey('paragraph-1')))
            .style
            .fontSize,
        26,
      );
      await tester.tap(find.byTooltip('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved chapter'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage, skipOffstage: false), findsNWidgets(2));
      await tester.tap(find.byTooltip('返回生词本'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage, skipOffstage: false), findsNothing);
      expect(find.byType(VocabularyPage), findsOneWidget);
      final after = (await db.book(id))!;
      expect(after.position, 0);
      expect(after.location, saved.encode());
      expect(after.content.encode(), book.content.encode());
      expect(ReaderStyle.decode(await db.setting('readerStyle')).size, 26);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'deleted book and invalid source keep the snapshot and allow return to list',
    (tester) async {
      final id = await db.addBook(
        'Old book',
        const BookContent([BookBlock('Tomorrow here.')]),
      );
      final book = (await db.book(id))!;
      final d = VocabularyDraft.capture(
        book: book,
        position: const BookPosition(0),
        word: const WordRange(0, 8, 'Tomorrow'),
        entry: glossEntry,
        english: false,
      );
      await db.addVocabulary(withLocation(d, 'bad'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: VocabularyPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('在书中查看原句'));
      await tester.pumpAndSettle();
      expect(find.text('原句位置已失效，收藏内容仍然保留。'), findsOneWidget);
      expect(find.byType(ReaderPage), findsNothing);
      await db.deleteBook(id);
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在书中查看原句').last);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(await db.vocabulary(), hasLength(1));
      expect(find.text('原书已不在书架中，收藏的原句仍然保留。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

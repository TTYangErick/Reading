import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/library/library.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/text/language.dart';
import 'package:reading_app/vocab/save_button.dart';
import 'package:reading_app/vocab/vocabulary.dart';
import 'package:reading_app/vocab/vocabulary_page.dart';

import 'gloss_language_test.dart' show glossEntry;
import 'reader_links_test.dart' show tapText;

class _Dictionary implements DictionaryProvider {
  @override
  DictionaryEntry? lookup(String word) => glossEntry;
  @override
  void close() {}
}

VocabularyDraft draft({
  String book = 'old',
  String word = 'Tomorrow',
  String dict = 'ecdict',
  String location = 'location',
}) => VocabularyDraft(
  word: word,
  lemma: word.toLowerCase(),
  gloss: '明天',
  lang: 'en',
  dictId: dict,
  source: 'ECDICT',
  sourceUrl: 'https://github.com/skywind3000/ECDICT',
  license: 'MIT',
  bookId: book,
  bookTitle: book,
  sentence: '$word is another day.',
  location: location,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real schema 4 migration, deduplication and reopen preserve all old tables', () async {
    final folder = Directory.systemTemp.createTempSync('vocabulary-migration-');
    final file = File('${folder.path}/reading.sqlite');
    final old = sqlite.sqlite3.open(file.path);
    old.execute(
      'CREATE TABLE books(id TEXT PRIMARY KEY,title TEXT NOT NULL,content TEXT NOT NULL,position INTEGER NOT NULL DEFAULT 0,style TEXT,location TEXT,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,last_read_at INTEGER NOT NULL DEFAULT 0)',
    );
    old.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
    old.execute(
      'CREATE TABLE book_assets(book_id TEXT NOT NULL,path TEXT NOT NULL,data BLOB NOT NULL,PRIMARY KEY(book_id,path))',
    );
    old.execute(
      'CREATE TABLE translations(engine TEXT NOT NULL,source_language TEXT NOT NULL,target_language TEXT NOT NULL,source TEXT NOT NULL,result TEXT NOT NULL,PRIMARY KEY(engine,source_language,target_language,source))',
    );
    old.execute(
      "INSERT INTO books VALUES('old','Old',?,1,'{}','precise location',1,2,3)",
      [TxtParser().parseText('one\ntwo').encode()],
    );
    old.execute("INSERT INTO settings VALUES('readerStyle','{}')");
    old.execute("INSERT INTO book_assets VALUES('old','p',X'010203')");
    old.execute(
      "INSERT INTO translations VALUES('native','en','zh','text','译文')",
    );
    old.execute('PRAGMA user_version=4');
    final tables = ['books', 'settings', 'book_assets', 'translations'];
    final before = {
      for (final t in tables)
        t: old
            .select('SELECT * FROM $t')
            .map((r) => r.values.toList())
            .toList(),
    };
    old.close();
    var db = ReadingDatabase(NativeDatabase(file));
    try {
      final ids = await Future.wait([
        db.addVocabulary(draft()),
        db.addVocabulary(draft()),
      ]);
      expect(ids.toSet(), hasLength(1));
      await db.addVocabulary(draft(dict: 'wiktionary'));
      await db.addVocabulary(draft(location: 'another source'));
      expect(await db.vocabulary(), hasLength(3));
      for (final t in tables) {
        expect(
          (await db.customSelect('SELECT * FROM $t').get())
              .map((r) => r.data.values.toList())
              .toList(),
          before[t],
        );
      }
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        7,
      );
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      expect(await db.vocabularyId(draft()), ids.first);
      final entries = await db.vocabulary();
      expect(entries.first.createdAt, greaterThan(0));
      expect(entries.first.updatedAt, entries.first.createdAt);
      await db.deleteBook('old');
      expect(await db.vocabulary(), hasLength(3));
      await db.deleteVocabulary(ids.first);
      expect(await db.vocabulary(), hasLength(2));
      expect(await db.translationCount(), 1);
      expect(await db.setting('readerStyle'), '{}');
      await expectLater(db.addVocabulary(draft(word: '')), throwsArgumentError);
    } finally {
      await db.close();
      folder.deleteSync(recursive: true);
    }
  });

  test('capture retains selected language, exact source, table cell, caption and note sentences', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    final id = await db.addBook(
      'Source',
      const BookContent(
        [
          BookBlock('Yesterday. Tomorrow is another day.'),
          BookBlock(
            'table',
            rows: [
              ['Tomorrow in a cell.'],
            ],
          ),
          BookBlock('Tomorrow in a caption.', image: 'image'),
        ],
        supplementaryDocuments: {
          'note': [BookBlock('Tomorrow in a footnote.')],
        },
      ),
    );
    final book = (await db.book(id))!;
    for (final (position, cell, offset, sentence) in [
      (const BookPosition(0), null, 11, 'Tomorrow is another day.'),
      (const BookPosition(1), '0-0', 0, 'Tomorrow in a cell.'),
      (const BookPosition(2), 'caption', 0, 'Tomorrow in a caption.'),
      (
        const BookPosition(0, document: 'note'),
        null,
        0,
        'Tomorrow in a footnote.',
      ),
    ]) {
      final v = VocabularyDraft.capture(
        book: book,
        position: position,
        cell: cell,
        word: WordRange(offset, offset + 8, 'Tomorrow'),
        entry: glossEntry,
        english: false,
      );
      expect(v.sentence, sentence);
      expect(v.gloss, glossEntry.fullGloss);
      expect(v.lemma, 'tomorrow');
      final location = jsonDecode(v.location) as Map;
      expect(location['position']['offset'], offset);
      expect(location['position']['document'], position.document);
      expect(location['cell'], cell);
      await db.addVocabulary(v);
    }
    final english = VocabularyDraft.capture(
      book: book,
      position: const BookPosition(0),
      word: const WordRange(11, 19, 'Tomorrow'),
      entry: glossEntry,
      english: true,
    );
    expect(english.lemma, 'morrow');
    expect(english.gloss, contains('The next day.'));
    expect(english.gloss, isNot(contains('明天')));
    expect(english.license, 'CC-BY-SA-4.0');
    expect(english.sourceUrl, endsWith('/morrow#English'));
    await db.addVocabulary(english);
    expect(await db.vocabulary(), hasLength(5));
    await db.close();
  });

  testWidgets(
    'save, load and delete failures remain retryable without losing entries',
    (tester) async {
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.vocabulary();
      await db.customStatement(
        "CREATE TRIGGER reject_save BEFORE INSERT ON vocabulary BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      Future<void> show(Widget child) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(home: child),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(
        Scaffold(
          body: SaveVocabularyButton(draft: draft(), color: Colors.black),
        ),
      );
      await tester.tap(find.byTooltip('加入生词本'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('收藏失败，点击重试'), findsOneWidget);
      expect(await db.vocabulary(), isEmpty);
      await db.customStatement('DROP TRIGGER reject_save');
      await tester.tap(find.byTooltip('收藏失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('已加入生词本'), findsOneWidget);
      await db.customStatement(
        'ALTER TABLE vocabulary RENAME TO unavailable_vocabulary',
      );
      await show(const VocabularyPage());
      expect(find.text('生词本暂时无法读取'), findsOneWidget);
      await db.customStatement(
        'ALTER TABLE unavailable_vocabulary RENAME TO vocabulary',
      );
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow'), findsOneWidget);
      await db.customStatement(
        "CREATE TRIGGER reject_delete BEFORE DELETE ON vocabulary BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await tester.tap(find.byTooltip('删除生词'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除失败，请重试。'), findsOneWidget);
      expect(await db.vocabulary(), hasLength(1));
      await db.customStatement('DROP TRIGGER reject_delete');
      await tester.tap(find.byTooltip('删除生词'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(await db.vocabulary(), isEmpty);
      expect(find.textContaining('还没有收藏生词'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final (size, platform) in [
    (const Size(320, 740), TargetPlatform.android),
    (const Size(402, 874), TargetPlatform.iOS),
    (const Size(1194, 834), TargetPlatform.iOS),
  ]) {
    testWidgets(
      'reader saves only from full card and respects language at $size $platform',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
        final db = ReadingDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final id = await db.addBook(
          'A book',
          const BookContent([BookBlock('Tomorrow is another day.')]),
        );
        final book = (await db.book(id))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              dictionaryProvider.overrideWith((_) async => _Dictionary()),
            ],
            child: MaterialApp(
              theme: const ReadingApp()
                  .theme(Brightness.light)
                  .copyWith(platform: platform),
              home: ReaderPage(
                book: book,
                defaultStyle: const ReaderStyle(
                  paged: false,
                  landscapePaged: false,
                  glossExpansion: GlossExpansion.otherLanguage,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapText(tester, 0, 'Tomorrow');
        expect(find.byType(SaveVocabularyButton), findsNothing);
        await tester.tap(find.byType(WordBubble));
        await tester.pumpAndSettle();
        expect(find.byTooltip('加入生词本'), findsOneWidget);
        await tester.tap(find.byTooltip('加入生词本'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('已加入生词本'), findsOneWidget);
        expect((await db.vocabulary()).single.draft.dictId, 'wiktionary');
        await tester.tap(find.text('英汉'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('加入生词本'));
        await tester.pumpAndSettle();
        expect(await db.vocabulary(), hasLength(2));
        await tester.tap(find.text('英英'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('已加入生词本'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭释义'));
        await tester.pumpAndSettle();
        expect((await db.book(id))!.position, book.position);
        expect(find.byType(WordBubble), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final size in [const Size(320, 740), const Size(1194, 834)]) {
    testWidgets(
      'shelf vocabulary search filter sort detail and confirmed deletion at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = ReadingDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.addVocabulary(draft(book: 'First book'));
        await db.addVocabulary(draft(book: 'Second book', word: 'Future'));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: const ReadingApp().theme(Brightness.light),
              home: const LibraryPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('生词本'));
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyPage), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('vocabulary-search')),
          'TOMORROW',
        );
        await tester.pumpAndSettle();
        expect(find.text('Tomorrow'), findsOneWidget);
        expect(find.text('Future'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('vocabulary-search')),
          '%',
        );
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的生词'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('vocabulary-search')),
          '',
        );
        await tester.pumpAndSettle();
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const ValueKey('vocabulary-book')),
            )
            .onChanged!('First book');
        await tester.pumpAndSettle();
        expect(find.text('Future'), findsNothing);
        await tester.tap(find.byTooltip('最新收藏在前'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('最早收藏在前'), findsOneWidget);
        await tester.tap(find.text('Tomorrow'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('删除生词'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await db.vocabulary(), hasLength(2));
        await tester.tap(find.byTooltip('删除生词'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(await db.vocabulary(), hasLength(1));
        expect(find.text('Future'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:reading_app/backup/backup.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/history/history.dart';
import 'package:reading_app/history/history_page.dart';
import 'package:reading_app/library/library.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/translate/translator.dart';

import 'backup_test.dart' show seed, snapshot, payload;
import 'gloss_language_test.dart' show glossEntry;
import 'reader_links_test.dart' show textPoint;
import 'translation_test.dart' show TestTranslator;
import 'word_fallback_test.dart' show Dictionary;

Future<void> record(
  LookupHistory history,
  String word, {
  String language = 'en',
}) => history.record(language, word, generation: history.generation);

class FailingHistory extends LookupHistory {
  FailingHistory(super.database);
  bool fail = true;
  @override
  Future<List<LookupRecord>> recent() =>
      fail ? Future.error(StateError('read failure')) : super.recent();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v6 migration adds empty history, preserving all six tables across reopen',
    () async {
      final dir = Directory.systemTemp.createTempSync('reading-history-');
      final file = File('${dir.path}/reading.sqlite');
      var db = ReadingDatabase(NativeDatabase(file));
      await seed(db);
      final before = await snapshot(db)
        ..remove('lookup_history');
      await db.close();
      final old = sqlite.sqlite3.open(file.path);
      old.execute('DROP TABLE lookup_history');
      old.execute('PRAGMA user_version=6');
      old.close();
      db = ReadingDatabase(NativeDatabase(file));
      try {
        expect(await LookupHistory(db).recent(), isEmpty);
        expect(
          await snapshot(db)
            ..remove('lookup_history'),
          before,
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          7,
        );
        await record(LookupHistory(db), 'May');
        await db.close();
        db = ReadingDatabase(NativeDatabase(file));
        expect((await LookupHistory(db).recent()).single.word, 'May');
        expect(
          await snapshot(db)
            ..remove('lookup_history'),
          before,
        );
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );

  test('bounded exact words, languages and recency; invalid input ignored; clear isolated', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final before = await snapshot(db)
      ..remove('lookup_history');
    final history = LookupHistory(db);
    await Future.wait(List.generate(205, (i) => record(history, 'word$i')));
    expect(await history.recent(), hasLength(200));
    expect((await history.recent()).last.word, 'word5');
    await record(history, 'word10');
    expect((await history.recent()).first.word, 'word10');
    for (final word in ['May', 'may', 'café', 'can’t', '😀']) {
      await record(history, word);
    }
    await record(history, 'May', language: 'future');
    expect(
      (await history.recent()).where((r) => r.word == 'May'),
      hasLength(2),
    );
    for (final word in ['', ' bad', 'bad\nword', 'x' * 257]) {
      await record(history, word);
    }
    expect(await history.recent(), hasLength(200));
    await history.clear();
    expect(await history.recent(), isEmpty);
    expect(
      await snapshot(db)
        ..remove('lookup_history'),
      before,
    );
  });

  test('clear/restore invalidate late lookups; failed writes and clears recover safely', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final history = LookupHistory(db);
    final old = history.generation;
    final pending = record(history, 'old');
    await history.clear();
    await pending;
    await history.record('en', 'late', generation: old);
    expect(await history.recent(), isEmpty);
    await db.customStatement(
      "CREATE TRIGGER reject_history BEFORE INSERT ON lookup_history BEGIN SELECT RAISE(ABORT,'failure'); END",
    );
    await expectLater(record(history, 'failed'), throwsA(anything));
    expect(history.writeFailed, isTrue);
    await db.customStatement('DROP TRIGGER reject_history');
    await record(history, 'good');
    await db.customStatement(
      "CREATE TRIGGER reject_clear BEFORE DELETE ON lookup_history BEGIN SELECT RAISE(ABORT,'failure'); END",
    );
    await expectLater(history.clear(), throwsA(anything));
    expect((await history.recent()).single.word, 'good');
    await db.customStatement('DROP TRIGGER reject_clear');
    final oldGeneration = history.generation;
    final backup = ReadingBackup.decode(await BackupStore(db).export());
    await history.replace(() => BackupStore(db).restore(backup));
    await history.record('en', 'lateAfterRestore', generation: oldGeneration);
    expect((await history.recent()).single.word, 'good');
    await history.clear();
    expect(history.writeFailed, isFalse);
  });

  test('new backup round-trips history; old six-table backup clears it; malformed rows reject', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final history = LookupHistory(db), store = BackupStore(db);
    await record(history, 'may');
    await record(history, 'May');
    final before = await snapshot(db);
    final bytes = await store.export();
    await record(history, 'later');
    await store.restore(ReadingBackup.decode(bytes));
    expect(await snapshot(db), before);
    expect((await history.recent()).map((r) => r.word), ['May', 'may']);
    for (final change in <void Function(Map<String, dynamic>)>[
      (p) => p['tables'].remove('lookup_history'),
      (p) => p['tables']['lookup_history'].add(['en', 'May', 1]),
      (p) => p['tables']['lookup_history'][0][1] = '',
      (p) => p['tables']['lookup_history'][0][2] = -1,
      (p) => p['tables']['lookup_history'] = List.generate(
        201,
        (i) => ['en', 'w$i', i],
      ),
    ]) {
      final p = payload(bytes);
      change(p);
      expect(() => ReadingBackup.encode(p), throwsFormatException);
    }
    final legacy = payload(bytes)..['schema'] = 6;
    legacy['tables'].remove('lookup_history');
    final restored = ReadingBackup.decode(ReadingBackup.encode(legacy));
    expect(restored.count('lookup_history'), 0);
    await store.restore(restored);
    expect(await history.recent(), isEmpty);
    expect(
      await snapshot(db)
        ..remove('lookup_history'),
      before..remove('lookup_history'),
    );
  });

  test('failed restore rolls history and old tables back together', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final history = LookupHistory(db), store = BackupStore(db);
    await record(history, 'backup');
    final backup = ReadingBackup.decode(await store.export());
    await record(history, 'current');
    final before = await snapshot(db);
    await db.customStatement(
      "CREATE TRIGGER reject_restore BEFORE INSERT ON books BEGIN SELECT RAISE(ABORT,'failure'); END",
    );
    await expectLater(
      history.replace(() => store.restore(backup)),
      throwsA(anything),
    );
    expect(await snapshot(db), before);
    await db.customStatement('DROP TRIGGER reject_restore');
    await history.replace(() => store.restore(backup));
    expect((await history.recent()).single.word, 'backup');
  });

  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 16; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> unmount(WidgetTester t, ReadingDatabase db) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await t.runAsync(db.close);
  }

  for (final size in [
    const Size(320, 740),
    const Size(402, 874),
    const Size(1194, 834),
  ]) {
    testWidgets(
      'history entry, primary language, literal search and confirmed clear at $size',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final db = ReadingDatabase(NativeDatabase.memory()),
            dictionary = Dictionary(glossEntry);
        final history = LookupHistory(db);
        await t.runAsync(() async {
          await record(history, 'Tomorrow');
          await record(history, 'May');
          await db.setSetting(
            'readerStyle',
            const ReaderStyle(
              glossLanguage: GlossLanguage.enEn,
              glossExpansion: GlossExpansion.otherLanguage,
            ).encode(),
          );
        });
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              lookupHistoryProvider.overrideWithValue(history),
              dictionaryProvider.overrideWith((_) async => dictionary),
            ],
            child: MaterialApp(
              theme: const ReadingApp().theme(Brightness.light),
              home: const LibraryPage(),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('更多'));
        await t.pumpAndSettle();
        await t.tap(find.text('查词历史'));
        await flush(t);
        await t.pumpAndSettle();
        expect(
          dictionary.words,
          isEmpty,
        ); // Viewing a list does not open dictionaries.
        await t.enterText(find.byKey(const ValueKey('history-search')), '%');
        await t.pump();
        expect(find.text('没有匹配的记录。'), findsOneWidget);
        await t.enterText(find.byKey(const ValueKey('history-search')), 'tom');
        await t.pump();
        expect(find.text('May'), findsNothing);
        await t.tap(find.text('Tomorrow'));
        await flush(t);
        await t.pumpAndSettle();
        expect(find.text('The next day.'), findsOneWidget);
        expect(find.text('收藏生词'), findsNothing);
        await t.tap(find.byTooltip('关闭释义'));
        await flush(t);
        await t.pumpAndSettle();
        expect((await t.runAsync(history.recent))!.first.word, 'Tomorrow');
        expect(find.text('暂时无法打开释义，请重试。'), findsNothing);
        await t.tap(find.byTooltip('清空历史'));
        await t.pumpAndSettle();
        await t.tap(find.text('取消'));
        await t.pumpAndSettle();
        expect(await t.runAsync(history.recent), hasLength(2));
        await t.tap(find.byTooltip('清空历史'));
        await t.pumpAndSettle();
        await t.tap(find.text('清空'));
        await flush(t);
        expect(find.text('还没有查词历史，阅读时点一个词试试。'), findsOneWidget);
        expect(await t.runAsync(history.recent), isEmpty);
        expect(find.text('清空失败，请重试。'), findsNothing);
        expect(t.takeException(), isNull);
        await unmount(t, db);
      },
    );
  }

  testWidgets(
    'reader records only completed live lookups, including miss; dismiss tap and failure do not record',
    (t) async {
      t.binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      final db = ReadingDatabase(NativeDatabase.memory());
      final history = LookupHistory(db), dictionary = Dictionary(glossEntry);
      final loading = Completer<DictionaryProvider>();
      final native = TestTranslator()
        ..availability = TranslationStatus.unavailable;
      final id = (await t.runAsync(
        () => db.addBook(
          'History test',
          const BookContent([BookBlock('Tomorrow Alpha Missing.')]),
        ),
      ))!;
      final book = (await t.runAsync(() => db.book(id)))!;
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            lookupHistoryProvider.overrideWithValue(history),
            dictionaryProvider.overrideWith((_) => loading.future),
            translatorProvider.overrideWithValue(CachedTranslator(native, db)),
          ],
          child: MaterialApp(
            home: ReaderPage(
              book: book,
              defaultStyle: const ReaderStyle(paged: false),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 1));
      await flush(t);
      final before = (await t.runAsync(() => snapshot(db)))!
        ..remove('lookup_history');
      Future<void> tap(String word) async {
        await t.tapAt(textPoint(t, 0, word));
        await flush(t);
      }

      await tap('Tomorrow');
      await tap('Alpha');
      loading.complete(dictionary);
      await flush(t);
      expect(await t.runAsync(history.recent), isEmpty);
      await tap('Tomorrow');
      await tap('Alpha'); // Second tap only dismisses.
      expect((await t.runAsync(history.recent))!.map((r) => r.word), [
        'Tomorrow',
      ]);
      dictionary.entry = null;
      await tap('Missing');
      await tap('Alpha');
      expect((await t.runAsync(history.recent))!.map((r) => r.word), [
        'Missing',
        'Tomorrow',
      ]);
      dictionary.fail = true;
      await tap('Alpha');
      expect(find.text('词典暂时无法打开，请返回书架后重试。'), findsOneWidget);
      expect((await t.runAsync(history.recent))!.map((r) => r.word), [
        'Missing',
        'Tomorrow',
      ]);
      expect(
        (await t.runAsync(() => snapshot(db)))!..remove('lookup_history'),
        before,
      );
      await unmount(t, db);
    },
  );
  testWidgets(
    'history relookup error retries; miss uses existing fallback, without vocabulary writes',
    (t) async {
      final db = ReadingDatabase(NativeDatabase.memory()),
          dictionary = Dictionary()..fail = true;
      final history = LookupHistory(db), native = TestTranslator();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            lookupHistoryProvider.overrideWithValue(history),
            dictionaryProvider.overrideWith((_) async => dictionary),
            translatorProvider.overrideWithValue(CachedTranslator(native, db)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: HistoryLookupSheet(
                record: const LookupRecord('en', 'Missing', 0),
                style: const ReaderStyle(),
              ),
            ),
          ),
        ),
      );
      await flush(t);
      expect(find.text('重试查词'), findsOneWidget);
      expect(await t.runAsync(history.recent), isEmpty);
      dictionary.fail = false;
      await t.tap(find.text('重试查词'));
      await flush(t);
      expect(find.text('词典未收录 · 英译中机器翻译'), findsOneWidget);
      expect(find.text(native.output), findsOneWidget);
      expect((await t.runAsync(history.recent))!.single.word, 'Missing');
      expect(
        (await t.runAsync(
          () => db.customSelect('SELECT * FROM vocabulary').get(),
        ))!,
        isEmpty,
      );
      await unmount(t, db);
    },
  );
  testWidgets(
    'history read failure can retry; narrow large-text dark layout stays usable',
    (t) async {
      t.view.physicalSize = const Size(320, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = ReadingDatabase(NativeDatabase.memory());
      final history = FailingHistory(db);
      final word = List.filled(100, 'a').join();
      await t.runAsync(() => record(history, word));
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            lookupHistoryProvider.overrideWithValue(history),
          ],
          child: MaterialApp(
            theme: const ReadingApp().theme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const HistoryPage(),
          ),
        ),
      );
      await flush(t);
      expect(find.text('查词历史暂时无法读取。'), findsOneWidget);
      history.fail = false;
      await t.tap(find.text('重试'));
      await flush(t);
      expect(find.text(word), findsOneWidget);
      expect(t.takeException(), isNull);
      await unmount(t, db);
    },
  );

  testWidgets(
    'closing history detail before dictionary completes never records a lookup',
    (t) async {
      final db = ReadingDatabase(NativeDatabase.memory()),
          pending = Completer<DictionaryProvider>();
      final history = LookupHistory(db);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            lookupHistoryProvider.overrideWithValue(history),
            dictionaryProvider.overrideWith((_) => pending.future),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: HistoryLookupSheet(
                record: LookupRecord('en', 'Tomorrow', 0),
                style: ReaderStyle(),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pumpWidget(const SizedBox.shrink());
      pending.complete(Dictionary(glossEntry));
      await flush(t);
      expect(await t.runAsync(history.recent), isEmpty);
      expect(t.takeException(), isNull);
      await t.runAsync(db.close);
    },
  );
}

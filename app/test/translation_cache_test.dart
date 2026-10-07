import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/library/library.dart';
import 'package:reading_app/translate/cache_page.dart';
import 'package:reading_app/translate/translator.dart';

import 'translation_test.dart' show TestTranslator;

class FailingClearDatabase extends ReadingDatabase {
  FailingClearDatabase() : super(NativeDatabase.memory());
  bool fail = true;
  @override
  Future<void> clearTranslations() async {
    if (fail) throw StateError('test storage failure');
    await super.clearTranslations();
  }
}

void main() {
  test('clear survives reopen and preserves books, exact position, assets and settings', () async {
    final temp = Directory.systemTemp.createTempSync('reading-clear-cache-');
    final file = File('${temp.path}/reading.sqlite');
    var db = ReadingDatabase(NativeDatabase(file));
    try {
      final id = await db.addBook('Book', TxtParser().parseText('one\ntwo'));
      await db.savePosition(id, 1, location: 'precise position');
      await db.saveStyle(id, '{"size":22}');
      await db.setSetting('readerStyle', '{}');
      await db.customStatement(
        "INSERT INTO book_assets VALUES(?, 'image', X'010203')",
        [id],
      );
      final before =
          (await db.customSelect('SELECT * FROM books').getSingle()).data;
      final native = TestTranslator();
      final service = CachedTranslator(native, db);
      await service.translate('First.', 'en', 'zh-Hans');
      await service.translate('Second.', 'en', 'zh-Hans');
      expect(await service.cacheCount(), 2);
      await service.clearCache();
      expect(await service.cacheCount(), 0);
      await service.translate('First.', 'en', 'zh-Hans');
      expect(native.calls, 3);
      expect(native.downloads, 0);
      await service.clearCache();
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      expect(await db.translationCount(), 0);
      expect(
        (await db.customSelect('SELECT * FROM books').getSingle()).data,
        before,
      );
      expect(await db.asset(id, 'image'), [1, 2, 3]);
      expect(await db.setting('readerStyle'), '{}');
    } finally {
      await db.close();
      temp.deleteSync(recursive: true);
    }
  });

  test('clear excludes old in-flight writes and does not reuse their pending result', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final oldResult = Completer<String>();
    final native = TestTranslator()..pending = oldResult;
    final service = CachedTranslator(native, db);
    final old = service.translate('Sentence.', 'en', 'zh-Hans');
    for (var i = 0; i < 100 && native.calls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(native.calls, 1);
    // Both a later clear and a new request are issued before the old result.
    final cleared = service.clearCache();
    native.pending = null;
    native.output = 'new result';
    final fresh = service.translate('Sentence.', 'en', 'zh-Hans');
    expect(identical(fresh, old), isFalse);
    await cleared;
    expect(await fresh, 'new result');
    oldResult.complete('old result');
    expect(await old, 'old result');
    expect(await service.translate('Sentence.', 'en', 'zh-Hans'), 'new result');
    expect(native.calls, 2);
    await service.clearCache();
    expect(await service.cacheCount(), 0);
  });

  testWidgets(
    'shelf entry, cancel and confirmed clear update count; empty clear is disabled',
    (tester) async {
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.saveTranslation('test-v1', 'en', 'zh-Hans', 'One.', '一。');
      final native = TestTranslator();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            translatorProvider.overrideWithValue(CachedTranslator(native, db)),
            // Library warms the dictionary; this test exercises no word lookup.
            dictionaryProvider.overrideWith((_) => Completer<Never>().future),
          ],
          child: const MaterialApp(home: LibraryPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('翻译缓存'));
      await tester.pumpAndSettle();
      expect(find.text('已缓存 1 条译文'), findsOneWidget);
      await tester.tap(find.text('清除译文缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await db.translationCount(), 1);
      await tester.tap(find.text('清除译文缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(find.text('已缓存 0 条译文'), findsOneWidget);
      expect(find.text('译文缓存已清除'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(native.checks, 0);
      expect(native.downloads, 0);
      expect(native.calls, 0);
    },
  );

  testWidgets('failed clear preserves cache and retry succeeds', (
    tester,
  ) async {
    final db = FailingClearDatabase();
    addTearDown(db.close);
    await db.saveTranslation('e', 'en', 'zh', 'One.', '一。');
    final service = CachedTranslator(TestTranslator(), db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [translatorProvider.overrideWithValue(service)],
        child: const MaterialApp(home: TranslationCachePage()),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('清除译文缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      if (attempt == 0) {
        expect(find.text('清除失败，请重试。'), findsOneWidget);
        expect(await service.cacheCount(), 1);
        db.fail = false;
      }
    }
    expect(find.text('已缓存 0 条译文'), findsOneWidget);
    expect(find.text('译文缓存已清除'), findsOneWidget);
  });
}

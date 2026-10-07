import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/translate/sentence_sheet.dart';
import 'package:reading_app/translate/translator.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class TestTranslator implements Translator {
  @override
  String engine = 'test-v1';
  TranslationStatus availability = TranslationStatus.ready;
  int calls = 0, checks = 0, downloads = 0;
  String output = '明天又是新的一天。';
  bool fail = false;
  Completer<String>? pending;
  @override
  Future<TranslationStatus> status(String from, String to) async {
    checks++;
    return availability;
  }

  @override
  Future<void> prepare(String from, String to) async {
    downloads++;
    availability = TranslationStatus.ready;
  }

  @override
  Future<String> translate(String text, String from, String to) async {
    calls++;
    if (fail) throw const TranslationFailure('translationFailed');
    return pending?.future ?? output;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sentence = 'Tomorrow is another day.';

  test('v3 migration and cache reopen preserve all reader data', () async {
    final temp = Directory.systemTemp.createTempSync('translation-migrate-');
    final file = File('${temp.path}/reading.sqlite');
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
    final content = TxtParser().parseText('one\ntwo').encode();
    old.execute(
      "INSERT INTO books VALUES('old','Old',?,1,'{}','precise location',1,2,3)",
      [content],
    );
    old.execute("INSERT INTO settings VALUES('readerStyle','{}')");
    old.execute("INSERT INTO book_assets VALUES('old','p',X'010203')");
    old.execute('PRAGMA user_version=3');
    final snapshot = old.select('SELECT * FROM books').single.values.toList();
    old.close();
    var db = ReadingDatabase(NativeDatabase(file));
    final native = TestTranslator();
    try {
      expect(
        await CachedTranslator(native, db).translate(sentence, 'en', 'zh-Hans'),
        native.output,
      );
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      native.availability = TranslationStatus.unavailable;
      expect(
        await CachedTranslator(native, db).translate(sentence, 'en', 'zh-Hans'),
        native.output,
      );
      expect(native.calls, 1);
      expect(native.checks, 1);
      expect(
        (await db.customSelect('SELECT * FROM books').getSingle()).data.values
            .toList(),
        snapshot,
      );
      expect(await db.asset('old', 'p'), [1, 2, 3]);
      expect(await db.setting('readerStyle'), '{}');
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        7,
      );
    } finally {
      await db.close();
      temp.deleteSync(recursive: true);
    }
  });

  test('cache isolates exact text, languages and engine; coalesces in-flight requests', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final native = TestTranslator()..pending = Completer<String>();
    final service = CachedTranslator(native, db);
    final first = service.translate(sentence, 'en', 'zh-Hans');
    final second = service.translate(sentence, 'en', 'zh-Hans');
    expect(identical(first, second), isTrue);
    native.pending!.complete(native.output);
    await Future.wait([first, second]);
    native.pending = null;
    await service.translate('$sentence ', 'en', 'zh-Hans');
    await service.translate(sentence, 'en', 'de');
    await service.translate(sentence, 'de', 'zh-Hans');
    native.engine = 'test-v2';
    await service.translate(sentence, 'en', 'zh-Hans');
    expect(native.calls, 5);
  });

  test(
    'failed and empty results never cache; retry and model preparation succeed',
    () async {
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final native = TestTranslator()
        ..availability = TranslationStatus.downloadRequired;
      final service = CachedTranslator(native, db);
      final failure = isA<TranslationFailure>();
      await expectLater(
        service.translate(sentence, 'en', 'zh-Hans'),
        throwsA(failure),
      );
      expect(native.downloads, 0);
      await service.prepare('en', 'zh-Hans');
      native.fail = true;
      await expectLater(
        service.translate(sentence, 'en', 'zh-Hans'),
        throwsA(failure),
      );
      native.fail = false;
      native.output = ' ';
      await expectLater(
        service.translate(sentence, 'en', 'zh-Hans'),
        throwsA(failure),
      );
      native.output = 'x' * 16001;
      await expectLater(
        service.translate(sentence, 'en', 'zh-Hans'),
        throwsA(failure),
      );
      native.output = '成功';
      expect(await service.translate(sentence, 'en', 'zh-Hans'), '成功');
      expect(native.calls, 4);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          service.translate('x' * 4001, 'en', 'zh-Hans'),
          throwsA(failure),
        );
      }
      expect(native.calls, 4);
    },
  );

  test(
    'persistent cache is bounded and can be cleared without deleting books',
    () async {
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await db.addBook('Book', TxtParser().parseText(sentence));
      for (var i = 0; i < 1002; i++) {
        await db.saveTranslation('e', 'en', 'zh', '$i', 'result');
      }
      expect(await db.translation('e', 'en', 'zh', '1'), isNull);
      expect(await db.translation('e', 'en', 'zh', '2'), 'result');
      expect(await db.translation('e', 'en', 'zh', '1001'), 'result');
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM translations')
                .getSingle())
            .read<int>('n'),
        1000,
      );
      await db.clearTranslations();
      expect(await db.translation('e', 'en', 'zh', '1001'), isNull);
      expect(await db.book(id), isNotNull);
    },
  );

  test('method channel maps native failures and passes exact source and language tags', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(PlatformTranslator.channel, null),
    );
    messenger.setMockMethodCallHandler(PlatformTranslator.channel, (
      call,
    ) async {
      expect(call.arguments['from'], 'en');
      expect(call.arguments['to'], 'zh-Hans');
      if (call.method == 'translate') {
        expect(call.arguments['text'], sentence);
        throw PlatformException(code: 'downloadRequired');
      }
      return null;
    });
    await expectLater(
      const PlatformTranslator().translate(sentence, 'en', 'zh-Hans'),
      throwsA(
        isA<TranslationFailure>().having(
          (e) => e.code,
          'code',
          'downloadRequired',
        ),
      ),
    );
  });

  testWidgets(
    'timeout cancels only its native request and ignores a late reply',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final pending = Completer<String>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(PlatformTranslator.channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'translate' ? pending.future : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          PlatformTranslator.channel,
          null,
        ),
      );
      final check = expectLater(
        const PlatformTranslator().translate(sentence, 'en', 'zh-Hans'),
        throwsA(
          isA<TranslationFailure>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      await check;
      expect(calls.map((c) => c.method), ['translate', 'cancel']);
      expect(calls.last.arguments['id'], calls.first.arguments['id']);
      pending.complete('late');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> sheet(
    WidgetTester tester,
    CachedTranslator translator, {
    VoidCallback? copy,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [translatorProvider.overrideWithValue(translator)],
        child: MaterialApp(
          home: Scaffold(
            body: SentenceSheet(sentence: sentence, onCopy: copy ?? () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'missing model requires a tap; copy works; translated result is selectable',
    (tester) async {
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final native = TestTranslator()
        ..engine = 'mlkit-17-v1'
        ..availability = TranslationStatus.downloadRequired;
      var copied = false;
      await sheet(
        tester,
        CachedTranslator(native, db),
        copy: () => copied = true,
      );
      expect(native.downloads, 0);
      await tester.tap(find.text('复制句子'));
      expect(copied, isTrue);
      await tester.tap(find.text('下载语言模型并翻译'));
      await tester.pumpAndSettle();
      expect(native.downloads, 1);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('翻译说明'));
      await tester.pumpAndSettle();
      expect(find.text('离线翻译说明'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, native.output),
        findsOneWidget,
      );
    },
  );

  testWidgets('late translation after sheet disposal is harmless', (
    tester,
  ) async {
    final db = ReadingDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pending = Completer<String>();
    final native = TestTranslator()..pending = pending;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translatorProvider.overrideWithValue(CachedTranslator(native, db)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SentenceSheet(sentence: sentence, onCopy: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete('翻译完成');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

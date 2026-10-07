import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/backup/backup.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/catalog.dart';
import 'package:reading_app/library/library.dart';
import 'package:reading_app/onboarding/reading_guide.dart';
import 'package:reading_app/translate/translator.dart';

class _Catalog extends DictionaryCatalog {
  bool fail = false;
  int calls = 0;
  @override
  Future<List<DictionaryInfo>> inspect() async {
    calls++;
    if (fail) throw StateError('catalog');
    return [
      for (final state in DictionaryAvailability.values)
        DictionaryInfo(
          id: state.name,
          name: state.name,
          source: 'test',
          availability: state,
        ),
    ];
  }
}

class _Translator implements Translator {
  @override
  String get engine => 'apple-v1';
  TranslationStatus current = TranslationStatus.downloadRequired;
  int checks = 0, downloads = 0, translations = 0;
  bool failStatus = false, failDownload = false, staysMissing = false;
  Completer<void>? pending;
  @override
  Future<TranslationStatus> status(String from, String to) async {
    expect((from, to), ('en', 'zh-Hans'));
    checks++;
    if (failStatus) throw const TranslationFailure('unavailable');
    return current;
  }

  @override
  Future<void> prepare(String from, String to) async {
    downloads++;
    if (pending != null) await pending!.future;
    if (failDownload) throw const TranslationFailure('downloadFailed');
    if (!staysMissing) current = TranslationStatus.ready;
  }

  @override
  Future<String> translate(String text, String from, String to) async {
    translations++;
    throw StateError('Guide must not translate');
  }
}

class _Database extends ReadingDatabase {
  _Database() : super(NativeDatabase.memory());
  bool fail = false;
  @override
  Future<void> setSetting(String key, String value) async {
    if (fail) throw StateError('write');
    await super.setSetting(key, value);
  }
}

void main() {
  late _Database db;
  late _Catalog catalog;
  late _Translator translator;
  setUp(() {
    db = _Database();
    catalog = _Catalog();
    translator = _Translator();
  });
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester t, {
    bool shelf = false,
    Size size = const Size(402, 874),
    double scale = 1,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryCatalogProvider.overrideWithValue(catalog),
          translatorProvider.overrideWithValue(
            CachedTranslator(translator, db),
          ),
          dictionaryProvider.overrideWith(
            (_) async => throw StateError('Must not initialize dictionary'),
          ),
        ],
        child: MaterialApp(
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: shelf
              ? const LibraryPage()
              : Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ReadingGuidePage(),
                        ),
                      ),
                      child: const Text('Open guide'),
                    ),
                  ),
                ),
        ),
      ),
    );
    await settle(t);
    if (!shelf) {
      await t.tap(find.text('Open guide'));
      await settle(t);
    }
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(db.close);
    });
  }

  Future<void> reveal(WidgetTester t, Finder target) async {
    await t.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
  }

  test(
    'guide preference roundtrips backup; old settings without it stay valid',
    () async {
      try {
        final old = ReadingBackup.decode(await BackupStore(db).export());
        await db.setSetting(readingGuideKey, '1');
        await db.setSetting('readerStyle', '{"size":23}');
        final saved = ReadingBackup.decode(await BackupStore(db).export());
        await BackupStore(db).restore(old);
        expect(await db.setting(readingGuideKey), isNull);
        await BackupStore(db).restore(saved);
        expect(await db.setting(readingGuideKey), '1');
        expect(await db.setting('readerStyle'), '{"size":23}');
      } finally {
        await db.close();
      }
    },
  );
  testWidgets(
    'shelf invite skips persistently; menu reopens; no work before explicit entry',
    (t) async {
      await mount(t, shelf: true);
      expect(find.byKey(const ValueKey('reading-guide-card')), findsOneWidget);
      expect(catalog.calls, 0);
      expect(translator.checks, 0);
      await t.tap(find.text('暂时跳过'));
      await settle(t);
      expect(find.byKey(const ValueKey('reading-guide-card')), findsNothing);
      expect(await t.runAsync(() => db.setting(readingGuideKey)), '1');
      await t.tap(find.byTooltip('更多'));
      await t.pumpAndSettle();
      await t.tap(find.text('阅读与离线准备'));
      await settle(t);
      expect(find.byType(ReadingGuidePage), findsOneWidget);
      expect(catalog.calls, 1);
      expect(translator.downloads, 0);
      expect(translator.translations, 0);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.byKey(const ValueKey('reading-guide-card')), findsNothing);
    },
  );
  testWidgets(
    'existing dismissed setting hides invite; old settings remain unchanged',
    (t) async {
      await t.runAsync(() async {
        await db.setSetting(readingGuideKey, '1');
        await db.setSetting('readerStyle', '{"size":23}');
      });
      await mount(t, shelf: true);
      expect(find.byKey(const ValueKey('reading-guide-card')), findsNothing);
      expect(await t.runAsync(() => db.setting('readerStyle')), '{"size":23}');
      expect(translator.checks, 0);
    },
  );
  testWidgets('skip write failure stays actionable and retries', (t) async {
    await mount(t, shelf: true);
    db.fail = true;
    await t.tap(find.text('暂时跳过'));
    await settle(t);
    expect(find.textContaining('暂未记住此选择'), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-guide-card')), findsOneWidget);
    db.fail = false;
    await t.tap(find.text('暂时跳过'));
    await settle(t);
    expect(find.byKey(const ValueKey('reading-guide-card')), findsNothing);
  });
  testWidgets(
    'only explicit download prepares; ready checked; finish records dismissal',
    (t) async {
      await mount(t);
      expect(translator.downloads, 0);
      await reveal(t, find.text('下载语言模型'));
      await t.tap(find.text('下载语言模型'));
      await settle(t);
      expect(translator.downloads, 1);
      expect(translator.checks, 2);
      expect(translator.translations, 0);
      expect(find.text('语言模型已就绪 · 可离线翻译'), findsOneWidget);
      await reveal(t, find.text('先去阅读'));
      await t.tap(find.text('先去阅读'));
      await settle(t);
      expect(find.byType(ReadingGuidePage), findsNothing);
      expect(await t.runAsync(() => db.setting(readingGuideKey)), '1');
    },
  );
  testWidgets(
    'state errors retry independently; download failure and incomplete result stay honest',
    (t) async {
      catalog.fail = true;
      translator.failStatus = true;
      await mount(t);
      await reveal(t, find.text('翻译状态未能读取，请刷新重试。'));
      expect(find.text('下载语言模型'), findsNothing);
      catalog.fail = false;
      translator.failStatus = false;
      await t.tap(find.byTooltip('刷新准备状态'));
      await settle(t);
      await reveal(t, find.text('下载语言模型'));
      translator.failDownload = true;
      await t.tap(find.text('下载语言模型'));
      await settle(t);
      expect(find.textContaining('语言模型准备未完成'), findsOneWidget);
      translator.failDownload = false;
      translator.staysMissing = true;
      await t.tap(find.text('下载语言模型'));
      await settle(t);
      expect(find.text('语言模型已就绪 · 可离线翻译'), findsNothing);
      expect(find.textContaining('模型尚未就绪'), findsOneWidget);
    },
  );
  testWidgets(
    'closing during download ignores late completion and never starts translation',
    (t) async {
      translator.pending = Completer<void>();
      await mount(t);
      await reveal(t, find.text('下载语言模型'));
      await t.tap(find.text('下载语言模型'));
      await t.pump();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      translator.pending!.complete();
      await settle(t);
      expect(translator.checks, 1);
      expect(translator.translations, 0);
      expect(find.byType(ReadingGuidePage), findsNothing);
      expect(await t.runAsync(() => db.setting(readingGuideKey)), isNull);
      expect(t.takeException(), isNull);
    },
  );
  for (final status in [
    TranslationStatus.ready,
    TranslationStatus.unsupported,
    TranslationStatus.unavailable,
  ]) {
    testWidgets('status $status is usable on narrow screen with large text', (
      t,
    ) async {
      translator.current = status;
      await mount(t, size: const Size(320, 740), scale: 1.5);
      await reveal(t, find.text('先去阅读'));
      expect(find.text('下载语言模型'), findsNothing);
      expect(translator.downloads, 0);
      expect(t.takeException(), isNull);
    });
  }
}

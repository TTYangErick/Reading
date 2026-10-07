import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/dict/wiktionary.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/translate/translation_content.dart';
import 'package:reading_app/translate/translator.dart';

import 'gloss_language_test.dart' show glossEntry;


import 'selection_test.dart' show renderFor, point;
import 'translation_test.dart' show TestTranslator;

class Dictionary implements DictionaryProvider {
  Dictionary([this.entry]);
  DictionaryEntry? entry;
  bool fail = false;
  final words = <String>[];
  @override
  DictionaryEntry? lookup(String word) {
    words.add(word);
    if (fail) throw StateError('Unavailable');
    return entry;
  }

  @override
  void close() {}
}

class DownloadTranslator extends TestTranslator {
  final prepared = Completer<void>();
  @override
  Future<void> prepare(String from, String to) async {
    downloads++;
    await prepared.future;
    availability = TranslationStatus.ready;
  }
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
  });
  test('only successful absence in both dictionaries is a miss', () {
    final chinese = Dictionary(), english = Dictionary();
    final combined = CombinedDictionary(chinese, english);
    expect(combined.lookup('Xyloword'), isNull);
    english.fail = true;
    expect(() => combined.lookup('Xyloword'), throwsStateError);
    expect(
      () => CombinedDictionary(chinese, null).lookup('X'),
      throwsStateError,
    );
    chinese.entry = glossEntry;
    expect(combined.lookup('Tomorrow')!.meanings, glossEntry.meanings);
    expect(combined.lookup('Tomorrow')!.englishNotice, isNotNull);
    english.fail = false;
    chinese.entry = null;
    english.entry = glossEntry;
    expect(combined.lookup('Tomorrow'), isNotNull);
    chinese.fail = true;
    expect(() => combined.lookup('Tomorrow'), throwsStateError);
    chinese.fail = false;
    english.entry = null;
    chinese.entry = const DictionaryEntry(
      word: 'X',
      phonetic: '',
      fullGloss: '',
      definition: 'An existing definition.',
      meanings: [],
    );
    expect(combined.lookup('X')!.definition, 'An existing definition.');
  });

  late ReadingDatabase db;
  late TestTranslator native;
  late CachedTranslator translator;
  setUp(() {
    db = ReadingDatabase(NativeDatabase.memory());
    native = TestTranslator()..output = '测试用机器译文';
    translator = CachedTranslator(native, db);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  tearDown(() async => db.close());

  // Allows database I/O to finish without waiting for a pending spinner.
  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> panel(WidgetTester t, String text) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [translatorProvider.overrideWithValue(translator)],
        child: MaterialApp(
          home: Scaffold(
            body: TranslationContent(text: text, machineFallback: true),
          ),
        ),
      ),
    );
    await flush(t);
  }

  Future<String> reader(
    WidgetTester t,
    DictionaryProvider dictionary, {
    Size size = const Size(402, 874),
    ReaderStyle style = const ReaderStyle(paged: false),
    Future<DictionaryProvider>? loading,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final id = (await t.runAsync(
      () => db.addBook(
        'Fallback test',
        const BookContent([
          BookBlock('Xyloword Tomorrow Alpha.'),
          BookBlock('Reading position stays here.'),
        ]),
      ),
    ))!;
    final book = (await t.runAsync(() => db.book(id)))!;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dictionaryProvider.overrideWith(
            (_) => loading ?? Future.value(dictionary),
          ),
          translatorProvider.overrideWithValue(translator),
        ],
        child: MaterialApp(
          theme: const ReadingApp().theme(Brightness.light),
          home: ReaderPage(book: book, defaultStyle: style),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    await flush(t);
    return id;
  }

  Offset wordPoint(WidgetTester t, String word) {
    final r = renderFor(t, find.byType(ReaderParagraph).first);
    return point(r, r.text.toPlainText(), word);
  }

  Future<void> word(WidgetTester t, String text) async {
    await t.tapAt(wordPoint(t, text));
    await flush(t);
  }

  Future<void> remove(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  testWidgets(
    'found, other-language-only, definition-only and dictionary errors never translate',
    (t) async {
      final dictionary = Dictionary(glossEntry);
      await reader(
        t,
        dictionary,
        style: const ReaderStyle(
          paged: false,
          glossLanguage: GlossLanguage.enEn,
        ),
      );
      for (final entry in [
        glossEntry,
        const DictionaryEntry(
          word: 'Tomorrow',
          phonetic: '',
          fullGloss: '明天',
          definition: '',
          meanings: ['明天'],
        ),
        const DictionaryEntry(
          word: 'Tomorrow',
          phonetic: '',
          fullGloss: '',
          definition: 'The next day.',
          meanings: [],
        ),
        const DictionaryEntry(
          word: 'Tomorrow',
          phonetic: '',
          fullGloss: '',
          definition: '',
          meanings: [],
        ),
      ]) {
        dictionary.entry = entry;
        await word(t, 'Tomorrow');
        expect(find.byType(TranslationContent), findsNothing);
        await word(t, 'Alpha'); // dismiss only
      }
      dictionary.fail = true;
      await word(t, 'Tomorrow');
      expect(find.text('词典暂时无法打开，请返回书架后重试。'), findsOneWidget);
      expect(native.checks, 0);
      expect(native.calls, 0);
      await remove(t);
    },
  );

  testWidgets('closing while dictionary loads prevents translation startup', (
    t,
  ) async {
    final loading = Completer<DictionaryProvider>();
    await reader(t, Dictionary(), loading: loading.future);
    await word(t, 'Xyloword');
    expect(find.text('正在打开离线词典…'), findsOneWidget);
    await word(t, 'Tomorrow');
    loading.complete(Dictionary());
    await flush(t);
    expect(find.byType(WordBubble), findsNothing);
    expect(native.checks, 0);
    await remove(t);
  });

  for (final variant in [
    (const Size(320, 740), TargetPlatform.android),
    (const Size(402, 874), TargetPlatform.iOS),
    (const Size(1194, 834), TargetPlatform.iOS),
  ]) {
    testWidgets(
      'miss translates, expands, copies, caches and dismisses without changing body at $variant',
      (t) async {
        native.engine = variant.$2 == TargetPlatform.android
            ? 'mlkit-17-v1'
            : 'apple-v1';
        final dictionary = Dictionary();
        final id = await reader(
          t,
          dictionary,
          size: variant.$1,
          style: const ReaderStyle(
            font: 'Literata',
            glossLanguage: GlossLanguage.enEn,
            glossExpansion: GlossExpansion.otherLanguage,
          ),
        );
        // Snapshot all stored reader fields, including content, style and precise position.
        final bodyBefore = (await t.runAsync(() => db.book(id)))!;
        await word(t, 'Xyloword');
        await t.pumpAndSettle();
        expect(find.text('词典未收录 · 英译中机器翻译'), findsOneWidget);
        expect(find.text(native.output), findsOneWidget);
        if (native.engine.startsWith('mlkit')) {
          expect(find.byType(Image), findsOneWidget);
        }
        final bounds = t.getRect(find.byType(WordBubble));
        expect(bounds.left, greaterThanOrEqualTo(12));
        expect(bounds.right, lessThanOrEqualTo(variant.$1.width - 12));
        expect(bounds.contains(wordPoint(t, 'Xyloword')), isFalse);
        await t.tap(find.text(native.output));
        await t.pumpAndSettle();
        expect(find.text('复制单词'), findsOneWidget);
        expect(find.text('收藏生词'), findsNothing);
        expect(find.textContaining('ECDICT'), findsNothing);
        expect(find.textContaining('Wiktionary'), findsNothing);
        expect(native.calls, 1); // expanding must keep the same request/state
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
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await t.ensureVisible(find.text('复制单词'));
        await t.tap(find.text('复制单词'));
        expect(copied, 'Xyloword');
        await t.tap(find.byTooltip('关闭释义'));
        await t.pumpAndSettle();
        native.availability = TranslationStatus.unavailable;
        await word(t, 'Xyloword');
        await t.pumpAndSettle();
        expect(find.text(native.output), findsOneWidget);
        expect(native.calls, 1);
        expect(native.checks, 1);
        await word(t, 'Tomorrow');
        expect(find.byType(WordBubble), findsNothing);
        expect(dictionary.words, ['Xyloword', 'Xyloword']);
        final bodyAfter = (await t.runAsync(() => db.book(id)))!;
        expect(bodyAfter.content.encode(), bodyBefore.content.encode());
        expect(bodyAfter.position, bodyBefore.position);
        expect(bodyAfter.location, bodyBefore.location);
        expect(bodyAfter.style, bodyBefore.style);
        expect(await t.runAsync(() => db.translationCount()), 1);
        expect(
          (await t.runAsync(
            () => db.customSelect('SELECT * FROM vocabulary').get(),
          ))!,
          isEmpty,
        );
        await remove(t);
      },
    );
  }

  testWidgets(
    'download is explicit, failed translation retries without fake cache',
    (t) async {
      native.availability = TranslationStatus.downloadRequired;
      await panel(t, 'Xyloword');
      expect(native.downloads, 0);
      expect(find.text('下载语言模型并翻译'), findsOneWidget);
      native.fail = true;
      await t.tap(find.text('下载语言模型并翻译'));
      await flush(t);
      expect(native.downloads, 1);
      expect(await t.runAsync(() => db.translationCount()), 0);
      expect(find.text('重试翻译'), findsOneWidget);
      native.fail = false;
      await t.tap(find.text('重试翻译'));
      await flush(t);
      expect(find.text(native.output), findsOneWidget);
      expect(await t.runAsync(() => db.translationCount()), 1);
      await remove(t);
    },
  );

  testWidgets(
    'late result cannot overwrite a new source or reopen a dismissed bubble',
    (t) async {
      final old = Completer<String>();
      native.pending = old;
      await panel(t, 'Firstword');
      expect(native.calls, 1);
      native.pending = null;
      await panel(t, 'Secondword');
      expect(find.text(native.output), findsOneWidget);
      old.complete('过时译文');
      await flush(t);
      expect(find.text('过时译文'), findsNothing);
      expect(find.text(native.output), findsOneWidget);
      await remove(t);
      final pending = Completer<String>();
      native.pending = pending;
      await reader(t, Dictionary());
      await word(t, 'Xyloword');
      await word(t, 'Tomorrow');
      pending.complete('关闭后的译文');
      await flush(t);
      expect(find.byType(WordBubble), findsNothing);
      expect(t.takeException(), isNull);
      await remove(t);
    },
  );

  testWidgets(
    'closing during model download does not start a later translation',
    (t) async {
      final downloading = DownloadTranslator()
        ..availability = TranslationStatus.downloadRequired;
      translator = CachedTranslator(downloading, db);
      await panel(t, 'Xyloword');
      await t.tap(find.text('下载语言模型并翻译'));
      await t.pump();
      await remove(t);
      downloading.prepared.complete();
      await flush(t);
      expect(downloading.calls, 0);
      expect(t.takeException(), isNull);
    },
  );
}

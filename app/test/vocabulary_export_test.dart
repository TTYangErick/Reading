import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/vocab/export.dart';
import 'package:reading_app/vocab/vocabulary.dart';
import 'package:reading_app/vocab/vocabulary_page.dart';

import 'vocabulary_test.dart' show draft;

// Independent CSV reader verifies fields survive embedded quotes and newlines.
List<List<String>> readCsv(Uint8List bytes) {
  final text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
  final rows = <List<String>>[], row = <String>[];
  var field = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == ',' || c == '\r')) {
      row.add(field.toString());
      field = StringBuffer();
      if (c == '\r') {
        expect(text[++i], '\n');
        rows.add(List.of(row));
        row.clear();
      }
    } else {
      field.write(c);
    }
  }
  expect(quoted, isFalse);
  expect(row, isEmpty);
  return rows;
}

class SavePicker extends FilePickerPlatform {
  final calls = <({String name, Uint8List bytes, String mime})>[];
  Future<Uri?> Function() result = () async =>
      Uri.parse('content://saved/vocabulary.csv');
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    calls.add((name: fileName, bytes: bytes, mime: mimeType));
    return result();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'CSV roundtrip preserves Unicode, multiline attribution, IDs and UTC dates',
    () {
      final value = VocabularyDraft(
        word: 'café',
        lemma: 'café',
        gloss: '名词, 咖啡\r\n"饮品"\n☕',
        lang: 'en',
        dictId: 'wiktionary',
        source: 'Wiktionary contributors · Kaikki',
        sourceUrl: 'https://en.wiktionary.org/wiki/caf%C3%A9#English',
        license: 'CC-BY-SA-4.0',
        bookId: 'deleted-book',
        bookTitle: '书名, "一"',
        sentence: 'A "café", here.\nNext line.',
        location: '{"version":1,"cell":"2-3"}',
      );
      final bytes = const CsvVocabExporter().encode([
        VocabularyItem('uuid', value, 0, 1000),
      ]);
      expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
      final rows = readCsv(bytes);
      expect(rows, hasLength(2));
      expect(rows.first, [
        'word',
        'lemma',
        'gloss',
        'sentence',
        'book_title',
        'created_at',
        'lang',
        'dict_id',
        'source',
        'source_url',
        'license',
        'id',
        'book_id',
        'location',
        'updated_at',
      ]);
      expect(rows[1], [
        value.word,
        value.lemma,
        value.gloss,
        value.sentence,
        value.bookTitle,
        '1970-01-01T00:00:00.000Z',
        value.lang,
        value.dictId,
        value.source,
        value.sourceUrl,
        value.license,
        'uuid',
        'deleted-book',
        value.location,
        '1970-01-01T00:00:01.000Z',
      ]);
      expect(readCsv(const CsvVocabExporter().encode([])), hasLength(1));
    },
  );

  test('spreadsheet formulas and leading control characters become text', () {
    for (final text in [
      '=1+2',
      '+1',
      '-1',
      '@SUM(A1)',
      '  =cmd()',
      '\t=1',
      '\rtext',
      '\ntext',
      '＝1',
      '＋1',
      '－1',
      '＠x',
    ]) {
      final value = VocabularyDraft(
        word: text,
        lemma: text,
        gloss: text,
        lang: text,
        dictId: text,
        source: text,
        sourceUrl: text,
        license: text,
        bookId: text,
        bookTitle: text,
        sentence: text,
        location: text,
      );
      final row = readCsv(
        const CsvVocabExporter().encode([VocabularyItem(text, value, 0, 0)]),
      )[1];
      for (final index in [0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13]) {
        expect(row[index], "'$text");
      }
      expect(value.word, text);
    }
  });

  for (final size in [
    const Size(320, 740),
    const Size(402, 874),
    const Size(1194, 834),
  ]) {
    testWidgets(
      'export filtered/all order, cancellation, retry and isolation at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previous = FilePickerPlatform.instance, picker = SavePicker();
        FilePickerPlatform.instance = picker;
        addTearDown(() => FilePickerPlatform.instance = previous);
        final db = ReadingDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.addVocabulary(
          draft(book: 'Book A', word: 'Apple', location: 'a'),
        );
        await db.addVocabulary(
          draft(book: 'Book B', word: 'Apricot', location: 'b'),
        );
        await db.addVocabulary(
          draft(book: 'Book A', word: 'Banana', location: 'c'),
        );
        await db.customStatement(
          "UPDATE vocabulary SET created_at=CASE word WHEN 'Apple' THEN 1 WHEN 'Apricot' THEN 2 ELSE 3 END",
        );
        final bookId = await db.addBook(
          'Original book',
          const BookContent([BookBlock('Original text')]),
        );
        await db.customStatement(
          'UPDATE books SET position=7,location=? WHERE id=?',
          ['precise', bookId],
        );
        await db.customStatement(
          "INSERT INTO book_assets VALUES(?, 'image', X'010203')",
          [bookId],
        );
        await db.customStatement(
          "INSERT INTO settings VALUES('readerStyle','{}')",
        );
        await db.customStatement(
          "INSERT INTO translations VALUES('native','en','zh','source','译文')",
        );
        Future<Map<String, List<Map<String, Object?>>>> records() async => {
          for (final table in [
            'books',
            'book_assets',
            'settings',
            'translations',
            'vocabulary',
          ])
            table:
                (await db
                        .customSelect('SELECT * FROM $table ORDER BY rowid')
                        .get())
                    .map((r) => r.data)
                    .toList(),
        };
        final before = await records();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: const VocabularyPage(),
              theme: ThemeData(
                platform: size.width == 320
                    ? TargetPlatform.android
                    : TargetPlatform.iOS,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> open() async {
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('导出 CSV'));
          await tester.pumpAndSettle();
        }

        await tester.enterText(
          find.byKey(const ValueKey('vocabulary-search')),
          'Ap',
        );
        await tester.tap(find.byKey(const ValueKey('vocabulary-book')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Book A').last);
        await tester.pumpAndSettle();
        await open();
        expect(find.text('当前列表（1 条）'), findsOneWidget);
        expect(find.text('全部生词（3 条）'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(picker.calls, isEmpty);
        await open();
        await tester.tap(find.text('当前列表（1 条）'));
        await tester.pumpAndSettle();
        expect(readCsv(picker.calls.last.bytes).skip(1).map((r) => r[0]), [
          'Apple',
        ]);
        expect(
          picker.calls.last.name,
          matches(r'^Reading-vocabulary-\d+\.csv$'),
        );
        expect(picker.calls.last.mime, 'text/csv');
        expect(find.text('已导出 1 条生词'), findsOneWidget);
        await tester.tap(find.byTooltip('最新收藏在前'));
        await tester.pumpAndSettle();
        await open();
        await tester.tap(find.text('全部生词（3 条）'));
        await tester.pumpAndSettle();
        expect(readCsv(picker.calls.last.bytes).skip(1).map((r) => r[0]), [
          'Apple',
          'Apricot',
          'Banana',
        ]);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        picker.result = () async => null;
        await open();
        await tester.tap(find.text('当前列表（1 条）'));
        await tester.pumpAndSettle();
        expect(find.textContaining('已导出'), findsNothing);
        picker.result = () async => throw StateError('disk failure');
        await open();
        await tester.tap(find.text('当前列表（1 条）'));
        await tester.pumpAndSettle();
        expect(find.text('导出失败，请重试。'), findsOneWidget);
        final pending = Completer<Uri?>();
        picker.result = () => pending.future;
        await open();
        await tester.tap(find.text('当前列表（1 条）'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == '正在导出',
                ),
              )
              .onPressed,
          isNull,
        );
        pending.complete(Uri.file('/saved.csv'));
        await tester.pumpAndSettle();
        expect(find.text('已导出 1 条生词'), findsOneWidget);
        expect(await records(), before);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'Ap',
        );
        await tester.enterText(
          find.byKey(const ValueKey('vocabulary-search')),
          'no match',
        );
        await open();
        expect(
          tester
              .widget<SimpleDialogOption>(
                find.ancestor(
                  of: find.text('当前列表（0 条）'),
                  matching: find.byType(SimpleDialogOption),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'empty and failed loads disable export; disposal while saving is safe',
    (tester) async {
      final previous = FilePickerPlatform.instance, picker = SavePicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final db = ReadingDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: VocabularyPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '导出 CSV',
              ),
            )
            .onPressed,
        isNull,
      );
      await db.addVocabulary(draft());
      await tester.tap(find.byTooltip('刷新生词本'));
      await tester.pumpAndSettle();
      final pending = Completer<Uri?>();
      picker.result = () => pending.future;
      await tester.tap(find.byTooltip('导出 CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('当前列表（1 条）'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.completeError(StateError('cancelled after page closed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await db.customStatement('DROP TABLE vocabulary');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: VocabularyPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('生词本暂时无法读取'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '导出 CSV',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/backup/backup.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/bookmarks/bookmark.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/startup/preferences.dart';
import 'package:reading_app/orientation/orientation.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/translate/translator.dart';
import 'package:reading_app/vocab/vocabulary.dart';

Future<String> seed(ReadingDatabase db) async {
  final id = await db.addBook(
    'Book 😀',
    BookContent(
      [
        const BookBlock('Hello café 😀.'),
        const BookBlock('caption', image: 'OPS/img.png'),
        const BookBlock(
          '',
          rows: [
            ['a', 'b'],
            ['c', 'd'],
          ],
        ),
      ],
      supplementaryDocuments: {
        'notes.xhtml': [const BookBlock('A note.')],
      },
      authors: const ['Jane Austen', 'Coauthor'],
      cover: 'OPS/img.png',
      assets: {
        'OPS/img.png': Uint8List.fromList([137, 80, 78, 71, 0, 255]),
      },
      anchors: {
        'notes.xhtml#n': const BookPosition(0, document: 'notes.xhtml'),
      },
      links: [
        const BookLink(
          block: 0,
          start: 0,
          end: 5,
          href: 'notes.xhtml#n',
          kind: BookLinkKind.noteref,
          status: BookLinkStatus.resolved,
          target: BookPosition(0, document: 'notes.xhtml'),
        ),
      ],
    ),
  );
  await db.savePosition(
    id,
    2,
    location: const PageAnchor(
      BookPosition(2),
      part: PagePart.tableRow,
      row: 1,
    ).encode(),
  );
  await db.saveStyle(
    id,
    const ReaderStyle(glossLanguage: GlossLanguage.enEn).encode(),
  );
  await db.setSetting('readerStyle', const ReaderStyle(size: 23).encode());
  await db.addBookmark(
    id,
    const PageAnchor(BookPosition(1, offset: 4), part: PagePart.caption),
  );
  await db.addBookmark(
    id,
    const PageAnchor(BookPosition(0, offset: 2, document: 'notes.xhtml')),
  );
  await db.saveTranslation('apple-v1', 'en', 'zh-Hans', 'Hello.', '你好。');
  await db.addVocabulary(
    const VocabularyDraft(
      word: 'lost',
      lemma: 'lose',
      gloss: '失去',
      lang: 'en',
      dictId: 'ecdict',
      source: 'ECDICT',
      sourceUrl: 'https://example.test',
      license: 'MIT',
      bookId: 'deleted',
      bookTitle: 'Deleted book',
      sentence: 'A lost book.',
      location: '{"version":1,"position":{"block":0,"offset":2}}',
    ),
  );
  return id;
}

Future<Map<String, List<List<Object?>>>> snapshot(ReadingDatabase db) async => {
  for (final e in backupColumns.entries)
    e.key:
        (await db
                .customSelect(
                  'SELECT ${e.value.join(',')} FROM ${e.key} ORDER BY rowid',
                )
                .get())
            .map((r) => e.value.map((c) => r.data[c]).toList())
            .toList(),
};
Map<String, dynamic> payload(Uint8List b) =>
    jsonDecode(utf8.decode(b.sublist(20))) as Map<String, dynamic>;
Uint8List forge(Map<String, dynamic> d) {
  final raw = utf8.encode(jsonEncode(d));
  final out = Uint8List(raw.length + 20)
    ..setRange(0, 8, [82, 69, 65, 68, 73, 78, 71, 10])
    ..setRange(20, raw.length + 20, raw);
  ByteData.sublistView(out)
    ..setUint32(8, 1)
    ..setUint32(12, raw.length)
    ..setUint32(16, getCrc32(raw));
  return out;
}

class PendingTranslator implements Translator {
  final started = Completer<void>(), response = Completer<String>();
  @override
  String get engine => 'test';
  @override
  Future<TranslationStatus> status(String f, String t) async =>
      TranslationStatus.ready;
  @override
  Future<void> prepare(String f, String t) async {}
  @override
  Future<String> translate(String s, String f, String t) {
    started.complete();
    return response.future;
  }
}

final class MemoryFile extends PlatformFile {
  MemoryFile(this.bytes, {this.reported});
  final Uint8List bytes;
  final int? reported;
  bool read = false;
  @override
  String get name => 'backup.readingbackup';
  @override
  Uri get uri => Uri.parse('content://backup/file');
  @override
  Never get xFile => throw UnsupportedError('stream only');
  @override
  int? lengthSync() => reported;
  @override
  Future<int?> length() async => reported;
  @override
  Future<Uint8List> readAsBytes() async =>
      throw UnsupportedError('stream only');
  @override
  Stream<Uint8List> readAsByteStream() async* {
    read = true;
    yield bytes;
  }
}

class BackupPicker extends FilePickerPlatform {
  PlatformFile? selection;
  Uint8List? saved;
  bool cancelSave = false, failSave = false;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selection;
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
  }) async {
    saved = bytes;
    expect(fileName, endsWith('.readingbackup'));
    if (failSave) throw StateError('save');
    return cancelSave ? null : Uri.parse('content://saved/backup');
  }
}

Future<void> until(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  expect(ready(), true);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all table roundtrip, legacy content, orphan vocabulary, reopen and empty backup', () async {
    final source = ReadingDatabase(NativeDatabase.memory()),
        dir = await Directory.systemTemp.createTemp('reading-backup-');
    final file = File('${dir.path}/restored.sqlite');
    var target = ReadingDatabase(NativeDatabase(file));
    try {
      final id = await seed(source),
          legacy = await source.addBook(
            'legacy',
            const BookContent([BookBlock('old text')]),
          );
      await source.customStatement('UPDATE books SET content=? WHERE id=?', [
        '{"blocks":[{"text":"old text"}]}',
        legacy,
      ]);
      final before = await snapshot(source),
          bytes = await BackupStore(source).export();
      expect(await snapshot(source), before);
      final backup = ReadingBackup.decode(bytes);
      expect(backup.count('books'), 2);
      expect(() => backup.rows['books']!.clear(), throwsUnsupportedError);
      expect(
        () => (backup.rows['book_assets']!.first[2] as Uint8List)[0] = 1,
        throwsUnsupportedError,
      );
      await target.addBook('replace', const BookContent([BookBlock('old')]));
      await BackupStore(target).restore(backup);
      expect(await snapshot(target), before);
      await target.close();
      target = ReadingDatabase(NativeDatabase(file));
      expect(await snapshot(target), before);
      final book = (await target.book(id))!;
      expect(book.content.authors, ['Jane Austen', 'Coauthor']);
      expect(book.content.cover, 'OPS/img.png');
      expect(book.content.supplementaryDocuments, contains('notes.xhtml'));
      expect(PageAnchor.decode(book.location)!.row, 1);
      expect(
        (await target.bookmarks(id)).every((b) => b.resolve(book) != null),
        true,
      );
      final empty = ReadingDatabase(NativeDatabase.memory());
      await BackupStore(target)
          .restore(ReadingBackup.decode(await BackupStore(empty).export()));
      expect((await snapshot(target)).values.every((r) => r.isEmpty), true);
      await empty.close();
    } finally {
      await source.close();
      await target.close();
      await dir.delete(recursive: true);
    }
  });
  test('corruption, future versions, duplicates, bad rows, missing assets and paths rejected', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    try {
      await seed(db);
      final bytes = await BackupStore(db).export(), before = await snapshot(db);
      expect(
        () => ReadingBackup.decode(
          Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
        ),
        throwsFormatException,
      );
      final corrupt = Uint8List.fromList(bytes);
      corrupt[30] ^= 1;
      expect(() => ReadingBackup.decode(corrupt), throwsFormatException);
      final future = Uint8List.fromList(bytes);
      ByteData.sublistView(future).setUint32(8, 2);
      expect(() => ReadingBackup.decode(future), throwsFormatException);
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['schema'] = 999,
        (d) => d['tables'].remove('settings'),
        (d) => d['tables']['books'][0][3] = -1,
        (d) => d['tables']['books'][0][2] = '{"blocks":[{"text":42}]}',
        (d) => d['tables']['books'].add(d['tables']['books'][0]),
        (d) => d['tables']['book_assets'].clear(),
        (d) => d['tables']['book_assets'][0][1] = '../escape',
        (d) => d['tables']['book_assets'][0][2] = '!!',
        (d) => d['tables']['bookmarks'][0][1] = 'missing',
        (d) => d['tables']['bookmarks'].add(
          [...d['tables']['bookmarks'][0]]..[0] = 'another',
        ),
        (d) => d['tables']['vocabulary'].add(
          [...d['tables']['vocabulary'][0]]..[0] = 'another',
        ),
        (d) => d['tables']['books'][0][2] = '[' * 40 + ']' * 40,
      ]) {
        final data = payload(bytes);
        change(data);
        expect(() => ReadingBackup.decode(forge(data)), throwsFormatException);
      }
      expect(await snapshot(db), before);
    } finally {
      await db.close();
    }
  });
  test(
    'stream, record and content budgets prevent oversized import/export',
    () async {
      await expectLater(
        ReadingBackup.readStream(
          Stream.fromIterable([
            Uint8List(ReadingBackup.maxFileBytes),
            Uint8List(1),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        await ReadingBackup.readStream(
          Stream.value(Uint8List.fromList([1, 2])),
        ),
        [1, 2],
      );
      final db = ReadingDatabase(NativeDatabase.memory());
      try {
        final data = payload(await BackupStore(db).export());
        data['tables']['settings'] = List.generate(
          50001,
          (i) => ['$i', 'value'],
        );
        expect(() => ReadingBackup.decode(forge(data)), throwsFormatException);
        data['tables']['settings'] = [
          ['large', 'x' * (ReadingBackup.maxDataBytes + 1)],
        ];
        expect(() => ReadingBackup.decode(forge(data)), throwsFormatException);
        await db.customStatement('INSERT INTO settings VALUES(?,?)', [
          'huge',
          'x' * (ReadingBackup.maxDataBytes + 1),
        ]);
        await expectLater(BackupStore(db).export(), throwsFormatException);
      } finally {
        await db.close();
      }
    },
  );
  test('SQL failure after partial insert rolls back all business tables and retry succeeds', () async {
    final source = ReadingDatabase(NativeDatabase.memory()),
        target = ReadingDatabase(NativeDatabase.memory());
    try {
      await seed(source);
      await seed(target);
      await target.setSetting('sentinel', 'keep');
      final before = await snapshot(target),
          backup = ReadingBackup.decode(await BackupStore(source).export());
      await target.customStatement(
        "CREATE TRIGGER reject_backup BEFORE INSERT ON bookmarks BEGIN SELECT RAISE(ABORT,'failure'); END",
      );
      await expectLater(BackupStore(target).restore(backup), throwsA(anything));
      expect(await snapshot(target), before);
      await target.customStatement('DROP TRIGGER reject_backup');
      await BackupStore(target).restore(backup);
      expect(await snapshot(target), await snapshot(source));
    } finally {
      await source.close();
      await target.close();
    }
  });
  test('late native translation cannot repopulate cache after successful or failed restore', () async {
    final db = ReadingDatabase(NativeDatabase.memory());
    try {
      await seed(db);
      final backup = ReadingBackup.decode(await BackupStore(db).export());
      for (final fails in [false, true]) {
        final native = PendingTranslator(),
            translator = CachedTranslator(PendingTranslator(), db);
        final current = CachedTranslator(native, db),
            future = current.translate('unseen', 'en', 'zh-Hans');
        await native.started.future;
        final before = await snapshot(db);
        final restore = current.replaceCache(
          () => fails
              ? Future.error(StateError('failure'))
              : BackupStore(db).restore(backup),
        );
        if (fails) {
          await expectLater(restore, throwsStateError);
        } else {
          await restore;
        }
        native.response.complete('旧请求');
        await future;
        expect(await snapshot(db), before);
        expect(await translator.cacheCount(), 1);
      }
    } finally {
      await db.close();
    }
  });
  test('EPUB2/3 parsed content, footnotes, assets and links survive backup unchanged', () async {
    final source = ReadingDatabase(NativeDatabase.memory());
    final target = ReadingDatabase(NativeDatabase.memory());
    try {
      for (final name in ['footnotes-epub2.epub', 'footnotes-epub3.epub']) {
        await source.addBook(
          name,
          EpubParser().parse(
            await File('test/fixtures/epub/$name').readAsBytes(),
          ),
        );
      }
      final before = await snapshot(source);
      await BackupStore(target)
          .restore(ReadingBackup.decode(await BackupStore(source).export()));
      expect(await snapshot(target), before);
      for (final book in await target.books()) {
        expect(book.content.links, isNotEmpty);
      }
    } finally {
      await source.close();
      await target.close();
    }
  });

  for (final size in [
    const Size(320, 740),
    const Size(402, 874),
    const Size(1194, 834),
  ]) {
    testWidgets(
      'save, cancel, failure, preview, confirm and refresh at $size',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final db = ReadingDatabase(NativeDatabase.memory()),
            source = ReadingDatabase(NativeDatabase.memory());
        final previous = FilePickerPlatform.instance, picker = BackupPicker();
        FilePickerPlatform.instance = picker;
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWithValue(db)],
        );
        addTearDown(() async {
          FilePickerPlatform.instance = previous;
          container.dispose();
          await db.close();
          await source.close();
        });
        await t.runAsync(() async {
          await seed(source);
          await source.setSetting(resumeReadingKey, '1');
          await source.setSetting(readingOrientationKey, 'landscape');
          await db.addBook('Current', const BookContent([BookBlock('text')]));
          expect(await container.read(resumeReadingProvider.future), false);
          expect(
            await container.read(readingOrientationProvider.future),
            ReadingOrientation.system,
          );
          picker.selection = MemoryFile(await BackupStore(source).export());
        });
        final before = await t.runAsync(() => snapshot(db));
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ReadingApp(),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('更多'));
        await t.pumpAndSettle();
        await t.tap(find.text('备份与恢复'));
        await t.pumpAndSettle();
        Future<void> start(String key) async {
          await t.tap(find.byKey(ValueKey(key)));
          await t.pump();
        }

        await start('backup-export');
        await until(t, () => find.text('备份已保存。').evaluate().isNotEmpty);
        expect(ReadingBackup.decode(picker.saved!).count('books'), 1);
        expect(await t.runAsync(() => snapshot(db)), before);
        picker.cancelSave = true;
        await start('backup-export');
        await until(t, () => find.text('已取消保存，当前数据未改变。').evaluate().isNotEmpty);
        picker.failSave = true;
        await start('backup-export');
        await until(
          t,
          () => find.textContaining('备份未保存成功').evaluate().isNotEmpty,
        );
        await start('backup-import');
        await until(t, () => find.text('用此备份替换当前数据？').evaluate().isNotEmpty);
        expect(find.textContaining('1 本书 · 1 个图片资源'), findsOneWidget);
        expect(await t.runAsync(() => snapshot(db)), before);
        await t.tap(find.text('取消'));
        await t.pumpAndSettle();
        expect(await t.runAsync(() => snapshot(db)), before);
        final valid = picker.selection;
        picker.selection = MemoryFile(Uint8List(4));
        await start('backup-import');
        await until(
          t,
          () => find.text('这不是 Reading 备份文件。').evaluate().isNotEmpty,
        );
        expect(await t.runAsync(() => snapshot(db)), before);
        picker.selection = null;
        await start('backup-import');
        await until(t, () => find.text('已取消，当前数据未改变。').evaluate().isNotEmpty);
        final oversized = MemoryFile(
          Uint8List(1),
          reported: ReadingBackup.maxFileBytes + 1,
        );
        picker.selection = oversized;
        await start('backup-import');
        await until(t, () => find.text('备份超过 64 MB 上限。').evaluate().isNotEmpty);
        expect(oversized.read, false);
        picker.selection = valid;
        await t.runAsync(
          () => db.customStatement(
            "CREATE TRIGGER reject_backup BEFORE INSERT ON bookmarks BEGIN SELECT RAISE(ABORT,'failure'); END",
          ),
        );
        await start('backup-import');
        await until(t, () => find.text('替换并恢复').evaluate().isNotEmpty);
        await t.tap(find.text('替换并恢复'));
        await t.pump();
        await until(
          t,
          () => find.textContaining('恢复失败，当前数据未改变').evaluate().isNotEmpty,
        );
        expect(await t.runAsync(() => snapshot(db)), before);
        await t.runAsync(
          () => db.customStatement('DROP TRIGGER reject_backup'),
        );
        await start('backup-import');
        await until(t, () => find.text('替换并恢复').evaluate().isNotEmpty);
        await t.tap(find.text('替换并恢复'));
        await t.pump();
        await until(
          t,
          () => find.textContaining('已恢复 1 本书').evaluate().isNotEmpty,
        );
        expect(
          await t.runAsync(() => snapshot(db)),
          await t.runAsync(() => snapshot(source)),
        );
        expect((await container.read(globalStyleProvider.future)).size, 23);
        expect(await container.read(resumeReadingProvider.future), true);
        expect(
          await container.read(readingOrientationProvider.future),
          ReadingOrientation.landscape,
        );
        expect(find.byType(ReaderPage), findsNothing);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        expect(find.text('Book 😀'), findsWidgets);
        expect(find.byType(ReaderPage), findsNothing);
        expect(find.text('Current'), findsNothing);
        expect(t.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(
        size.width == 320 ? TargetPlatform.android : TargetPlatform.iOS,
      ),
    );
  }
}

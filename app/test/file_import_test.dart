import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/bubble.dart';

// Replace only the native selection dialog. File I/O, compute/TXT parsing,
// SQLite writes, navigation, and the reader use their production code.
class _Picker extends FilePickerPlatform {
  PlatformFile? selection;
  Object? error;
  int calls = 0;

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
  }) async {
    calls++;
    expect(type, FileType.custom);
    expect(allowedExtensions, ['txt', 'epub']);
    if (error case final failure?) throw failure;
    return selection;
  }
}

final class _PickedFile extends PlatformFile {
  final File file;
  @override
  final String name;
  final bool contentUri;
  final int? reportedLength;
  bool read = false;

  _PickedFile(
    String fixture, {
    required this.name,
    this.contentUri = false,
    this.reportedLength,
  }) : file = File('test/fixtures/txt/$fixture');

  // Android document providers can return a content URI with no local path.
  @override
  Uri get uri =>
      contentUri ? Uri.parse('content://reading-test/file') : file.uri;
  @override
  Never get xFile =>
      throw UnsupportedError('Import must use PlatformFile reads');
  @override
  int? lengthSync() => reportedLength;
  @override
  Future<int?> length() async => reportedLength;
  @override
  Future<Uint8List> readAsBytes() async {
    read = true;
    return file.readAsBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    // File I/O and compute run outside the fake widget-test clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: 'Import did not reach its expected UI state');
  await tester.pumpAndSettle();
}

Future<void> _chooseFile(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('add-book')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('导入 EPUB / TXT'));
  await tester.pump();
}

Future<void> _tapReaderControl(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 2 && target.evaluate().isEmpty; i++) {
    await tester.tap(find.byKey(const ValueKey('page-label')));
    await tester.pumpAndSettle();
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  late ReadingDatabase database;
  late ProviderContainer container;
  late _Picker picker;
  late FilePickerPlatform previousPicker;

  setUp(() {
    previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker = _Picker();
    database = ReadingDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        dictionaryProvider.overrideWith((ref) async {
          final dictionary = SqliteDictionary.open(
            'assets/dictionaries/ecdict.sqlite',
          );
          ref.onDispose(dictionary.close);
          return dictionary;
        }),
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });

  tearDown(() async {
    FilePickerPlatform.instance = previousPicker;
    container.dispose();
    await database.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReadingApp(),
      ),
    );
    await _until(
      tester,
      () => find.byKey(const ValueKey('add-book')).evaluate().isNotEmpty,
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  for (final version in [2, 3]) {
    testWidgets(
      'EPUB $version import, image/table, word lookup, TOC and reopen',
      (tester) async {
        tester.view.physicalSize = version == 2
            ? const Size(430, 1000)
            : const Size(1180, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        picker.selection = _PickedFile(
          '../epub/lesson-epub$version.epub',
          name: 'lesson.EPUB',
        );
        await mount(tester);
        await _chooseFile(tester);
        await _until(
          tester,
          () => find.byType(ReaderPage).evaluate().isNotEmpty,
        );
        final saved = await tester.runAsync(() => database.books());
        expect(saved!.single.title, 'Reading EPUB $version sample');
        expect(saved.single.content.format, 'epub');
        await _until(tester, () => find.byType(Image).evaluate().isNotEmpty);
        expect(find.text('图片无法显示'), findsNothing);
        expect(tester.takeException(), isNull);
        await _tapReaderControl(tester, find.byTooltip('目录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Word table'));
        await tester.pumpAndSettle();
        final rich = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ReaderParagraph && w.text == 'Tomorrow',
          ),
          matching: find.byType(RichText),
        );
        final render = tester.renderObject<RenderParagraph>(rich);
        final wordBox = render
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 8),
            )
            .first
            .toRect();
        await tester.tapAt(render.localToGlobal(wordBox.center));
        await tester.pumpAndSettle();
        expect(find.byType(WordBubble), findsOneWidget);
        expect(find.text('明天；未来'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(WordBubble), findsOneWidget);
        await _tapReaderControl(tester, find.byTooltip('目录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second lesson'));
        await tester.pumpAndSettle();
        expect(find.text('Chapter Two', findRichText: true), findsOneWidget);
        await _tapReaderControl(
          tester,
          find.byKey(const ValueKey('back-library')),
        );
        await _until(tester, () => find.byType(ReaderPage).evaluate().isEmpty);
        final book = await tester.runAsync(
          () => database.book(saved.single.id),
        );
        expect(book!.position, book.content.chapters.last.block);
        await tester.tap(find.text(book.title).first);
        await _until(
          tester,
          () => find.byType(ReaderPage).evaluate().isNotEmpty,
        );
        expect(find.text('Chapter Two', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      },
    );
  }

  for (final encoding in ['UTF-8', 'GBK']) {
    testWidgets('$encoding file → persisted book → reader → shelf', (
      tester,
    ) async {
      final picked = _PickedFile(
        encoding == 'UTF-8' ? 'utf8-bom.txt' : 'gbk.txt',
        name: '$encoding 教材.TXT',
        contentUri: encoding == 'GBK',
      );
      picker.selection = picked;
      await mount(tester);
      await _chooseFile(tester);
      await _until(tester, () => find.byType(ReaderPage).evaluate().isNotEmpty);
      final book = (await database.books()).single;
      expect(book.title, '$encoding 教材');
      expect(book.content.encoding, encoding);
      expect(book.content.blocks.map((block) => block.text), [
        'Chapter 1',
        'Tomorrow is another day. The children went to school.',
        '第二章 新的开始',
        '中文与 English。',
      ]);
      expect(book.content.blocks.where((block) => block.heading).length, 2);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is ReaderParagraph && w.text == 'Chapter 1',
        ),
        findsOneWidget,
      );
      // The next chapter no longer shares the first page's remaining space.
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('中文与 English。', findRichText: true), findsOneWidget);
      expect(picked.read, isTrue);
      if (encoding == 'GBK') expect(picked.path, isNull);
      await _tapReaderControl(
        tester,
        find.byKey(const ValueKey('back-library')),
      );
      await tester.pumpAndSettle();
      expect(find.text('$encoding 教材'), findsWidgets);
      expect(picker.calls, 1);
      await unmount(tester);
    });
  }

  testWidgets('cancel picker leaves shelf empty and allows another import', (
    tester,
  ) async {
    await mount(tester);
    await _chooseFile(tester);
    await tester.pumpAndSettle();
    expect(await database.books(), isEmpty);
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('add-book')))
          .onPressed,
      isNotNull,
    );
    picker.selection = _PickedFile('utf8-bom.txt', name: '重试.txt');
    await _chooseFile(tester);
    await _until(tester, () => find.byType(ReaderPage).evaluate().isNotEmpty);
    expect((await database.books()).single.title, '重试');
    expect(picker.calls, 2);
    await unmount(tester);
  });

  for (final scenario in [
    'empty',
    'binary',
    'unreadable',
    'oversized',
    'picker-error',
  ]) {
    testWidgets(
      '$scenario reports failure without saving a book; retry succeeds',
      (tester) async {
        final picked = _PickedFile(
          switch (scenario) {
            'empty' => 'empty.txt',
            'binary' => 'binary.txt',
            'unreadable' => 'does-not-exist.txt',
            _ => 'utf8-bom.txt',
          },
          name: '错误样本.txt',
          reportedLength: scenario == 'oversized' ? 20 * 1024 * 1024 + 1 : null,
        );
        picker.selection = picked;
        if (scenario == 'picker-error') {
          picker.error = PlatformException(code: 'unavailable');
        }
        await mount(tester);
        await _chooseFile(tester);
        final expected = switch (scenario) {
          'empty' => '文本是空的，请加入正文后再导入。',
          'binary' => '这个文件不像普通文本，请另存为 UTF-8 或 GBK。',
          'oversized' => '文本超过 20 MB，请先拆分后导入。',
          _ => '导入失败，请确认文件可以读取后重试。',
        };
        await _until(tester, () => find.text(expected).evaluate().isNotEmpty);
        expect(await database.books(), isEmpty);
        expect(find.byType(ReaderPage), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (scenario == 'oversized') expect(picked.read, isFalse);
        picker.error = null;
        picker.selection = _PickedFile(
          'gbk.txt',
          name: '恢复导入.txt',
          contentUri: true,
        );
        await _chooseFile(tester);
        await _until(
          tester,
          () => find.byType(ReaderPage).evaluate().isNotEmpty,
        );
        expect((await database.books()).single.title, '恢复导入');
        expect(picker.calls, 2);
        await unmount(tester);
      },
    );
  }
}

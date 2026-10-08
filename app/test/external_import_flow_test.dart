import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/backup/backup_page.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/imports/inbox.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/reader.dart';

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), true);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReadingDatabase database;
  late ProviderContainer container;
  late Directory directory;
  late List<Map<String, Object?>> pending;
  late List<String> released;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reading-inbox-flow-');
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
    pending = [];
    released = [];
    messenger.setMockMethodCallHandler(importChannel, (call) async {
      if (call.method == 'pending') return pending;
      if (call.method == 'release') {
        final id = call.arguments as String;
        released.add(id);
        final item = pending.where((item) => item['id'] == id).first;
        if (item['path'] case final String path) await File(path).delete();
        pending.removeWhere((item) => item['id'] == id);
      }
      return null;
    });
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });
  tearDown(() async {
    container.dispose();
    await database.close();
    await directory.delete(recursive: true);
    messenger.setMockMethodCallHandler(importChannel, null);
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      null,
    );
  });

  Future<File> receipt(
    String name, {
    String fixture = 'txt/utf8-bom.txt',
  }) async {
    final staged = await File('test/fixtures/$fixture')
        .copy('${directory.path}/staged-${pending.length}');
    pending.add({
      'id': 'in-${pending.length}',
      'name': name,
      'ready': true,
      'path': staged.path,
    });
    return staged;
  }

  Future<void> notify(WidgetTester tester) async {
    await tester.runAsync(
      () => messenger.handlePlatformMessage(
        importChannel.name,
        importChannel.codec.encodeMethodCall(const MethodCall('changed')),
        (_) {},
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReadingApp(),
      ),
    );
    await until(
      tester,
      () => find.byKey(const ValueKey('add-book')).evaluate().isNotEmpty,
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cold receipt waits for confirmation then imports once and clears only the copy',
    (tester) async {
      final staged = (await tester.runAsync(() => receipt('Shared.TXT')))!;
      final original = await tester.runAsync(
        () => File('test/fixtures/txt/utf8-bom.txt').readAsBytes(),
      );
      await mount(tester);
      expect(find.text('Shared.TXT'), findsOneWidget);
      expect(await tester.runAsync(database.books), isEmpty);
      await notify(tester);
      expect(find.text('Shared.TXT'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept-import-in-0')));
      await tester.pump();
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey('library-import-lock')),
            )
            .absorbing,
        true,
      );
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>).first,
            )
            .enabled,
        false,
      );

      await until(tester, () => find.byType(ReaderPage).evaluate().isNotEmpty);
      final books = await tester.runAsync(database.books);
      expect(books, hasLength(1));
      expect(books!.single.title, 'Shared');
      expect(books.single.content.blocks.length, 4);
      expect(released, ['in-0']);
      expect(await tester.runAsync(staged.exists), false);
      expect(
        await tester.runAsync(
          () => File('test/fixtures/txt/utf8-bom.txt').readAsBytes(),
        ),
        original,
      );
      await notify(tester);
      expect(await tester.runAsync(database.books), hasLength(1));
      await unmount(tester);
    },
  );

  testWidgets('ignore and corrupt-file failure preserve the existing library', (
    tester,
  ) async {
    final id = await database.addBook(
      'Existing',
      TxtParser().parseText('Existing text.'),
    );
    await database.savePosition(id, 0, location: 'existing-source-location');
    final staged = (await tester.runAsync(
      () => receipt('Broken.epub', fixture: 'txt/binary.txt'),
    ))!;
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('accept-import-in-0')));
    await until(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(find.byType(ReaderPage), findsNothing);
    expect(await tester.runAsync(database.books), hasLength(1));
    expect(
      (await tester.runAsync(() => database.book(id)))!.location,
      'existing-source-location',
    );
    expect(await tester.runAsync(staged.exists), true);
    await tester.tap(find.byKey(const ValueKey('ignore-import-in-0')));
    await until(tester, () => find.text('Broken.epub').evaluate().isEmpty);
    expect(await tester.runAsync(staged.exists), false);
    expect(await tester.runAsync(database.books), hasLength(1));
    // The next valid receipt remains usable after the failure.
    await tester.runAsync(() => receipt('Next.txt'));
    await notify(tester);
    expect(find.text('Next.txt'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'receipt during reading waits on the shelf and preserves source position',
    (tester) async {
      final id = await database.addBook(
        'Current book',
        TxtParser().parseText(
          List.generate(
            40,
            (i) => 'Paragraph $i. Tomorrow is another day.',
          ).join('\n\n'),
        ),
      );
      await database.savePosition(id, 10);
      await mount(tester);
      await tester.tap(find.text('Current book').first);
      await until(tester, () => find.byType(ReaderPage).evaluate().isNotEmpty);
      final before = await tester.runAsync(() => database.book(id));
      await tester.runAsync(() => receipt('Waiting.txt'));
      await notify(tester);
      expect(find.byType(ReaderPage), findsOneWidget);
      expect(find.text('Waiting.txt'), findsNothing);
      expect(await tester.runAsync(database.books), hasLength(1));
      final after = await tester.runAsync(() => database.book(id));
      expect(after!.position, before!.position);
      expect(after.location, before.location);
      await tester.tap(find.byKey(const ValueKey('page-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('back-library')));
      await until(tester, () => find.byType(ReaderPage).evaluate().isEmpty);
      expect(find.text('Waiting.txt'), findsOneWidget);
      expect(released, isEmpty);
      await unmount(tester);
    },
  );

  testWidgets(
    'receipt on backup page performs no automatic import or navigation',
    (tester) async {
      await mount(tester);
      final context = tester.element(find.byKey(const ValueKey('add-book')));
      unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const BackupPage())),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => receipt('After backup.txt'));
      await notify(tester);
      expect(find.byType(BackupPage), findsOneWidget);
      expect(await tester.runAsync(database.books), isEmpty);
      Navigator.of(tester.element(find.byType(BackupPage))).pop();
      await tester.pumpAndSettle();
      expect(find.text('After backup.txt'), findsOneWidget);
      expect(released, isEmpty);
      await unmount(tester);
    },
  );
}

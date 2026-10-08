import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/backup/backup.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/imports/inbox.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/reader.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/startup/preferences.dart';

class _Dictionary implements DictionaryProvider {
  @override
  DictionaryEntry? lookup(String word) => null;
  @override
  void close() {}
}

class _Database extends ReadingDatabase {
  _Database() : super(NativeDatabase.memory());
  bool failRead = false, failWrite = false, failBook = false;
  int bookReads = 0;
  Completer<void>? reading, writing;
  @override
  Future<String?> setting(String key) async {
    if (key == resumeReadingKey && failRead) throw StateError('read');
    if (key == 'readerStyle') await reading?.future;
    return super.setting(key);
  }

  @override
  Future<void> setSetting(String key, String value) async {
    if (key == resumeReadingKey) {
      if (failWrite) throw StateError('write');
      await writing?.future;
    }
    await super.setSetting(key, value);
  }

  @override
  Future<List<Book>> books() async {
    bookReads++;
    if (failBook) throw StateError('book');
    return super.books();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Database db;
  late ProviderContainer container;
  late List<Map<String, Object?>> pending;

  ProviderContainer scope() => ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      dictionaryProvider.overrideWith((_) async => _Dictionary()),
    ],
  );

  setUp(() {
    db = _Database();
    container = scope();
    pending = [];
    messenger.setMockMethodCallHandler(importChannel, (call) async => pending);
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    messenger.setMockMethodCallHandler(importChannel, null);
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      null,
    );
  });

  Future<String> seed(
    String title, {
    int readAt = 10,
    int position = 0,
    String? location,
    String? style,
  }) async {
    final id = await db.addBook(
      title,
      TxtParser().parseText(
        List.generate(
          32,
          (i) => 'Read paragraph $i. Tomorrow is another day.',
        ).join('\n\n'),
      ),
    );
    await db.customStatement(
      'UPDATE books SET last_read_at=?,position=?,location=?,style=? WHERE id=?',
      [readAt, position, location, style, id],
    );
    return id;
  }

  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 80 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(ready(), true);
    await t.pumpAndSettle();
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  Future<void> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ReadingApp(),
      ),
    );
    await settle(t);
  }

  Future<void> unmount(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  Future<void> settings(WidgetTester t) async {
    await t.tap(find.byTooltip('更多'));
    await t.pumpAndSettle();
    await t.tap(find.text('启动设置'));
    await settle(t);
  }

  Future<void> closeSettings(WidgetTester t) async {
    Navigator.of(t.element(find.byType(StartupSettings))).pop();
    await t.pumpAndSettle();
  }

  for (final value in <String?>[null, '0', 'true', 'unexpected']) {
    testWidgets(
      'legacy/disabled value $value keeps the shelf and loads books only once',
      (t) async {
        await seed('Previously read');
        if (value != null) await db.setSetting(resumeReadingKey, value);
        await mount(t);
        expect(find.byType(ReaderPage), findsNothing);
        expect(find.byKey(const ValueKey('add-book')), findsOneWidget);
        expect(db.bookReads, 1);
        await unmount(t);
      },
    );
  }

  testWidgets(
    'enabled launches the most recently read book with source anchor and per-book style; Back stays on shelf',
    (t) async {
      await db.setSetting(resumeReadingKey, '1');
      await seed('Earlier', readAt: 1);
      final anchor = const PageAnchor(BookPosition(18, offset: 6)).encode();
      final style = const ReaderStyle(
        size: 27,
        paged: false,
        theme: ReaderTheme.paper,
      ).encode();
      final id = await seed(
        'Recent',
        readAt: 2,
        position: 18,
        location: anchor,
        style: style,
      );
      await seed('New but unread', readAt: 0);
      await mount(t);
      await until(t, () => find.byType(ReaderPage).evaluate().isNotEmpty);
      final reader = t.widget<ReaderPage>(find.byType(ReaderPage));
      expect(reader.book.id, id);
      expect(reader.book.location, anchor);
      expect(reader.book.style, style);
      final dynamic state = t.state(find.byType(ReaderPage));
      expect(state.initialLocation().encode(), anchor);
      expect(state.style.size, 27);
      expect(state.style.paged, false);
      if (find.byKey(const ValueKey('back-library')).evaluate().isEmpty) {
        await t.tap(find.byKey(const ValueKey('page-label')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('back-library')));
      await settle(t);
      expect(find.byType(ReaderPage), findsNothing);
      expect(db.bookReads, 2);
      // Foregrounding/rebuilds must not run another startup navigation.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      container.invalidate(booksProvider);
      await settle(t);
      expect(find.byType(ReaderPage), findsNothing);
      expect(db.bookReads, 3);
      await unmount(t);
    },
  );

  for (final empty in [true, false]) {
    testWidgets(
      'enabled with ${empty ? 'empty shelf' : 'only unread/deleted books'} safely stays on shelf',
      (t) async {
        await db.setSetting(resumeReadingKey, '1');
        if (!empty) {
          final id = await seed('Deleted');
          await db.deleteBook(id);
          await seed('Unread', readAt: 0);
        }
        await mount(t);
        expect(find.byType(ReaderPage), findsNothing);
        expect(t.takeException(), isNull);
        await unmount(t);
      },
    );
  }

  testWidgets('cold external receipt wins over automatic reading', (t) async {
    await db.setSetting(resumeReadingKey, '1');
    await seed('Recent');
    pending = [
      {'id': 'shared', 'name': 'Shared.epub', 'ready': false},
    ];
    await mount(t);
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.text('Shared.epub'), findsOneWidget);
    expect((await t.runAsync(db.books))!, hasLength(1));
    await unmount(t);
  });

  testWidgets('late receipt while startup is waiting cancels auto navigation', (
    t,
  ) async {
    await db.setSetting(resumeReadingKey, '1');
    await seed('Recent');
    db.reading = Completer<void>();
    await mount(t);
    pending = [
      {'id': 'late', 'name': 'Late.txt', 'ready': true, 'error': 'unreadable'},
    ];
    await container.read(importInboxProvider.notifier).refresh();
    db.reading!.complete();
    await settle(t);
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.text('Late.txt'), findsOneWidget);
    await unmount(t);
  });

  testWidgets('unknown native inbox state keeps the shelf accessible', (
    t,
  ) async {
    await db.setSetting(resumeReadingKey, '1');
    await seed('Recent');
    messenger.setMockMethodCallHandler(
      importChannel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    await mount(t);
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.byKey(const ValueKey('add-book')), findsOneWidget);
    await unmount(t);
  });

  testWidgets('manual settings interaction cancels a slow startup attempt', (
    t,
  ) async {
    await db.setSetting(resumeReadingKey, '1');
    await seed('Recent');
    db.reading = Completer<void>();
    await mount(t);
    await settings(t);
    db.reading!.complete();
    await settle(t);
    expect(find.byType(StartupSettings), findsOneWidget);
    expect(find.byType(ReaderPage), findsNothing);
    await closeSettings(t);
    await settle(t);
    expect(find.byType(ReaderPage), findsNothing);
    await unmount(t);
  });

  for (final preference in [true, false]) {
    testWidgets(
      '${preference ? 'preference' : 'book'} read failure falls back to shelf',
      (t) async {
        await seed('Recent');
        await db.setSetting(resumeReadingKey, '1');
        db.failRead = preference;
        db.failBook = !preference;
        await mount(t);
        expect(find.byType(ReaderPage), findsNothing);
        expect(find.byTooltip('更多'), findsOneWidget);
        expect(t.takeException(), isNull);
        await unmount(t);
      },
    );
  }

  testWidgets('root disposal during a slow startup ignores its late result', (
    t,
  ) async {
    await db.setSetting(resumeReadingKey, '1');
    await seed('Recent');
    db.reading = Completer<void>();
    await mount(t);
    await unmount(t);
    db.reading!.complete();
    await settle(t);
    expect(find.byType(ReaderPage), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'global switch saves, survives root restart and remains separate from reader style',
    (t) async {
      await mount(t);
      await settings(t);
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('resume-reading-switch')),
            )
            .value,
        false,
      );
      await t.tap(find.byKey(const ValueKey('resume-reading-switch')));
      await settle(t);
      expect(await db.setting(resumeReadingKey), '1');
      expect(await db.setting('readerStyle'), isNull);
      await closeSettings(t);
      expect(find.byType(ReaderPage), findsNothing);
      await unmount(t);
      container.dispose();
      container = scope();
      await seed('Next launch');
      await mount(t);
      expect(find.byType(ReaderPage), findsOneWidget);
      await unmount(t);
    },
  );

  testWidgets('switch write failure preserves prior value and permits retry', (
    t,
  ) async {
    await mount(t);
    await settings(t);
    db.failWrite = true;
    await t.tap(find.byKey(const ValueKey('resume-reading-switch')));
    await settle(t);
    expect(find.text('设置未能保存，请重试。'), findsOneWidget);
    expect(
      t
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('resume-reading-switch')),
          )
          .value,
      false,
    );
    expect(await db.setting(resumeReadingKey), isNull);
    db.failWrite = false;
    await t.tap(find.byKey(const ValueKey('resume-reading-switch')));
    await settle(t);
    expect(await db.setting(resumeReadingKey), '1');
    await t.tap(find.byKey(const ValueKey('resume-reading-switch')));
    await settle(t);
    expect(await db.setting(resumeReadingKey), '0');
    expect(await container.read(resumeReadingProvider.future), false);
    await unmount(t);
  });

  testWidgets(
    'dismissing a saving sheet still refreshes its app-scoped value',
    (t) async {
      await mount(t);
      await settings(t);
      db.writing = Completer<void>();
      await t.tap(find.byKey(const ValueKey('resume-reading-switch')));
      await t.pump();
      await closeSettings(t);
      db.writing!.complete();
      await settle(t);
      await settings(t);
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('resume-reading-switch')),
            )
            .value,
        true,
      );
      expect(await db.setting(resumeReadingKey), '1');
      await unmount(t);
    },
  );

  test(
    'backup preserves the switch; an older backup without it defaults off',
    () async {
      final original = ReadingDatabase(NativeDatabase.memory());
      addTearDown(original.close);
      await original.setSetting(resumeReadingKey, '1');
      final enabled = ReadingBackup.decode(
        await BackupStore(original).export(),
      );
      await BackupStore(db).restore(enabled);
      expect(await container.read(resumeReadingProvider.future), true);
      await original.customStatement('DELETE FROM settings');
      final old = ReadingBackup.decode(await BackupStore(original).export());
      await BackupStore(db).restore(old);
      container.invalidate(resumeReadingProvider);
      expect(await container.read(resumeReadingProvider.future), false);
      expect(await db.books(), isEmpty);
    },
  );
}

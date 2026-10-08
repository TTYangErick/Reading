import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/backup/backup.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/orientation/orientation.dart';
import 'package:reading_app/orientation/settings.dart';
import 'package:reading_app/reader/settings.dart';
import 'package:reading_app/reader/style.dart';

class _Database extends ReadingDatabase {
  _Database() : super(NativeDatabase.memory());
  bool failWrite = false, failRead = false;
  Completer<void>? reading;
  @override
  Future<String?> setting(String key) async {
    if (key == readingOrientationKey) await reading?.future;
    if (key == readingOrientationKey && failRead) throw StateError('read');
    return super.setting(key);
  }

  @override
  Future<void> setSetting(String key, String value) async {
    if (key == readingOrientationKey && failWrite) throw StateError('write');
    return super.setSetting(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old, missing and future settings follow system', () {
    for (final value in [null, '', 'future', 'Portrait']) {
      expect(ReadingOrientation.decode(value), ReadingOrientation.system);
    }
    expect(
      ReadingOrientation.decode('landscape'),
      ReadingOrientation.landscape,
    );
  });

  test('support uses display dimensions, independent of rotation', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(supportsReadingOrientation(platform, const Size(402, 874)), true);
      expect(supportsReadingOrientation(platform, const Size(874, 402)), true);
      expect(supportsReadingOrientation(platform, const Size(600, 900)), false);
      expect(
        supportsReadingOrientation(platform, const Size(1194, 834)),
        false,
      );
    }
    expect(
      supportsReadingOrientation(TargetPlatform.macOS, const Size(402, 874)),
      false,
    );
  });

  test('nested leases retain lock until last reader leaves', () async {
    final calls = <List<DeviceOrientation>>[];
    final session = ReadingOrientationSession(
      (value) async => calls.add(value),
    );
    final root = Object(), note = Object();
    session.update(root, ReadingOrientation.portrait, true);
    await session.pending;
    session.update(note, ReadingOrientation.landscape, true);
    await session.pending;
    session.update(root, ReadingOrientation.portrait, true);
    await session.pending;
    expect(calls.last, ReadingOrientation.landscape.orientations);
    session.release(note);
    await session.pending;
    expect(calls.last, ReadingOrientation.portrait.orientations);
    session.release(root);
    await session.pending;
    expect(calls.last, isEmpty);
    session.dispose();
    await session.pending;
  });

  test(
    'in flight rotation finishes before final reset; stale requests skipped',
    () async {
      final calls = <List<DeviceOrientation>>[];
      final gate = Completer<void>();
      final session = ReadingOrientationSession((value) async {
        calls.add(value);
        if (calls.length == 1) await gate.future;
      });
      final owner = Object();
      session.update(owner, ReadingOrientation.portrait, true);
      await Future<void>.delayed(Duration.zero);
      session.update(owner, ReadingOrientation.landscape, true);
      session.release(owner);
      expect(calls, [ReadingOrientation.portrait.orientations]);
      gate.complete();
      await session.pending;
      expect(calls, [
        ReadingOrientation.portrait.orientations,
        <DeviceOrientation>[],
      ]);
      session.dispose();
      await session.pending;
    },
  );

  test(
    'moving to a large display resets and moving back restores preference',
    () async {
      final calls = <List<DeviceOrientation>>[];
      final session = ReadingOrientationSession(
        (value) async => calls.add(value),
      );
      final owner = Object();
      session.update(owner, ReadingOrientation.landscape, true);
      await session.pending;
      session.update(owner, ReadingOrientation.landscape, false);
      await session.pending;
      expect(calls.last, isEmpty);
      session.update(owner, ReadingOrientation.landscape, true);
      await session.pending;
      expect(calls.last, ReadingOrientation.landscape.orientations);
      session.dispose();
      await session.pending;
      expect(calls.last, isEmpty);
    },
  );

  test(
    'native errors are reported, retryable and do not poison request queue',
    () async {
      var fail = true;
      final calls = <List<DeviceOrientation>>[];
      final session = ReadingOrientationSession((value) async {
        if (fail) throw PlatformException(code: 'rotation');
        calls.add(value);
      });
      final owner = Object();
      session.update(owner, ReadingOrientation.portrait, true);
      await session.pending;
      expect(session.error, isNotNull);
      fail = false;
      session.retry();
      await session.pending;
      expect(session.error, isNull);
      expect(calls.last, ReadingOrientation.portrait.orientations);
      session.release(owner);
      await session.pending;
      expect(calls.last, isEmpty);
      session.dispose();
      await session.pending;
    },
  );

  test(
    'saved preference survives backup and old backup returns to default',
    () async {
      final db = _Database(), source = _Database();
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      try {
        expect(
          await container.read(readingOrientationProvider.future),
          ReadingOrientation.system,
        );
        final old = ReadingBackup.decode(await BackupStore(source).export());
        await container
            .read(readingOrientationProvider.notifier)
            .save(ReadingOrientation.landscape);
        expect(await db.setting(readingOrientationKey), 'landscape');
        await BackupStore(source)
            .restore(ReadingBackup.decode(await BackupStore(db).export()));
        expect(await source.setting(readingOrientationKey), 'landscape');
        await BackupStore(db).restore(old);
        container.invalidate(readingOrientationProvider);
        expect(
          await container.read(readingOrientationProvider.future),
          ReadingOrientation.system,
        );
        await db.setSetting(readingOrientationKey, 'future');
        container.invalidate(readingOrientationProvider);
        expect(
          await container.read(readingOrientationProvider.future),
          ReadingOrientation.system,
        );
      } finally {
        container.dispose();
        await db.close();
        await source.close();
      }
    },
  );

  Future<void> waitFor(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    expect(ready(), true);
    await t.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester t, Finder finder) async {
    await t.scrollUntilVisible(finder, 100);
    await Scrollable.ensureVisible(t.element(finder), alignment: .5);
    await t.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 740),
    const Size(402, 874),
    const Size(1194, 834),
  ]) {
    testWidgets(
      'settings preserve reader controls and handle save failures at $size',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        t.view.display.size = size;
        t.view.display.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.display.resetSize);
        addTearDown(t.view.display.resetDevicePixelRatio);
        final db = _Database();
        final calls = <List<DeviceOrientation>>[];
        final session = ReadingOrientationSession(
          (value) async => calls.add(value),
        );
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            readingOrientationSessionProvider.overrideWithValue(session),
          ],
        );
        addTearDown(() async {
          container.dispose();
          session.dispose();
          await t.pump();
          await db.close();
        });
        var style = const ReaderStyle();
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ReadingOrientationScope(
                child: Scaffold(
                  body: ReaderSettings(
                    style: style,
                    onChanged: (value) => style = value,
                    orientationSetting: const ReadingOrientationSetting(),
                  ),
                ),
              ),
            ),
          ),
        );
        await waitFor(
          t,
          () => container.read(readingOrientationProvider).hasValue,
        );
        if (size.shortestSide >= 600) {
          await reveal(t, find.textContaining('此设备跟随系统方向'));
          expect(
            find.byKey(const ValueKey('reading-orientation-setting')),
            findsNothing,
          );
          expect(calls.last, isEmpty);
        } else {
          final control = find.byKey(
            const ValueKey('reading-orientation-setting'),
          );
          await reveal(t, control);
          Future<void> choose(String label) async {
            await t.tap(
              find.descendant(of: control, matching: find.text(label)),
            );
            await t.pump();
          }

          db.failWrite = true;
          await choose('横屏');
          await waitFor(
            t,
            () => find.text('阅读方向未能保存，请重试。').evaluate().isNotEmpty,
          );
          expect(
            container.read(readingOrientationProvider).requireValue,
            ReadingOrientation.system,
          );
          db.failWrite = false;
          await choose('横屏');
          await waitFor(
            t,
            () =>
                container.read(readingOrientationProvider).asData?.value ==
                ReadingOrientation.landscape,
          );
          expect(calls.last, ReadingOrientation.landscape.orientations);
          expect(style.encode(), const ReaderStyle().encode());
        }
        // Existing controls remain operational; this preference is not a style.
        final font = find.byType(DropdownButtonFormField<String>);
        await reveal(t, font);
        expect(font, findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await session.pending;
        expect(calls.last, isEmpty);
      },
      variant: TargetPlatformVariant.only(
        size.width == 320 ? TargetPlatform.android : TargetPlatform.iOS,
      ),
    );
  }

  testWidgets(
    'read failure retries safely and emits real SystemChrome arguments',
    (t) async {
      final db = _Database()..failRead = true;
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final calls = <Object?>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            calls.add(call.arguments);
          }
          return null;
        },
      );
      t.view.display.size = const Size(402, 874);
      t.view.display.devicePixelRatio = 1;
      addTearDown(t.view.display.resetSize);
      addTearDown(t.view.display.resetDevicePixelRatio);
      addTearDown(() async {
        container.dispose();
        await t.pump();
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await db.close();
      });
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ReadingOrientationScope(
              child: Scaffold(body: ReadingOrientationSetting()),
            ),
          ),
        ),
      );
      await waitFor(t, () => find.text('读取阅读方向失败，点击重试').evaluate().isNotEmpty);
      db.failRead = false;
      await t.tap(find.text('读取阅读方向失败，点击重试'));
      await waitFor(
        t,
        () => container.read(readingOrientationProvider).hasValue,
      );
      await t.runAsync(
        () => container
            .read(readingOrientationProvider.notifier)
            .save(ReadingOrientation.portrait),
      );
      await t.pumpAndSettle();
      expect(calls.last, ['DeviceOrientation.portraitUp']);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(calls.last, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'small tablet window follows system and delayed preference cannot lock a closed reader',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.view.display.size = const Size(1194, 834);
      t.view.display.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.display.resetSize);
      addTearDown(t.view.display.resetDevicePixelRatio);
      final db = _Database();
      final calls = <List<DeviceOrientation>>[];
      final session = ReadingOrientationSession(
        (value) async => calls.add(value),
      );
      var container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          readingOrientationSessionProvider.overrideWithValue(session),
        ],
      );
      addTearDown(() async {
        container.dispose();
        session.dispose();
        await t.pump();
        await db.close();
      });
      await t.runAsync(() => db.setSetting(readingOrientationKey, 'landscape'));
      Widget reader() => UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ReadingOrientationScope(
            child: Scaffold(body: ReadingOrientationSetting()),
          ),
        ),
      );
      await t.pumpWidget(reader());
      await waitFor(
        t,
        () => container.read(readingOrientationProvider).hasValue,
      );
      expect(find.textContaining('此设备跟随系统方向'), findsOneWidget);
      expect(calls.every((value) => value.isEmpty), true);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();

      t.view.display.size = const Size(390, 844);
      db.reading = Completer<void>();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          readingOrientationSessionProvider.overrideWithValue(session),
        ],
      );
      calls.clear();
      await t.pumpWidget(reader());
      await t.pump();
      expect(calls.every((value) => value.isEmpty), true);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      db.reading!.complete();
      await waitFor(
        t,
        () => container.read(readingOrientationProvider).hasValue,
      );
      expect(calls, isNotEmpty);
      expect(calls.every((value) => value.isEmpty), true);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

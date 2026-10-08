import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/imports/inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late List<Map<String, Object?>> pending;
  late List<String> released;
  late Directory directory;

  setUp(() async {
    pending = [];
    released = [];
    directory = await Directory.systemTemp.createTemp('reading-import-test-');
    messenger.setMockMethodCallHandler(importChannel, (call) async {
      if (call.method == 'pending') return pending;
      if (call.method == 'release') {
        released.add(call.arguments as String);
        pending.removeWhere((item) => item['id'] == call.arguments);
      }
      return null;
    });
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    messenger.setMockMethodCallHandler(importChannel, null);
    await directory.delete(recursive: true);
  });

  Future<ImportInbox> start() async {
    final inbox = container.read(importInboxProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await inbox.refresh();
    return inbox;
  }

  test(
    'cold snapshot, in-flight receipt, duplicate notifications and ignore',
    () async {
      pending = [
        {'id': 'a', 'name': 'Book.txt', 'ready': false},
      ];
      final inbox = await start();
      expect(container.read(importInboxProvider).single.ready, false);
      pending = [
        {
          'id': 'a',
          'name': 'Book.txt',
          'ready': true,
          'path': '/private/staged',
        },
        {'id': 'a', 'name': 'duplicate.txt', 'ready': true},
      ];
      // Exercise the actual native -> Dart changed method, not only direct refresh.
      await messenger.handlePlatformMessage(
        importChannel.name,
        importChannel.codec.encodeMethodCall(const MethodCall('changed')),
        (_) {},
      );
      expect(container.read(importInboxProvider).single.name, 'Book.txt');
      expect(container.read(importInboxProvider).single.ready, true);
      await inbox.refresh();
      expect(container.read(importInboxProvider), hasLength(1));
      await inbox.release('a');
      expect(container.read(importInboxProvider), isEmpty);
      expect(released, ['a']);
    },
  );

  test(
    'older asynchronous snapshots cannot overwrite the newest receipt',
    () async {
      final inbox = await start();
      final first = Completer<List<Object?>>();
      var calls = 0;
      messenger.setMockMethodCallHandler(importChannel, (_) async {
        if (++calls == 1) return first.future;
        return [
          {'id': 'new', 'name': 'New.txt', 'ready': true},
        ];
      });
      final oldRefresh = inbox.refresh();
      await Future<void>.delayed(Duration.zero);
      await inbox.refresh();
      first.complete([
        {'id': 'old', 'name': 'Old.txt', 'ready': true},
      ]);
      await oldRefresh;
      expect(container.read(importInboxProvider).single.id, 'new');
    },
  );

  test(
    'release failure hides a consumed file instead of importing twice',
    () async {
      pending = [
        {'id': 'a', 'name': 'Book.txt', 'ready': true},
      ];
      final inbox = await start();
      messenger.setMockMethodCallHandler(importChannel, (call) async {
        if (call.method == 'release') {
          throw PlatformException(code: 'unavailable');
        }
        return pending;
      });
      await inbox.release('a');
      await inbox.refresh();
      expect(container.read(importInboxProvider), isEmpty);
      pending = [];
      await inbox.refresh();
      pending = [
        {'id': 'b', 'name': 'Next.txt', 'ready': true},
      ];
      await inbox.refresh();
      expect(container.read(importInboxProvider).single.id, 'b');
    },
  );

  test('host without a native receiver keeps existing import usable', () async {
    messenger.setMockMethodCallHandler(importChannel, null);
    await start();
    expect(container.read(importInboxProvider), isEmpty);
  });

  test('dispose ignores an outstanding native snapshot', () async {
    final inbox = await start();
    final reply = Completer<List<Object?>>();
    messenger.setMockMethodCallHandler(importChannel, (_) => reply.future);
    final refresh = inbox.refresh();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    // Replace so teardown does not dispose an already disposed container.
    container = ProviderContainer();
    reply.complete([
      {'id': 'late', 'name': 'Late.txt', 'ready': true},
    ]);
    await refresh;
  });

  testWidgets('receiving/error cards expose ignore without an enabled import', (
    tester,
  ) async {
    final ignored = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportInboxCards(
            items: const [
              IncomingBook(id: 'loading', name: 'Receiving', ready: false),
              IncomingBook(
                id: 'full',
                name: 'Overflow',
                ready: true,
                error: 'queueFull',
              ),
              IncomingBook(
                id: 'bad',
                name: 'Unsupported',
                ready: true,
                error: 'unsupported',
              ),
            ],
            busy: false,
            onImport: (_) => fail('Receiving/error input cannot be imported'),
            onIgnore: ignored.add,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('accept-import-loading')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('accept-import-full')), findsNothing);
    expect(find.byKey(const ValueKey('accept-import-bad')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ignore-import-loading')));
    expect(ignored, ['loading']);
    expect(tester.takeException(), isNull);
  });

  for (final encoding in ['utf8-bom.txt', 'gbk.txt']) {
    test(
      'received $encoding uses the existing parser and preserves source',
      () async {
        final source = File('test/fixtures/txt/$encoding');
        final before = await source.readAsBytes();
        final book = await parseReceivedFile(('Received.TXT', source.path));
        expect(book.blocks, isNotEmpty);
        expect(await source.readAsBytes(), before);
      },
    );
  }

  test(
    'received EPUB retains content, links, positions, assets and metadata',
    () async {
      final file = File('test/fixtures/epub/footnotes-epub3.epub');
      final bytes = await file.readAsBytes();
      final expected = EpubParser().parse(bytes);
      final actual = await parseReceivedFile(('Footnotes.epub', file.path));
      expect(actual.encode(), expected.encode());
      expect(actual.assets.keys, expected.assets.keys);
      for (final key in expected.assets.keys) {
        expect(actual.assets[key], expected.assets[key]);
      }
      expect(await file.readAsBytes(), bytes);
    },
  );

  for (final (name, limit) in [
    ('Large.txt', 20 * 1024 * 1024),
    ('Large.epub', EpubParser.maxFileSize),
  ]) {
    test(
      '$name enforces actual bytes before parsing and leaves source intact',
      () async {
        final file = File('${directory.path}/large');
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(limit + 1);
        await handle.close();
        await expectLater(
          parseReceivedFile((name, file.path)),
          throwsFormatException,
        );
        expect(await file.length(), limit + 1);
      },
    );
  }

  test(
    'unsupported, corrupt and disappeared inputs fail without a partial result',
    () async {
      final file = File('${directory.path}/bad')
        ..writeAsStringSync('not an EPUB');
      await expectLater(
        parseReceivedFile(('Book.pdf', file.path)),
        throwsFormatException,
      );
      await expectLater(
        parseReceivedFile(('Book.epub', file.path)),
        throwsFormatException,
      );
      await file.delete();
      await expectLater(
        parseReceivedFile(('Book.txt', file.path)),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:reading_app/core/providers.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/catalog.dart';
import 'package:reading_app/dict/management_page.dart';
import 'package:reading_app/main.dart';
import 'package:reading_app/library/library.dart';

class _Assets extends CachingAssetBundle {
  final values = <String, String>{};
  final reads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    if (!values.containsKey(key)) {
      throw StateError('Unexpected asset read: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(values[key]!)));
  }
}

class _Catalog extends DictionaryCatalog {
  int calls = 0;
  bool fail = false;
  @override
  Future<List<DictionaryInfo>> inspect() async {
    calls++;
    if (fail) throw const FileSystemException('test');
    return const [
      DictionaryInfo(
        id: 'ecdict',
        name: 'ECDICT 英汉词典',
        source: 'ECDICT',
        version: 'bc015ed2e24a',
        license: 'MIT',
        packageBytes: 118620160,
        expectedBytes: 118620160,
        localBytes: 118620160,
        availability: DictionaryAvailability.ready,
      ),
      DictionaryInfo(
        id: 'wiktionary',
        name: 'Wiktionary 英英词典',
        source: 'Wiktionary contributors · Kaikki',
        version: '2026-09-02 · 提取 2026-10-03',
        license: 'CC-BY-SA-4.0',
        packageBytes: 118980347,
        expectedBytes: 320331776,
        localBytes: 0,
        availability: DictionaryAvailability.notPrepared,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late _Assets assets;
  final sha = 'a' * 64;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('reading-catalog-');
    assets = _Assets();
  });
  tearDown(() => folder.deleteSync(recursive: true));

  void manifest(String id, {int bytes = 4096}) {
    assets.values['assets/dictionaries/${id == 'ecdict' ? 'manifest' : 'wiktionary-manifest'}.json'] =
        jsonEncode({
          'sha256': sha,
          'schemaVersion': 1,
          'bytes': bytes,
          if (id == 'wiktionary') 'compressedBytes': 1000,
          'source': {
            'revision': '123456789012abcdef',
            'license': id == 'ecdict' ? 'MIT' : 'CC-BY-SA-4.0',
            'dumpDate': '2026-09-02',
            'extractedDate': '2026-10-03',
          },
        });
  }

  File database(String id) {
    final file = File('${folder.path}/$id-$sha.sqlite');
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA user_version=1');
    if (id == 'ecdict') {
      db.execute(
        'CREATE TABLE entries(headword TEXT,phonetic TEXT,full_gloss TEXT,definition TEXT,freq INT)',
      );
      db.execute('CREATE TABLE senses(headword TEXT,rank INT,gloss_zh TEXT)');
      db.execute('CREATE TABLE forms(form TEXT,lemma TEXT)');
    } else {
      db.execute(
        'CREATE TABLE entries(id INT,word TEXT,word_key TEXT,pos TEXT,ipa TEXT)',
      );
      db.execute(
        'CREATE TABLE senses(entry_id INT,rank INT,gloss TEXT,tags TEXT,examples TEXT,is_form INT)',
      );
      db.execute('CREATE TABLE forms(form_key TEXT,lemma TEXT)');
    }
    db.close();
    manifest(id, bytes: file.lengthSync());
    return file;
  }

  Future<List<DictionaryInfo>> inspect() => DictionaryCatalog(
    assets: assets,
    directory: () async => folder,
  ).inspect();

  test('unprepared dictionaries read manifests only without installing or removing files', () async {
    manifest('ecdict');
    manifest('wiktionary');
    final leftover = File('${folder.path}/wiktionary-$sha.sqlite.tmp')
      ..writeAsStringSync('partial');
    final result = await inspect();
    expect(
      result.map((i) => i.availability),
      everyElement(DictionaryAvailability.notPrepared),
    );
    expect(result.map((i) => i.localBytes), [0, 0]);
    expect(result.last.packageBytes, 1000);
    expect(result.last.expectedBytes, 4096);
    expect(folder.listSync().map((f) => f.path), [leftover.path]);
    expect(leftover.readAsStringSync(), 'partial');
    expect(assets.reads, hasLength(2));
    expect(assets.reads.every((s) => s.endsWith('.json')), isTrue);
  });

  test(
    'ready libraries are inspected read-only with truthful metadata and size',
    () async {
      final files = [database('ecdict'), database('wiktionary')];
      final before = files.map((f) => f.readAsBytesSync()).toList();
      final result = await inspect();
      expect(
        result.map((i) => i.availability),
        everyElement(DictionaryAvailability.ready),
      );
      expect(result.first.version, '123456789012');
      expect(result.last.version, '2026-09-02 · 提取 2026-10-03');
      expect(result.last.license, 'CC-BY-SA-4.0');
      for (var i = 0; i < files.length; i++) {
        expect(result[i].localBytes, files[i].lengthSync());
        expect(files[i].readAsBytesSync(), before[i]);
      }
      expect(folder.listSync(), hasLength(2));
    },
  );

  test('wrong schema or damaged SQLite is unavailable independently of the other dictionary', () async {
    database('ecdict');
    final file = database('wiktionary');
    final db = sqlite3.open(file.path);
    db.execute('PRAGMA user_version=99');
    db.close();
    expect((await inspect()).map((i) => i.availability), [
      DictionaryAvailability.ready,
      DictionaryAvailability.unavailable,
    ]);
    file.writeAsBytesSync(List.filled(file.lengthSync(), 0));
    expect(
      (await inspect()).last.availability,
      DictionaryAvailability.unavailable,
    );
    file.writeAsStringSync('truncated');
    final result = await inspect();
    expect(result.last.localBytes, 9);
    expect(result.last.availability, DictionaryAvailability.unavailable);
    expect(result.first.availability, DictionaryAvailability.ready);
  });

  test(
    'manifest or directory errors remain unknown and can be retried',
    () async {
      manifest('ecdict');
      assets.values['assets/dictionaries/wiktionary-manifest.json'] = '{broken';
      var result = await inspect();
      expect(result.first.availability, DictionaryAvailability.notPrepared);
      expect(result.last.availability, DictionaryAvailability.unknown);
      expect(result.last.localBytes, isNull);
      manifest('wiktionary');
      final service = DictionaryCatalog(
        assets: assets,
        directory: () async => throw const FileSystemException('denied'),
      );
      expect(
        (await service.inspect()).map((i) => i.availability),
        everyElement(DictionaryAvailability.unknown),
      );
      result = await inspect();
      expect(result.last.availability, DictionaryAvailability.notPrepared);
    },
  );

  for (final (size, brightness) in [
    (const Size(320, 740), Brightness.light),
    (const Size(1194, 834), Brightness.dark),
  ]) {
    testWidgets(
      'shelf dictionary page refreshes without opening lookup or changing data at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = ReadingDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.setSetting('readerStyle', 'unchanged');
        await db.saveTranslation('test', 'en', 'zh', 'Word.', '词。');
        final catalog = _Catalog();
        var lookupsOpened = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              dictionaryCatalogProvider.overrideWithValue(catalog),
              dictionaryProvider.overrideWith((_) {
                lookupsOpened++;
                throw StateError('must not prepare');
              }),
            ],
            child: MaterialApp(
              theme: const ReadingApp().theme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: const LibraryPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('词典管理'));
        await tester.pumpAndSettle();
        expect(find.byType(DictionaryManagementPage), findsOneWidget);
        expect(find.text('本地已就绪'), findsOneWidget);
        expect(find.text('内置 · 待准备'), findsOneWidget);
        expect(find.text('准备后词库：320.3 MB'), findsOneWidget);
        expect(tester.takeException(), isNull);
        catalog.fail = true;
        await tester.tap(find.byTooltip('刷新词典状态'));
        await tester.pumpAndSettle();
        expect(find.text('暂时无法读取词典信息'), findsOneWidget);
        catalog.fail = false;
        await tester.tap(find.text('重试'));
        await tester.pumpAndSettle();
        expect(catalog.calls, 3);
        expect(lookupsOpened, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(await db.setting('readerStyle'), 'unchanged');
        expect(await db.translationCount(), 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

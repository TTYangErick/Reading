import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/dict/wiktionary.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/style.dart';
import 'package:sqlite3/sqlite3.dart';

class _Assets extends CachingAssetBundle {
  _Assets(this.content);
  final Uint8List content;
  bool corrupt = false;
  int reads = 0;
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.json')) {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'sha256': 'test-package',
              'bytes': content.length,
              'schemaVersion': 1,
            }),
          ),
        ),
      );
    }
    reads++;
    return ByteData.sublistView(
      Uint8List.fromList(corrupt ? [1, 2, 3] : gzip.encode(content)),
    );
  }
}

WiktionaryDictionary fixture() {
  final db = sqlite3.openInMemory();
  db.execute(
    'CREATE TABLE entries(id INTEGER PRIMARY KEY,word TEXT,word_key TEXT,pos TEXT,ipa TEXT)',
  );
  db.execute(
    'CREATE TABLE senses(entry_id INTEGER,rank INTEGER,gloss TEXT,tags TEXT,examples TEXT,is_form INTEGER)',
  );
  db.execute('CREATE TABLE forms(form_key TEXT,lemma TEXT)');
  void entry(
    int id,
    String word,
    String gloss, {
    bool reference = false,
    String pos = 'verb',
  }) {
    db.execute('INSERT INTO entries VALUES(?,?,?,?,?)', [
      id,
      word,
      word.toLowerCase(),
      pos,
      '/test/',
    ]);
    db.execute('INSERT INTO senses VALUES(?,0,?,?,?,?)', [
      id,
      gloss,
      jsonEncode(['test-tag']),
      jsonEncode(['Test example.']),
      reference ? 1 : 0,
    ]);
  }

  entry(1, 'go', 'Test movement sense.');
  entry(2, 'went', 'Test past form.', reference: true);
  entry(3, 'reading', 'Test noun sense.', pos: 'noun');
  entry(4, 'read', 'Test verb sense.');
  entry(5, 'May', 'Test month sense.', pos: 'name');
  entry(6, 'may', 'Test modal sense.');
  entry(7, 'onlywiki', 'Test English-only entry.');
  for (final pair in [
    ['went', 'go'],
    ['reading', 'read'],
    ['reads', 'read'],
    ['loop1', 'loop2'],
    ['loop2', 'loop1'],
  ]) {
    db.execute('INSERT INTO forms VALUES(?,?)', pair);
  }
  return WiktionaryDictionary(db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compressed asset installs once, repairs truncated files and rejects corrupt gzip', () async {
    final temp = Directory.systemTemp.createTempSync('wiktionary-install-');
    try {
      final seed = File('${temp.path}/seed.sqlite');
      final db = sqlite3.open(seed.path);
      db.execute('PRAGMA user_version=1');
      db.execute(
        'CREATE TABLE entries(id INTEGER,word TEXT,word_key TEXT,pos TEXT,ipa TEXT)',
      );
      db.execute(
        'CREATE TABLE senses(entry_id INTEGER,rank INTEGER,gloss TEXT,tags TEXT,examples TEXT,is_form INTEGER)',
      );
      db.execute('CREATE TABLE forms(form_key TEXT,lemma TEXT)');
      db.execute('CREATE TABLE padding(data BLOB)');
      final random = Random(42);
      db.execute('INSERT INTO padding VALUES(?)', [
        Uint8List.fromList(List.generate(200000, (_) => random.nextInt(256))),
      ]);
      db.close();
      final assets = _Assets(seed.readAsBytesSync());
      var dictionary = await WiktionaryDictionary.fromAssets(
        bundle: assets,
        directory: temp,
      );
      dictionary.close();
      dictionary = await WiktionaryDictionary.fromAssets(
        bundle: assets,
        directory: temp,
      );
      dictionary.close();
      expect(assets.reads, 1);
      final installed = File('${temp.path}/wiktionary-test-package.sqlite');
      installed.writeAsBytesSync([0]);
      dictionary = await WiktionaryDictionary.fromAssets(
        bundle: assets,
        directory: temp,
      );
      dictionary.close();
      expect(assets.reads, 2);
      expect(installed.readAsBytesSync(), seed.readAsBytesSync());
      installed.deleteSync();
      assets.corrupt = true;
      await expectLater(
        WiktionaryDictionary.fromAssets(bundle: assets, directory: temp),
        throwsA(isA<Exception>()),
      );
      expect(installed.existsSync(), isFalse);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
  test(
    'exact definitions, case, possessives, forms, missing targets and cycles',
    () {
      final dictionary = fixture();
      addTearDown(dictionary.close);
      expect(dictionary.lookup('went')!.englishWord, 'go');
      expect(dictionary.lookup('reading')!.englishWord, 'reading');
      expect(dictionary.lookup('reads')!.englishWord, 'read');
      expect(dictionary.lookup('READS')!.englishWord, 'read');
      expect(dictionary.lookup('reading’s')!.englishWord, 'reading');
      expect(
        dictionary.lookup('May')!.englishSenses.single.gloss,
        'Test month sense.',
      );
      expect(
        dictionary.lookup('may')!.englishSenses.single.gloss,
        'Test modal sense.',
      );
      expect(dictionary.lookup('loop1'), isNull);
      expect(dictionary.lookup('missing'), isNull);
    },
  );

  test('combined dictionary preserves real ECDICT and survives unavailable English', () {
    final primary = SqliteDictionary.open('assets/dictionaries/ecdict.sqlite');
    final wiki = fixture();
    final combined = CombinedDictionary(primary, wiki);
    addTearDown(combined.close);
    final before = primary.lookup('went')!;
    final after = combined.lookup('went')!;
    expect(after.meanings, before.meanings);
    expect(after.fullGloss, before.fullGloss);
    expect(after.phonetic, before.phonetic);
    expect(after.definition, before.definition);
    expect(after.englishWord, 'go');
    expect(combined.lookup('onlywiki')!.hasChineseSource, isFalse);
    expect(combined.lookup('zzzzunlistedword'), isNull);
    wiki.database.execute('DROP TABLE senses');
    final degraded = combined.lookup('went')!;
    expect(degraded.meanings, before.meanings);
    expect(degraded.englishNotice, isNotNull);
  });

  testWidgets(
    'English appears only in expanded/full view with source and examples',
    (tester) async {
      final wiki = fixture();
      addTearDown(wiki.close);
      final entry = wiki.lookup('reading')!;
      Future<void> render(GlossTier tier) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: WordBubble(
                  word: 'reading',
                  entry: entry,
                  style: ReaderStyle(tier: tier),
                  palette: ReaderPalette.palettes[ReaderTheme.white]!,
                  expanded: false,
                  onExpand: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(GlossTier.brief);
      expect(find.text('Test noun sense.'), findsNothing);
      expect(find.text('暂无中文释义 · 点此查看词条'), findsOneWidget);
      await render(GlossTier.full);
      expect(find.text('Test noun sense.'), findsOneWidget);
      expect(find.text('Test example.'), findsOneWidget);
      expect(find.text('Wiktionary · 离线'), findsOneWidget);
      await tester.ensureVisible(find.text('词条来源与许可'));
      await tester.tap(find.text('词条来源与许可'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('https://en.wiktionary.org/wiki/reading#English'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

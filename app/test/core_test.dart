import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/reader/bubble.dart';
import 'package:reading_app/reader/style.dart';
import 'package:reading_app/text/language.dart';

void main() {
  test('UTF-8 BOM, CRLF and GBK imports preserve paragraphs and detect chapters', () {
    const input =
        'Chapter 1\r\n\r\nTomorrow is another day.\r\n第二章 新的开始\r\n中文与 English。';
    final parser = TxtParser();
    final utf = parser.parse(
      Uint8List.fromList([239, 187, 191, ...utf8.encode(input)]),
    );
    final gbk = parser.parse(Uint8List.fromList(gbk_bytes.encode(input)));
    expect(utf.blocks.length, 4);
    expect(utf.blocks.where((b) => b.heading).length, 2);
    expect(gbk.encoding, 'GBK');
    expect(gbk.blocks.last.text, utf.blocks.last.text);
    expect(BookContent.decode(utf.encode()).blocks.last.text, '中文与 English。');
    expect(() => parser.parseText('  \n'), throwsFormatException);
    expect(() => parser.parseText('x\u0000'), throwsFormatException);
    expect(
      () => ParserRegistry([parser]).parse('book.epub', Uint8List(0)),
      throwsFormatException,
    );
  });
  test('word boundaries, possessives and sentence abbreviations', () {
    final language = EnglishLanguage();
    expect(
      language.wordAt('“Mother-in-law’s book.”', 4)?.text,
      'Mother-in-law’s',
    );
    expect(language.candidates('Alice’s'), ["alice's", 'alice']);
    expect(language.wordAt('word, next', 4), isNull);
    expect(
      language
          .sentenceAt('Mr. Bennet went home. Tomorrow is another day!', 7)
          .text,
      'Mr. Bennet went home.',
    );
    expect(
      language
          .sentenceAt('Mr. Bennet went home. Tomorrow is another day!', 23)
          .text,
      'Tomorrow is another day!',
    );
  });
  test(
    'settings survive round trip, clamp invalid values, respect system theme',
    () {
      final style = const ReaderStyle()
          .withValue('size', 100)
          .withValue('tier', 'full');
      expect(ReaderStyle.decode(style.encode()).size, 34);
      expect(ReaderStyle.decode(style.encode()).tier, GlossTier.full);
      expect(style.palette(Brightness.dark).dark, isTrue);
      expect(
        style.withValue('followSystem', false).palette(Brightness.dark).dark,
        isFalse,
      );
      expect(ReaderStyle.decode('broken').size, 19);
    },
  );
  test('real database retains book, paragraph, per-book style and defaults after close/reopen', () async {
    final dir = await Directory.systemTemp.createTemp('reading-db-test-');
    final file = File('${dir.path}/reading.sqlite');
    var db = ReadingDatabase(NativeDatabase(file));
    final id = await db.addBook(
      'Original',
      TxtParser().parseText('Chapter 1\nOne\nTwo'),
    );
    await db.rename(id, 'Renamed');
    await db.savePosition(id, 2);
    await db.saveStyle(id, const ReaderStyle(size: 24).encode());
    await db.setSetting(
      'readerStyle',
      const ReaderStyle(theme: ReaderTheme.paper).encode(),
    );
    await db.close();
    db = ReadingDatabase(NativeDatabase(file));
    final book = (await db.book(id))!;
    expect(book.title, 'Renamed');
    expect(book.position, 2);
    expect(book.progress, 1);
    expect(ReaderStyle.decode(book.style).size, 24);
    expect(
      ReaderStyle.decode(await db.setting('readerStyle')).theme,
      ReaderTheme.paper,
    );
    await db.deleteBook(id);
    expect(await db.books(), isEmpty);
    await db.close();
    await dir.delete(recursive: true);
  });
  test('full ECDICT resolves inflections and misses, with ordered meanings', () {
    final dictionary = SqliteDictionary.open(
      'assets/dictionaries/ecdict.sqlite',
    );
    addTearDown(dictionary.close);
    for (final pair in {
      'went': 'go',
      'studies': 'study',
      'children': 'child',
      'ALICE’S': 'alice',
    }.entries) {
      expect(dictionary.lookup(pair.key)?.word, pair.value, reason: pair.key);
    }
    expect(dictionary.lookup('tomorrow')!.meanings.take(2), ['明天', '未来']);
    expect(dictionary.lookup('zzzzunlistedword'), isNull);
    final durations = <int>[];
    for (int i = 0; i < 1000; i++) {
      final watch = Stopwatch()..start();
      dictionary.lookup(
        ['went', 'tomorrow', 'reading', 'studies', 'children'][i % 5],
      );
      durations.add(watch.elapsedMicroseconds);
    }
    durations.sort();
    // Report measured lookup time; device-specific performance is not inferred from this host run.
    debugPrint(
      'ECDICT host lookup p50=${durations[500]}µs p95=${durations[950]}µs max=${durations.last}µs (1000 queries)',
    );
  });
  test(
    'bubble geometry keeps all corners on screen and leaves tapped line clear',
    () {
      for (final size in [
        const Size(320, 568),
        const Size(430, 932),
        const Size(1024, 768),
      ]) {
        for (final anchor in [
          Rect.fromLTWH(12, 80, 50, 24),
          Rect.fromLTWH(size.width - 62, 80, 50, 24),
          Rect.fromLTWH(12, size.height - 130, 50, 24),
          Rect.fromLTWH(size.width - 62, size.height - 130, 50, 24),
        ]) {
          final layout = BubbleLayout(anchor, safeTop: 68, safeBottom: 100);
          final child = layout
              .getConstraintsForChild(BoxConstraints.tight(size))
              .constrain(const Size(380, 420));
          final origin = layout.getPositionForChild(size, child),
              rect = layout.getPositionForChild(size, child) & child;
          expect(origin.dx, greaterThanOrEqualTo(12));
          expect(rect.right, lessThanOrEqualTo(size.width - 12));
          expect(rect.top, greaterThanOrEqualTo(68));
          expect(rect.bottom, lessThanOrEqualTo(size.height - 100));
          expect(rect.overlaps(anchor), isFalse);
        }
      }
    },
  );
}

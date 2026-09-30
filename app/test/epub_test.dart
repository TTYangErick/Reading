import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

Uint8List sample([int version = 3]) =>
    File('test/fixtures/epub/lesson-epub$version.epub').readAsBytesSync();
Uint8List change(
  Map<String, String> replacements, {
  String? path,
  List<int>? bytes,
}) {
  final archive = ZipDecoder().decodeBytes(sample());
  for (final replacement in replacements.entries) {
    final file = archive.find(replacement.key)!;
    archive.add(ArchiveFile.string(file.name, replacement.value));
  }
  if (path != null) archive.add(ArchiveFile.bytes(path, bytes ?? [1]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  for (final version in [2, 3]) {
    test(
      'EPUB $version: spine, nested TOC fragments, image paths, table and serialization',
      () {
        final book = EpubParser().parse(sample(version));
        expect(book.title, 'Reading EPUB $version sample');
        expect(book.format, 'epub');
        expect(
          book.blocks.first.text,
          'Chapter One',
        ); // Manifest lists second first.
        expect(
          book.blocks[1].text,
          'Tomorrow is another day. Reading is a quiet pleasure.',
        );
        expect(book.blocks[2].text, 'Words & pictures.');
        expect(book.chapters.map((c) => c.title), [
          'First lesson',
          'Word table',
          'Second lesson',
        ]);
        expect(book.chapters.map((c) => c.depth), [0, 1, 0]);
        expect(book.blocks[book.chapters.last.block].text, 'Chapter Two');
        final table = book.blocks.firstWhere((b) => b.rows != null);
        expect(table.rows![1], ['Tomorrow', 'The next day']);
        expect(table.tableHeader, isTrue);
        expect(book.blocks[book.chapters[1].block].text, 'Vocabulary');
        expect(book.assets.keys, ['OPS/images/lesson image.png']);
        final decoded = BookContent.decode(book.encode());
        expect(decoded.chapters.last.block, book.chapters.last.block);
        expect(
          decoded.blocks.firstWhere((b) => b.rows != null).rows,
          table.rows,
        );
        expect(decoded.assets, isEmpty); // Blobs must not inflate shelf JSON.
      },
    );
  }
  test('reject incorrect declared sizes before unbounded decompression', () {
    final bytes = sample();
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 46; i++) {
      if (view.getUint32(i, Endian.little) == 0x02014b50) {
        final length = view.getUint16(i + 28, Endian.little);
        final name = utf8.decode(bytes.sublist(i + 46, i + 46 + length));
        if (name == 'OPS/text/first.xhtml') {
          view.setUint32(i + 24, 8, Endian.little);
          break;
        }
      }
    }
    expect(() => EpubParser().parse(bytes), throwsFormatException);
  });
  test('missing image has a readable placeholder; scripts and remote images are not loaded', () {
    final bytes = change({
      'OPS/text/first.xhtml': '<html><body><h1>Local</h1><script>SECRET</script><img src="../missing.png" alt="Diagram"/><img src="https://example.com/picture.png" alt="Remote"/><p>Still reading.</p></body></html>',
    });
    final book = EpubParser().parse(bytes);
    expect(book.blocks.map((b) => b.text).join(' '), isNot(contains('SECRET')));
    expect(book.blocks.map((b) => b.text).join(' '), contains('图片缺失'));
    expect(book.assets, isEmpty);
  });
  test(
    'merged cells degrade explicitly instead of displaying misleading columns',
    () {
      final book = EpubParser().parse(
        change({
          'OPS/text/first.xhtml': '<html><body><table><tr><td colspan="2">Merged</td></tr><tr><td>Left</td><td>Right</td></tr></table></body></html>',
        }),
      );
      expect(book.blocks.first.text, '复杂表格（按行显示）');
      expect(book.blocks[2].text, 'Left · Right');
      expect(book.blocks.where((b) => b.rows != null), isEmpty);
    },
  );
  test('old TXT JSON remains readable', () {
    final book = BookContent.decode(
      '{"blocks":[{"text":"Chapter 1","heading":true}],"encoding":"GBK"}',
    );
    expect(book.format, 'txt');
    expect(book.contents.single.title, 'Chapter 1');
  });
  test('reject corrupt, oversized, traversal, DRM, fixed-layout and missing resources', () {
    final parser = EpubParser();
    expect(
      () => parser.parse(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => parser.parse(Uint8List(EpubParser.maxFileSize + 1)),
      throwsFormatException,
    );
    expect(
      () => parser.parse(change({}, path: '../bad')),
      throwsFormatException,
    );
    final archive = ZipDecoder().decodeBytes(sample());
    final opf = utf8.decode(archive.find('OPS/book.opf')!.content);
    expect(
      () => parser.parse(
        change({
          'OPS/book.opf': opf.replaceFirst(
            '</metadata>',
            '<meta property="rendition:layout">pre-paginated</meta></metadata>',
          ),
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        change({
          'OPS/book.opf': opf.replaceFirst('text/first.xhtml', 'missing.xhtml'),
        }),
      ),
      throwsFormatException,
    );
  });
  test('DRM rejects; obfuscated fonts do not block readable content', () {
    expect(
      () => EpubParser().parse(
        change(
          {},
          path: 'META-INF/encryption.xml',
          bytes: utf8.encode(
            '<encryption><EncryptionMethod Algorithm="drm"/></encryption>',
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(
      EpubParser()
          .parse(
            change(
              {},
              path: 'META-INF/encryption.xml',
              bytes: utf8.encode(
                '<encryption><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/></encryption>',
              ),
            ),
          )
          .blocks,
      isNotEmpty,
    );
  });
  test('schema 1 upgrades without losing books/settings; resources survive reopen and delete', () async {
    final temp = Directory.systemTemp.createTempSync('reading-migrate-');
    final file = File('${temp.path}/reading.sqlite');
    final old = sql.sqlite3.open(file.path);
    old.execute(
      'CREATE TABLE books(id TEXT PRIMARY KEY,title TEXT NOT NULL,content TEXT NOT NULL,position INTEGER NOT NULL DEFAULT 0,style TEXT,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,last_read_at INTEGER NOT NULL DEFAULT 0)',
    );
    old.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
    old.execute('INSERT INTO books VALUES(?,?,?,?,?,?,?,?)', [
      'old',
      'Old book',
      TxtParser().parseText('one\ntwo').encode(),
      1,
      'saved style',
      1,
      2,
      3,
    ]);
    old.execute("INSERT INTO settings VALUES('readerStyle','saved global')");
    old.execute('PRAGMA user_version=1');
    old.close();
    var database = ReadingDatabase(NativeDatabase(file));
    final previous = (await database.book('old'))!;
    expect(previous.position, 1);
    expect(previous.style, 'saved style');
    expect(await database.setting('readerStyle'), 'saved global');
    final book = EpubParser().parse(sample());
    final id = await database.addBook(book.title!, book);
    await database.savePosition(id, book.chapters.last.block);
    await database.close();
    database = ReadingDatabase(NativeDatabase(file));
    expect((await database.book(id))!.position, book.chapters.last.block);
    final path = book.assets.keys.single;
    expect(await database.asset(id, path), book.assets[path]);
    await database.deleteBook(id);
    expect(await database.asset(id, path), isNull);
    expect((await database.books()).single.id, 'old');
    await database.close();
    temp.deleteSync(recursive: true);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/db/database.dart';

Uint8List linkedBook(
  String first,
  String second, {
  int version = 3,
  bool nonLinear = false,
}) {
  final archive = ZipDecoder().decodeBytes(
    File('test/fixtures/epub/lesson-epub$version.epub').readAsBytesSync(),
  );
  String page(String body) =>
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>$body</body></html>';
  archive.add(ArchiveFile.string('OPS/text/first.xhtml', page(first)));
  archive.add(ArchiveFile.string('OPS/text/second.xhtml', page(second)));
  if (nonLinear) {
    final opf = String.fromCharCodes(archive.find('OPS/book.opf')!.content);
    archive.add(
      ArchiveFile.string(
        'OPS/book.opf',
        opf.replaceFirst('idref="second"', 'idref="second" linear="no"'),
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  for (final version in [2, 3]) {
    test(
      'EPUB $version text ranges, cross-chapter note and backlink round trip',
      () {
        final book = EpubParser().parse(
          linkedBook(
            '''
        <p>Before 😀 <a id="ref" epub:type="noteref" href="sec%6Fnd.xhtml#n%201">
          [ <em>1</em> ] \t </a> after.</p>
        <p><a href="#local">local</a></p><aside id="local">Local note.</aside>
        ''',
            '''<aside id="n 1" epub:type="footnote"><p>Explanation
          <a role="doc-backlink" href="first.xhtml#ref">Back</a>.</p></aside>''',
            version: version,
          ),
        );
        final note = book.links.first;
        final text = book.blocks[note.block].text;
        expect(text, 'Before 😀 [ 1 ] after.');
        expect(text.substring(note.start, note.end), '[ 1 ]');
        expect(note.start, 10); // Emoji occupies two UTF-16 code units.
        expect(note.kind, BookLinkKind.noteref);
        expect(note.status, BookLinkStatus.resolved);
        expect(note.targetKey, 'OPS/text/second.xhtml#n 1');
        expect(book.blocks[note.target!.block].text, 'Explanation Back.');
        final back = book.links.last;
        expect(back.kind, BookLinkKind.backlink);
        expect(back.target!.block, note.block);
        expect(back.target!.offset, note.start);
        expect(book.blocks[book.links[1].target!.block].text, 'Local note.');
        final restored = BookContent.decode(book.encode());
        expect(restored.encode(), book.encode());
        expect(restored.links.first.target!.block, note.target!.block);
      },
    );
  }

  test('missing, external, unsafe and non-linear targets never use chapter fallback', () {
    final book = EpubParser().parse(
      linkedBook(
        '''<p>
      <a href="#absent">missing id</a> <a href="missing.xhtml#n">missing file</a>
      <a href="second.xhtml#note">not loaded</a>
      <a href="https://example.com/#note">web</a> <a href="javascript:alert(1)">script</a>
      <a href="../../../escape.xhtml#x">escape</a> <a href="%ZZ#bad">bad</a>
      <a href="first.xhtml?q=1#n">query</a>
      </p>''',
        '<p id="note">Excluded note must not be appended.</p>',
        nonLinear: true,
      ),
    );
    expect(book.links.map((l) => l.status), [
      BookLinkStatus.missingTarget,
      BookLinkStatus.missingTarget,
      BookLinkStatus.unavailableDocument,
      BookLinkStatus.external,
      BookLinkStatus.external,
      BookLinkStatus.invalid,
      BookLinkStatus.invalid,
      BookLinkStatus.invalid,
    ]);
    expect(book.links.every((l) => l.target == null), isTrue);
    expect(book.blocks.length, 1);
  });

  test('duplicate IDs select first; document namespaces and empty terminal IDs are safe', () {
    final book = EpubParser().parse(
      linkedBook('''
      <p>One <span id="same">first</span> <span id="same">second</span>.</p>
      <p><a href="#same">one</a> <a href="second.xhtml#same">two</a>
      <a href="#end">end</a></p><div id="end"></div>
      ''', '<p id="same">Other chapter</p>'),
    );
    expect(book.links[0].target!.offset, 4);
    expect(book.blocks[book.links[1].target!.block].text, 'Other chapter');
    expect(book.links[2].status, BookLinkStatus.missingTarget);
    expect(book.anchors.containsKey('OPS/text/first.xhtml#end'), isFalse);
  });

  test('links across block boundaries split into valid ranges, whitespace links vanish', () {
    final book = EpubParser().parse(
      linkedBook('''
      <a href="second.xhtml#n"><p> One <b>two</b> </p><p>Three</p></a>
      <p><a href="#missing"> \t </a>Tail</p>
      ''', '<p id="n">Note</p>'),
    );
    expect(book.links.length, 2);
    expect(
      book.links.map(
        (l) => book.blocks[l.block].text.substring(l.start, l.end),
      ),
      ['One two', 'Three'],
    );
    expect(
      book.links.every((l) => l.status == BookLinkStatus.resolved),
      isTrue,
    );
  });

  test('old TXT/EPUB JSON defaults to empty metadata; new links survive database reopen', () async {
    for (final format in ['txt', 'epub']) {
      final old = BookContent.decode(
        '{"blocks":[{"text":"Old"}],"format":"$format"}',
      );
      expect(old.links, isEmpty);
      expect(old.anchors, isEmpty);
      expect(old.blocks.single.text, 'Old');
    }
    final dir = Directory.systemTemp.createTempSync('reading-links-');
    final file = File('${dir.path}/books.sqlite');
    final book = EpubParser().parse(
      linkedBook(
        '<p><a href="second.xhtml#n">note</a></p>',
        '<p id="n">Saved note.</p>',
      ),
    );
    var db = ReadingDatabase(NativeDatabase(file));
    try {
      final id = await db.addBook('Notes', book);
      await db.savePosition(id, 1);
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      final saved = (await db.book(id))!;
      expect(saved.position, 1);
      expect(saved.content.encode(), book.encode());
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });
}

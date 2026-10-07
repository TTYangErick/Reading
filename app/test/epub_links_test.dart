import 'dart:convert';
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

// Extra pages are manifest entries outside the spine. Main text/TOC stay fixed.
Uint8List supplementaryBook(
  String first,
  Map<String, String> pages, {
  int version = 3,
  bool declared = true,
  String mediaType = 'application/xhtml+xml',
  Map<String, List<int>> resources = const {},
}) {
  final archive = ZipDecoder().decodeBytes(
    linkedBook(first, '<h1 id="end">Main ending</h1>', version: version),
  );
  var opf = utf8.decode(archive.find('OPS/book.opf')!.content);
  for (final entry in pages.entries.indexed) {
    final name = entry.$2.key;
    archive.add(ArchiveFile.string('OPS/text/$name', entry.$2.value));
    if (declared) {
      opf = opf.replaceFirst(
        '</manifest>',
        '<item id="extra${entry.$1}" href="text/$name" media-type="$mediaType"/></manifest>',
      );
    }
  }
  archive.add(ArchiveFile.string('OPS/book.opf', opf));
  for (final entry in resources.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String notePage(String body) => '<html><body>$body</body></html>';
String noteOfSize(int size) {
  final content = notePage('<p id="n">Note</p><!-- -->');
  return content.replaceFirst(
    '<!-- -->',
    '<!--${'x' * (size - content.length + 1)}-->',
  );
}

// Change central directory metadata without changing the compressed payload.
Uint8List tamperNote(Uint8List bytes, int field, int value) {
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < bytes.length - 46; i++) {
    if (view.getUint32(i, Endian.little) != 0x02014b50) continue;
    final length = view.getUint16(i + 28, Endian.little);
    final name = utf8.decode(bytes.sublist(i + 46, i + 46 + length));
    if (name == 'OPS/text/note.xhtml') {
      view.setUint32(i + field, value, Endian.little);
      return bytes;
    }
  }
  throw StateError('Missing note directory entry');
}

void main() {
  test('fixed-layout non-linear pages stay unavailable', () {
    final archive = ZipDecoder().decodeBytes(
      linkedBook(
        '<p><a href="second.xhtml#n">Note</a></p>',
        '<p id="n">Fixed note</p>',
        nonLinear: true,
      ),
    );
    final opf = utf8.decode(archive.find('OPS/book.opf')!.content);
    archive.add(
      ArchiveFile.string(
        'OPS/book.opf',
        opf.replaceFirst(
          'idref="second"',
          'idref="second" properties="rendition:layout-pre-paginated"',
        ),
      ),
    );
    final book = EpubParser().parse(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(book.supplementaryDocuments, isEmpty);
    expect(book.links.single.status, BookLinkStatus.unavailableDocument);
    expect(book.links.single.target, isNull);
  });

  for (final version in [2, 3]) {
    for (final nonLinear in [false, true]) {
      test('EPUB $version ${nonLinear ? "linear=no" : "non-spine"} notes have separate positions and backlinks', () {
        const body =
            '<p>Before 😀 <a id="ref" role="doc-noteref" href="second.xhtml#n%201"> [1] </a> after.</p><p>Tail</p>';
        const note =
            '<aside id="n 1"><p>Explanation <a role="doc-backlink" href="first.xhtml#ref">Back</a>.</p></aside>';
        var bytes = linkedBook(body, note, version: version, nonLinear: true);
        if (!nonLinear) {
          final archive = ZipDecoder().decodeBytes(bytes);
          final opf = utf8.decode(archive.find('OPS/book.opf')!.content);
          archive.add(
            ArchiveFile.string(
              'OPS/book.opf',
              opf.replaceFirst(
                RegExp(r'<itemref[^>]*idref="second"[^>]*/>'),
                '',
              ),
            ),
          );
          bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        }
        final book = EpubParser().parse(bytes);
        expect(book.blocks.map((b) => b.text), [
          'Before 😀 [1] after.',
          'Tail',
        ]);
        final ref = book.links.first;
        final back = book.links.last;
        expect(ref.document, isNull);
        expect(ref.target!.document, 'OPS/text/second.xhtml');
        expect(ref.target!.block, 0);
        expect(ref.target!.offset, 0);
        final notes = book.supplementaryDocuments[ref.target!.document]!;
        expect(notes.single.text, 'Explanation Back.');
        expect(back.document, ref.target!.document);
        expect(notes[back.block].text.substring(back.start, back.end), 'Back');
        expect(back.kind, BookLinkKind.backlink);
        expect(back.target!.toJson(), {
          'block': ref.block,
          'offset': ref.start,
        });
        expect(BookContent.decode(book.encode()).encode(), book.encode());
        expect(
          book.chapters.every((c) => c.block < book.blocks.length),
          isTrue,
        );
      });
    }
  }

  test('supplements preserve all body blocks, TOC, anchors and saved progress after reopen', () async {
    const body =
        '<h1>Chapter One</h1><p id="ref">Before <a href="note.xhtml#n">note</a></p><p id="table">Tail</p>';
    final baseline = EpubParser().parse(supplementaryBook(body, {}));
    final book = EpubParser().parse(
      supplementaryBook(body, {
        'note.xhtml': notePage(
          '<p id="n">Note <a href="first.xhtml#ref">Back</a></p><img src="../images/lesson%20image.png"/><table><tr><td>A</td><td>B</td></tr></table>',
        ),
      }),
    );
    expect(
      book.blocks.map((b) => b.toJson()),
      baseline.blocks.map((b) => b.toJson()),
    );
    expect(
      book.contents.map((c) => c.toJson()),
      baseline.contents.map((c) => c.toJson()),
    );
    for (final anchor in baseline.anchors.entries) {
      expect(book.anchors[anchor.key]!.toJson(), anchor.value.toJson());
    }
    final dir = Directory.systemTemp.createTempSync('reading-supplements-');
    final file = File('${dir.path}/books.sqlite');
    var db = ReadingDatabase(NativeDatabase(file));
    try {
      final oldId = await db.addBook('Body', baseline);
      final id = await db.addBook('Notes', book);
      await db.savePosition(oldId, 2);
      await db.savePosition(id, 2);
      await db.close();
      db = ReadingDatabase(NativeDatabase(file));
      final saved = (await db.book(id))!;
      final old = (await db.book(oldId))!;
      expect(saved.position, old.position);
      expect(saved.progress, old.progress);
      expect(saved.content.encode(), book.encode());
      expect(old.content.encode(), baseline.encode());
      final notes = saved.content.supplementaryDocuments.values.single;
      expect(notes.last.rows, [
        ['A', 'B'],
      ]);
      final image = notes.firstWhere((b) => b.image != null).image!;
      expect(await db.asset(id, image), book.assets[image]);
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  });

  test(
    'old link/anchor JSON still means body positions and has no supplements',
    () {
      final old = BookContent.decode(
        '{"blocks":[{"text":"note"}],"links":[{"block":0,"start":0,"end":4,"href":"#n","kind":"link","status":"resolved","target":{"block":0,"offset":0}}],"anchors":{"chapter#n":{"block":0}}}',
      );
      expect(old.supplementaryDocuments, isEmpty);
      expect(old.links.single.document, isNull);
      expect(old.links.single.target!.document, isNull);
      expect(old.anchors.values.single.document, isNull);
      expect(old.links.single.target!.toJson(), {'block': 0, 'offset': 0});
      expect(BookContent.decode(old.encode()).encode(), old.encode());
    },
  );

  test('cycles, aliases, chains, duplicate and missing anchors are bounded and local', () {
    final book = EpubParser().parse(
      supplementaryBook(
        '<p id="ref"><a href="a.xhtml#n">A</a> <a href="./a.xhtml#absent">missing</a> <a href="a.xhtml#end">empty end</a> <a href="empty.xhtml">empty page</a></p>',
        {
          'a.xhtml': notePage(
            '<p id="n">First <span id="n">duplicate</span> <a href="b.xhtml#n">B</a></p><div id="end"></div>',
          ),
          'b.xhtml': notePage(
            '<p id="n">Other <a href="%61.xhtml#n">cycle</a> <a href="#n">self</a> <a href="first.xhtml#ref">Back</a></p>',
          ),
          'empty.xhtml': notePage('<div id="n"></div>'),
          'unused.xhtml': 'Not read',
        },
      ),
    );
    expect(book.supplementaryDocuments.length, 3);
    expect(book.links.take(4).map((l) => l.status), [
      BookLinkStatus.resolved,
      BookLinkStatus.missingTarget,
      BookLinkStatus.missingTarget,
      BookLinkStatus.missingTarget,
    ]);
    expect(book.links.first.target!.offset, 0);
    expect(book.links[4].target!.document, 'OPS/text/b.xhtml');
    expect(book.links[5].target!.document, 'OPS/text/a.xhtml');
    expect(book.links[6].target!.document, 'OPS/text/b.xhtml');
    expect(book.links.last.target!.document, isNull);
    expect(book.anchors.containsKey('OPS/text/a.xhtml#end'), isFalse);
    expect(book.anchors.containsKey('OPS/text/empty.xhtml'), isFalse);
  });

  test('only referenced local manifest HTML is loaded; bad links stay non-actionable', () {
    for (final config in [
      (false, 'application/xhtml+xml'),
      (true, 'image/svg+xml'),
    ]) {
      final book = EpubParser().parse(
        supplementaryBook(
          '<p><a href="note.xhtml#n">note</a></p>',
          {'note.xhtml': notePage('<p id="n">Note</p>')},
          declared: config.$1,
          mediaType: config.$2,
        ),
      );
      expect(book.supplementaryDocuments, isEmpty);
      expect(book.links.single.status, BookLinkStatus.unavailableDocument);
    }
    final book = EpubParser().parse(
      supplementaryBook('<p><a href="note.xhtml">note</a></p>', {
        'note.xhtml': notePage(
          '<p id="n"><a href="missing.xhtml">missing</a> <a href="#absent">id</a> <a href="https://example.com/note.xhtml">web</a> <a href="//example.com/note.xhtml">authority</a> <a href="javascript:alert(1)">script</a> <a href="../../../escape.xhtml">escape</a> <a href="note.xhtml?q=1">query</a> <a href="%ZZ">bad</a></p><script>SECRET</script>',
        ),
      }, mediaType: 'text/html'),
    );
    expect(
      book.supplementaryDocuments.values.single.single.text,
      isNot(contains('SECRET')),
    );
    expect(book.links.skip(1).map((l) => l.status), [
      BookLinkStatus.missingTarget,
      BookLinkStatus.missingTarget,
      BookLinkStatus.external,
      BookLinkStatus.external,
      BookLinkStatus.external,
      BookLinkStatus.invalid,
      BookLinkStatus.invalid,
      BookLinkStatus.invalid,
    ]);
    expect(book.links.skip(1).every((l) => l.target == null), isTrue);
  });

  test('supplementary document count and chain depth stop at their limits', () {
    final count = EpubParser.maxSupplementaryDocuments;
    final book = EpubParser().parse(
      supplementaryBook(
        '<p>${[for (var i = 0; i <= count; i++) '<a href="n$i.xhtml#n">$i</a>'].join(' ')}</p>',
        {
          for (var i = 0; i <= count; i++)
            'n$i.xhtml': notePage('<p id="n">Note $i</p>'),
        },
      ),
    );
    expect(book.supplementaryDocuments.length, count);
    expect(
      book.links.take(count).every((l) => l.status == BookLinkStatus.resolved),
      isTrue,
    );
    expect(book.links.last.status, BookLinkStatus.unavailableDocument);
    expect(book.links.last.target, isNull);
    final depth = EpubParser.maxSupplementaryDepth;
    final chain = EpubParser().parse(
      supplementaryBook('<p><a href="n0.xhtml">Start</a></p>', {
        for (var i = 0; i <= depth; i++)
          'n$i.xhtml': notePage(
            '<p>Note $i <a href="n${i + 1}.xhtml">next</a> <a href="n0.xhtml">cycle</a></p>',
          ),
      }),
    );
    expect(chain.supplementaryDocuments.length, depth);
    expect(
      chain.links[chain.links.length - 2].status,
      BookLinkStatus.unavailableDocument,
    );
    expect(chain.links.last.status, BookLinkStatus.resolved);
  });

  test('reference traversal budget also bounds repeated references', () {
    final body =
        '<p>${'<a href="note.xhtml#n">note</a> ' * EpubParser.maxSupplementaryReferences}<a href="later.xhtml">later</a></p>';
    final book = EpubParser().parse(
      supplementaryBook(body, {
        'note.xhtml': notePage('<p id="n">Note</p>'),
        'later.xhtml': notePage('<p>Not loaded</p>'),
      }),
    );
    expect(book.supplementaryDocuments.keys, ['OPS/text/note.xhtml']);
    expect(book.links.last.status, BookLinkStatus.unavailableDocument);
  });

  test('per-document and cumulative decompressed byte limits preserve the body', () {
    final limit = EpubParser.maxSupplementaryDocumentBytes;
    final oversized = EpubParser().parse(
      supplementaryBook('<p><a href="note.xhtml">note</a></p>', {
        'note.xhtml': noteOfSize(limit + 1),
      }),
    );
    expect(oversized.supplementaryDocuments, isEmpty);
    expect(oversized.links.single.status, BookLinkStatus.unavailableDocument);
    final count = EpubParser.maxSupplementaryBytes ~/ limit;
    final book = EpubParser().parse(
      supplementaryBook(
        '<p>${[for (var i = 0; i <= count; i++) '<a href="n$i.xhtml#n">$i</a>'].join(' ')}</p>',
        {for (var i = 0; i <= count; i++) 'n$i.xhtml': noteOfSize(limit)},
      ),
    );
    expect(book.supplementaryDocuments.length, count);
    expect(
      book.links.take(count).every((l) => l.status == BookLinkStatus.resolved),
      isTrue,
    );
    expect(book.links.last.status, BookLinkStatus.unavailableDocument);
    expect(book.blocks.length, 2);
  });

  test('supplementary images share the byte budget, reuse assets and retain placeholders', () {
    final image = Uint8List(EpubParser.maxSupplementaryBytes - 1024);
    final book = EpubParser().parse(
      supplementaryBook(
        '<p><a href="note.xhtml">note</a></p>',
        {
          'note.xhtml': notePage(
            '<p>Note</p><img src="large.png"/><img src="large.png"/><img src="extra.png" alt="Extra"/><img src="absent.png"/><img src="https://example.com/p.png"/><p><a href="tail.xhtml">Tail</a></p>',
          ),
          'tail.xhtml': notePage('<p>Small tail still fits</p>'),
        },
        resources: {
          'OPS/text/large.png': image,
          'OPS/text/extra.png': Uint8List(2048),
        },
      ),
    );
    final notes = book.supplementaryDocuments['OPS/text/note.xhtml']!;
    expect(book.assets.keys, ['OPS/text/large.png']);
    expect(notes.where((b) => b.image != null).length, 2);
    expect(notes[3].text, contains('补充资源超出限额'));
    expect(notes[4].text, contains('图片缺失'));
    expect(notes[5].text, contains('暂不支持此图片格式'));
    expect(book.supplementaryDocuments.length, 2);
  });

  test('supplementary decompression still verifies actual size and CRC', () {
    for (final field in [24, 16]) {
      final bytes = supplementaryBook('<p><a href="note.xhtml">note</a></p>', {
        'note.xhtml': notePage('<p>Stored note</p>'),
      });
      expect(
        () => EpubParser().parse(tamperNote(bytes, field, field == 24 ? 8 : 0)),
        throwsFormatException,
      );
    }
  });

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

  test('missing, external, unsafe and unsupported targets never use chapter fallback', () {
    final book = EpubParser().parse(
      linkedBook(
        '''<p>
      <a href="#absent">missing id</a> <a href="missing.xhtml#n">missing file</a>
      <a href="../images/lesson%20image.png">not a document</a>
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
      expect(old.supplementaryDocuments, isEmpty);
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

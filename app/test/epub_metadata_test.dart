import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';

// Existing fixtures and all added text/images are project-owned samples.
Uint8List metadataFixture({
  int version = 3,
  String metadata = '',
  String manifest = '',
  String guide = '',
  Map<String, List<int>> files = const {},
}) {
  final archive = ZipDecoder().decodeBytes(
    File('test/fixtures/epub/lesson-epub$version.epub').readAsBytesSync(),
  );
  var opf = utf8.decode(archive.find('OPS/book.opf')!.content);
  opf = opf
      .replaceFirst('</metadata>', '$metadata</metadata>')
      .replaceFirst('</manifest>', '$manifest</manifest>')
      .replaceFirst('</package>', '$guide</package>');
  archive.add(ArchiveFile.string('OPS/book.opf', opf));
  for (final entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const coverItem =
    '<item id="cover" href="images/cover%20art.png" '
    'media-type="image/png" properties="scripted cover-image"/>';
const coverPath = 'OPS/images/cover art.png';
final coverBytes = ZipDecoder()
    .decodeBytes(File('test/fixtures/epub/lesson-epub3.epub').readAsBytesSync())
    .find('OPS/images/lesson image.png')!
    .content;

void expectSameReadingContent(BookContent actual, BookContent original) {
  final a = jsonDecode(actual.encode()) as Map<String, dynamic>;
  final b = jsonDecode(original.encode()) as Map<String, dynamic>;
  a.remove('authors');
  a.remove('cover');
  expect(a, b); // Includes blocks, TOC, source offsets, links and anchors.
}

void main() {
  test(
    'EPUB3 cover-only image and creator roles preserve all reading content',
    () {
      final original = EpubParser().parse(metadataFixture());
      final parsed = EpubParser().parse(
        metadataFixture(
          metadata: '''<dc:creator id="a">  Jane\n Austen  </dc:creator>
        <meta refines="#a" property="role" scheme="marc:relators">aut</meta>
        <dc:creator id="t">Translator</dc:creator>
        <meta refines="#t" property="role">trl</meta>
        <dc:creator>Coauthor</dc:creator><dc:creator>Jane Austen</dc:creator>
        <dc:contributor>Editor</dc:contributor>''',
          manifest: coverItem,
          files: {coverPath: coverBytes},
        ),
      );
      expect(parsed.authors, ['Jane Austen', 'Coauthor']);
      expect(parsed.cover, coverPath);
      expect(parsed.assets[coverPath], coverBytes);
      expect(parsed.assets.length, original.assets.length + 1);
      expectSameReadingContent(parsed, original);
      final decoded = BookContent.decode(parsed.encode());
      expect(decoded.authors, parsed.authors);
      expect(decoded.cover, coverPath);
      expect(decoded.assets, isEmpty);
    },
  );

  test('EPUB2 cover ID, namespaced creator roles and shared body asset', () {
    final parsed = EpubParser().parse(
      metadataFixture(
        version: 2,
        metadata: '''<meta name="cover" content="picture"/>
        <dc:creator xmlns:opf="http://www.idpf.org/2007/opf" opf:role="aut">Author</dc:creator>
        <dc:creator xmlns:opf="http://www.idpf.org/2007/opf" opf:role="edt">Editor</dc:creator>''',
      ),
    );
    expect(parsed.authors, ['Author']);
    expect(parsed.cover, 'OPS/images/lesson image.png');
    expect(parsed.assets.length, 1);
  });

  test(
    'modern cover has precedence; missing modern cover falls back to legacy',
    () {
      for (final existing in [true, false]) {
        final parsed = EpubParser().parse(
          metadataFixture(
            metadata: '<meta name="cover" content="picture"/>',
            manifest: coverItem,
            files: existing ? {coverPath: coverBytes} : {},
          ),
        );
        expect(
          parsed.cover,
          existing ? coverPath : 'OPS/images/lesson image.png',
        );
      }
    },
  );

  for (final svg in [false, true]) {
    test('explicit guide page raster wrapper; svg=$svg leaves body unchanged', () {
      final original = EpubParser().parse(metadataFixture());
      final image = svg
          ? '<svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="images/cover%20art.png"/></svg>'
          : '<img src="images/cover%20art.png"/>';
      final parsed = EpubParser().parse(
        metadataFixture(
          manifest:
              '${coverItem.replaceFirst('scripted cover-image', '')}'
              '<item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>',
          guide: '<guide><reference type="cover" href="cover.xhtml#start"/></guide>',
          files: {
            coverPath: coverBytes,
            'OPS/cover.xhtml': utf8.encode(
              '<html><body>$image<a href="https://example.test">Ignored</a></body></html>',
            ),
          },
        ),
      );
      expect(parsed.cover, coverPath);
      expect(parsed.supplementaryDocuments, isEmpty);
      expectSameReadingContent(parsed, original);
    });
  }

  test('optional absent/unsafe/unsupported covers fall back without guessing first image', () {
    for (final href in [
      'missing.png',
      'https://example.test/cover.png',
      '//host/cover.png',
      '../../outside.png',
      '%ZZ',
      'images/cover%20art.png?query=1',
    ]) {
      final parsed = EpubParser().parse(
        metadataFixture(
          manifest: coverItem.replaceFirst('images/cover%20art.png', href),
          files: {coverPath: coverBytes},
        ),
      );
      expect(parsed.cover, isNull, reason: href);
      expect(parsed.assets.length, 1);
    }
    final unsupported = EpubParser().parse(
      metadataFixture(
        manifest: coverItem.replaceFirst('image/png', 'image/svg+xml'),
        files: {coverPath: coverBytes},
      ),
    );
    expect(unsupported.cover, isNull);
    expect(EpubParser().parse(metadataFixture()).cover, isNull);
  });

  test('cover and cover-page budgets skip optional resources; author list bounded', () {
    final parsed = EpubParser().parse(
      metadataFixture(
        metadata:
            '<dc:creator>${'x' * 257}</dc:creator>'
            '${List.generate(30, (i) => '<dc:creator>Author $i</dc:creator>').join()}',
        manifest: coverItem,
        files: {coverPath: Uint8List(EpubParser.maxCoverBytes + 1)},
      ),
    );
    expect(parsed.cover, isNull);
    expect(parsed.assets.length, 1);
    expect(parsed.authors.length, 16);
    expect(parsed.authors.first, 'Author 0');
    final largePage = EpubParser().parse(
      metadataFixture(
        manifest: '<item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>',
        guide: '<guide><reference type="cover" href="cover.xhtml"/></guide>',
        files: {
          'OPS/cover.xhtml': Uint8List(EpubParser.maxCoverDocumentBytes + 1),
        },
      ),
    );
    expect(largePage.cover, isNull);
  });

  test('bad optional cover pages do not prevent reading or traverse links', () {
    for (final page in [
      Uint8List.fromList([255, 254]),
      utf8.encode(
        '<html><body><svg><image href="images/cover%20art.png"/><path d="M0 0 L1 1"/></svg></body></html>',
      ),
      utf8.encode(
        '<html><body><a href="other.xhtml">Next cover</a><img src="https://example.test/cover.png"/></body></html>',
      ),
    ]) {
      final parsed = EpubParser().parse(
        metadataFixture(
          manifest:
              '${coverItem.replaceFirst('scripted cover-image', '')}'
              '<item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>',
          guide: '<guide><reference type="cover" href="cover.xhtml"/></guide>',
          files: {coverPath: coverBytes, 'OPS/cover.xhtml': page},
        ),
      );
      expect(parsed.cover, isNull);
      expect(parsed.assets.length, 1);
      expect(parsed.supplementaryDocuments, isEmpty);
    }
  });

  test('cover-only CRC failure still rejects import', () {
    final bytes = metadataFixture(
      manifest: coverItem,
      files: {coverPath: coverBytes},
    );
    final view = ByteData.sublistView(bytes);
    var changed = false;
    for (var i = 0; i < bytes.length - 46; i++) {
      if (view.getUint32(i, Endian.little) != 0x02014b50) continue;
      final length = view.getUint16(i + 28, Endian.little);
      final name = utf8.decode(bytes.sublist(i + 46, i + 46 + length));
      if (name == coverPath) {
        view.setUint32(i + 16, 0, Endian.little);
        changed = true;
        break;
      }
    }
    expect(changed, true);
    expect(() => EpubParser().parse(bytes), throwsFormatException);
  });

  test(
    'old JSON defaults, omits absent metadata and rejects malformed new types',
    () {
      final old = BookContent.decode('{"blocks":[{"text":"Old"}]}');
      expect(old.authors, isEmpty);
      expect(old.cover, isNull);
      expect(jsonDecode(old.encode()), isNot(contains('authors')));
      expect(jsonDecode(old.encode()), isNot(contains('cover')));
      expect(
        () => BookContent.decode('{"blocks":[],"authors":[1]}'),
        throwsA(isA<TypeError>()),
      );
    },
  );
}

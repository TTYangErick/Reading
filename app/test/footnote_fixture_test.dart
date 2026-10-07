import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';

void main() {
  for (final version in [2, 3]) {
    test(
      'native EPUB $version sample has independent notes and exact returns',
      () {
        final content = EpubParser().parse(
          File('test/fixtures/epub/footnotes-epub$version.epub')
              .readAsBytesSync(),
        );
        expect(
          content.supplementaryDocuments.keys,
          unorderedEquals(['OPS/notes.xhtml', 'OPS/extra.xhtml']),
        );
        expect(
          content.blocks.any((b) => b.text == 'Independent note one'),
          isFalse,
        );
        expect(content.contents.length, 2);
        final reference = content.links.singleWhere(
          (l) => l.document == null && l.href == 'notes.xhtml#one',
        );
        expect(reference.block, greaterThan(0));
        expect(reference.target?.document, 'OPS/notes.xhtml');
        final returns = content.links.where((l) => l.href == 'body.xhtml#ref');
        expect(returns.length, 2);
        for (final link in returns) {
          expect(link.target?.document, isNull);
          expect(link.target?.block, reference.block);
          expect(link.target?.offset, reference.start);
        }
        expect(content.assets.length, 1);
        expect(
          content.supplementaryDocuments['OPS/notes.xhtml']!
              .where((b) => b.rows != null)
              .length,
          1,
        );
        expect(BookContent.decode(content.encode()).encode(), content.encode());
      },
    );
  }
}

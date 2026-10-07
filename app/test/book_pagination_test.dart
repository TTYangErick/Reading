import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';
import 'package:reading_app/db/database.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/pagination.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const style = ReaderStyle(font: 'Literata');
  setUpAll(() async {
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
  });
  BookPagination layout(
    List<BookBlock> blocks, {
    Size viewport = const Size(408, 180),
    Map<String, Size> sizes = const {},
    ReaderStyle readerStyle = style,
    TextScaler scaler = TextScaler.noScaling,
  }) => const BookPaginator().paginate(
    BookContent(blocks),
    viewport: viewport,
    platform: TargetPlatform.android,
    style: readerStyle,
    imageSizes: sizes,
    textScaler: scaler,
  );
  List<PageFragment> fragments(BookPagination result) =>
      result.pages.expand((p) => p.fragments).toList();
  void checkPages(BookPagination result) {
    for (var page = 0; page < result.pages.length; page++) {
      final current = result.pages[page];
      expect(result.pageForAnchor(current.start), page);
      expect(current.fragments.first.top, 0);
      for (var i = 1; i < current.fragments.length; i++) {
        expect(
          current.fragments[i].top,
          greaterThanOrEqualTo(
            current.fragments[i - 1].top +
                current.fragments[i - 1].height -
                .001,
          ),
        );
      }
      if (!current.overflows) {
        expect(
          current.height,
          lessThanOrEqualTo(result.contentSize.height + .001),
        );
      }
    }
  }

  test('text-only book pages exactly match the existing text paginator', () {
    final blocks = [
      const BookBlock('Title', heading: true),
      BookBlock(List.filled(80, 'Hello 👨‍👩‍👧‍👦 tomorrow.\n').join()),
      const BookBlock(''),
      const BookBlock('Another title', heading: true),
      const BookBlock('Last'),
    ];
    final mixed = layout(blocks);
    final text = const TextPaginator().paginate(
      BookContent(blocks),
      viewport: const Size(408, 180),
      platform: TargetPlatform.android,
      style: style,
    );
    expect(mixed.pages.length, text.pages.length);
    for (var p = 0; p < text.pages.length; p++) {
      final actual = mixed.pages[p].fragments.cast<PageTextFragment>();
      expect(
        actual.map(
          (f) => [
            f.anchor.position.block,
            f.anchor.position.offset,
            f.endOffset,
            f.top,
            f.height,
          ],
        ),
        text.pages[p].lines.map(
          (l) => [l.start.block, l.start.offset, l.endOffset, l.top, l.height],
        ),
      );
    }
    checkPages(mixed);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      'chapter boundaries start pages on $platform without changing old JSON',
      () async {
        const original = BookContent(
          [
            BookBlock('Chapter one', heading: true),
            BookBlock('First paragraph.'),
            BookBlock('An ordinary subheading', heading: true),
            BookBlock('Still chapter one.'),
            BookBlock('Chapter two', heading: true),
            BookBlock('Second paragraph.'),
          ],
          chapters: [
            BookChapter('Chapter two', 4, depth: 1),
            BookChapter('Chapter one', 0),
            BookChapter('Duplicate target', 4),
            BookChapter('Invalid', -1),
            BookChapter('Outside', 999),
          ],
        );
        final json = original.encode();
        final content = BookContent.decode(json);
        const viewport = Size(408, 1000);
        final result = const BookPaginator().paginate(
          content,
          viewport: viewport,
          platform: platform,
          style: style,
        );
        expect(result.pages.map((p) => p.start.position.block), [0, 4]);
        expect(
          result.pages.first.fragments
              .map((f) => f.anchor.position.block)
              .toSet(),
          {0, 1, 2, 3},
        );
        checkPages(result);
        final text = const TextPaginator().paginate(
          content,
          viewport: viewport,
          platform: platform,
          style: style,
        );
        expect(text.pages.map((p) => p.lines.first.start.block), [0, 4]);
        final asyncResult = (await const BookPaginator().paginateAsync(
          content,
          viewport: viewport,
          platform: platform,
          style: style,
        ))!;
        expect(
          asyncResult.pages.map((p) => p.start.encode()),
          result.pages.map((p) => p.start.encode()),
        );
        final anchor = const PageAnchor(BookPosition(5, offset: 7));
        expect(result.pageForAnchor(anchor), 1);
        final resized = const BookPaginator().paginate(
          content,
          viewport: const Size(500, 800),
          platform: platform,
          style: const ReaderStyle(font: 'Literata', size: 26),
        );
        expect(resized.pageForAnchor(anchor), 1);
        expect(content.encode(), json);
      },
    );
  }

  test('TXT chapter fallback breaks pages but supplementary headings stay continuous', () {
    final txt = TxtParser().parseText('Chapter 1\nFirst.\nChapter 2\nSecond.');
    final result = const BookPaginator().paginate(
      txt,
      viewport: const Size(408, 1000),
      platform: TargetPlatform.android,
      style: style,
    );
    expect(result.pages.map((p) => p.start.position.block), [0, 2]);
    final note = BookContent(
      txt.blocks,
      chapters: txt.contents,
      supplementaryDocuments: {'note': txt.blocks},
    );
    final supplementary = const BookPaginator().paginate(
      note,
      document: 'note',
      viewport: const Size(408, 1000),
      platform: TargetPlatform.android,
      style: style,
    );
    expect(supplementary.pages, hasLength(1));
    expect(supplementary.pages.single.start.position.document, 'note');
    final text = const TextPaginator().paginate(
      note,
      document: 'note',
      viewport: const Size(408, 1000),
      platform: TargetPlatform.android,
      style: style,
    );
    expect(text.pages, hasLength(1));
  });

  test(
    'image and table chapters start clean pages without extra blank pages',
    () {
      const content = BookContent(
        [
          BookBlock('Preface.'),
          BookBlock('Caption.', image: 'picture'),
          BookBlock(
            '',
            rows: [
              ['One', 'Two'],
            ],
          ),
          BookBlock('Last chapter.'),
        ],
        chapters: [
          BookChapter('Preface', 0),
          BookChapter('Picture', 1),
          BookChapter('Table', 2),
          BookChapter('Last', 3),
        ],
      );
      final result = const BookPaginator().paginate(
        content,
        viewport: const Size(408, 1000),
        platform: TargetPlatform.android,
        style: style,
        imageSizes: {'picture': const Size(40, 40)},
      );
      expect(result.pages.map((p) => p.start.position.block), [0, 1, 2, 3]);
      expect(result.pages[1].start.part, PagePart.image);
      expect(result.pages[2].start.part, PagePart.tableRow);
      checkPages(result);
    },
  );

  test('mixed pages preserve order, caption text and body positions', () {
    final caption = List.filled(
      30,
      'A caption with e\u0301 and words. ',
    ).join();
    final blocks = [
      const BookBlock('Before'),
      BookBlock(caption, image: 'wide'),
      const BookBlock(
        '',
        rows: [
          ['Word', 'Meaning'],
          ['Day', 'Tomorrow'],
        ],
        tableHeader: true,
      ),
      const BookBlock('After'),
    ];
    final before = BookContent(blocks).encode();
    final result = layout(blocks, sizes: {'wide': const Size(800, 400)});
    final all = fragments(result);
    final indexes = all.map((f) => f.anchor.position.block).toList();
    expect(indexes, orderedEquals([...indexes]..sort()));
    final image = all.whereType<PageImageFragment>().single;
    expect(image.width / image.height, 2);
    expect(image.width, lessThanOrEqualTo(result.contentSize.width));
    final captions = all.whereType<PageTextFragment>().where(
      (f) => f.anchor.part == PagePart.caption,
    );
    expect(
      captions
          .map((f) => caption.substring(f.anchor.position.offset, f.endOffset))
          .join(),
      caption,
    );
    expect(
      result.pageForPosition(const BookPosition(1)),
      result.pageForAnchor(image.anchor),
    );
    expect(
      result.pageForPosition(BookPosition(1, offset: caption.length)),
      result.pageForAnchor(captions.last.anchor),
    );
    expect(
      result.pageForPosition(const BookPosition(3)),
      result.pages.length - 1,
    );
    expect(BookContent(blocks).encode(), before);
    checkPages(result);
  });

  test(
    'images fit proportionally without upscaling; captions may continue',
    () {
      for (final size in [
        const Size(50, 20),
        const Size(200, 900),
        const Size(900, 200),
      ]) {
        final result = layout(
          [const BookBlock('Caption', image: 'p')],
          sizes: {'p': size},
        );
        final image = fragments(result).whereType<PageImageFragment>().single;
        expect(
          image.width / image.height,
          closeTo(size.width / size.height, .00001),
        );
        expect(image.width, lessThanOrEqualTo(size.width));
        expect(image.height, lessThanOrEqualTo(180));
        expect(
          image.left,
          closeTo((result.contentSize.width - image.width) / 2, .001),
        );
        expect(result.pages.every((p) => !p.overflows), isTrue);
        checkPages(result);
      }
    },
  );

  test('missing or invalid image dimensions produce explicit placeholders', () {
    for (final size in [
      null,
      Size.zero,
      const Size(double.nan, 1),
      const Size(1, -1),
    ]) {
      final result = layout(
        [const BookBlock('Alternative text', image: 'p')],
        sizes: {'p': ?size},
      );
      final image = fragments(result).whereType<PageImageFragment>().single;
      expect(image.unavailable, isTrue);
      expect(image.height, 180);
      expect(fragments(result).whereType<PageTextFragment>(), isNotEmpty);
      checkPages(result);
    }
  });

  test('table rows paginate once, preserve header and exact row anchors', () {
    final rows = List.generate(12, (r) => ['Word $r', 'Definition $r']);
    final result = layout([BookBlock('', rows: rows, tableHeader: true)]);
    final actual = fragments(result).whereType<PageTableRowFragment>().toList();
    expect(actual.length, rows.length);
    expect(
      actual.map((r) => r.anchor.row),
      List.generate(rows.length, (i) => i),
    );
    expect(actual.map((r) => r.cells.map((c) => c.text).toList()), rows);
    expect(actual.where((r) => r.isHeader).length, 1);
    expect(result.pageForPosition(const BookPosition(0)), 0);
    expect(
      result.pageForAnchor(
        const PageAnchor(BookPosition(0), part: PagePart.tableRow, row: 10),
      ),
      greaterThan(0),
    );
    expect(
      result.pageForAnchor(
        const PageAnchor(BookPosition(0), part: PagePart.tableRow, row: 99),
      ),
      isNull,
    );
    expect(result.pageForPosition(const BookPosition(0, offset: 1)), isNull);
    expect(result.pageForAnchor(const PageAnchor(BookPosition(0))), isNull);
    checkPages(result);
  });

  test('tall rows and wide tables are preserved with explicit overflow', () {
    final long = List.filled(80, 'Long cell. ').join();
    final result = layout([
      BookBlock(
        '',
        rows: [
          [long, 'Short', 'Third'],
          ['Last'],
        ],
      ),
      const BookBlock('After'),
    ], viewport: const Size(200, 100));
    final rows = fragments(result).whereType<PageTableRowFragment>().toList();
    expect(rows.length, 2);
    expect(rows.first.cells.first.text, long);
    expect(rows.first.height, greaterThan(100));
    expect(rows.first.width, 480);
    expect(rows.last.cells.map((c) => c.text), ['Last', '', '']);
    expect(result.pages.first.overflows, isTrue);
    expect(result.pages.first.fragments.length, 1);
    expect(result.pageForPosition(const BookPosition(1)), isNotNull);
    checkPages(result);
  });

  test('empty tables remain addressable, tiny viewports terminate', () {
    final blocks = [
      const BookBlock('', rows: []),
      const BookBlock('', rows: [[], []]),
      const BookBlock('图片', image: 'p'),
      const BookBlock('Text'),
    ];
    final result = layout(
      blocks,
      viewport: const Size(50, 1),
      sizes: {'p': const Size(20, 10)},
    );
    expect(fragments(result).whereType<PageTableRowFragment>().length, 3);
    expect(
      fragments(result).whereType<PageTableRowFragment>().first.emptyTable,
      isTrue,
    );
    expect(
      fragments(result).whereType<PageImageFragment>().single.unavailable,
      isFalse,
    );
    expect(
      fragments(result)
          .whereType<PageTextFragment>()
          .every((f) => f.anchor.part == PagePart.text),
      isTrue,
    );
    for (var b = 0; b < blocks.length; b++) {
      expect(result.pageForPosition(BookPosition(b)), isNotNull);
    }
    checkPages(result);
    expect(layout([]).pages, isEmpty);
  });

  test(
    'namespace isolation and row anchors survive viewport and font changes',
    () {
      final content = BookContent(
        [const BookBlock('Body')],
        supplementaryDocuments: {
          'notes': [
            const BookBlock('Alt', image: 'p'),
            BookBlock(
              '',
              rows: List.generate(10, (r) => ['Row $r', 'Content']),
            ),
          ],
        },
      );
      const target = PageAnchor(
        BookPosition(1, document: 'notes'),
        part: PagePart.tableRow,
        row: 8,
      );
      for (final height in [100.0, 400.0]) {
        final result = const BookPaginator().paginate(
          content,
          document: 'notes',
          viewport: Size(400, height),
          platform: TargetPlatform.android,
          textScaler: TextScaler.linear(1.4),
        );
        expect(result.pageForPosition(const BookPosition(1)), isNull);
        expect(
          result.pageForPosition(const BookPosition(-1, document: 'notes')),
          isNull,
        );
        final page = result.pages[result.pageForAnchor(target)!];
        expect(page.fragments.any((f) => f.anchor.row == 8), isTrue);
        checkPages(result);
      }
      expect(
        () => const BookPaginator().paginate(
          content,
          document: 'absent',
          viewport: const Size(400, 300),
          platform: TargetPlatform.android,
        ),
        throwsArgumentError,
      );
      expect(() => layout([], viewport: Size.zero), throwsArgumentError);
    },
  );

  test('dimension loader uses persisted BLOBs and deduplicates target document only', () async {
    final parsed = EpubParser().parse(
      File('test/fixtures/epub/footnotes-epub3.epub').readAsBytesSync(),
    );
    final db = ReadingDatabase(NativeDatabase.memory());
    try {
      final id = await db.addBook('Notes', parsed);
      final restored = (await db.book(id))!.content;
      expect(restored.assets, isEmpty);
      final calls = <String>[];
      final sizes = await loadPaginationImageSizes(restored, (path) {
        calls.add(path);
        return db.asset(id, path);
      }, document: 'OPS/notes.xhtml');
      expect(sizes.values.single, const Size(480, 240));
      expect(calls.length, 1);
      final result = const BookPaginator().paginate(
        restored,
        document: 'OPS/notes.xhtml',
        viewport: const Size(400, 300),
        platform: TargetPlatform.android,
        imageSizes: sizes,
      );
      expect(
        fragments(result).whereType<PageImageFragment>().single.unavailable,
        isFalse,
      );
      expect(fragments(result).whereType<PageTableRowFragment>(), isNotEmpty);
      checkPages(result);
      final image = parsed.assets.values.single;
      final duplicates = BookContent(
        [
          const BookBlock('', image: 'same'),
          const BookBlock('', image: 'same'),
        ],
        supplementaryDocuments: {
          'other': [const BookBlock('', image: 'ignored')],
        },
      );
      calls.clear();
      await loadPaginationImageSizes(duplicates, (path) async {
        calls.add(path);
        return image;
      });
      expect(calls, ['same']);
      expect((await db.book(id))!.position, 0);
    } finally {
      await db.close();
    }
  });

  test(
    'dimension loader tolerates missing, corrupt and over-budget encoded data',
    () async {
      final content = BookContent([
        for (final path in ['missing', 'bad', 'large', 'io'])
          BookBlock('', image: path),
      ]);
      final sizes = await loadPaginationImageSizes(
        content,
        (path) async => switch (path) {
          'missing' => null,
          'bad' => Uint8List.fromList([1, 2, 3]),
          'large' => Uint8List(20 * 1024 * 1024 + 1),
          _ => throw const FileSystemException('test unavailable'),
        },
      );
      expect(sizes, isEmpty);
      final result = const BookPaginator().paginate(
        content,
        viewport: const Size(400, 300),
        platform: TargetPlatform.android,
        imageSizes: sizes,
      );
      expect(
        fragments(result)
            .whereType<PageImageFragment>()
            .where((f) => f.unavailable)
            .length,
        4,
      );
      checkPages(result);
    },
  );

  testWidgets(
    'row height agrees with rendered Table including header and padding',
    (tester) async {
      const rows = [
        ['Heading', 'Second'],
        ['A longer paragraph in the first cell that wraps.', 'Short'],
      ];
      final result = layout([
        const BookBlock('', rows: rows, tableHeader: true),
      ]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: Table(
                  key: const ValueKey('table'),
                  defaultColumnWidth: const FixedColumnWidth(160),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder.all(),
                  children: [
                    for (var r = 0; r < rows.length; r++)
                      TableRow(
                        children: [
                          for (final cell in rows[r])
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: RichText(
                                text: TextSpan(
                                  text: cell,
                                  style: TextStyle(
                                    fontFamily: 'Literata',
                                    fontFamilyFallback: const ['Literata'],
                                    fontSize: 19,
                                    height: 1.6,
                                    letterSpacing: 0,
                                    fontWeight: r == 0
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final measured = fragments(result)
          .whereType<PageTableRowFragment>()
          .fold<double>(0, (sum, row) => sum + row.height);
      expect(
        measured,
        closeTo(
          tester.getSize(find.byKey(const ValueKey('table'))).height,
          .001,
        ),
      );
    },
  );
}

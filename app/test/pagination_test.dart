import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/reader/pagination.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
  });

  TextPagination layout(
    List<BookBlock> blocks, {
    Size viewport = const Size(260, 160),
    ReaderStyle style = const ReaderStyle(font: 'Literata'),
    TextScaler scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
    List<BookChapter> chapters = const [],
  }) => const TextPaginator().paginate(
    BookContent(blocks, chapters: chapters),
    viewport: viewport,
    platform: TargetPlatform.android,
    style: style,
    textScaler: scaler,
    textDirection: direction,
  );

  void assertCoverage(TextPagination result, List<BookBlock> blocks) {
    final all = result.pages.expand((page) => page.lines).toList();
    for (var block = 0; block < blocks.length; block++) {
      final lines = all.where((line) => line.start.block == block).toList();
      final text = blocks[block].text;
      var offset = 0;
      final boundaries = <int>{0};
      for (final cluster in text.characters) {
        offset += cluster.length;
        boundaries.add(offset);
      }
      offset = 0;
      for (final line in lines) {
        expect(line.start.offset, offset);
        expect(boundaries, contains(line.start.offset));
        expect(boundaries, contains(line.endOffset));
        offset = line.endOffset;
      }
      expect(offset, text.length);
      expect(
        lines
            .map((line) => text.substring(line.start.offset, line.endOffset))
            .join(),
        text,
      );
    }
    for (var page = 0; page < result.pages.length; page++) {
      final current = result.pages[page];
      expect(current.lines, isNotEmpty);
      expect(result.pageForPosition(current.start), page);
      for (var i = 1; i < current.lines.length; i++) {
        expect(
          current.lines[i].top,
          greaterThanOrEqualTo(
            current.lines[i - 1].top + current.lines[i - 1].height - 0.001,
          ),
        );
      }
      if (!current.overflows) {
        expect(
          current.height,
          lessThanOrEqualTo(result.contentSize.height + 0.001),
        );
      }
    }
  }

  test('long paragraphs preserve every character and every page boundary', () {
    final blocks = [
      const BookBlock('Chapter one', heading: true),
      BookBlock(List.filled(120, 'Tomorrow is another day. ').join()),
      const BookBlock('Last paragraph.'),
    ];
    final result = layout(blocks);
    expect(result.pages.length, greaterThan(10));
    assertCoverage(result, blocks);
    for (var block = 0; block < blocks.length; block++) {
      for (var offset = 0; offset <= blocks[block].text.length; offset++) {
        final page = result.pageForPosition(
          BookPosition(block, offset: offset),
        )!;
        expect(
          result.pages[page].lines.any(
            (line) =>
                line.start.block == block &&
                line.start.offset <= offset &&
                (offset < line.endOffset ||
                    offset == blocks[block].text.length),
          ),
          isTrue,
        );
      }
    }
  });

  test(
    'Unicode clusters, hard breaks, CRLF and blank blocks survive pagination',
    () {
      final blocks = [
        BookBlock(
          List.filled(12, 'A e\u0301 👨‍👩‍👧‍👦 🇨🇳 👍🏽 中文 abc\n').join(),
        ),
        const BookBlock('one\r\ntwo\n\nthree\n'),
        const BookBlock(''),
        const BookBlock('\n'),
      ];
      assertCoverage(layout(blocks, viewport: const Size(130, 48)), blocks);
    },
  );

  test('RTL and mixed direction retain logical source ranges', () {
    final blocks = [
      BookBlock(
        List.filled(12, 'مرحبا بالعالم English 123 שלום עולם. ').join(),
      ),
    ];
    assertCoverage(layout(blocks, direction: TextDirection.rtl), blocks);
  });

  test('page source ranges stay inside the corresponding painted bands', () {
    for (final text in [
      '  leading spaces and trailing spaces   \n\nnext line\r\nlast\n',
      'Before 👨‍👩‍👧‍👦 🇨🇳 e\u0301 👍🏽 after. 中文文字。',
      'English שלום עולם مرحبا بالعالم 123 end.',
    ]) {
      for (final width in [50.0, 90.0, 180.0, 300.0]) {
        final result = layout([BookBlock(text)], viewport: Size(width, 65));
        assertCoverage(result, [BookBlock(text)]);
        final painter =
            TextPainter(
              text: TextSpan(
                text: text,
                style: const TextStyle(
                  fontFamily: 'Literata',
                  fontFamilyFallback: ['Literata'],
                  fontSize: 19,
                  height: 1.6,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w400,
                ),
              ),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.justify,
            )..layout(
              minWidth: result.contentSize.width,
              maxWidth: result.contentSize.width,
            );
        try {
          for (final line in result.pages.expand((page) => page.lines)) {
            final boxes = painter.getBoxesForSelection(
              TextSelection(
                baseOffset: line.start.offset,
                extentOffset: line.endOffset,
              ),
            );
            for (final box in boxes) {
              expect(
                box.top,
                greaterThanOrEqualTo(line.sourceTop - .01),
                reason:
                    'width $width, source ${line.start.offset}:${line.endOffset}',
              );
              expect(
                box.bottom,
                lessThanOrEqualTo(line.sourceTop + line.height + .01),
                reason:
                    'width $width, source ${line.start.offset}:${line.endOffset}',
              );
            }
          }
        } finally {
          painter.dispose();
        }
      }
    }
  });

  test(
    'viewport, font and accessibility scaling remap the same stable position',
    () {
      final blocks = [BookBlock(List.filled(140, 'Reading tomorrow. ').join())];
      final target = BookPosition(
        0,
        offset: blocks.first.text.indexOf('tomorrow', 1300),
      );
      final small = layout(blocks);
      final wide = layout(blocks, viewport: const Size(520, 360));
      final large = layout(
        blocks,
        style: const ReaderStyle(font: 'Literata', size: 28),
      );
      final scaled = layout(blocks, scaler: TextScaler.linear(1.6));
      expect(wide.pages.length, lessThan(small.pages.length));
      expect(large.pages.length, greaterThan(small.pages.length));
      expect(scaled.pages.length, greaterThan(small.pages.length));
      for (final result in [small, wide, large, scaled]) {
        assertCoverage(result, blocks);
        final page = result.pages[result.pageForPosition(target)!];
        expect(
          page.lines.any(
            (line) =>
                line.start.offset <= target.offset &&
                target.offset < line.endOffset,
          ),
          isTrue,
        );
      }
    },
  );

  test('paragraph and non-chapter heading gaps fit without empty pages', () {
    final blocks = [
      const BookBlock('One'),
      const BookBlock('Title', heading: true),
      const BookBlock('Two'),
    ];
    const style = ReaderStyle(font: 'Literata', paragraphSpacing: 1);
    const chapters = [BookChapter('Only chapter', 0)];
    final result = layout(
      blocks,
      chapters: chapters,
      style: style,
      viewport: const Size(500, 500),
    );
    final lines = result.pages.single.lines;
    expect(lines[1].top - lines[0].height, closeTo(19 + 16, 0.001));
    expect(lines[2].top - lines[1].top - lines[1].height, closeTo(19, 0.001));
    final short = layout(
      blocks,
      chapters: chapters,
      style: style,
      viewport: const Size(500, 40),
    );
    expect(short.pages.length, 3);
    expect(short.pages.every((page) => page.lines.first.top == 0), isTrue);
    assertCoverage(short, blocks);
  });

  test('supplementary namespace, invalid positions and old block progress', () {
    const content = BookContent(
      [BookBlock('Body'), BookBlock('Resume here')],
      supplementaryDocuments: {
        'OPS/note.xhtml': [BookBlock('A note')],
      },
    );
    final body = const TextPaginator().paginate(
      content,
      viewport: const Size(300, 60),
      platform: TargetPlatform.android,
    );
    final note = const TextPaginator().paginate(
      content,
      document: 'OPS/note.xhtml',
      viewport: const Size(300, 60),
      platform: TargetPlatform.android,
    );
    expect(body.pageForPosition(const BookPosition(1)), isNotNull);
    expect(note.pageForPosition(const BookPosition(0)), isNull);
    expect(body.pageForPosition(note.pages.single.start), isNull);
    expect(note.pageForPosition(note.pages.single.start), 0);
    for (final invalid in [
      const BookPosition(-1),
      const BookPosition(2),
      const BookPosition(0, offset: -1),
      const BookPosition(0, offset: 5),
    ]) {
      expect(body.pageForPosition(invalid), isNull);
    }
    expect(body.pageForPosition(const BookPosition(0, offset: 4)), 0);
    expect(
      () => const TextPaginator().paginate(
        content,
        document: 'absent',
        viewport: const Size(300, 60),
        platform: TargetPlatform.android,
      ),
      throwsArgumentError,
    );
  });

  test('tiny viewport progresses with explicit overflow, empty document has no pages', () {
    final blocks = [const BookBlock('Hello 👨‍👩‍👧‍👦 world')];
    final result = layout(blocks, viewport: const Size(50, 1));
    expect(result.pages.every((page) => page.overflows), isTrue);
    assertCoverage(result, blocks);
    final empty = layout([]);
    expect(empty.pages, isEmpty);
    expect(empty.pageForPosition(const BookPosition(0)), isNull);
  });

  test('invalid dimensions and unsupported media fail explicitly', () {
    for (final size in [
      Size.zero,
      const Size(48, 100),
      const Size(double.infinity, 100),
      const Size(200, double.nan),
    ]) {
      expect(
        () => layout([const BookBlock('Text')], viewport: size),
        throwsArgumentError,
      );
    }
    expect(
      () => layout([const BookBlock('Image', image: 'a.png')]),
      throwsUnsupportedError,
    );
    expect(
      () => layout([
        const BookBlock(
          'Table',
          rows: [
            ['a'],
          ],
        ),
      ]),
      throwsUnsupportedError,
    );
    expect(
      () =>
          layout([const BookBlock('Text')], style: const ReaderStyle(size: -1)),
      throwsArgumentError,
    );
  });

  testWidgets('source bands match actual RichText paragraph layout', (
    tester,
  ) async {
    final text = List.filled(60, 'A paragraph with spaces and words. ').join();
    const style = ReaderStyle(
      font: 'Literata',
      size: 21,
      lineHeight: 1.7,
      letterSpacing: .02,
      bold: true,
    );
    final result = layout([BookBlock(text)], style: style);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: SizedBox(
              width: result.contentSize.width,
              child: RichText(
                key: const ValueKey('text'),
                textAlign: TextAlign.justify,
                text: TextSpan(
                  text: text,
                  style: TextStyle(
                    fontFamily: 'Literata',
                    fontFamilyFallback: const ['Literata'],
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.7,
                    letterSpacing: .42,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final lines = result.pages.expand((page) => page.lines).toList();
    expect(
      lines.last.sourceTop + lines.last.height,
      closeTo(tester.getSize(find.byKey(const ValueKey('text'))).height, .001),
    );
    for (var i = 1; i < lines.length; i++) {
      expect(
        lines[i].sourceTop,
        closeTo(lines[i - 1].sourceTop + lines[i - 1].height, .001),
      );
    }
  });
}

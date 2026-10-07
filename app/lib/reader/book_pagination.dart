import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../book/book.dart';
import 'pagination.dart';
import 'style.dart';

enum PagePart { text, image, caption, tableRow }

/// Stable source location, persisted independently of page numbers. Rows never masquerade
/// as UTF-16 offsets; existing BookPosition links keep their original meaning.
class PageAnchor {
  final BookPosition position;
  final PagePart part;
  final int? row;
  const PageAnchor(this.position, {this.part = PagePart.text, this.row});

  String encode() => jsonEncode({
    'version': 1,
    'position': position.toJson(),
    'part': part.name,
    if (row != null) 'row': row,
  });

  static PageAnchor? decode(String? raw) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) return null;
      final position = BookPosition.fromJson(
        data['position'] as Map<String, dynamic>,
      );
      final part = PagePart.values.byName(data['part'] as String);
      final row = data['row'] as int?;
      if (position.block < 0 ||
          position.offset < 0 ||
          (part == PagePart.tableRow
              ? row == null || row < 0 || position.offset != 0
              : row != null) ||
          (part == PagePart.image && position.offset != 0)) {
        return null;
      }
      return PageAnchor(position, part: part, row: row);
    } catch (_) {
      return null;
    }
  }
}

sealed class PageFragment {
  final PageAnchor anchor;
  final double top, height, width;
  const PageFragment(this.anchor, this.top, this.height, this.width);
}

class PageTextFragment extends PageFragment {
  /// Original paragraph geometry; its temporary block index is always zero.
  /// Use anchor.position for the real document/block and source offset.
  final TextPageLine line;
  PageTextFragment._(PageAnchor anchor, double top, double width, this.line)
    : super(anchor, top, line.height, math.max(width, line.width));
  int get endOffset => line.endOffset;
  double get baseline => top + line.baseline - line.top;
}

class PageImageFragment extends PageFragment {
  final String path;
  final Size? intrinsicSize;
  final double left;
  bool get unavailable => intrinsicSize == null;
  const PageImageFragment._(
    super.anchor,
    super.top,
    super.height,
    super.width,
    this.path,
    this.intrinsicSize,
    this.left,
  );
}

class PageTableCell {
  final String text;
  final double textHeight;
  final bool overflows;
  const PageTableCell._(this.text, this.textHeight, this.overflows);
}

class PageTableRowFragment extends PageFragment {
  static const columnWidth = 160.0;
  static const padding = 10.0;
  final List<PageTableCell> cells;
  final bool isHeader;
  // A malformed empty table still has a visible, addressable placeholder row.
  final bool emptyTable;
  PageTableRowFragment._(
    super.anchor,
    super.top,
    super.height,
    super.width,
    List<PageTableCell> cells,
    this.isHeader,
    this.emptyTable,
  ) : cells = List.unmodifiable(cells);
}

class BookPage {
  final List<PageFragment> fragments;
  final bool overflows;
  final double height;
  BookPage._(List<PageFragment> fragments, Size available)
    : fragments = List.unmodifiable(fragments),
      height = fragments.last.top + fragments.last.height,
      overflows = fragments.any(
        (f) =>
            f.top + f.height > available.height + .001 ||
            f.width > available.width + .001 ||
            (f is PageTableRowFragment &&
                f.cells.any((cell) => cell.overflows)),
      );
  PageAnchor get start => fragments.first.anchor;
}

class BookPagination {
  final String? document;
  final Size contentSize;
  final List<BookPage> pages;
  final List<int> _lengths;
  final List<PagePart> _parts;
  final Map<int, List<(int, PageFragment)>> _byBlock = {};
  final Map<(int, PagePart, int?), List<(int, PageFragment)>> _byAnchor = {};
  BookPagination._(
    this.document,
    this.contentSize,
    List<BookPage> pages,
    List<BookBlock> blocks,
  ) : pages = List.unmodifiable(pages),
      _lengths = [for (final b in blocks) b.text.length],
      _parts = [
        for (final b in blocks)
          b.image != null
              ? PagePart.image
              : b.rows != null
              ? PagePart.tableRow
              : PagePart.text,
      ] {
    for (var page = 0; page < pages.length; page++) {
      for (final fragment in pages[page].fragments) {
        (_byBlock[fragment.anchor.position.block] ??= []).add((page, fragment));
        final anchor = fragment.anchor;
        (_byAnchor[(anchor.position.block, anchor.part, anchor.row)] ??= [])
            .add((page, fragment));
      }
    }
  }

  bool _valid(BookPosition p) =>
      p.document == document &&
      p.block >= 0 &&
      p.block < _lengths.length &&
      p.offset >= 0 &&
      p.offset <= _lengths[p.block];

  /// Existing links to a media block target its beginning. Nonzero image alt
  /// text offsets can target captions when present; table offsets must be zero.
  int? pageForPosition(BookPosition position) {
    if (!_valid(position)) return null;
    final part = _parts[position.block];
    if (part == PagePart.tableRow) {
      return position.offset == 0 ? _byBlock[position.block]!.first.$1 : null;
    }
    if (part == PagePart.image) {
      if (position.offset == 0) return _byBlock[position.block]!.first.$1;
      return pageForAnchor(PageAnchor(position, part: PagePart.caption)) ??
          _byBlock[position.block]!.first.$1;
    }
    return pageForAnchor(PageAnchor(position));
  }

  /// Exact page-start round trip, including caption continuations/table rows.
  int? pageForAnchor(PageAnchor anchor) {
    final position = anchor.position;
    if (!_valid(position)) return null;
    if (anchor.part != PagePart.tableRow && anchor.row != null) return null;
    final candidates = _byAnchor[(position.block, anchor.part, anchor.row)];
    if (candidates == null) return null;
    if (anchor.part == PagePart.image || anchor.part == PagePart.tableRow) {
      return position.offset == 0 ? candidates.first.$1 : null;
    }
    var low = 0;
    var high = candidates.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (candidates[middle].$2.anchor.position.offset <= position.offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return candidates[math.max(0, low - 1)].$1;
  }
}

/// Read only dimensions, not decoded pixel buffers. Complete this before layout
/// so late image loads cannot change page boundaries. Missing/invalid assets
/// are omitted and become explicit placeholders in BookPaginator.
Future<Map<String, Size>> loadPaginationImageSizes(
  BookContent content,
  Future<Uint8List?> Function(String path) load, {
  String? document,
}) async {
  final blocks = document == null
      ? content.blocks
      : content.supplementaryDocuments[document];
  if (blocks == null) throw ArgumentError.value(document, 'document');
  final sizes = <String, Size>{};
  final paths = {
    for (final b in blocks)
      if (b.image != null) b.image!,
  };
  for (final path in paths) {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final bytes = await load(path);
      if (bytes == null || bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
        continue;
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 0 && descriptor.height > 0) {
        sizes[path] = Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
      }
    } on Exception {
      // I/O or unsupported/corrupt encoding: retain a placeholder, not silence.
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
  return Map.unmodifiable(sizes);
}

class BookPaginator {
  const BookPaginator();

  BookPagination paginate(
    BookContent content, {
    required Size viewport,
    required TargetPlatform platform,
    ReaderStyle style = const ReaderStyle(),
    String? document,
    Map<String, Size> imageSizes = const {},
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
    Locale? locale,
  }) {
    BookPagination? result;
    for (final _ in _steps(
      content,
      viewport: viewport,
      platform: platform,
      style: style,
      document: document,
      imageSizes: imageSizes,
      textScaler: textScaler,
      textDirection: textDirection,
      locale: locale,
      onComplete: (value) => result = value,
    )) {}
    return result!;
  }

  Future<BookPagination?> paginateAsync(
    BookContent content, {
    required Size viewport,
    required TargetPlatform platform,
    ReaderStyle style = const ReaderStyle(),
    String? document,
    Map<String, Size> imageSizes = const {},
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
    Locale? locale,
    bool Function()? cancelled,
  }) async {
    final blocks = document == null
        ? content.blocks
        : content.supplementaryDocuments[document];
    if (blocks == null) throw ArgumentError.value(document, 'document');
    // A single huge paragraph/row cannot yield inside TextPainter. Keep a
    // readable scroll fallback until chunked shaping is implemented.
    if (blocks.any(
      (b) =>
          b.text.length > 40000 ||
          (b.rows?.any(
                (row) => row.fold<int>(0, (n, c) => n + c.length) > 40000,
              ) ??
              false),
    )) {
      throw const PaginationTooLargeException();
    }
    BookPagination? result;
    final watch = Stopwatch()..start();
    await Future<void>.delayed(Duration.zero);
    for (final _ in _steps(
      content,
      viewport: viewport,
      platform: platform,
      style: style,
      document: document,
      imageSizes: imageSizes,
      textScaler: textScaler,
      textDirection: textDirection,
      locale: locale,
      onComplete: (value) => result = value,
    )) {
      if (cancelled?.call() ?? false) return null;
      if (watch.elapsedMilliseconds >= 8) {
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
    return (cancelled?.call() ?? false) ? null : result;
  }

  Iterable<int> _steps(
    BookContent content, {
    required Size viewport,
    required TargetPlatform platform,
    ReaderStyle style = const ReaderStyle(),
    String? document,
    Map<String, Size> imageSizes = const {},
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
    Locale? locale,
    required void Function(BookPagination) onComplete,
  }) sync* {
    yield -1;
    TextPagination measure(List<BookBlock> blocks, ReaderStyle textStyle) =>
        const TextPaginator().paginate(
          BookContent(blocks),
          viewport: viewport,
          platform: platform,
          style: textStyle,
          textScaler: textScaler,
          textDirection: textDirection,
          locale: locale,
        );
    final available = measure(
      [],
      style,
    ).contentSize; // Same validation/width contract.
    final blocks = document == null
        ? content.blocks
        : content.supplementaryDocuments[document];
    if (blocks == null) throw ArgumentError.value(document, 'document');
    final pages = <BookPage>[];
    final chapterStarts = document == null
        ? content.chapterStarts
        : const <int>{};
    var fragments = <PageFragment>[];
    var used = 0.0;
    void finishPage() {
      if (fragments.isEmpty) return;
      pages.add(BookPage._(fragments, available));
      fragments = [];
      used = 0;
    }

    void add(
      double height,
      double gap,
      PageFragment Function(double top) create,
    ) {
      if (!height.isFinite || height <= 0) {
        throw StateError('Invalid fragment height.');
      }
      if (fragments.isNotEmpty &&
          used + gap + height > available.height + .001) {
        finishPage();
      }
      if (fragments.isEmpty) gap = 0;
      fragments.add(create(used + gap));
      used += gap + height;
    }

    final paragraphGap = math.max(6.0, style.size * style.paragraphSpacing);
    PageAnchor anchor(int block, PagePart part, {int offset = 0, int? row}) =>
        PageAnchor(
          BookPosition(block, offset: offset, document: document),
          part: part,
          row: row,
        );
    void addText(
      int index,
      BookBlock block,
      ReaderStyle textStyle,
      PagePart part,
      double gap,
    ) {
      final measured = measure([block], textStyle);
      var first = true;
      for (final line in measured.pages.expand((p) => p.lines)) {
        add(
          line.height,
          first ? gap : 0,
          (top) => PageTextFragment._(
            anchor(index, part, offset: line.start.offset),
            top,
            available.width,
            line,
          ),
        );
        first = false;
      }
    }

    final cellStyle = TextStyle(
      fontFamily: style.family(platform),
      fontFamilyFallback: const ['Literata'],
      fontSize: style.size,
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing * style.size,
    );
    for (var index = 0; index < blocks.length; index++) {
      if (chapterStarts.contains(index)) finishPage();
      final block = blocks[index];
      final gap = index > 0 ? paragraphGap : 0.0;
      if (block.image case final path?) {
        var intrinsic = imageSizes[path];
        if (intrinsic != null &&
            (!intrinsic.width.isFinite ||
                !intrinsic.height.isFinite ||
                intrinsic.width <= 0 ||
                intrinsic.height <= 0)) {
          intrinsic = null;
        }
        final scale = intrinsic == null
            ? 1.0
            : math.min(
                1.0,
                math.min(
                  available.width / intrinsic.width,
                  available.height / intrinsic.height,
                ),
              );
        final width = intrinsic == null
            ? available.width
            : intrinsic.width * scale;
        final height = intrinsic == null
            ? math.min(260.0, available.height)
            : intrinsic.height * scale;
        add(
          height,
          gap,
          (top) => PageImageFragment._(
            anchor(index, PagePart.image),
            top,
            height,
            width,
            path,
            intrinsic,
            (available.width - width) / 2,
          ),
        );
        if (block.text.isNotEmpty && block.text != '图片') {
          final captionStyle = ReaderStyle(
            font: style.font,
            size: style.size * .8,
            lineHeight: style.lineHeight,
            letterSpacing: style.letterSpacing / .8,
            margin: style.margin,
            bold: style.bold,
            justify: false,
          );
          addText(
            index,
            BookBlock(block.text),
            captionStyle,
            PagePart.caption,
            8,
          );
        }
      } else if (block.rows case final rawRows?) {
        final empty = rawRows.isEmpty;
        final rows = empty ? <List<String>>[const []] : rawRows;
        final columns = math.max(
          1,
          rows.fold<int>(0, (n, row) => math.max(n, row.length)),
        );
        for (var row = 0; row < rows.length; row++) {
          final header = row == 0 && block.tableHeader && !empty;
          final cells = <PageTableCell>[];
          for (var column = 0; column < columns; column++) {
            final text = column < rows[row].length ? rows[row][column] : '';
            final painter = TextPainter(
              text: TextSpan(
                text: text.isEmpty ? '\u200B' : text,
                style: header
                    ? cellStyle.copyWith(fontWeight: FontWeight.w700)
                    : cellStyle,
              ),
              textDirection: textDirection,
              textAlign: TextAlign.start,
              textScaler: textScaler,
              locale: locale,
            );
            try {
              const width =
                  PageTableRowFragment.columnWidth -
                  PageTableRowFragment.padding * 2;
              painter.layout(minWidth: width, maxWidth: width);
              cells.add(
                PageTableCell._(
                  text,
                  painter.height,
                  painter.computeLineMetrics().any(
                    (line) => line.width > width + .001,
                  ),
                ),
              );
            } finally {
              painter.dispose();
            }
          }
          final height =
              cells.map((c) => c.textHeight).reduce(math.max) +
              PageTableRowFragment.padding * 2;
          add(
            height,
            row == 0 ? gap : 0,
            (top) => PageTableRowFragment._(
              anchor(index, PagePart.tableRow, row: row),
              top,
              height,
              columns * PageTableRowFragment.columnWidth,
              cells,
              header,
              empty,
            ),
          );
          yield index;
        }
      } else {
        addText(
          index,
          block,
          style,
          PagePart.text,
          gap + (block.heading ? 16 : 0),
        );
      }
      yield index;
    }
    finishPage();
    onComplete(BookPagination._(document, available, pages, blocks));
  }
}

class PaginationTooLargeException implements Exception {
  const PaginationTooLargeException();
}

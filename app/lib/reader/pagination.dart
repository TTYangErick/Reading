import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../book/book.dart';
import 'style.dart';

/// An indivisible band of laid-out lines, retaining original block offsets.
/// Normally one line; fallback fonts can spread one grapheme over several
/// physical lines, which must stay on the same page. Ambiguous empty lines are
/// also grouped with a neighbor, retaining their full layout height.
///
/// To preserve shaping/justification, a future renderer must paint the original
/// paragraph at the same width and clip this band, not lay out its substring.
class TextPageLine {
  final BookPosition start;
  final int endOffset;
  final double top, sourceTop, height, baseline, left, width;

  const TextPageLine._({
    required this.start,
    required this.endOffset,
    required this.top,
    required this.sourceTop,
    required this.height,
    required this.baseline,
    required this.left,
    required this.width,
  });
}

class TextPage {
  final List<TextPageLine> lines;
  final double height;
  final bool overflows;

  TextPage._(List<TextPageLine> lines, Size available)
    : lines = List.unmodifiable(lines),
      height = lines.last.top + lines.last.height,
      overflows = lines.any(
        (line) =>
            line.top + line.height > available.height + 0.001 ||
            line.width > available.width + 0.001,
      );

  BookPosition get start => lines.first.start;
}

/// Ephemeral layout; page numbers are never durable reading positions.
class TextPagination {
  final String? document;
  final Size contentSize;
  final List<TextPage> pages;
  final List<int> _blockLengths;
  final Map<int, List<(int, TextPageLine)>> _linesByBlock;

  TextPagination._(
    this.document,
    this.contentSize,
    List<TextPage> pages,
    List<BookBlock> blocks,
  ) : pages = List.unmodifiable(pages),
      _blockLengths = [for (final block in blocks) block.text.length],
      _linesByBlock = {} {
    for (var page = 0; page < pages.length; page++) {
      for (final line in pages[page].lines) {
        (_linesByBlock[line.start.block] ??= []).add((page, line));
      }
    }
  }

  /// A boundary belongs to the following line/page; the final caret belongs
  /// to the block's final line. Invalid or foreign-document positions fail.
  int? pageForPosition(BookPosition position) {
    if (position.document != document ||
        position.block < 0 ||
        position.block >= _blockLengths.length ||
        position.offset < 0 ||
        position.offset > _blockLengths[position.block]) {
      return null;
    }
    final lines = _linesByBlock[position.block]!;
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].$2.start.offset <= position.offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return lines[math.max(0, low - 1)].$1;
  }
}

/// CPU layout on the Flutter UI isolate. This text-only foundation does not
/// mutate books, persist progress, paint pages, or silently discard media.
class TextPaginator {
  const TextPaginator();

  TextPagination paginate(
    BookContent content, {
    required Size viewport,
    required TargetPlatform platform,
    ReaderStyle style = const ReaderStyle(),
    String? document,
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
    Locale? locale,
  }) {
    for (final value in [
      viewport.width,
      viewport.height,
      style.size,
      style.lineHeight,
    ]) {
      if (!value.isFinite || value <= 0) {
        throw ArgumentError(
          'Viewport and text dimensions must be finite and positive.',
        );
      }
    }
    for (final size in [style.size, style.size * 1.35]) {
      final scaled = textScaler.scale(size);
      if (!scaled.isFinite || scaled <= 0) {
        throw ArgumentError(
          'Scaled text dimensions must be finite and positive.',
        );
      }
    }
    if (!style.margin.isFinite ||
        style.margin < 0 ||
        !style.paragraphSpacing.isFinite ||
        style.paragraphSpacing < 0 ||
        !style.letterSpacing.isFinite) {
      throw ArgumentError('Invalid text spacing.');
    }
    final margin = math.max(style.margin, (viewport.width - 680) / 2);
    final available = Size(viewport.width - margin * 2, viewport.height);
    if (available.width <= 0) {
      throw ArgumentError('Margins leave no space for text.');
    }
    final blocks = document == null
        ? content.blocks
        : content.supplementaryDocuments[document];
    if (blocks == null) throw ArgumentError.value(document, 'document');
    if (blocks.any((block) => block.image != null || block.rows != null)) {
      throw UnsupportedError('Image and table pagination is not implemented.');
    }
    final pages = <TextPage>[];
    final chapterStarts = document == null
        ? content.chapterStarts
        : const <int>{};
    var lines = <TextPageLine>[];
    var used = 0.0;
    void finishPage() {
      if (lines.isEmpty) return;
      pages.add(TextPage._(lines, available));
      lines = [];
      used = 0;
    }

    final baseStyle = TextStyle(
      fontFamily: style.family(platform),
      fontFamilyFallback: const ['Literata'],
      fontSize: style.size,
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing * style.size,
    );
    final paragraphGap = math.max(6.0, style.paragraphSpacing * style.size);
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      if (chapterStarts.contains(blockIndex)) finishPage();
      final block = blocks[blockIndex];
      final span = TextSpan(
        // Reserve one blank line without adding a character to source ranges.
        text: block.text.isEmpty ? '\u200B' : block.text,
        style: block.heading
            ? baseStyle.copyWith(
                fontSize: style.size * 1.35,
                fontWeight: FontWeight.w600,
                height: 1.3,
              )
            : baseStyle,
      );
      // Match TextPainter's public ParagraphStyle/TextSpan construction. Keeping
      // the paragraph exposes getLineNumberAt without a second shaping pass.
      final builder = ui.ParagraphBuilder(
        span.style!.getParagraphStyle(
          textAlign: style.justify && !block.heading
              ? TextAlign.justify
              : TextAlign.start,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        ),
      );
      span.build(builder, textScaler: textScaler);
      final paragraph = builder.build();
      try {
        paragraph.layout(ui.ParagraphConstraints(width: available.width));
        final metrics = paragraph.computeLineMetrics();
        final boundaries = [0];
        for (final grapheme in block.text.characters) {
          boundaries.add(boundaries.last + grapheme.length);
        }
        int clusterStart(int offset) {
          var low = 0;
          var high = boundaries.length;
          while (low < high) {
            final middle = (low + high) ~/ 2;
            if (boundaries[middle] <= offset) {
              low = middle + 1;
            } else {
              high = middle;
            }
          }
          return boundaries[math.max(0, low - 1)];
        }

        final bands = <(int, int)>[]; // (first physical line, source start)
        for (var i = 0; i < metrics.length; i++) {
          final metric = metrics[i];
          // Empty lines can share a legacy source band with a neighbor (e.g.
          // bidi controls before a blank line). Preserve hit/affinity queries
          // for the empty line and both neighbors, not just the empty line.
          final clearLine =
              metric.width > 0 &&
              (i == 0 || metrics[i - 1].width > 0) &&
              (i + 1 == metrics.length || metrics[i + 1].width > 0);
          // Small paragraphs already have cheap range queries. Logical source
          // line numbers are monotone regardless of the visual bidi order.
          var sourceStart = metrics.length >= 64 && clearLine
              ? _lineStart(paragraph, i, block.text.length)
              : null;
          if (sourceStart == null) {
            final hit = paragraph.getPositionForOffset(
              Offset(
                metric.left + metric.width / 2,
                metric.baseline - metric.ascent / 2,
              ),
            );
            final range = paragraph.getLineBoundary(hit);
            if (!range.isValid || range.start > block.text.length) {
              throw StateError('Text layout returned an invalid line range.');
            }
            sourceStart = range.start;
          }
          final start = i == 0 ? 0 : clusterStart(sourceStart);
          if (bands.isEmpty || start > bands.last.$2) bands.add((i, start));
        }
        for (var band = 0; band < bands.length; band++) {
          final (i, offset) = bands[band];
          final nextLine = band + 1 < bands.length
              ? bands[band + 1].$1
              : metrics.length;
          final end = band + 1 < bands.length
              ? bands[band + 1].$2
              : block.text.length;
          final metric = metrics[i];
          final sourceTop = i == 0 ? 0.0 : metric.baseline - metric.ascent;
          final sourceBottom = nextLine == metrics.length
              ? paragraph.height
              : metrics[nextLine].baseline - metrics[nextLine].ascent;
          final height = sourceBottom - sourceTop;
          if (!height.isFinite || height <= 0) {
            throw StateError('Text layout returned an invalid line height.');
          }
          var gap = i == 0
              ? (blockIndex > 0 ? paragraphGap : 0.0) +
                    (block.heading ? 16.0 : 0.0)
              : 0.0;
          if (lines.isNotEmpty &&
              used + gap + height > available.height + 0.001) {
            finishPage();
          }
          // Spacing separates blocks, never creates an otherwise blank page.
          if (lines.isEmpty) gap = 0;
          lines.add(
            TextPageLine._(
              start: BookPosition(
                blockIndex,
                offset: offset,
                document: document,
              ),
              endOffset: end,
              top: used + gap,
              sourceTop: sourceTop,
              height: height,
              baseline: used + gap + metric.baseline - sourceTop,
              left: metrics
                  .sublist(i, nextLine)
                  .map((m) => m.left)
                  .reduce(math.min),
              width: metrics
                  .sublist(i, nextLine)
                  .map((m) => m.width)
                  .reduce(math.max),
            ),
          );
          used += gap + height;
        }
        if (metrics.isEmpty) {
          throw StateError('Text layout did not cover the entire block.');
        }
      } finally {
        paragraph.dispose();
      }
    }
    finishPage();
    return TextPagination._(document, available, pages, blocks);
  }
}

// Lower bound over logical UTF-16 offsets, independent of language/direction.
// Newline code units belong to the preceding line (Paragraph API contract).
// Null denotes an engine offset that cannot be mapped; retain the old query.
int? _lineStart(ui.Paragraph paragraph, int line, int length) {
  var low = 0, high = length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final actual = paragraph.getLineNumberAt(middle);
    if (actual == null) return null;
    if (actual < line) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

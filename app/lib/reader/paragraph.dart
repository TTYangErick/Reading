import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../book/book.dart';
import '../text/language.dart';

class ReaderParagraph extends StatefulWidget {
  final String text;
  final LanguageSupport language;
  final TextStyle style;
  final TextAlign align;
  final WordRange? selection;
  final void Function(WordRange, Rect) onWord;
  final ValueChanged<int> onSentence;
  final ValueChanged<WordRange>? onSelection;
  final VoidCallback? onSelectionStart;
  final int visibleStart;
  final int? visibleEnd;
  final VoidCallback onBlank;
  final List<BookLink> links;
  final ValueChanged<BookLink>? onLink;
  final GlobalKey? anchorKey;
  const ReaderParagraph({
    super.key,
    required this.text,
    required this.language,
    required this.style,
    required this.align,
    required this.selection,
    required this.onWord,
    required this.onSentence,
    this.onSelection,
    this.onSelectionStart,
    this.visibleStart = 0,
    this.visibleEnd,
    required this.onBlank,
    this.links = const [],
    this.onLink,
    this.anchorKey,
  });
  @override
  State<ReaderParagraph> createState() => _ReaderParagraphState();
}

class _ReaderParagraphState extends State<ReaderParagraph> {
  final textKey = GlobalKey();
  int? sentenceOffset;
  Offset? pressOrigin;
  TextRange? pressWord;
  WordRange? pressRange;
  bool dragged = false;
  Size? viewSize;
  TextScaler? scaler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context),
        scale = MediaQuery.textScalerOf(context);
    if (viewSize != size || scaler != scale) clearPress();
    viewSize = size;
    scaler = scale;
  }

  int get visibleEnd => widget.visibleEnd ?? widget.text.length;

  void clearPress() {
    sentenceOffset = null;
    pressOrigin = null;
    pressWord = null;
    pressRange = null;
    dragged = false;
  }

  @override
  void didUpdateWidget(covariant ReaderParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.visibleStart != widget.visibleStart ||
        oldWidget.visibleEnd != widget.visibleEnd) {
      clearPress();
    }
  }

  void startPress(Offset global) {
    final render = paragraph;
    final offset = render
        .getPositionForOffset(render.globalToLocal(global))
        .offset;
    if (offset < widget.visibleStart || offset >= visibleEnd) return;
    final word = render.getWordBoundary(TextPosition(offset: offset));
    if (!word.isValid || word.isCollapsed) return;
    setState(() {
      sentenceOffset = offset;
      pressOrigin = global;
      pressWord = word;
      pressRange = widget.language.sentenceAt(widget.text, offset);
      dragged = false;
    });
    widget.onSelectionStart?.call();
  }

  void movePress(Offset global) {
    if (pressOrigin == null ||
        pressWord == null ||
        widget.onSelection == null ||
        (!dragged && (global - pressOrigin!).distance < 8)) {
      return;
    }
    final render = paragraph, local = render.globalToLocal(global);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, global, View.of(context).viewId);
    if (!hit.path.any((entry) => entry.target == render)) return;
    final offset = render
        .getPositionForOffset(local)
        .offset
        .clamp(widget.visibleStart, visibleEnd - 1);
    final word = render.getWordBoundary(TextPosition(offset: offset));
    if (!word.isValid || word.isCollapsed) return;
    final start =
        (word.start < pressWord!.start ? word.start : pressWord!.start).clamp(
          widget.visibleStart,
          visibleEnd,
        );
    final end = (word.end > pressWord!.end ? word.end : pressWord!.end).clamp(
      widget.visibleStart,
      visibleEnd,
    );
    if (start >= end) return;
    setState(() {
      dragged = true;
      pressRange = WordRange(start, end, widget.text.substring(start, end));
    });
  }

  void endPress() {
    final offset = sentenceOffset, range = pressRange, adjusted = dragged;
    setState(clearPress);
    if (offset == null) return;
    if (adjusted && range != null && range.text.trim().isNotEmpty) {
      widget.onSelection?.call(range);
    } else {
      widget.onSentence(offset);
    }
  }

  RenderParagraph get paragraph =>
      (widget.anchorKey ?? textKey).currentContext!.findRenderObject()!
          as RenderParagraph;
  Iterable<BookLink> get links => widget.links.where(
    (link) =>
        link.start >= 0 &&
        link.end > link.start &&
        link.end <= widget.text.length,
  );
  void tap(Offset global) {
    final render = paragraph, local = paragraph.globalToLocal(global);
    // Hit the actual glyph boxes, not the nearest text offset in blank margins.
    // This also makes punctuation/numeric note markers clickable without words.
    for (final link in links) {
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: link.start, extentOffset: link.end),
      );
      if (boxes.any((box) => box.toRect().inflate(2).contains(local))) {
        widget.onLink?.call(link);
        return;
      }
    }
    final offset = render.getPositionForOffset(local).offset;
    final range = widget.language.wordAt(widget.text, offset);
    if (range == null) {
      widget.onBlank();
      return;
    }
    final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    final hit = boxes
        .where((b) => b.toRect().inflate(2).contains(local))
        .firstOrNull;
    if (hit == null) {
      widget.onBlank();
      return;
    }
    widget.onWord(range, hit.toRect().shift(render.localToGlobal(Offset.zero)));
  }

  @override
  Widget build(BuildContext context) {
    final range = pressRange ?? widget.selection;
    final textLinks = links.toList();
    final boundaries = <int>{
      0,
      widget.text.length,
      for (final link in textLinks) ...[link.start, link.end],
      if (range != null) ...[range.start, range.end],
    }.toList()..sort();
    final span = TextSpan(
      style: widget.style,
      children: [
        for (var i = 0; i < boundaries.length - 1; i++)
          TextSpan(
            text: widget.text.substring(boundaries[i], boundaries[i + 1]),
            style: TextStyle(
              decoration:
                  textLinks.any(
                    (link) =>
                        link.start <= boundaries[i] &&
                        link.end >= boundaries[i + 1],
                  )
                  ? TextDecoration.underline
                  : null,
              backgroundColor:
                  range != null &&
                      range.start <= boundaries[i] &&
                      range.end >= boundaries[i + 1]
                  ? const Color(0x55DDBA73)
                  : null,
            ),
          ),
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => tap(details.globalPosition),
      // Present the modal after release. Pushing a route while the press is
      // active cancels the reader's pointer sequence on native platforms.
      onLongPressStart: (details) => startPress(details.globalPosition),
      onLongPressMoveUpdate: (details) => movePress(details.globalPosition),
      onLongPressEnd: (_) => endPress(),
      onLongPressCancel: () => setState(clearPress),
      child: RichText(
        key: widget.anchorKey ?? textKey,
        text: span,
        textAlign: widget.align,
        textScaler: MediaQuery.textScalerOf(context),
      ),
    );
  }
}

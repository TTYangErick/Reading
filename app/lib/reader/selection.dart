import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../book/book.dart';

abstract interface class ReadingSelectionRegion {
  int get selectionBlock;
  int get selectionStart;
  int get selectionEnd;
  RenderParagraph get selectionRender;
  void selectionChanged();
  void selectionCancelled();
}

typedef _Point = ({int block, int offset});

/// A transient selection in one document. Regions identify source intervals,
/// including two clipped renderings of the same paragraph on a spread.
class ReadingSelection {
  List<BookBlock> blocks;
  ValueChanged<String> onSelected;
  ReadingSelection(this.blocks, this.onSelected);
  final _regions = <ReadingSelectionRegion>{};
  final _painted = <ReadingSelectionRegion, TextRange>{};
  ReadingSelectionRegion? _origin;
  Offset? _press;
  TextRange? _word;
  _Point? _start, _end;

  void register(ReadingSelectionRegion region) {
    if (_regions.contains(region)) return;
    cancel();
    _regions.add(region);
  }

  void unregister(ReadingSelectionRegion region) {
    _painted.remove(region);
    if (_regions.remove(region)) cancel();
  }

  bool owns(ReadingSelectionRegion region) => identical(_origin, region);

  void begin(ReadingSelectionRegion region, Offset global, TextRange word) {
    cancel();
    _origin = region;
    _press = global;
    _word = TextRange(
      start: word.start.clamp(region.selectionStart, region.selectionEnd),
      end: word.end.clamp(region.selectionStart, region.selectionEnd),
    );
  }

  void move(Offset global, int viewId) {
    final origin = _origin, word = _word;
    if (origin == null || word == null || (global - _press!).distance < 8) {
      return;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, global, viewId);
    ReadingSelectionRegion? target;
    for (final entry in hit.path) {
      target = _regions
          .where((r) => identical(r.selectionRender, entry.target))
          .firstOrNull;
      if (target != null) break;
    }
    if (target == null || target.selectionStart >= target.selectionEnd) return;
    final render = target.selectionRender;
    final offset = render
        .getPositionForOffset(render.globalToLocal(global))
        .offset
        .clamp(target.selectionStart, target.selectionEnd - 1);
    final endWord = render.getWordBoundary(TextPosition(offset: offset));
    if (!endWord.isValid || endWord.isCollapsed) return;
    final targetStart = endWord.start.clamp(
      target.selectionStart,
      target.selectionEnd,
    );
    final targetEnd = endWord.end.clamp(
      target.selectionStart,
      target.selectionEnd,
    );
    final forward =
        target.selectionBlock > origin.selectionBlock ||
        (target.selectionBlock == origin.selectionBlock &&
            targetStart >= word.start);
    final start = (
      block: forward ? origin.selectionBlock : target.selectionBlock,
      offset: forward ? word.start : targetStart,
    );
    final end = (
      block: forward ? target.selectionBlock : origin.selectionBlock,
      offset: forward ? targetEnd : word.end,
    );
    if (!_covered(start, end)) return;
    _start = start;
    _end = end;
    _notify();
  }

  bool _covered(_Point start, _Point end) {
    if (start.block < 0 || end.block >= blocks.length) return false;
    for (var block = start.block; block <= end.block; block++) {
      final value = blocks[block];
      // Media and table text have their own local selection semantics.
      if (value.image != null || value.rows != null) return false;
      final from = block == start.block ? start.offset : 0;
      final to = block == end.block ? end.offset : value.text.length;
      var cursor = from;
      final regions = _regions.where((r) => r.selectionBlock == block).toList()
        ..sort((a, b) => a.selectionStart.compareTo(b.selectionStart));
      for (final region in regions) {
        if (region.selectionEnd <= cursor || region.selectionStart >= to) {
          continue;
        }
        if (region.selectionStart > cursor &&
            value.text
                .substring(cursor, region.selectionStart)
                .trim()
                .isNotEmpty) {
          return false;
        }
        cursor = region.selectionEnd;
        if (cursor >= to) break;
      }
      if (cursor < to && value.text.substring(cursor, to).trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  TextRange? rangeFor(ReadingSelectionRegion region) {
    final start = _start, end = _end;
    if (start == null ||
        end == null ||
        region.selectionBlock < start.block ||
        region.selectionBlock > end.block) {
      return null;
    }
    final from = (region.selectionBlock == start.block ? start.offset : 0)
        .clamp(region.selectionStart, region.selectionEnd);
    final to =
        (region.selectionBlock == end.block ? end.offset : region.selectionEnd)
            .clamp(region.selectionStart, region.selectionEnd);
    return from < to ? TextRange(start: from, end: to) : null;
  }

  String? finish(ReadingSelectionRegion region) {
    if (!owns(region)) return null;
    final start = _start, end = _end;
    final parts = <String>[];
    if (start != null && end != null && _covered(start, end)) {
      for (var i = start.block; i <= end.block; i++) {
        final text = blocks[i].text;
        parts.add(
          text.substring(
            i == start.block ? start.offset : 0,
            i == end.block ? end.offset : text.length,
          ),
        );
      }
    }
    _clear();
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  void cancel() {
    if (_origin == null) return;
    final origin = _origin;
    _clear();
    origin?.selectionCancelled();
  }

  void _clear() {
    _origin = null;
    _press = null;
    _word = null;
    _start = _end = null;
    _notify();
  }

  void _notify() {
    for (final region in _regions) {
      final next = rangeFor(region), previous = _painted[region];
      if (next == previous) continue;
      if (next == null) {
        _painted.remove(region);
      } else {
        _painted[region] = next;
      }
      region.selectionChanged();
    }
  }
}

class ReadingSelectionScope extends StatefulWidget {
  final List<BookBlock> blocks;
  final ValueChanged<String> onSelected;
  final Widget child;
  const ReadingSelectionScope({
    super.key,
    required this.blocks,
    required this.onSelected,
    required this.child,
  });

  static ReadingSelection? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SelectionHost>()?.selection;

  @override
  State<ReadingSelectionScope> createState() => _SelectionScopeState();
}

class _SelectionScopeState extends State<ReadingSelectionScope> {
  late final selection = ReadingSelection(widget.blocks, widget.onSelected);
  @override
  void didUpdateWidget(covariant ReadingSelectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    selection.onSelected = widget.onSelected;
    if (!identical(widget.blocks, oldWidget.blocks)) {
      selection.cancel();
      selection.blocks = widget.blocks;
    }
  }

  @override
  Widget build(BuildContext context) => _SelectionHost(
    selection: selection,
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is OverscrollNotification) {
          selection.cancel();
        }
        return false;
      },
      child: widget.child,
    ),
  );
}

class _SelectionHost extends InheritedWidget {
  final ReadingSelection selection;
  const _SelectionHost({required this.selection, required super.child});
  @override
  bool updateShouldNotify(_SelectionHost oldWidget) =>
      oldWidget.selection != selection;
}

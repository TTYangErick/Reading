import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../book/book.dart';
import 'selection_paging.dart';

abstract interface class ReadingSelectionRegion {
  int get selectionBlock;
  int get selectionStart;
  int get selectionEnd;
  RenderParagraph get selectionRender;
  void selectionChanged();
  void selectionCancelled();
}

typedef _Point = ({int block, int offset});
typedef SelectionSpan = ({int block, int start, int end});

/// A transient selection in one document. Regions identify source intervals,
/// including two clipped renderings of the same paragraph on a spread.
class ReadingSelection {
  List<BookBlock> blocks;
  ValueChanged<String> onSelected;
  ReadingSelection(this.blocks, this.onSelected);
  SelectionPageTurner? paging;
  Iterable<SelectionSpan> Function()? visibleSpans;
  VoidCallback? onSessionEnd;
  final _regions = <ReadingSelectionRegion>{};
  final _visited = <int, List<TextRange>>{};
  final _painted = <ReadingSelectionRegion, TextRange>{};
  ReadingSelectionRegion? _origin;
  Offset? _press;
  TextRange? _word;
  _Point? _start, _end;
  int? _downPointer, _pointer, _originBlock;
  int session = 0;
  bool turningPage = false;
  bool _dragging = false;

  void pointerDown(PointerDownEvent event) {
    if (_downPointer != null && _downPointer != event.pointer) cancel();
    _downPointer = event.pointer;
  }

  void pointerMove(PointerMoveEvent event) {
    if (_pointer == event.pointer) move(event.position, event.viewId);
  }

  void pointerUp(PointerUpEvent event) {
    if (_downPointer == event.pointer) _downPointer = null;
    if (_pointer != event.pointer || _origin == null) return;
    if (_start != null) {
      final text = finish(_origin!);
      if (text != null && text.trim().isNotEmpty) onSelected(text);
    } else if (turningPage || !_regions.contains(_origin)) {
      cancel();
    }
    // A stationary press still finishes through the paragraph's sentence path.
  }

  void pointerCancel(PointerCancelEvent event) {
    if (_pointer == event.pointer) cancel();
    if (_downPointer == event.pointer) _downPointer = null;
  }

  void register(ReadingSelectionRegion region) {
    if (_regions.contains(region)) return;
    if (!turningPage) cancel();
    _regions.add(region);
  }

  void unregister(ReadingSelectionRegion region) {
    _painted.remove(region);
    if (_regions.remove(region) && !turningPage) cancel();
  }

  bool owns(ReadingSelectionRegion region) => identical(_origin, region);

  void begin(ReadingSelectionRegion region, Offset global, TextRange word) {
    cancel();
    _origin = region;
    _originBlock = region.selectionBlock;
    _pointer = _downPointer;
    _press = global;
    _word = TextRange(
      start: word.start.clamp(region.selectionStart, region.selectionEnd),
      end: word.end.clamp(region.selectionStart, region.selectionEnd),
    );
    if (visibleSpans != null) _remember(visibleSpans!());
  }

  void move(Offset global, int viewId) {
    final origin = _origin, word = _word;
    if (origin == null || word == null) return;
    _dragging |= (global - _press!).distance >= 8;
    if (!_dragging) return;
    paging?.update(global);
    if (turningPage) return;
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
    final range = _rangeTo(target.selectionBlock, targetStart, targetEnd);
    if (!_covered(range.start, range.end)) return;
    _start = range.start;
    _end = range.end;
    _notify();
  }

  ({_Point start, _Point end}) _rangeTo(int block, int from, int to) {
    final word = _word!;
    final forward =
        block > _originBlock! || (block == _originBlock && from >= word.start);
    final start = (
      block: forward ? _originBlock! : block,
      offset: forward ? word.start : from,
    );
    final end = (
      block: forward ? block : _originBlock!,
      offset: forward ? to : word.end,
    );
    return (start: start, end: end);
  }

  bool canTurnTo(SelectionSpan edge, Iterable<SelectionSpan> spans) {
    if (_origin == null || turningPage) return false;
    final range = _rangeTo(edge.block, edge.start, edge.end);
    return _covered(range.start, range.end, extra: spans);
  }

  void arriveAt(SelectionSpan edge, Iterable<SelectionSpan> spans) {
    if (_origin == null) return;
    _remember(spans);
    final range = _rangeTo(edge.block, edge.start, edge.end);
    _start = range.start;
    _end = range.end;
    turningPage = false;
    _notify();
  }

  void _remember(Iterable<SelectionSpan> spans) {
    for (final span in spans) {
      final ranges = [
        ...?_visited[span.block],
        TextRange(start: span.start, end: span.end),
      ]..sort((a, b) => a.start.compareTo(b.start));
      final merged = <TextRange>[];
      for (final range in ranges) {
        if (merged.isNotEmpty && merged.last.end >= range.start) {
          final previous = merged.removeLast();
          merged.add(
            TextRange(
              start: previous.start,
              end: previous.end > range.end ? previous.end : range.end,
            ),
          );
        } else {
          merged.add(range);
        }
      }
      _visited[span.block] = merged;
    }
  }

  bool _covered(
    _Point start,
    _Point end, {
    Iterable<SelectionSpan> extra = const [],
  }) {
    if (start.block < 0 || end.block >= blocks.length) return false;
    for (var block = start.block; block <= end.block; block++) {
      final value = blocks[block];
      // Media and table text have their own local selection semantics.
      if (value.image != null || value.rows != null) return false;
      final from = block == start.block ? start.offset : 0;
      final to = block == end.block ? end.offset : value.text.length;
      var cursor = from;
      final ranges = visibleSpans == null
          ? _regions
                .where((r) => r.selectionBlock == block)
                .map(
                  (r) =>
                      TextRange(start: r.selectionStart, end: r.selectionEnd),
                )
                .toList()
          : [
              ...?_visited[block],
              ...extra
                  .where((s) => s.block == block)
                  .map((s) => TextRange(start: s.start, end: s.end)),
            ];
      ranges.sort((a, b) => a.start.compareTo(b.start));
      for (final region in ranges) {
        if (region.end <= cursor || region.start >= to) {
          continue;
        }
        if (region.start > cursor &&
            value.text.substring(cursor, region.start).trim().isNotEmpty) {
          return false;
        }
        if (region.end > cursor) cursor = region.end;
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
    _clear();
  }

  void _clear() {
    final origin = _origin;
    _origin = null;
    _originBlock = null;
    _pointer = null;
    turningPage = false;
    _dragging = false;
    session++;
    paging?.stop();
    _visited.clear();
    _press = null;
    _word = null;
    _start = _end = null;
    _notify();
    origin?.selectionCancelled();
    onSessionEnd?.call();
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

class _SelectionScopeState extends State<ReadingSelectionScope>
    with WidgetsBindingObserver {
  late final selection = ReadingSelection(widget.blocks, widget.onSelected);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) selection.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    selection.cancel();
    selection.paging?.stop();
    super.dispose();
  }

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
    child: Listener(
      onPointerDown: selection.pointerDown,
      onPointerMove: selection.pointerMove,
      onPointerUp: selection.pointerUp,
      onPointerCancel: selection.pointerCancel,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification ||
              notification is OverscrollNotification) {
            if (!selection.turningPage) selection.cancel();
          }
          return false;
        },
        child: widget.child,
      ),
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

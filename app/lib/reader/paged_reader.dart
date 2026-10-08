import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../book/book.dart';
import '../text/language.dart';
import 'book_pagination.dart';
import 'paragraph.dart';
import 'pagination_cache.dart';
import 'selection.dart';
import 'selection_paging.dart';
import 'style.dart';

typedef PageGeometry = ({
  Size size,
  int columns,
  String style,
  TextScaler scaler,
  TargetPlatform platform,
  TextDirection direction,
  Locale? locale,
});

class PagedReader extends StatefulWidget {
  final PaginationCache? cache;
  final String? cacheBookId, cacheContent;
  final BookContent content;
  final String? document;
  final ReaderStyle style;
  final bool compact;
  final PageAnchor initialAnchor;
  final Future<Uint8List?> Function(String) loadImage;
  final void Function(Uint8List bytes, String description)? onImage;
  final void Function(PageAnchor anchor, int page, int count) onPosition;
  final void Function(int block, WordRange word, Rect rect, String? cell)
  onWord;
  final void Function(String text, int offset) onSentence;
  final ValueChanged<WordRange>? onSelection;
  final VoidCallback? onSelectionStart;
  final ValueChanged<BookLink> onLink;
  final VoidCallback onBlank, onTurn, onScrollFallback;
  final int? selectedBlock;
  final String? selectedCell;
  final WordRange? selection;
  final PageAnchor? sourceAnchor;
  final String? sourceCell;
  final int sourceOffset;
  const PagedReader({
    super.key,
    this.cache,
    this.cacheBookId,
    this.cacheContent,
    required this.content,
    this.document,
    required this.style,
    this.compact = false,
    required this.initialAnchor,
    required this.loadImage,
    this.onImage,
    required this.onPosition,
    required this.onWord,
    required this.onSentence,
    this.onSelection,
    this.onSelectionStart,
    required this.onLink,
    required this.onBlank,
    required this.onTurn,
    required this.onScrollFallback,
    this.selectedBlock,
    this.selectedCell,
    this.selection,
    this.sourceAnchor,
    this.sourceCell,
    this.sourceOffset = 0,
  });
  @override
  State<PagedReader> createState() => PagedReaderState();
}

class PagedReaderState extends State<PagedReader> {
  final sourceCellKey = GlobalKey();
  final selectionViewportKey = GlobalKey();
  ReadingSelection? selectionGroup;
  int? selectionOriginPage;
  late final selectionTurner = SelectionPageTurner(
    viewport: () {
      final render = selectionViewportKey.currentContext?.findRenderObject();
      return render is RenderBox && render.hasSize
          ? render.localToGlobal(Offset.zero) & render.size
          : null;
    },
    onTurn: turnSelection,
  );
  late PageAnchor anchor = widget.initialAnchor;
  BookPagination? layout;
  PageController? controller;
  PageGeometry? geometry;
  Future<Map<String, Size>>? imageSizes;
  int generation = 0, page = 0;
  Animation<double>? entryAnimation;
  Completer<void>? entryWait;
  String? error;
  final language = EnglishLanguage();
  static const gutter = 44.0;
  int get columns => geometry?.columns ?? 1;
  int get spread => page ~/ columns;
  int get spreadCount => ((layout?.pages.length ?? 0) / columns).ceil();
  bool get hasOverflow =>
      layout != null && visiblePages.any((i) => layout!.pages[i].overflows);
  String get pageRange =>
      '${visiblePages.first + 1}${visiblePages.length > 1 ? '–${visiblePages.last + 1}' : ''} / ${layout!.pages.length}';
  String? get chapterTitle {
    if (widget.document != null || layout == null) return null;
    final block = selectionOriginPage == null
        ? anchor.position.block
        : layout!.pages[page].start.position.block;
    BookChapter? current;
    for (final chapter in widget.content.contents) {
      if (chapter.block <= block &&
          (current == null || chapter.block >= current.block)) {
        current = chapter;
      }
    }
    return current?.title;
  }

  Iterable<int> get visiblePages sync* {
    for (
      var i = spread * columns;
      i < math.min((spread + 1) * columns, layout!.pages.length);
      i++
    ) {
      yield i;
    }
  }

  List<BookBlock> get blocks => widget.document == null
      ? widget.content.blocks
      : widget.content.supplementaryDocuments[widget.document]!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = ReadingSelectionScope.maybeOf(context);
    if (group == selectionGroup) return;
    detachSelection();
    selectionGroup = group;
    if (group != null) {
      group.paging = selectionTurner;
      group.visibleSpans = () => spansFor(visiblePages);
      group.onSessionEnd = restoreSelectionPage;
    }
  }

  void detachSelection() {
    final group = selectionGroup;
    if (group != null && identical(group.paging, selectionTurner)) {
      group.onSessionEnd = null;
      group.cancel();
      group.paging = null;
      group.visibleSpans = null;
    }
    selectionTurner.stop();
    selectionOriginPage = null;
  }

  Iterable<SelectionSpan> spansFor(Iterable<int> pages) sync* {
    if (layout == null) return;
    for (final index in pages) {
      for (final fragment in layout!.pages[index].fragments) {
        if (fragment is PageTextFragment &&
            fragment.anchor.part == PagePart.text) {
          yield (
            block: fragment.anchor.position.block,
            start: fragment.anchor.position.offset,
            end: fragment.endOffset,
          );
        }
      }
    }
  }

  Future<bool> turnSelection(int direction) async {
    final group = selectionGroup, currentLayout = layout;
    if (!mounted ||
        group == null ||
        currentLayout == null ||
        controller?.hasClients != true ||
        hasOverflow) {
      return false;
    }
    final target = spread + direction;
    if (target < 0 || target >= spreadCount) return false;
    final indexes = List.generate(
      columns,
      (i) => target * columns + i,
    ).where((i) => i < currentLayout.pages.length).toList();
    if (indexes.any((i) => currentLayout.pages[i].overflows)) return false;
    final spans = spansFor(indexes).toList();
    if (spans.isEmpty) return false;
    final edge = direction > 0 ? spans.first : spans.last;
    if (!group.canTurnTo(edge, spans)) return false;
    selectionOriginPage ??= page;
    final session = group.session, token = generation;
    group.turningPage = true;
    setState(() => page = target * columns);
    controller!.jumpToPage(target);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        token != generation ||
        session != group.session ||
        !identical(layout, currentLayout)) {
      return false;
    }
    group.arriveAt(edge, spans);
    return true;
  }

  void restoreSelectionPage() {
    final original = selectionOriginPage;
    selectionOriginPage = null;
    if (original == null) return;
    final token = generation, currentController = controller;
    void restore() {
      if (!mounted ||
          token != generation ||
          !identical(controller, currentController) ||
          currentController?.hasClients != true) {
        return;
      }
      setState(() => page = original);
      currentController!.jumpToPage(original ~/ columns);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => restore());
    } else {
      restore();
    }
  }

  @override
  void didUpdateWidget(covariant PagedReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.cacheBookId != widget.cacheBookId ||
        oldWidget.cacheContent != widget.cacheContent ||
        (widget.cacheContent == null &&
            !identical(oldWidget.content, widget.content))) {
      selectionGroup?.cancel();
      generation++;
      geometry = null;
      imageSizes = null;
      anchor = widget.initialAnchor;
    }
  }

  @override
  void dispose() {
    detachSelection();
    generation++;
    finishEntryWait();
    controller?.dispose();
    super.dispose();
  }

  PageAnchor normalized(PageAnchor candidate) {
    final p = candidate.position;
    final index = p.block.clamp(0, blocks.length - 1);
    final block = blocks[index];
    final offset = index == p.block ? p.offset.clamp(0, block.text.length) : 0;
    final position = BookPosition(
      index,
      offset: block.rows != null ? 0 : offset,
      document: widget.document,
    );
    if (block.image != null) {
      return PageAnchor(
        position,
        part:
            offset == 0 && candidate.part != PagePart.caption ||
                block.text.isEmpty ||
                block.text == '图片'
            ? PagePart.image
            : PagePart.caption,
      );
    }
    if (block.rows != null) {
      return PageAnchor(
        position,
        part: PagePart.tableRow,
        row: (candidate.row ?? 0).clamp(0, math.max(0, block.rows!.length - 1)),
      );
    }
    return PageAnchor(position);
  }

  void finishEntryWait() {
    entryAnimation?.removeStatusListener(entryStatusChanged);
    entryAnimation = null;
    final wait = entryWait;
    entryWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
  }

  void entryStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.forward) finishEntryWait();
  }

  Future<void> waitForEntry() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status != AnimationStatus.forward) {
      return;
    }
    if (entryWait == null) {
      entryWait = Completer<void>();
      entryAnimation = animation;
      animation.addStatusListener(entryStatusChanged);
    }
    await entryWait!.future;
  }

  PaginationCacheKey? cacheKey(PageGeometry config) {
    final id = widget.cacheBookId, content = widget.cacheContent;
    if (id == null || content == null || widget.cache == null) return null;
    return (
      book: id,
      content: content,
      document: widget.document,
      geometry: config,
    );
  }

  Future<void> calculate(PageGeometry config, int token) async {
    final cache = widget.cache;
    final cacheGeneration = cache?.generation;
    try {
      // Pagination uses TextPainter on the UI isolate. Do not compete with
      // the route's entrance animation; dismissal must also release the wait.
      await waitForEntry();
      if (!mounted ||
          token != generation ||
          ModalRoute.of(context)?.animation?.status ==
              AnimationStatus.reverse) {
        return;
      }
      final sizes = await (imageSizes ??= loadPaginationImageSizes(
        widget.content,
        widget.loadImage,
        document: widget.document,
      ));
      if (!mounted || token != generation) return;
      final result = await const BookPaginator().paginateAsync(
        widget.content,
        viewport: config.size,
        platform: config.platform,
        style: widget.style,
        document: widget.document,
        imageSizes: sizes,
        textScaler: config.scaler,
        textDirection: config.direction,
        locale: config.locale,
        cancelled: () => !mounted || token != generation,
      );
      if (!mounted || token != generation || result == null) return;
      if (result.pages.isEmpty) throw StateError('empty document');
      final key = cacheKey(config);
      if (key != null &&
          identical(cache, widget.cache) &&
          cacheGeneration == cache?.generation) {
        cache!.put(key, result);
      }
      anchor = normalized(anchor);
      final index =
          result.pageForAnchor(anchor) ??
          result.pageForPosition(anchor.position) ??
          0;
      final previous = controller;
      setState(() {
        layout = result;
        page = index;
        controller = PageController(initialPage: index ~/ config.columns);
      });
      previous?.dispose();
      publish();
      if (widget.sourceAnchor != null &&
          result.pageForAnchor(widget.sourceAnchor!) == page) {
        WidgetsBinding.instance.addPostFrameCallback((_) => revealSourceCell());
      }
    } catch (e) {
      if (!mounted || token != generation) return;
      setState(
        () => error = e is PaginationTooLargeException
            ? '这份内容含特别长的段落，建议使用滚动阅读。'
            : '暂时无法分页，可以继续滚动阅读。',
      );
    }
  }

  void publish() {
    final value = anchor;
    final index = page, count = layout?.pages.length ?? 0, token = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == generation) {
        widget.onPosition(value, index, count);
      }
    });
  }

  void jumpPage(int index) {
    if (layout == null || controller?.hasClients != true) return;
    selectionGroup?.cancel();
    widget.onTurn();
    final target = index.clamp(0, layout!.pages.length - 1);
    setState(() {
      page = target;
      anchor = layout!.pages[target].start;
    });
    controller!.jumpToPage(target ~/ columns);
    publish();
  }

  void jump(BookPosition position) => jumpAnchor(PageAnchor(position));

  void jumpAnchor(PageAnchor value) {
    selectionGroup?.cancel();
    anchor = normalized(value);
    final index =
        layout?.pageForAnchor(anchor) ??
        layout?.pageForPosition(anchor.position);
    if (index != null && controller?.hasClients == true) {
      setState(() => page = index);
      controller!.jumpToPage(index ~/ columns);
      publish();
    }
  }

  void turn(int delta) {
    if (layout == null || controller?.hasClients != true) return;
    selectionGroup?.cancel();
    final target = (spread + delta).clamp(0, spreadCount - 1);
    if (target != spread) {
      controller!.animateToPage(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void focusPage(int index) {
    if (page == index) return;
    setState(() {
      page = index;
      anchor = layout!.pages[index].start;
    });
    publish();
  }

  TextStyle textStyle(Color ink) => TextStyle(
    fontFamily: widget.style.family(geometry!.platform),
    fontFamilyFallback: const ['Literata'],
    fontSize: widget.style.size,
    fontWeight: widget.style.bold ? FontWeight.w700 : FontWeight.w400,
    height: widget.style.lineHeight,
    letterSpacing: widget.style.letterSpacing * widget.style.size,
    color: ink,
  );

  Widget paragraph(
    int pageIndex,
    int index,
    String text,
    TextStyle style,
    TextAlign align, {
    String? cell,
    bool links = true,
    int visibleStart = 0,
    int? visibleEnd,
    Key? key,
  }) => ReaderParagraph(
    key: key,
    sourceBlock: cell == null && links ? index : null,
    anchorKey:
        cell != null &&
            cell.contains('-') &&
            cell == widget.sourceCell &&
            index == widget.sourceAnchor?.position.block
        ? sourceCellKey
        : null,
    text: text,
    visibleStart: visibleStart,
    visibleEnd: visibleEnd,
    onSelectionStart: widget.onSelectionStart,
    onSelection: widget.onSelection,
    language: language,
    style: style,
    align: align,
    selection: widget.selectedBlock == index && widget.selectedCell == cell
        ? widget.selection
        : null,
    links: links
        ? widget.content.links
              .where((l) => l.document == widget.document && l.block == index)
              .toList()
        : const [],
    onLink: (link) {
      focusPage(pageIndex);
      widget.onLink(link);
    },
    onBlank: () {
      focusPage(pageIndex);
      widget.onBlank();
    },
    onWord: (word, rect) {
      focusPage(pageIndex);
      widget.onWord(index, word, rect, cell);
    },
    onSentence: (offset) {
      focusPage(pageIndex);
      widget.onSentence(text, offset);
    },
  );

  void revealSourceCell() {
    if (!mounted) return;
    final context = sourceCellKey.currentContext;
    final render = context?.findRenderObject();
    if (context == null || render is! RenderParagraph) return;
    Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position.ensureVisible(render);
    final vertical = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (vertical == null) return;
    vertical.ensureVisible(render);
    final caret = render.getOffsetForCaret(
      TextPosition(offset: widget.sourceOffset),
      Rect.zero,
    );
    vertical.jumpTo(
      (vertical.pixels + caret.dy).clamp(
        vertical.minScrollExtent,
        vertical.maxScrollExtent,
      ),
    );
  }

  Widget pageWidget(BookPage value, int pageIndex, Color ink) {
    final width = layout!.contentSize.width;
    final text = textStyle(ink);
    final items = <Widget>[];
    final fragments = value.fragments;
    for (var i = 0; i < fragments.length; i++) {
      final f = fragments[i];
      final index = f.anchor.position.block;
      final block = blocks[index];
      if (f is PageTextFragment) {
        var last = f;
        while (i + 1 < fragments.length) {
          final next = fragments[i + 1];
          if (next is! PageTextFragment ||
              next.anchor.position.block != index ||
              next.anchor.part != f.anchor.part) {
            break;
          }
          last = next;
          i++;
        }
        final caption = f.anchor.part == PagePart.caption;
        final style = caption
            ? text.copyWith(fontSize: widget.style.size * .8)
            : block.heading
            ? text.copyWith(
                fontSize: widget.style.size * 1.35,
                fontWeight: FontWeight.w600,
                height: 1.3,
              )
            : text;
        items.add(
          Positioned(
            top: f.top,
            left: 0,
            width: width,
            height: last.top + last.height - f.top,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: width,
                maxWidth: width,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(0, -f.line.sourceTop),
                  child: paragraph(
                    pageIndex,
                    index,
                    block.text,
                    style,
                    !caption && widget.style.justify && !block.heading
                        ? TextAlign.justify
                        : TextAlign.start,
                    links: !caption,
                    visibleStart: f.anchor.position.offset,
                    visibleEnd: last.endOffset,
                    cell: caption ? 'caption' : null,
                    key: ValueKey(
                      'page-text-$pageIndex-$index-${f.anchor.part.name}',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      } else if (f is PageImageFragment) {
        items.add(
          Positioned(
            top: f.top,
            left: f.left,
            width: f.width,
            height: f.height,
            child: f.unavailable
                ? Center(child: Text('图片无法读取', style: text))
                : FutureBuilder<Uint8List?>(
                    future: widget.loadImage(f.path),
                    builder: (_, snapshot) => snapshot.data == null
                        ? Center(
                            child:
                                snapshot.connectionState == ConnectionState.done
                                ? Text('图片无法读取', style: text)
                                : const CircularProgressIndicator(),
                          )
                        : Semantics(
                            button: true,
                            label: '放大图片',
                            child: GestureDetector(
                              key: ValueKey('reader-image-$index'),
                              onTap: () => widget.onImage != null
                                  ? widget.onImage!(snapshot.data!, block.text)
                                  : widget.onBlank(),
                              child: Image.memory(
                                snapshot.data!,
                                fit: BoxFit.contain,
                                cacheWidth: 1400,
                                semanticLabel: block.text,
                                errorBuilder: (_, error, stack) =>
                                    Text('图片无法显示', style: text),
                              ),
                            ),
                          ),
                  ),
          ),
        );
      } else if (f is PageTableRowFragment) {
        final rows = [f];
        while (i + 1 < fragments.length) {
          final next = fragments[i + 1];
          if (next is! PageTableRowFragment ||
              next.anchor.position.block != index) {
            break;
          }
          rows.add(next);
          i++;
        }
        items.add(
          Positioned(
            top: f.top,
            left: 0,
            width: width,
            height: rows.last.top + rows.last.height - f.top,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              key: ValueKey('page-table-$pageIndex-$index'),
              child: SizedBox(
                width: f.width,
                child: Column(
                  children: [
                    for (final row in rows)
                      SizedBox(
                        height: row.height,
                        child: Row(
                          children: [
                            for (var c = 0; c < row.cells.length; c++)
                              Container(
                                width: PageTableRowFragment.columnWidth,
                                height: row.height,
                                foregroundDecoration: BoxDecoration(
                                  border: Border.all(
                                    color: ink.withValues(alpha: .25),
                                  ),
                                ),
                                color: row.isHeader
                                    ? ink.withValues(alpha: .07)
                                    : null,
                                padding: const EdgeInsets.all(10),
                                alignment: AlignmentDirectional.centerStart,
                                child: paragraph(
                                  pageIndex,
                                  index,
                                  row.emptyTable ? '空表格' : row.cells[c].text,
                                  row.isHeader
                                      ? text.copyWith(
                                          fontWeight: FontWeight.w700,
                                        )
                                      : text,
                                  TextAlign.start,
                                  cell: '${row.anchor.row}-$c',
                                  links: false,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        focusPage(pageIndex);
        widget.onBlank();
      },
      child: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            key: ValueKey('page-scroll-$pageIndex'),
            child: SizedBox(
              height: math.max(layout!.contentSize.height, value.height),
              child: Stack(children: items),
            ),
          ),
        ),
      ),
    );
  }

  void expandPage() {
    widget.onTurn();
    final indexes = visiblePages
        .expand((index) => layout!.pages[index].fragments)
        .map((f) => f.anchor.position.block)
        .toSet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Expanded(child: Text('本页完整内容')),
                IconButton(
                  tooltip: '关闭完整内容',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            for (final index in indexes) ...[
              if (blocks[index].rows case final rows?) ...[
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final cell in row) SelectableText(cell)],
                    ),
                  ),
              ] else
                SelectableText(blocks[index].text),
              const Divider(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.style
        .palette(MediaQuery.platformBrightnessOf(context))
        .ink;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            ReaderStyle.isWideLandscape(MediaQuery.sizeOf(context)) &&
                constraints.maxWidth >= 900
            ? 2
            : 1;
        final config = (
          size: Size(
            (constraints.maxWidth - (columns - 1) * gutter) / columns,
            math.max(1, constraints.maxHeight - 40),
          ),
          columns: columns,
          style: widget.style.paginationKey,
          scaler: MediaQuery.textScalerOf(context),
          platform: Theme.of(context).platform,
          direction: Directionality.of(context),
          locale: Localizations.maybeLocaleOf(context),
        );
        if (geometry != config) {
          selectionGroup?.cancel();
          geometry = config;
          layout = null;
          error = null;
          final token = ++generation;
          final key = cacheKey(config);
          final cached = key == null ? null : widget.cache!.get(key);
          if (cached != null) {
            anchor = normalized(anchor);
            page =
                cached.pageForAnchor(anchor) ??
                cached.pageForPosition(anchor.position) ??
                0;
            layout = cached;
            controller?.dispose();
            controller = PageController(initialPage: page ~/ config.columns);
            publish();
            if (widget.sourceAnchor != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && token == generation) revealSourceCell();
              });
            }
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && token == generation) {
                unawaited(calculate(config, token));
              }
            });
          }
        }
        if (error != null) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBlank,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: widget.onScrollFallback,
                    child: const Text('改用滚动阅读'),
                  ),
                ],
              ),
            ),
          );
        }
        if (layout == null) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBlank,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在分页…'),
                ],
              ),
            ),
          );
        }
        final pages = Column(
          children: [
            Expanded(
              // Cover the gutter and an empty final right page as well as
              // page-local whitespace. Text gestures still win their taps;
              // PageView continues to handle horizontal drags.
              child: GestureDetector(
                key: selectionViewportKey,
                behavior: HitTestBehavior.opaque,
                onTap: widget.onBlank,
                child: PageView.builder(
                  key: ValueKey(controller),
                  controller: controller,
                  itemCount: spreadCount,
                  onPageChanged: (index) {
                    if (index == spread) return;
                    widget.onTurn();
                    setState(() {
                      page = index * columns;
                      anchor = layout!.pages[page].start;
                    });
                    publish();
                  },
                  itemBuilder: (_, index) => Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0)
                          SizedBox(
                            width: gutter,
                            child: Center(
                              child: Container(
                                width: 1,
                                color: ink.withValues(alpha: .12),
                              ),
                            ),
                          ),
                        Expanded(
                          child: index * columns + column < layout!.pages.length
                              ? KeyedSubtree(
                                  key: ValueKey(
                                    'visible-page-${index * columns + column}',
                                  ),
                                  child: pageWidget(
                                    layout!.pages[index * columns + column],
                                    index * columns + column,
                                    ink,
                                  ),
                                )
                              : const SizedBox.expand(
                                  key: ValueKey('empty-page'),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: widget.compact
                  ? Semantics(
                      button: true,
                      label: '阅读操作',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onBlank,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Center(
                            child: DefaultTextStyle(
                              style: Theme.of(context).textTheme.labelSmall!
                                  .copyWith(
                                    fontSize: 11,
                                    color: ink.withValues(alpha: .45),
                                  ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (chapterTitle case final title?) ...[
                                    Flexible(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Text(' — '),
                                  ],
                                  Text(
                                    pageRange,
                                    key: const ValueKey('page-label'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          key: const ValueKey('previous-page'),
                          tooltip: '上一页',
                          onPressed: spread > 0 ? () => turn(-1) : null,
                          icon: Icon(Icons.chevron_left, color: ink),
                        ),
                        Text(
                          '$pageRange 页',
                          key: const ValueKey('page-label'),
                          style: TextStyle(color: ink),
                        ),
                        IconButton(
                          key: const ValueKey('next-page'),
                          tooltip: '下一页',
                          onPressed: spread + 1 < spreadCount
                              ? () => turn(1)
                              : null,
                          icon: Icon(Icons.chevron_right, color: ink),
                        ),
                        if (visiblePages.any(
                          (index) => layout!.pages[index].overflows,
                        ))
                          IconButton(
                            tooltip: '展开本页内容',
                            onPressed: expandPage,
                            icon: Icon(
                              Icons.open_in_full,
                              size: 18,
                              color: ink,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
        return pages;
      },
    );
  }
}

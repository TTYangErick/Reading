import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../book/book.dart';
import '../bookmarks/bookmark.dart';
import '../bookmarks/bookmark_sheet.dart';
import '../search/book_search.dart';
import '../search/search_page.dart';
import '../core/providers.dart';
import '../core/reader_system_ui.dart';
import '../orientation/orientation.dart';
import '../orientation/settings.dart';
import '../dict/dictionary.dart';
import '../text/language.dart';
import '../translate/sentence_sheet.dart';
import 'bubble.dart';
import 'image_viewer.dart';
import 'settings.dart';
import 'selection.dart';
import '../vocab/vocabulary.dart';
import '../vocab/save_button.dart';
import 'style.dart';
import 'paragraph.dart';
import 'book_pagination.dart';
import 'paged_reader.dart';
export 'paragraph.dart';

typedef _ViewportGeometry = ({
  Size size,
  double pixelRatio,
  EdgeInsets padding,
  EdgeInsets insets,
});

class ReaderPage extends ConsumerStatefulWidget {
  final Book book;
  final ReaderStyle defaultStyle;
  final BookPosition? linkTarget;
  final List<BookPosition> linkOrigins;
  final String linkTitle;
  final void Function(ReaderStyle, bool)? onStyleChanged;
  final ValueChanged<int>? onChapter;
  final VoidCallback? onLeave;
  final bool? initialPerBook;
  final PageAnchor? sourceAnchor;
  final PageAnchor? linkAnchor;
  final String? sourceCell;
  final bool fromVocabulary;
  final BookSearchHit? searchHit;
  const ReaderPage({super.key, required this.book, required this.defaultStyle})
    : linkTarget = null,
      linkOrigins = const [],
      linkTitle = '',
      onStyleChanged = null,
      onChapter = null,
      onLeave = null,
      initialPerBook = null,
      sourceAnchor = null,
      linkAnchor = null,
      sourceCell = null,
      fromVocabulary = false,
      searchHit = null;

  const ReaderPage.source({
    super.key,
    required this.book,
    required this.defaultStyle,
    required BookPosition target,
    required PageAnchor anchor,
    String? cell,
  }) : linkTarget = target,
       sourceAnchor = anchor,
       linkAnchor = null,
       sourceCell = cell,
       fromVocabulary = true,
       searchHit = null,
       linkOrigins = const [],
       linkTitle = '原句',
       onStyleChanged = null,
       onChapter = null,
       onLeave = null,
       initialPerBook = null;

  const ReaderPage._linked({
    required this.book,
    required this.defaultStyle,
    required this.linkTarget,
    required this.linkOrigins,
    required this.linkTitle,
    required this.onStyleChanged,
    required this.onChapter,
    required this.onLeave,
    required this.initialPerBook,
    required this.fromVocabulary,
    this.linkAnchor,
    this.sourceCell,
    this.searchHit,
  }) : sourceAnchor = null;
  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  final controller = ItemScrollController();
  final offsetController = ScrollOffsetController();
  final positions = ItemPositionsListener.create();
  final stackKey = GlobalKey();
  final targetTextKey = GlobalKey();
  final pagedKey = GlobalKey<PagedReaderState>();
  final language = EnglishLanguage();
  bool get isLinkView => widget.linkTarget != null;
  bool get isSourceRoot => widget.sourceAnchor != null;
  bool get ownsReadingSession => !isLinkView || isSourceRoot;
  String get exitLabel => widget.fromVocabulary ? '返回生词本' : '返回书架';
  String get originLabel => widget.fromVocabulary ? '回到原句' : '回到原阅读处';
  List<BookBlock> get blocks => widget.linkTarget?.document == null
      ? widget.book.content.blocks
      : widget.book.content.supplementaryDocuments[widget
            .linkTarget!
            .document]!;
  late final linksByBlock = <int, List<BookLink>>{};
  late ReaderStyle style = isLinkView && !isSourceRoot
      ? widget.defaultStyle
      : ReaderStyle.decode(widget.book.style ?? widget.defaultStyle.encode());
  late bool perBook = widget.initialPerBook ?? (widget.book.style != null);
  late int position = (widget.linkTarget?.block ?? widget.book.position).clamp(
    0,
    blocks.length - 1,
  );
  bool chrome = true, expanded = false, saving = false;
  bool openingLink = false;
  ({
    PageAnchor anchor,
    double? alignment,
    String style,
    _ViewportGeometry viewport,
  })?
  chapterOrigin;
  int chapterNavigation = 0;

  void rememberChapterOrigin() {
    if (chapterOrigin != null || isLinkView) return;
    PageAnchor? value;
    double? alignment;
    if (paged) {
      if (!pagedReady) return;
      value = pagedKey.currentState?.anchor;
    } else if (controller.isAttached) {
      final visible =
          positions.itemPositions.value
              .where((p) => p.itemTrailingEdge > .02 && p.itemLeadingEdge < 1)
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
      if (visible.isEmpty) return;
      final first = visible.first, block = blocks[visible.first.index];
      value = PageAnchor(
        BookPosition(first.index),
        part: block.image != null
            ? PagePart.image
            : block.rows != null
            ? PagePart.tableRow
            : PagePart.text,
        row: block.rows != null ? 0 : null,
      );
      alignment = first.itemLeadingEdge;
    }
    if (value == null) return;
    setState(
      () => chapterOrigin = (
        anchor: value!,
        alignment: alignment,
        style: style.encode(),
        viewport: viewportGeometry,
      ),
    );
  }

  void returnFromChapter() {
    final origin = chapterOrigin;
    if (origin == null || isLinkView) return;
    if (paged && (!pagedReady || pagedKey.currentState?.layout == null)) return;
    if (!paged && !controller.isAttached) return;
    dismiss();
    final token = ++chapterNavigation;
    setState(() => chapterOrigin = null);
    saveTimer?.cancel();
    if (paged) {
      pagedKey.currentState!.jumpAnchor(origin.anchor);
    } else {
      final alignment =
          origin.alignment != null &&
              origin.style == style.encode() &&
              origin.viewport == viewportGeometry
          ? origin.alignment!
          : 0.0;
      controller.jumpTo(
        index: origin.anchor.position.block,
        alignment: alignment.clamp(0, 1),
      );
      setState(() {
        position = origin.anchor.position.block;
        precise = origin.anchor;
      });
      if (alignment < 0) {
        final height =
            (stackKey.currentContext!.findRenderObject()! as RenderBox)
                .size
                .height;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !paged &&
              controller.isAttached &&
              token == chapterNavigation) {
            unawaited(
              offsetController.animateScroll(
                offset: -alignment * height,
                duration: const Duration(milliseconds: 1),
              ),
            );
          }
        });
      }
      savePosition();
    }
  }

  late PageAnchor precise = initialLocation();
  bool pagedReady = false;
  int currentPage = 0, pageCount = 0;
  bool? activePaged;
  bool wideLandscape = false;
  bool compactReader = false;
  bool get paged => activePaged ?? style.paged;

  // Orientation preferences can change the mode without opening settings.
  // Keep the last source anchor until the user actually moves in scroll mode.
  void syncMode(Size size) {
    wideLandscape = ReaderStyle.isWideLandscape(size);
    final next = style.pagedFor(size);
    compactReader = size.shortestSide >= 600 || next;
    if (activePaged != null && activePaged != next) {
      if (activePaged!) {
        precise = pagedKey.currentState?.anchor ?? precise;
        position = precise.position.block;
      }
      pagedReady = false;
      saveTimer?.cancel();
      lookupGeneration++;
      selected = null;
      selectedParagraph = null;
      anchor = null;
      expanded = false;
    }
    activePaged = next;
  }

  PageAnchor initialLocation() {
    if (widget.sourceAnchor != null) return widget.sourceAnchor!;
    if (widget.linkAnchor != null) return widget.linkAnchor!;
    if (isLinkView) return PageAnchor(widget.linkTarget!);
    final saved = PageAnchor.decode(widget.book.location);
    return saved != null && saved.position.document == null
        ? saved
        : PageAnchor(BookPosition(position));
  }

  void pagedPosition(PageAnchor value, int page, int count) {
    if (!mounted || !paged) return;
    setState(() {
      precise = value;
      position = value.position.block;
      currentPage = page;
      pageCount = count;
      pagedReady = true;
    });
    if (!isLinkView) {
      saveTimer?.cancel();
      saveTimer = Timer(const Duration(milliseconds: 250), savePosition);
    }
  }

  void scrollFallback() {
    dismiss();
    setState(
      () => style = style.withValue(
        wideLandscape ? 'landscapePaged' : 'paged',
        false,
      ),
    );
    if (!isLinkView) persistStyle();
  }

  int? selectedParagraph;
  String? selectedCell;
  final imageLoads = <String, Future<Uint8List?>>{};
  WordRange? selected;
  Rect? anchor;
  _ViewportGeometry? lookupViewport;
  DictionaryEntry? entry;
  String? lookupMessage;
  Timer? saveTimer;
  int lookupGeneration = 0;
  Future<void> writes = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final link in widget.book.content.links) {
      if (link.document == widget.linkTarget?.document) {
        linksByBlock.putIfAbsent(link.block, () => []).add(link);
      }
    }
    positions.itemPositions.addListener(positionChanged);
    if (ownsReadingSession) unawaited(WakelockPlus.enable());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isLinkView) {
        revealLinkTarget();
      } else {
        savePosition();
      }
    });
  }

  void revealLinkTarget([int attempt = 0]) {
    if (!mounted || paged) return;
    final render = targetTextKey.currentContext?.findRenderObject();
    final stack = stackKey.currentContext?.findRenderObject();
    if (render is! RenderParagraph ||
        stack is! RenderBox ||
        !controller.isAttached) {
      // The positioned list mounts its visible items after its first layout.
      if (attempt < 3) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => revealLinkTarget(attempt + 1),
        );
        WidgetsBinding.instance.scheduleFrame();
      }
      return;
    }
    final caret = render.getOffsetForCaret(
      TextPosition(offset: widget.linkTarget!.offset),
      Rect.zero,
    );
    final delta =
        render.localToGlobal(caret).dy -
        stack.localToGlobal(const Offset(0, 84)).dy;
    if (delta.abs() > 1) {
      unawaited(
        offsetController.animateScroll(
          offset: delta,
          duration: const Duration(milliseconds: 1),
        ),
      );
    }
    if (widget.sourceCell != null && targetTextKey.currentContext != null) {
      Scrollable.maybeOf(
        targetTextKey.currentContext!,
        axis: Axis.horizontal,
      )?.position.ensureVisible(render);
    }
  }

  bool validTarget(BookPosition? target) {
    if (target == null) return false;
    final content = widget.book.content;
    final targetBlocks = target.document == null
        ? content.blocks
        : content.supplementaryDocuments[target.document];
    return targetBlocks != null &&
        target.block >= 0 &&
        target.block < targetBlocks.length &&
        target.offset >= 0 &&
        target.offset <= targetBlocks[target.block].text.length;
  }

  Future<void> openLink(
    BookLink link, {
    PageAnchor? bookmarkAnchor,
    BookSearchHit? searchHit,
    BuildContext? navigationContext,
  }) async {
    if (selected != null) {
      dismiss();
      return;
    }
    final routeContext = navigationContext ?? context;
    if (openingLink || ModalRoute.of(routeContext)?.isCurrent == false) return;
    dismiss();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (link.status != BookLinkStatus.resolved ||
        (searchHit != null
            ? !searchHit.valid(widget.book.content)
            : !validTarget(link.target))) {
      final message = switch (link.status) {
        BookLinkStatus.external => '这是书外链接，暂不打开。',
        BookLinkStatus.unavailableDocument => '这处引用的内容尚未载入。',
        BookLinkStatus.invalid => '这处链接格式不受支持。',
        _ => '找不到这处引用的内容。',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final target = link.target!;
    // EPUB 2 often has no backlink semantics. Match the actual source position.
    final originIndex = widget.linkOrigins.lastIndexWhere(
      (source) =>
          source.document == target.document &&
          source.block == target.block &&
          source.offset == target.offset,
    );
    if (bookmarkAnchor == null && searchHit == null && originIndex >= 0) {
      final navigator = Navigator.of(context);
      var remaining = widget.linkOrigins.length - originIndex;
      navigator.popUntil((route) {
        if (remaining == 0) return route.settings.name != 'reading-search';
        if (route.settings.name == 'reading-link') {
          remaining--;
          return false;
        }
        return route.settings.name != 'reading-search';
      });
      return;
    }
    if (widget.linkOrigins.length >= 16) {
      messenger.showSnackBar(const SnackBar(content: Text('打开的链接较多，请先返回再继续。')));
      return;
    }
    final source = BookPosition(
      link.block,
      offset: link.start,
      document: link.document,
    );
    openingLink = true;
    try {
      unawaited(ReaderSystemUi.setImmersive(false));
      await Navigator.of(routeContext).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'reading-link'),
          builder: (_) => ReaderPage._linked(
            book: widget.book,
            defaultStyle: style,
            linkTarget: target,
            linkOrigins: [...widget.linkOrigins, source],
            linkTitle: searchHit != null
                ? '搜索结果'
                : bookmarkAnchor != null
                ? '书签'
                : link.kind == BookLinkKind.noteref
                ? '脚注'
                : '书内链接',
            searchHit: searchHit,
            linkAnchor: searchHit?.anchor ?? bookmarkAnchor,
            sourceCell:
                searchHit?.cell ??
                (bookmarkAnchor?.part == PagePart.caption
                    ? 'caption'
                    : bookmarkAnchor?.part == PagePart.tableRow
                    ? '${bookmarkAnchor!.row}-0'
                    : null),
            onStyleChanged: changeStyle,
            onChapter: openChapter,
            onLeave: leave,
            initialPerBook: perBook,
            fromVocabulary: widget.fromVocabulary,
          ),
        ),
      );
    } finally {
      openingLink = false;
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(ReaderSystemUi.setImmersive(!chrome));
      }
    }
  }

  void enqueue(Future<void> Function() action) {
    writes = writes.then((_) => action()).catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请检查设备剩余空间。')));
      }
    });
  }

  void savePosition() {
    if (isLinkView || (paged && !pagedReady)) return;
    final anchor = pagedKey.currentState?.anchor ?? precise;
    final current = paged ? anchor.position.block : position;
    final location = paged ? anchor.encode() : null;
    final database = ref.read(databaseProvider);
    enqueue(
      () => database.savePosition(widget.book.id, current, location: location),
    );
  }

  void positionChanged() {
    if (paged) return;
    final visible =
        positions.itemPositions.value
            .where((p) => p.itemTrailingEdge > .02 && p.itemLeadingEdge < 1)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty || visible.first.index == position || !mounted) return;
    setState(() => position = visible.first.index);
    precise = PageAnchor(
      BookPosition(position, document: widget.linkTarget?.document),
    );
    if (isLinkView) return;
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 250), savePosition);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) savePosition();
  }

  @override
  void didChangeMetrics() {
    // iOS can report metrics again after a tap without changing the layout.
    // Only invalidate the word's anchor when this view's geometry changes.
    if (selected != null && lookupViewport != viewportGeometry) dismiss();
  }

  _ViewportGeometry get viewportGeometry {
    final view = View.of(context);
    return (
      size: view.physicalSize,
      pixelRatio: view.devicePixelRatio,
      padding: EdgeInsets.fromViewPadding(view.padding, 1),
      insets: EdgeInsets.fromViewPadding(view.viewInsets, 1),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    positions.itemPositions.removeListener(positionChanged);
    saveTimer?.cancel();
    if (ownsReadingSession) {
      unawaited(WakelockPlus.disable());
      unawaited(ReaderSystemUi.setImmersive(false));
    }
    super.dispose();
  }

  void dismiss() {
    lookupGeneration++;
    if (mounted && selected != null) {
      setState(() {
        selected = null;
        selectedParagraph = null;
        anchor = null;
        expanded = false;
      });
    }
  }

  void toggleChrome() {
    if (selected != null) {
      dismiss();
      return;
    }
    if (compactReader) {
      readingActions();
      return;
    }
    setState(() => chrome = !chrome);
    unawaited(ReaderSystemUi.setImmersive(!chrome));
  }

  PageAnchor? bookmarkPosition() {
    if (paged) {
      final view = pagedKey.currentState;
      if (!pagedReady || view?.layout == null) return null;
      return view!.layout!.pages[view.visiblePages.first].start;
    }
    final block = blocks[position];
    return PageAnchor(
      BookPosition(position, document: widget.linkTarget?.document),
      part: block.image != null
          ? PagePart.image
          : block.rows != null
          ? PagePart.tableRow
          : PagePart.text,
      row: block.rows != null ? 0 : null,
    );
  }

  Future<void> bookmarks() async {
    dismiss();
    final source = bookmarkPosition();
    final item = await showModalBottomSheet<Bookmark>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: BookmarkSheet(bookId: widget.book.id, current: source),
      ),
    );
    if (!mounted || item == null) return;
    final target = item.resolve(widget.book);
    if (target == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('书签位置已失效。可以删除这条书签。')));
      return;
    }
    await openLink(
      BookLink(
        block: source?.position.block ?? position,
        start: source?.position.offset ?? 0,
        end: source?.position.offset ?? 0,
        document: widget.linkTarget?.document,
        href: '',
        kind: BookLinkKind.link,
        status: BookLinkStatus.resolved,
        target: target.position,
      ),
      bookmarkAnchor: target,
    );
  }

  bool isTemporaryReadingRoute(Route<dynamic> route) =>
      route.settings.name == 'reading-link' ||
      route.settings.name == 'reading-search';

  Future<void> searchBook() async {
    dismiss();
    unawaited(ReaderSystemUi.setImmersive(false));
    final source =
        bookmarkPosition()?.position ??
        BookPosition(position, document: widget.linkTarget?.document);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'reading-search'),
        builder: (_) => BookSearchPage(
          content: widget.book.content,
          onOpen: (hit, searchContext) => openLink(
            BookLink(
              block: source.block,
              start: source.offset,
              end: source.offset,
              document: source.document,
              href: '',
              kind: BookLinkKind.link,
              status: BookLinkStatus.resolved,
              target: hit.position,
            ),
            searchHit: hit,
            navigationContext: searchContext,
          ),
        ),
      ),
    );
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      unawaited(ReaderSystemUi.setImmersive(!chrome));
    }
  }

  Future<void> readingActions() async {
    double value = pageCount > 1 ? currentPage / (pageCount - 1) : 0;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          void run(VoidCallback action) {
            Navigator.pop(sheetContext);
            action();
          }

          final view = pagedKey.currentState;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('back-library'),
                        onPressed: () => run(leave),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(exitLabel),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭阅读操作',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      Tooltip(
                        message: '目录',
                        child: TextButton.icon(
                          onPressed: () => run(contents),
                          icon: const Icon(Icons.format_list_bulleted),
                          label: const Text('目录'),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('reader-settings'),
                        onPressed: () => run(settings),
                        icon: const Icon(Icons.text_fields),
                        label: const Text('阅读设置'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('reader-bookmarks'),
                        onPressed: () => run(bookmarks),
                        icon: const Icon(Icons.bookmarks_outlined),
                        label: const Text('书签'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('reader-search'),
                        onPressed: () => run(searchBook),
                        icon: const Icon(Icons.search),
                        label: const Text('书内搜索'),
                      ),
                      if (!isLinkView && chapterOrigin != null)
                        TextButton.icon(
                          key: const ValueKey('return-chapter'),
                          onPressed: () => run(returnFromChapter),
                          icon: const Icon(Icons.undo),
                          label: const Text('返回目录跳转前'),
                        ),
                      if (isLinkView && !isSourceRoot) ...[
                        TextButton.icon(
                          key: const ValueKey('back-link'),
                          onPressed: () =>
                              run(() => Navigator.pop(this.context)),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('返回上一处'),
                        ),
                        TextButton(
                          key: const ValueKey('close-links'),
                          onPressed: () => run(
                            () => Navigator.of(this.context)
                                .popUntil((r) => !isTemporaryReadingRoute(r)),
                          ),
                          child: Text(originLabel),
                        ),
                      ],
                      if (view?.hasOverflow == true)
                        Tooltip(
                          message: '展开本页内容',
                          child: TextButton(
                            onPressed: () => run(view!.expandPage),
                            child: const Text('展开本页内容'),
                          ),
                        ),
                    ],
                  ),
                  if (paged && view?.layout != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          key: const ValueKey('previous-page'),
                          onPressed: view!.spread > 0
                              ? () => run(() => view.turn(-1))
                              : null,
                          child: const Text('上一页'),
                        ),
                        TextButton(
                          key: const ValueKey('next-page'),
                          onPressed: view.spread + 1 < view.spreadCount
                              ? () => run(() => view.turn(1))
                              : null,
                          child: const Text('下一页'),
                        ),
                      ],
                    ),
                    Slider(
                      key: const ValueKey('reading-progress'),
                      value: value.clamp(0, 1),
                      onChanged: (v) {
                        update(() => value = v);
                        view.jumpPage((v * (pageCount - 1)).round());
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void jump(int index) {
    dismiss();
    if (paged) {
      pagedKey.currentState?.jump(
        BookPosition(
          index.clamp(0, blocks.length - 1),
          document: widget.linkTarget?.document,
        ),
      );
      return;
    }
    if (controller.isAttached) {
      final target = index.clamp(0, blocks.length - 1);
      controller.jumpTo(index: target);
      setState(() => position = target);
      precise = PageAnchor(
        BookPosition(position, document: widget.linkTarget?.document),
      );
      saveTimer?.cancel();
      savePosition();
    }
  }

  Future<void> lookup(
    int index,
    WordRange range,
    Rect globalRect, {
    String? cell,
  }) async {
    // A tap outside an open gloss only dismisses it. A subsequent tap can
    // select a new word, without changing scroll or page-turn gestures.
    if (selected != null) {
      dismiss();
      return;
    }
    final box = stackKey.currentContext!.findRenderObject()! as RenderBox;
    final generation = ++lookupGeneration;
    final history = ref.read(lookupHistoryProvider);
    final historyGeneration = history.generation;
    lookupViewport = viewportGeometry;
    setState(() {
      selectedParagraph = index;
      selectedCell = cell;
      selected = range;
      anchor = globalRect.shift(-box.localToGlobal(Offset.zero));
      entry = null;
      expanded = false;
      lookupMessage = '正在打开离线词典…';
    });
    try {
      final dictionary = await ref.read(dictionaryProvider.future);
      final result = dictionary.lookup(range.text);
      if (mounted && generation == lookupGeneration) {
        setState(() {
          entry = result;
          lookupMessage = null;
        });
        unawaited(
          history
              .record(language.code, range.text, generation: historyGeneration)
              .catchError((Object _) {
                debugPrint('Lookup history could not be saved.');
              }),
        );
      }
    } catch (_) {
      if (mounted && generation == lookupGeneration) {
        setState(() => lookupMessage = '词典暂时无法打开，请返回书架后重试。');
      }
      ref.invalidate(dictionaryProvider);
    }
  }

  Future<void> copySentence(String text, int offset) async {
    await showSelectedText(language.sentenceAt(text, offset).text);
  }

  Future<void> showSelectedText(
    String sentence, {
    bool adjusted = false,
  }) async {
    dismiss();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SentenceSheet(
        sentence: sentence,
        adjusted: adjusted,
        onCopy: () {
          Clipboard.setData(ClipboardData(text: sentence));
          Navigator.pop(context);
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text(adjusted ? '已复制文字' : '已复制句子'),
              duration: const Duration(seconds: 2),
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            ),
          );
        },
      ),
    );
  }

  Future<void> settings() async {
    dismiss();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReaderSettings(
        orientationSetting: const ReadingOrientationSetting(),
        style: style,
        perBook: perBook,
        onChanged: (value) => changeStyle(value, perBook),
        onPerBook: (value) => changeStyle(style, value),
      ),
    );
  }

  void changeStyle(ReaderStyle value, bool onlyBook) {
    final index = position;
    final styleChanged = style.encode() != value.encode();
    setState(() {
      style = value;
      perBook = onlyBook;
    });
    if (widget.onStyleChanged != null) {
      widget.onStyleChanged!(value, onlyBook);
    } else {
      persistStyle();
    }
    if (styleChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !paged) jump(index);
      });
    }
  }

  void openChapter(int index) {
    if (widget.onChapter != null) {
      widget.onChapter!(index);
      return;
    }
    if (index < 0 || index >= widget.book.content.blocks.length) return;
    final token = ++chapterNavigation;
    Navigator.of(context).popUntil((route) => !isTemporaryReadingRoute(route));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != chapterNavigation) return;
      if (isSourceRoot) {
        openLink(
          BookLink(
            block: widget.linkTarget!.block,
            start: widget.linkTarget!.offset,
            end: widget.linkTarget!.offset,
            document: widget.linkTarget!.document,
            href: '',
            kind: BookLinkKind.link,
            status: BookLinkStatus.resolved,
            target: BookPosition(index),
          ),
        );
      } else {
        rememberChapterOrigin();
        jump(index);
      }
    });
  }

  void persistStyle() {
    final database = ref.read(databaseProvider),
        snapshot = style.encode(),
        onlyBook = perBook;
    enqueue(() async {
      await database.saveStyle(widget.book.id, onlyBook ? snapshot : null);
      if (!onlyBook) {
        await database.setSetting('readerStyle', snapshot);
        if (mounted) ref.invalidate(globalStyleProvider);
      }
    });
  }

  void contents() {
    dismiss();
    final chapters = widget.book.content.contents;
    final preceding =
        chapters
            .where(
              (c) => widget.linkTarget?.document == null && c.block <= position,
            )
            .toList()
          ..sort((a, b) => a.block.compareTo(b.block));
    final current = preceding.lastOrNull?.block;
    var chosen = false;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '目录',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: chapters.isEmpty
                  ? const Center(child: Text('未识别到章节，可用底部进度条跳转。'))
                  : ListView(
                      children: chapters
                          .map(
                            (c) => ListTile(
                              title: Padding(
                                padding: EdgeInsets.only(left: c.depth * 12.0),
                                child: Text(c.title),
                              ),
                              selected: c.block == current,
                              trailing: c.block == current
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onTap: () {
                                if (chosen) return;
                                chosen = true;
                                Navigator.pop(context);
                                openChapter(c.block);
                              },
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget paragraph(
    int index,
    String text,
    TextStyle textStyle, {
    String? cell,
    bool heading = false,
  }) => ReaderParagraph(
    sourceBlock: cell == null && blocks[index].image == null ? index : null,
    key: ValueKey(cell == null ? 'paragraph-$index' : 'cell-$index-$cell'),
    anchorKey:
        isLinkView &&
            widget.linkTarget!.block == index &&
            cell == widget.sourceCell
        ? targetTextKey
        : null,
    text: text,
    links: cell == null ? linksByBlock[index] ?? const [] : const [],
    onLink: openLink,
    language: language,
    style: heading
        ? textStyle.copyWith(
            fontSize: style.size * 1.35,
            fontWeight: FontWeight.w600,
            height: 1.3,
          )
        : textStyle,
    align: style.justify && !heading && cell == null
        ? TextAlign.justify
        : TextAlign.start,
    selection: selectedParagraph == index && selectedCell == cell
        ? selected
        : widget.searchHit?.position.block == index &&
              widget.searchHit?.cell == cell
        ? WordRange(
            widget.searchHit!.position.offset,
            widget.searchHit!.end,
            '', // Highlight uses source offsets; avoid copying an unbounded match.
          )
        : null,
    onWord: (word, rect) => lookup(index, word, rect, cell: cell),
    onBlank: toggleChrome,
    onSentence: (offset) => copySentence(text, offset),
    onSelectionStart: dismiss,
    onSelection: (range) => showSelectedText(range.text, adjusted: true),
  );

  bool openingImage = false;
  Future<void> openImage(Uint8List bytes, String description) async {
    if (selected != null) {
      dismiss();
      return;
    }
    if (openingImage || ModalRoute.of(context)?.isCurrent == false) return;
    openingImage = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ReaderImageViewer(
            bytes: bytes,
            description: description,
            palette: style.palette(MediaQuery.platformBrightnessOf(context)),
          ),
        ),
      );
    } finally {
      openingImage = false;
    }
  }

  Widget renderBlock(int index, TextStyle textStyle, Color ink) {
    final block = blocks[index];
    if (block.image case final path?) {
      return FutureBuilder<Uint8List?>(
        future: imageLoads.putIfAbsent(
          path,
          () => ref.read(databaseProvider).asset(widget.book.id, path),
        ),
        builder: (context, snapshot) => Column(
          children: [
            // Fixed viewport avoids shifting saved block positions on late image loads.
            SizedBox(
              height: 260,
              width: double.infinity,
              child: snapshot.data == null
                  ? Center(
                      child: Text(
                        snapshot.connectionState == ConnectionState.done
                            ? '图片无法读取'
                            : '正在读取图片…',
                        style: textStyle,
                      ),
                    )
                  : Semantics(
                      button: true,
                      label: '放大图片',
                      child: GestureDetector(
                        key: ValueKey('reader-image-$index'),
                        onTap: () => openImage(snapshot.data!, block.text),
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          cacheWidth: 1400,
                          semanticLabel: block.text,
                          errorBuilder: (_, error, stack) =>
                              Center(child: Text('图片无法显示', style: textStyle)),
                        ),
                      ),
                    ),
            ),
            if (block.text.isNotEmpty && block.text != '图片')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: paragraph(
                  index,
                  block.text,
                  textStyle.copyWith(fontSize: style.size * .8),
                  cell: 'caption',
                ),
              ),
          ],
        ),
      );
    }
    if (block.rows case final rows?) {
      final columns = rows.fold<int>(0, (n, row) => math.max(n, row.length));
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(160),
          border: TableBorder.all(color: ink.withValues(alpha: .25)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: r == 0 && block.tableHeader
                    ? BoxDecoration(color: ink.withValues(alpha: .07))
                    : null,
                children: [
                  for (var c = 0; c < columns; c++)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: paragraph(
                        index,
                        c < rows[r].length ? rows[r][c] : '',
                        r == 0 && block.tableHeader
                            ? textStyle.copyWith(fontWeight: FontWeight.w700)
                            : textStyle,
                        cell: '$r-$c',
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    }
    return paragraph(index, block.text, textStyle, heading: block.heading);
  }

  Future<void> leave() async {
    if (widget.onLeave != null) {
      widget.onLeave!();
      return;
    }
    if (saving) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => saving = true);
    saveTimer?.cancel();
    savePosition();
    await writes;
    if (!mounted) return;
    ref.invalidate(booksProvider);
    Navigator.of(context).popUntil((route) => !isTemporaryReadingRoute(route));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ReadingOrientationScope(
    child: ReadingSelectionScope(
      blocks: blocks,
      onSelected: (text) => showSelectedText(text, adjusted: true),
      child: buildReader(context),
    ),
  );

  Widget buildReader(BuildContext context) {
    syncMode(MediaQuery.sizeOf(context));
    final palette = style.palette(MediaQuery.platformBrightnessOf(context));
    final progress = paged && pageCount > 0
        ? (pageCount == 1 ? 1.0 : currentPage / (pageCount - 1))
        : blocks.length <= 1
        ? 1.0
        : position / (blocks.length - 1);
    final textStyle = TextStyle(
      fontFamily: style.family(Theme.of(context).platform),
      fontFamilyFallback: const ['Literata'],
      fontSize: style.size,
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing * style.size,
      color: palette.ink,
    );
    return PopScope(
      canPop: isLinkView || saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: palette.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: palette.background,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                key: stackKey,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selected != null ? dismiss : null,
                    ),
                  ),
                  if (paged)
                    Positioned.fill(
                      // SafeArea already handles cutouts and system gestures.
                      // Reading controls live in a sheet, not reserved bands.
                      top: MediaQuery.sizeOf(context).shortestSide >= 600
                          ? 32
                          : 20,
                      bottom: 0,
                      child: PagedReader(
                        onImage: openImage,
                        cache: ref.watch(paginationCacheProvider),
                        cacheBookId: widget.book.id,
                        cacheContent: widget.book.contentSnapshot,
                        sourceAnchor: widget.sourceAnchor ?? widget.linkAnchor,
                        sourceCell: widget.sourceCell,
                        sourceOffset: widget.linkTarget?.offset ?? 0,
                        key: pagedKey,
                        content: widget.book.content,
                        document: widget.linkTarget?.document,
                        style: style,
                        compact: compactReader,
                        initialAnchor: precise,
                        loadImage: (path) => imageLoads.putIfAbsent(
                          path,
                          () => ref
                              .read(databaseProvider)
                              .asset(widget.book.id, path),
                        ),
                        onPosition: pagedPosition,
                        onWord: (index, word, rect, cell) =>
                            lookup(index, word, rect, cell: cell),
                        onSentence: copySentence,
                        onSelectionStart: dismiss,
                        onSelection: (range) =>
                            showSelectedText(range.text, adjusted: true),
                        onLink: openLink,
                        onBlank: toggleChrome,
                        onTurn: dismiss,
                        onScrollFallback: scrollFallback,
                        selectedBlock: selected != null
                            ? selectedParagraph
                            : widget.searchHit?.position.block,
                        selectedCell: selected != null
                            ? selectedCell
                            : widget.searchHit?.cell,
                        selection:
                            selected ??
                            (widget.searchHit == null
                                ? null
                                : WordRange(
                                    widget.searchHit!.position.offset,
                                    widget.searchHit!.end,
                                    '', // Highlight uses source offsets; avoid copying an unbounded match.
                                  )),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: toggleChrome,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null) {
                              dismiss();
                            }
                            return false;
                          },
                          child: ScrollablePositionedList.builder(
                            key: const ValueKey('reader-text'),
                            itemScrollController: controller,
                            scrollOffsetController: offsetController,
                            itemPositionsListener: positions,
                            initialScrollIndex: position,
                            initialAlignment: isLinkView
                                ? (76 / constraints.maxHeight).clamp(0, 1)
                                : 0,
                            padding: EdgeInsets.fromLTRB(
                              math.max(
                                style.margin,
                                (constraints.maxWidth - 680) / 2,
                              ),
                              compactReader ? 32 : 76,
                              math.max(
                                style.margin,
                                (constraints.maxWidth - 680) / 2,
                              ),
                              compactReader ? 40 : 140,
                            ),
                            itemCount: blocks.length,
                            itemBuilder: (context, index) => Padding(
                              padding: EdgeInsets.only(
                                bottom: math.max(
                                  6,
                                  style.paragraphSpacing * style.size,
                                ),
                                top: blocks[index].heading ? 16 : 0,
                              ),
                              child: renderBlock(index, textStyle, palette.ink),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (compactReader && !paged)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 40,
                      child: ColoredBox(
                        color: palette.background,
                        child: TextButton(
                          onPressed: readingActions,
                          child: Text(
                            '阅读操作',
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.ink.withValues(alpha: .45),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (chrome && !compactReader)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ColoredBox(
                        color: palette.background.withValues(alpha: .97),
                        child: SizedBox(
                          height: 60,
                          child: Row(
                            children: [
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 48,
                                ),
                                padding: EdgeInsets.zero,
                                key: const ValueKey('back-library'),
                                tooltip: exitLabel,
                                onPressed: leave,
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 20,
                                  color: palette.ink,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  isLinkView
                                      ? widget.linkTitle
                                      : widget.book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: palette.ink,
                                  ),
                                ),
                              ),
                              if (!isLinkView && chapterOrigin != null)
                                IconButton(
                                  key: const ValueKey('return-chapter'),
                                  tooltip: '返回目录跳转前',
                                  onPressed: returnFromChapter,
                                  icon: Icon(Icons.undo, color: palette.ink),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 48,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              if (isLinkView && !isSourceRoot)
                                IconButton(
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 48,
                                  ),
                                  padding: EdgeInsets.zero,
                                  key: const ValueKey('back-link'),
                                  tooltip: '返回上一处',
                                  onPressed: () => Navigator.pop(context),
                                  icon: Icon(
                                    Icons.arrow_back,
                                    color: palette.ink,
                                  ),
                                ),
                              if (isLinkView && !isSourceRoot)
                                IconButton(
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 48,
                                  ),
                                  padding: EdgeInsets.zero,
                                  key: const ValueKey('close-links'),
                                  tooltip: originLabel,
                                  onPressed: () => Navigator.of(context)
                                      .popUntil(
                                        (route) =>
                                            !isTemporaryReadingRoute(route),
                                      ),
                                  icon: Icon(Icons.close, color: palette.ink),
                                ),
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 48,
                                ),
                                padding: EdgeInsets.zero,
                                key: const ValueKey('reader-bookmarks'),
                                tooltip: '书签',
                                onPressed: bookmarks,
                                icon: Icon(
                                  Icons.bookmarks_outlined,
                                  color: palette.ink,
                                  size: 22,
                                ),
                              ),
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 48,
                                ),
                                padding: EdgeInsets.zero,
                                key: const ValueKey('reader-search'),
                                tooltip: '书内搜索',
                                onPressed: searchBook,
                                icon: Icon(
                                  Icons.search,
                                  color: palette.ink,
                                  size: 22,
                                ),
                              ),
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 48,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: '目录',
                                onPressed: contents,
                                icon: Icon(
                                  Icons.format_list_bulleted,
                                  color: palette.ink,
                                  size: 22,
                                ),
                              ),
                              IconButton(
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 48,
                                ),
                                padding: EdgeInsets.zero,
                                key: const ValueKey('reader-settings'),
                                tooltip: '阅读设置',
                                onPressed: settings,
                                icon: Text(
                                  'Aa',
                                  style: TextStyle(
                                    fontFamily: 'Literata',
                                    fontSize: 22,
                                    color: palette.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (chrome && !compactReader)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ColoredBox(
                        color: palette.background.withValues(alpha: .97),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                          child: Column(
                            children: [
                              Slider(
                                key: const ValueKey('reading-progress'),
                                value: progress,
                                onChanged: (v) => paged
                                    ? pagedKey.currentState?.jumpPage(
                                        (v * (pageCount - 1)).round(),
                                      )
                                    : jump((v * (blocks.length - 1)).round()),
                                activeColor: palette.ink,
                                inactiveColor: palette.ink.withValues(
                                  alpha: .15,
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    paged
                                        ? (pagedReady
                                              ? '${currentPage + 1} / $pageCount 页'
                                              : '正在分页…')
                                        : '${position + 1} / ${blocks.length} 段',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: palette.ink.withValues(alpha: .5),
                                    ),
                                  ),
                                  Text(
                                    '${(progress * 100).round()}%',
                                    key: const ValueKey('progress-label'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (anchor != null && selected != null) ...[
                    Positioned.fill(
                      child: CustomSingleChildLayout(
                        delegate: BubbleLayout(
                          anchor!,
                          safeTop: chrome && !compactReader ? 68 : 12,
                          safeBottom: chrome && !compactReader ? 100 : 12,
                          preferredHeight:
                              expanded || style.tier == GlossTier.full
                              ? 360
                              : style.tier == GlossTier.brief ||
                                    (entry == null && lookupMessage == null)
                              ? 180
                              : 70,
                        ),
                        child: WordBubble(
                          key: ValueKey(lookupGeneration),
                          word: selected!.text,
                          entry: entry,
                          message: lookupMessage,
                          translateMissing:
                              lookupMessage == null && entry == null,
                          style: style,
                          palette: palette,
                          expanded: expanded,
                          onExpand: () => setState(() => expanded = true),
                          onClose: dismiss,
                          actionBuilder: entry == null
                              ? null
                              : (language) {
                                  final draft = VocabularyDraft.capture(
                                    book: widget.book,
                                    position: BookPosition(
                                      selectedParagraph!,
                                      document: widget.linkTarget?.document,
                                    ),
                                    word: selected!,
                                    entry: entry!,
                                    english: language == GlossLanguage.enEn,
                                    cell: selectedCell,
                                  );
                                  return SaveVocabularyButton(
                                    key: ValueKey(
                                      '$lookupGeneration:${draft.dictId}',
                                    ),
                                    draft: draft,
                                    color: palette.ink,
                                  );
                                },
                        ),
                      ),
                    ),
                    Positioned(
                      left: (anchor!.center.dx - 7).clamp(
                        12,
                        constraints.maxWidth - 26,
                      ),
                      top:
                          BubbleLayout(
                            anchor!,
                            safeTop: chrome && !compactReader ? 68 : 12,
                            safeBottom: chrome && !compactReader ? 100 : 12,
                            preferredHeight:
                                expanded || style.tier == GlossTier.full
                                ? 360
                                : style.tier == GlossTier.brief ||
                                      (entry == null && lookupMessage == null)
                                ? 180
                                : 70,
                          ).above(constraints.biggest)
                          ? anchor!.top - 11
                          : anchor!.bottom + 1,
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: const Size(14, 10),
                          painter: BubbleArrow(
                            palette.surface,
                            !BubbleLayout(
                              anchor!,
                              safeTop: chrome && !compactReader ? 68 : 12,
                              safeBottom: chrome && !compactReader ? 100 : 12,
                              preferredHeight:
                                  expanded || style.tier == GlossTier.full
                                  ? 360
                                  : style.tier == GlossTier.brief ||
                                        (entry == null && lookupMessage == null)
                                  ? 180
                                  : 70,
                            ).above(constraints.biggest),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

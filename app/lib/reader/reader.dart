import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../book/book.dart';
import '../core/providers.dart';
import '../core/reader_system_ui.dart';
import '../dict/dictionary.dart';
import '../text/language.dart';
import 'bubble.dart';
import 'settings.dart';
import 'style.dart';

typedef _ViewportGeometry = ({
  Size size,
  double pixelRatio,
  EdgeInsets padding,
  EdgeInsets insets,
});

class ReaderPage extends ConsumerStatefulWidget {
  final Book book;
  final ReaderStyle defaultStyle;
  const ReaderPage({super.key, required this.book, required this.defaultStyle});
  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  final controller = ItemScrollController();
  final positions = ItemPositionsListener.create();
  final stackKey = GlobalKey();
  final language = EnglishLanguage();
  late ReaderStyle style = ReaderStyle.decode(
    widget.book.style ?? widget.defaultStyle.encode(),
  );
  late bool perBook = widget.book.style != null;
  late int position = widget.book.position.clamp(
    0,
    widget.book.content.blocks.length - 1,
  );
  bool chrome = true, expanded = false, saving = false;
  int? selectedParagraph;
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
    positions.itemPositions.addListener(positionChanged);
    unawaited(WakelockPlus.enable());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) savePosition();
    });
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
    final current = position;
    final database = ref.read(databaseProvider);
    enqueue(() => database.savePosition(widget.book.id, current));
  }

  void positionChanged() {
    final visible =
        positions.itemPositions.value
            .where((p) => p.itemTrailingEdge > .02 && p.itemLeadingEdge < 1)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty || visible.first.index == position || !mounted) return;
    setState(() => position = visible.first.index);
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
    unawaited(WakelockPlus.disable());
    unawaited(ReaderSystemUi.setImmersive(false));
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
    setState(() => chrome = !chrome);
    unawaited(ReaderSystemUi.setImmersive(!chrome));
  }

  void jump(int index) {
    dismiss();
    if (controller.isAttached) {
      final target = index.clamp(0, widget.book.content.blocks.length - 1);
      controller.jumpTo(index: target);
      setState(() => position = target);
      saveTimer?.cancel();
      savePosition();
    }
  }

  Future<void> lookup(int index, WordRange range, Rect globalRect) async {
    final box = stackKey.currentContext!.findRenderObject()! as RenderBox;
    final generation = ++lookupGeneration;
    lookupViewport = viewportGeometry;
    setState(() {
      selectedParagraph = index;
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
      }
    } catch (_) {
      if (mounted && generation == lookupGeneration) {
        setState(() => lookupMessage = '词典暂时无法打开，请返回书架后重试。');
      }
      ref.invalidate(dictionaryProvider);
    }
  }

  Future<void> copySentence(String text, int offset) async {
    dismiss();
    final sentence = language.sentenceAt(text, offset).text;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选中的句子',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .4,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    sentence,
                    style: const TextStyle(fontSize: 18, height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sentence));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制句子'),
                      duration: Duration(seconds: 2),
                      margin: EdgeInsets.fromLTRB(20, 0, 20, 120),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 17),
                label: const Text('复制句子'),
              ),
            ],
          ),
        ),
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
        style: style,
        perBook: perBook,
        onChanged: (value) {
          final index = position;
          setState(() => style = value);
          persistStyle();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) jump(index);
          });
        },
        onPerBook: (value) {
          setState(() => perBook = value);
          persistStyle();
        },
      ),
    );
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
    final chapters = widget.book.content.blocks.indexed
        .where((b) => b.$2.heading)
        .toList();
    final current = chapters.where((b) => b.$1 <= position).lastOrNull?.$1;
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
                              title: Text(c.$2.text),
                              selected: c.$1 == current,
                              trailing: c.$1 == current
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onTap: () {
                                Navigator.pop(context);
                                jump(c.$1);
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

  Future<void> leave() async {
    if (saving) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => saving = true);
    saveTimer?.cancel();
    savePosition();
    await writes;
    if (!mounted) return;
    ref.invalidate(booksProvider);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = style.palette(MediaQuery.platformBrightnessOf(context));
    final blocks = widget.book.content.blocks;
    final progress = blocks.length <= 1 ? 1.0 : position / (blocks.length - 1);
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
      canPop: saving,
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
                          itemPositionsListener: positions,
                          initialScrollIndex: position,
                          padding: EdgeInsets.fromLTRB(
                            math.max(
                              style.margin,
                              (constraints.maxWidth - 680) / 2,
                            ),
                            76,
                            math.max(
                              style.margin,
                              (constraints.maxWidth - 680) / 2,
                            ),
                            140,
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
                            child: ReaderParagraph(
                              key: ValueKey('paragraph-$index'),
                              text: blocks[index].text,
                              language: language,
                              style: blocks[index].heading
                                  ? textStyle.copyWith(
                                      fontSize: style.size * 1.35,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    )
                                  : textStyle,
                              align: style.justify && !blocks[index].heading
                                  ? TextAlign.justify
                                  : TextAlign.start,
                              selection: selectedParagraph == index
                                  ? selected
                                  : null,
                              onWord: (word, rect) => lookup(index, word, rect),
                              onBlank: toggleChrome,
                              onSentence: (offset) =>
                                  copySentence(blocks[index].text, offset),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (chrome)
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
                                key: const ValueKey('back-library'),
                                tooltip: '返回书架',
                                onPressed: leave,
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 20,
                                  color: palette.ink,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  widget.book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: palette.ink,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '目录',
                                onPressed: contents,
                                icon: Icon(
                                  Icons.format_list_bulleted,
                                  color: palette.ink,
                                  size: 22,
                                ),
                              ),
                              IconButton(
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
                  if (chrome)
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
                                onChanged: (v) =>
                                    jump((v * (blocks.length - 1)).round()),
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
                                    '${position + 1} / ${blocks.length} 段',
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
                          safeTop: chrome ? 68 : 12,
                          safeBottom: chrome ? 100 : 12,
                          preferredHeight:
                              expanded || style.tier == GlossTier.full
                              ? 360
                              : style.tier == GlossTier.brief
                              ? 180
                              : 70,
                        ),
                        child: WordBubble(
                          word: selected!.text,
                          entry: entry,
                          message: lookupMessage,
                          style: style,
                          palette: palette,
                          expanded: expanded,
                          onExpand: () => setState(() => expanded = true),
                          onClose: dismiss,
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
                            safeTop: chrome ? 68 : 12,
                            safeBottom: chrome ? 100 : 12,
                            preferredHeight:
                                expanded || style.tier == GlossTier.full
                                ? 360
                                : style.tier == GlossTier.brief
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
                              safeTop: chrome ? 68 : 12,
                              safeBottom: chrome ? 100 : 12,
                              preferredHeight:
                                  expanded || style.tier == GlossTier.full
                                  ? 360
                                  : style.tier == GlossTier.brief
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

class ReaderParagraph extends StatefulWidget {
  final String text;
  final LanguageSupport language;
  final TextStyle style;
  final TextAlign align;
  final WordRange? selection;
  final void Function(WordRange, Rect) onWord;
  final ValueChanged<int> onSentence;
  final VoidCallback onBlank;
  const ReaderParagraph({
    super.key,
    required this.text,
    required this.language,
    required this.style,
    required this.align,
    required this.selection,
    required this.onWord,
    required this.onSentence,
    required this.onBlank,
  });
  @override
  State<ReaderParagraph> createState() => _ReaderParagraphState();
}

class _ReaderParagraphState extends State<ReaderParagraph> {
  final textKey = GlobalKey();
  int? sentenceOffset;
  RenderParagraph get paragraph =>
      textKey.currentContext!.findRenderObject()! as RenderParagraph;
  void tap(Offset global) {
    final render = paragraph, local = paragraph.globalToLocal(global);
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
    final range = widget.selection;
    final span = range == null
        ? TextSpan(text: widget.text, style: widget.style)
        : TextSpan(
            style: widget.style,
            children: [
              TextSpan(text: widget.text.substring(0, range.start)),
              TextSpan(
                text: widget.text.substring(range.start, range.end),
                style: const TextStyle(backgroundColor: Color(0x55DDBA73)),
              ),
              TextSpan(text: widget.text.substring(range.end)),
            ],
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => tap(details.globalPosition),
      // Present the modal after release. Pushing a route while the press is
      // active cancels the reader's pointer sequence on native platforms.
      onLongPressStart: (details) {
        sentenceOffset = paragraph
            .getPositionForOffset(
              paragraph.globalToLocal(details.globalPosition),
            )
            .offset;
      },
      onLongPressEnd: (_) {
        final offset = sentenceOffset;
        sentenceOffset = null;
        if (offset != null) widget.onSentence(offset);
      },
      onLongPressCancel: () => sentenceOffset = null,
      child: RichText(
        key: textKey,
        text: span,
        textAlign: widget.align,
        textScaler: MediaQuery.textScalerOf(context),
      ),
    );
  }
}

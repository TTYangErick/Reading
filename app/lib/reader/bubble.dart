import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dict/dictionary.dart';
import '../translate/translation_content.dart';
import 'style.dart';

/// Prefer above the word when there is enough room, otherwise use the larger side.
/// Its content scrolls when necessary, so the current line stays uncovered.
class BubbleLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final double safeTop, safeBottom, preferredHeight;
  const BubbleLayout(
    this.anchor, {
    this.safeTop = 12,
    this.safeBottom = 12,
    this.preferredHeight = 70,
  });
  bool above(Size size) =>
      anchor.top - safeTop - 10 >= preferredHeight ||
      anchor.top - safeTop >= size.height - safeBottom - anchor.bottom;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final available = above(size)
        ? anchor.top - safeTop - 10
        : size.height - safeBottom - anchor.bottom - 10;
    return BoxConstraints(
      maxWidth: math.min(380, math.max(0, size.width - 24)),
      maxHeight: math.max(0, math.min(420, available)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.center.dx - childSize.width / 2).clamp(
      12,
      math.max(12, size.width - childSize.width - 12),
    ),
    above(size) ? anchor.top - 10 - childSize.height : anchor.bottom + 10,
  );
  @override
  bool shouldRelayout(covariant BubbleLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.safeTop != safeTop ||
      oldDelegate.safeBottom != safeBottom ||
      oldDelegate.preferredHeight != preferredHeight;
}

class WordBubble extends StatefulWidget {
  final String word;
  final DictionaryEntry? entry;
  final String? message;
  final ReaderStyle style;
  final ReaderPalette palette;
  final bool expanded;
  final bool translateMissing;
  final VoidCallback onExpand, onClose;
  final Widget Function(GlossLanguage)? actionBuilder;
  const WordBubble({
    super.key,
    required this.word,
    required this.entry,
    this.message,
    this.translateMissing = false,
    required this.style,
    required this.palette,
    required this.expanded,
    required this.onExpand,
    required this.onClose,
    this.actionBuilder,
  });
  @override
  State<WordBubble> createState() => _WordBubbleState();
}

class _WordBubbleState extends State<WordBubble> {
  GlossLanguage? languageOverride;

  @override
  void didUpdateWidget(covariant WordBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word ||
        oldWidget.style.glossLanguage != widget.style.glossLanguage ||
        oldWidget.style.glossExpansion != widget.style.glossExpansion ||
        oldWidget.style.tier != widget.style.tier ||
        (oldWidget.expanded && !widget.expanded)) {
      languageOverride = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final entry = widget.entry;
    final message = widget.message;
    final style = widget.style;
    final palette = widget.palette;
    final expanded = widget.expanded;
    final onExpand = widget.onExpand;
    final onClose = widget.onClose;
    final full = expanded || style.tier == GlossTier.full;
    final legacy =
        style.glossLanguage == GlossLanguage.enZh &&
        style.glossExpansion == GlossExpansion.current;
    final crossLanguage =
        expanded &&
        style.tier != GlossTier.full &&
        style.glossExpansion == GlossExpansion.otherLanguage;
    final initialLanguage = crossLanguage
        ? (style.glossLanguage == GlossLanguage.enZh
              ? GlossLanguage.enEn
              : GlossLanguage.enZh)
        : style.glossLanguage;
    final language = languageOverride ?? initialLanguage;
    final english = !legacy && language == GlossLanguage.enEn;
    final hasEnglish = entry?.englishSenses.isNotEmpty ?? false;
    final hasChinese =
        (entry?.hasChineseSource ?? false) &&
        (entry!.meanings.isNotEmpty || entry.fullGloss.isNotEmpty);
    final missing = english ? !hasEnglish : !hasChinese;
    final hasOther = english ? hasChinese : hasEnglish;
    final otherLanguage = english ? GlossLanguage.enZh : GlossLanguage.enEn;
    final headword = english ? entry?.englishWord : entry?.word;
    final phonetic = english
        ? (entry?.englishPhonetic ?? '')
        : ((entry?.phonetic.isNotEmpty ?? false) ? '/${entry!.phonetic}/' : '');
    final meanings = entry?.meanings ?? [];
    final chineseText =
        message ??
        (entry == null
            ? '未收录这个词'
            : meanings.isEmpty
            ? '暂无中文释义 · 点此查看词条'
            : (style.tier == GlossTier.minimal
                      ? meanings.take(style.senses)
                      : meanings)
                  .join('；'));
    final String text;
    if (legacy) {
      text = chineseText;
    } else if (message != null) {
      text = message;
    } else if (missing) {
      final notice = english && entry?.englishNotice != null
          ? entry!.englishNotice!
          : entry == null
          ? '未收录这个词'
          : english
          ? '英英词典未收录这个词'
          : '英汉词典未收录这个词';
      text = !full && hasOther
          ? '$notice · 点此查看${english ? '英汉' : '英英'}'
          : notice;
    } else if (english) {
      text = entry!.englishSenses
          .take(style.tier == GlossTier.minimal ? style.senses : 24)
          .map((sense) => sense.gloss)
          .join('\n');
    } else {
      text = chineseText;
    }
    return Material(
      key: const ValueKey('word-bubble'),
      color: palette.surface,
      elevation: 7,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.ink.withValues(alpha: .1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: InkWell(
          onTap: full
              ? null
              : () {
                  if (!legacy && message == null && missing && hasOther) {
                    setState(() => languageOverride = otherLanguage);
                  }
                  onExpand();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: DefaultTextStyle(
              style: TextStyle(
                color: palette.ink,
                fontSize: style.bubbleSize,
                height: 1.45,
              ),
              child: widget.translateMissing && entry == null && message == null
                  ? SizedBox(
                      width: full ? 330 : 280,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (full)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    word,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontFamily: 'Literata',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭释义',
                                  onPressed: onClose,
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ],
                            ),
                          TranslationContent(
                            key: ValueKey(word),
                            text: word,
                            compact: !full,
                            machineFallback: true,
                            dark: palette.dark,
                            footer: full
                                ? TextButton.icon(
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(text: word),
                                    ),
                                    icon: const Icon(Icons.copy, size: 16),
                                    label: const Text('复制单词'),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    )
                  : full
                  ? SizedBox(
                      width: 330,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  word,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontFamily: 'Literata',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (widget.actionBuilder != null &&
                                  message == null &&
                                  !missing)
                                widget.actionBuilder!(language),
                              IconButton(
                                tooltip: '关闭释义',
                                onPressed: onClose,
                                icon: Icon(
                                  Icons.close,
                                  color: palette.ink,
                                  size: 19,
                                ),
                              ),
                            ],
                          ),
                          if (!legacy) ...[
                            SegmentedButton<GlossLanguage>(
                              key: const ValueKey('card-gloss-language'),
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: GlossLanguage.enZh,
                                  label: Text('英汉'),
                                ),
                                ButtonSegment(
                                  value: GlossLanguage.enEn,
                                  label: Text('英英'),
                                ),
                              ],
                              selected: {language},
                              onSelectionChanged: (v) =>
                                  setState(() => languageOverride = v.first),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (headword != null &&
                              headword.toLowerCase() != word.toLowerCase())
                            Text(
                              '原形 $headword',
                              style: const TextStyle(fontSize: 13),
                            ),
                          if (phonetic.isNotEmpty)
                            Text(
                              phonetic,
                              style: TextStyle(
                                color: palette.ink.withValues(alpha: .6),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (legacy || !english || missing || message != null)
                            Text(
                              (legacy || (!english && !missing)) &&
                                      entry?.fullGloss.isNotEmpty == true
                                  ? entry!.fullGloss
                                  : text,
                            ),
                          if (legacy &&
                              (entry?.definition.isNotEmpty ?? false) &&
                              (entry?.englishSenses.isEmpty ?? true)) ...[
                            const Divider(height: 28),
                            Text(
                              entry!.definition,
                              style: TextStyle(fontSize: style.bubbleSize - 1),
                            ),
                          ],
                          if ((legacy || english) && hasEnglish) ...[
                            const Divider(height: 28),
                            Text(
                              '英英 · Wiktionary',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.ink.withValues(alpha: .65),
                              ),
                            ),
                            if (legacy && entry!.englishWord != entry.word)
                              Text(
                                entry.englishWord!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (legacy && entry!.englishPhonetic.isNotEmpty)
                              Text(
                                entry.englishPhonetic,
                                style: const TextStyle(fontSize: 13),
                              ),
                            for (final sense in entry!.englishSenses.take(24))
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [
                                        sense.pos,
                                        ...sense.tags,
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: palette.ink.withValues(
                                          alpha: .65,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      sense.gloss,
                                      style: TextStyle(
                                        fontSize: style.bubbleSize - 1,
                                      ),
                                    ),
                                    for (final example in sense.examples.take(
                                      2,
                                    ))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          example,
                                          style: TextStyle(
                                            fontSize: style.bubbleSize - 2,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            if (entry.englishSenses.length > 24)
                              const Text(
                                '显示前 24 条释义，更多内容见来源词条。',
                                style: TextStyle(fontSize: 12),
                              ),
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Wiktionary 来源'),
                                  content: SelectableText(
                                    'Wiktionary contributors · CC BY-SA 4.0\n'
                                    '由 Kaikki / Wiktextract 提取；Reading 筛选英语释义、词形与用法示例。\n\n'
                                    'https://en.wiktionary.org/wiki/${Uri.encodeComponent(entry.englishWord!)}#English\n\n'
                                    'https://creativecommons.org/licenses/by-sa/4.0/',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('关闭'),
                                    ),
                                  ],
                                ),
                              ),
                              child: const Text('词条来源与许可'),
                            ),
                          ],
                          if (legacy && entry?.englishNotice != null)
                            Text(
                              entry!.englishNotice!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  !legacy
                                      ? (english
                                            ? 'Wiktionary · 离线'
                                            : 'ECDICT · 离线')
                                      : entry?.englishSenses.isNotEmpty == true
                                      ? entry!.hasChineseSource
                                            ? 'ECDICT + Wiktionary · 离线'
                                            : 'Wiktionary · 离线'
                                      : 'ECDICT · 离线',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.ink.withValues(alpha: .55),
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: word));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已复制单词'),
                                      duration: Duration(seconds: 2),
                                      margin: EdgeInsets.fromLTRB(
                                        20,
                                        0,
                                        20,
                                        120,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('复制'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Text(
                      !legacy &&
                              english &&
                              style.tier == GlossTier.brief &&
                              (entry?.englishSenses.length ?? 0) > 24
                          ? '$text\n显示前 24 条释义，展开可查看来源。'
                          : text,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class BubbleArrow extends CustomPainter {
  final Color color;
  final bool up;
  BubbleArrow(this.color, this.up);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, up ? size.height : 0)
      ..lineTo(size.width / 2, up ? 0 : size.height)
      ..lineTo(size.width, up ? size.height : 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant BubbleArrow oldDelegate) =>
      color != oldDelegate.color || up != oldDelegate.up;
}

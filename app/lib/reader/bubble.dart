import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dict/dictionary.dart';
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

class WordBubble extends StatelessWidget {
  final String word;
  final DictionaryEntry? entry;
  final String? message;
  final ReaderStyle style;
  final ReaderPalette palette;
  final bool expanded;
  final VoidCallback onExpand, onClose;
  const WordBubble({
    super.key,
    required this.word,
    required this.entry,
    this.message,
    required this.style,
    required this.palette,
    required this.expanded,
    required this.onExpand,
    required this.onClose,
  });
  @override
  Widget build(BuildContext context) {
    final full = expanded || style.tier == GlossTier.full;
    final meanings = entry?.meanings ?? [];
    final text =
        message ??
        (entry == null
            ? '未收录这个词'
            : meanings.isEmpty
            ? '暂无中文释义 · 点此查看词条'
            : (style.tier == GlossTier.minimal
                      ? meanings.take(style.senses)
                      : meanings)
                  .join('；'));
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
          onTap: full ? null : onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: DefaultTextStyle(
              style: TextStyle(
                color: palette.ink,
                fontSize: style.bubbleSize,
                height: 1.45,
              ),
              child: full
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
                          if (entry != null &&
                              entry!.word.toLowerCase() != word.toLowerCase())
                            Text(
                              '原形 ${entry!.word}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          if (entry?.phonetic.isNotEmpty ?? false)
                            Text(
                              '/${entry!.phonetic}/',
                              style: TextStyle(
                                color: palette.ink.withValues(alpha: .6),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            entry?.fullGloss.isNotEmpty == true
                                ? entry!.fullGloss
                                : text,
                          ),
                          if (entry?.definition.isNotEmpty ?? false) ...[
                            const Divider(height: 28),
                            Text(
                              entry!.definition,
                              style: TextStyle(fontSize: style.bubbleSize - 1),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'ECDICT · 离线',
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
                  : Text(text),
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

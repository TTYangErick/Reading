import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/reader/pagination.dart';
import 'package:reading_app/reader/style.dart';

// Oracle: the pre-optimization TextPainter range queries and visual metrics.
// It does not use the new logical-offset search or reproduce page packing.
void compareWithLegacy(
  String text, {
  required Size viewport,
  required ReaderStyle style,
  required TextDirection direction,
  required TextScaler scaler,
  required bool heading,
}) {
  final spanStyle = TextStyle(
    fontFamily: style.family(TargetPlatform.android),
    fontFamilyFallback: const ['Literata'],
    fontSize: heading ? style.size * 1.35 : style.size,
    fontWeight: heading
        ? FontWeight.w600
        : style.bold
        ? FontWeight.w700
        : FontWeight.w400,
    height: heading ? 1.3 : style.lineHeight,
    letterSpacing: style.letterSpacing * style.size,
  );
  final painter = TextPainter(
    text: TextSpan(text: text.isEmpty ? '\u200B' : text, style: spanStyle),
    textAlign: style.justify && !heading ? TextAlign.justify : TextAlign.start,
    textDirection: direction,
    textScaler: scaler,
    locale: const Locale('en'),
  );
  final margin = math.max(style.margin, (viewport.width - 680) / 2);
  try {
    painter.layout(
      minWidth: viewport.width - margin * 2,
      maxWidth: viewport.width - margin * 2,
    );
    final metrics = painter.computeLineMetrics();
    final clusters = [0];
    for (final cluster in text.characters) {
      clusters.add(clusters.last + cluster.length);
    }
    final bands = <(int, int)>[];
    final merged = <String>[];
    for (var i = 0; i < metrics.length; i++) {
      final m = metrics[i];
      final hit = painter.getPositionForOffset(
        Offset(m.left + m.width / 2, m.baseline - m.ascent / 2),
      );
      final range = painter.getLineBoundary(hit);
      expect(range.isValid, isTrue);
      final start = i == 0 ? 0 : clusters.lastWhere((c) => c <= range.start);
      if (bands.isEmpty || start > bands.last.$2) {
        bands.add((i, start));
      } else if (merged.length < 8) {
        merged.add(
          'line=$i width=${m.width} hit=$hit range=$range start=$start',
        );
      }
    }
    final actual = const TextPaginator().paginate(
      BookContent([BookBlock(text, heading: heading)]),
      viewport: viewport,
      platform: TargetPlatform.android,
      style: style,
      textDirection: direction,
      textScaler: scaler,
      locale: const Locale('en'),
    );
    final lines = actual.pages.expand((p) => p.lines).toList();
    final firstDifference = List.generate(
      math.min(lines.length, bands.length),
      (i) => i,
    ).where((i) => lines[i].start.offset != bands[i].$2).firstOrNull;
    expect(
      lines.length,
      bands.length,
      reason:
          '$direction length=${text.length} '
          'merged=$merged firstDifference=$firstDifference '
          'actual=${firstDifference == null ? null : lines[firstDifference].start.offset} '
          'legacy=${firstDifference == null ? null : bands[firstDifference]}',
    );
    for (var i = 0; i < bands.length; i++) {
      final (lineIndex, offset) = bands[i];
      final nextLine = i + 1 < bands.length ? bands[i + 1].$1 : metrics.length;
      final end = i + 1 < bands.length ? bands[i + 1].$2 : text.length;
      final metric = metrics[lineIndex];
      final top = lineIndex == 0 ? 0.0 : metric.baseline - metric.ascent;
      final bottom = nextLine == metrics.length
          ? painter.height
          : metrics[nextLine].baseline - metrics[nextLine].ascent;
      final line = lines[i];
      expect(line.start.offset, offset, reason: 'source band $i');
      expect(line.endOffset, end);
      expect(line.sourceTop, closeTo(top, .001));
      expect(line.height, closeTo(bottom - top, .001));
      expect(line.baseline - line.top, closeTo(metric.baseline - top, .001));
      expect(
        line.left,
        closeTo(
          metrics
              .sublist(lineIndex, nextLine)
              .map((m) => m.left)
              .reduce(math.min),
          .001,
        ),
      );
      expect(
        line.width,
        closeTo(
          metrics
              .sublist(lineIndex, nextLine)
              .map((m) => m.width)
              .reduce(math.max),
          .001,
        ),
      );
    }
    for (var i = 0; i < actual.pages.length; i++) {
      expect(actual.pageForPosition(actual.pages[i].start), i);
    }
  } finally {
    painter.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
  });
  final texts = <String>[
    List.filled(
      180,
      'A reader follows the river, considers every word, and continues reading. ',
    ).join(),
    List.filled(
      100,
      '  Leading and trailing spaces.   \r\n\n\t  \nAnother line.\n',
    ).join(),
    List.filled(
      80,
      'cafe\u0301 A\u0308 👨‍👩‍👧‍👦 🇨🇳 👍🏽 word\u00ADbreak\u200Bnext ',
    ).join(),
    List.filled(100, 'English שלום עולם العربية 123 words and more. ').join(),
    List.filled(
      80,
      '\u2067שלום 123\u2069 \u2066reading\u2069 \u200Fword\u200E\n',
    ).join(),
    List.filled(100, '漢字とかな mixed words, punctuation。中文測試 ').join(),
    '',
    ' \n\r\n\n',
    'single line with trailing spaces   ',
  ];
  for (final direction in TextDirection.values) {
    for (var variant = 0; variant < 3; variant++) {
      test(
        'line mapping equals legacy geometry: $direction variant $variant',
        () {
          for (final text in texts) {
            compareWithLegacy(
              text,
              viewport: switch (variant) {
                0 => const Size(390, 700),
                1 => const Size(160, 130),
                _ => const Size(575, 762),
              },
              style: variant == 1
                  ? const ReaderStyle(
                      font: 'Literata',
                      size: 22,
                      lineHeight: 1.15,
                      letterSpacing: .03,
                      bold: true,
                      justify: false,
                    )
                  : const ReaderStyle(font: 'Literata'),
              direction: direction,
              scaler: variant == 0
                  ? TextScaler.noScaling
                  : const TextScaler.linear(1.25),
              heading: variant == 2,
            );
          }
        },
      );
    }
  }
  test('near-limit and seeded mixed-control paragraphs match legacy', () {
    final random = math.Random(7919);
    const tokens = [
      'reader ',
      'words ',
      'שלום ',
      'العربية ',
      '123 ',
      '漢字 ',
      '\u2067RTL\u2069',
      '\u2066LTR\u2069',
      '\r\n',
      '\n\n',
      '\u2028',
      '\u2029',
      '\u00A0',
      '\t',
      'e\u0301',
      '👨‍👩‍👧‍👦',
      '🇨🇳',
      '  ',
    ];
    final samples = [
      List.filled(
        500,
        'A reader follows the river, considers every word, and continues reading. ',
      ).join(),
      for (var seedCase = 0; seedCase < 8; seedCase++)
        List.generate(350, (_) => tokens[random.nextInt(tokens.length)]).join(),
    ];
    for (final direction in TextDirection.values) {
      for (final text in samples) {
        compareWithLegacy(
          text,
          viewport: const Size(200, 300),
          style: const ReaderStyle(font: 'Literata'),
          direction: direction,
          scaler: TextScaler.noScaling,
          heading: false,
        );
      }
    }
  });
}

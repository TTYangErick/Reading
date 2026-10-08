// Run explicitly with flutter test; excluded from the regular test/ suite.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/pagination_cache.dart';
import 'package:reading_app/reader/style.dart';

const _style = ReaderStyle(font: 'Literata');
const _paragraph =
    'The reader walked beside the river and watched the light on the water. '
    'Every chapter offered a different view of the same familiar town. '
    'She paused to consider the meaning of a sentence, then continued reading. '
    'The evening train crossed the bridge while people waited quietly below. '
    'A small notebook held the words she hoped to remember the next morning. ';

typedef _Geometry = ({
  String name,
  Size size,
  int columns,
  TargetPlatform platform,
});
const _geometries = <_Geometry>[
  (
    name: 'phone',
    size: Size(390, 700),
    columns: 1,
    platform: TargetPlatform.android,
  ),
  (
    name: 'spread',
    size: Size(575, 762),
    columns: 2,
    platform: TargetPlatform.iOS,
  ),
];

BookContent _fixture({int chapters = 16, int group = 1, bool media = false}) {
  final blocks = <BookBlock>[];
  var image = 0;
  for (var chapter = 0; chapter < chapters; chapter++) {
    blocks.add(BookBlock('Chapter ${chapter + 1}', heading: true));
    for (var i = 0; i < 100; i += group) {
      blocks.add(BookBlock(List.filled(group, _paragraph).join('\n')));
      if (media && i % 20 == 0) {
        blocks.add(
          BookBlock('A view of the river.', image: 'image-${image++ % 8}.png'),
        );
        blocks.add(
          BookBlock(
            '',
            rows: [
              ['Place', 'Observation', 'Note'],
              for (var row = 0; row < 7; row++)
                [
                  'River $row',
                  'The light changes during the day.',
                  'Chapter $chapter',
                ],
            ],
            tableHeader: true,
          ),
        );
      }
    }
  }
  return BookContent(blocks);
}

Future<Uint8List> _image() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 480),
    Paint()..color = Colors.brown,
  );
  canvas.drawRect(
    const Rect.fromLTWH(50, 80, 400, 240),
    Paint()..color = Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 480);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Correctness checks are outside all timing windows, not performance gates.
void _checkLayout(BookContent content, BookPagination layout) {
  expect(layout.pages, isNotEmpty);
  final ends = List.filled(content.blocks.length, 0);
  final tableRows = <(int, int)>{};
  var images = 0;
  for (final page in layout.pages) {
    for (final fragment in page.fragments) {
      final position = fragment.anchor.position;
      if (fragment is PageTextFragment) {
        expect(position.offset, ends[position.block]);
        expect(
          fragment.endOffset,
          inInclusiveRange(
            position.offset,
            content.blocks[position.block].text.length,
          ),
        );
        ends[position.block] = fragment.endOffset;
      } else if (fragment is PageImageFragment) {
        expect(fragment.unavailable, isFalse);
        images++;
      } else if (fragment is PageTableRowFragment) {
        expect(tableRows.add((position.block, fragment.anchor.row!)), isTrue);
      }
    }
  }
  for (var i = 0; i < content.blocks.length; i++) {
    expect(ends[i], content.blocks[i].text.length);
    if (content.blocks[i].rows case final rows?) {
      expect(tableRows.where((r) => r.$1 == i).length, rows.length);
    }
  }
  expect(images, content.blocks.where((b) => b.image != null).length);
  for (final chapter in content.chapterStarts) {
    expect(
      layout.pages.any(
        (p) =>
            p.start.position.block == chapter && p.start.position.offset == 0,
      ),
      isTrue,
    );
  }
  for (final page in [0, layout.pages.length ~/ 2, layout.pages.length - 1]) {
    expect(layout.pageForAnchor(layout.pages[page].start), page);
  }
}

Future<Map<String, Object?>> _sample(
  String name,
  String source,
  Uint8List image,
  _Geometry geometry,
) async {
  final watch = Stopwatch()..start();
  final content = BookContent.decode(source);
  final decodeUs = watch.elapsedMicroseconds;
  var imageLoads = 0;
  watch.reset();
  final sizes = await loadPaginationImageSizes(content, (_) async {
    imageLoads++;
    return image;
  });
  final imageUs = watch.elapsedMicroseconds;

  // Real timers in a plain test, not FakeAsync/testWidgets. This measures host
  // scheduling gaps, including OS/GC activity; it does NOT measure UI frames.
  watch.reset();
  var lastTick = 0, maxGap = 0, ticks = 0;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 16), (_) {
    final now = watch.elapsedMicroseconds;
    maxGap = math.max(maxGap, now - lastTick);
    lastTick = now;
    ticks++;
  });
  late final BookPagination layout;
  try {
    layout = (await const BookPaginator().paginateAsync(
      content,
      viewport: geometry.size,
      platform: geometry.platform,
      style: _style,
      imageSizes: sizes,
    ))!;
  } finally {
    maxGap = math.max(maxGap, watch.elapsedMicroseconds - lastTick);
    heartbeat.cancel();
  }
  final paginateUs = watch.elapsedMicroseconds;
  watch.stop();

  final cache = PaginationCache();
  final key = (
    book: name,
    content: source,
    document: null,
    geometry: (
      size: geometry.size,
      columns: geometry.columns,
      style: _style.paginationKey,
      scaler: TextScaler.noScaling,
      platform: geometry.platform,
      direction: TextDirection.ltr,
      locale: null,
    ),
  );
  watch
    ..reset()
    ..start();
  cache.put(key, layout);
  final putUs = watch.elapsedMicroseconds;
  // Simulate an equal source string freshly read on reopening, outside timing.
  final reopenedKey = (
    book: key.book,
    content: String.fromCharCodes(source.codeUnits),
    document: key.document,
    geometry: key.geometry,
  );
  watch.reset();
  final cached = cache.get(reopenedKey);
  final getUs = watch.elapsedMicroseconds;
  watch.stop();

  _checkLayout(content, layout);
  expect(content.encode(), source);
  expect(sizes.length, imageLoads);
  if (cached != null) expect(cached, same(layout));
  return {
    'case': name,
    'geometry': geometry.name,
    'sourceUtf16': source.length,
    'blocks': content.blocks.length,
    'uniqueImages': imageLoads,
    'imageBytesEach': imageLoads == 0 ? 0 : image.length,
    'pages': layout.pages.length,
    'decodeUs': decodeUs,
    'imagePreflightUs': imageUs,
    'paginateUs': paginateUs,
    'heartbeatTicks': ticks,
    'maxHeartbeatGapUs': maxGap,
    'cachePutUs': putUs,
    'cacheGetUs': getUs,
    'cacheHit': cached != null,
    'cacheRetainedCost': cache.retainedCost,
  };
}

// Historical attribution probe using the pre-optimization TextPainter calls.
// Not a second paginator: the production API above remains the measured pipeline.
Map<String, Object> _paragraphProbe(String text, _Geometry geometry) {
  final width =
      geometry.size.width -
      2 * math.max(_style.margin, (geometry.size.width - 680) / 2);
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: _style.family(geometry.platform),
        fontFamilyFallback: const ['Literata'],
        fontSize: _style.size,
        fontWeight: FontWeight.w400,
        height: _style.lineHeight,
        letterSpacing: _style.letterSpacing * _style.size,
      ),
    ),
    textAlign: TextAlign.justify,
    textDirection: TextDirection.ltr,
  );
  try {
    final watch = Stopwatch()..start();
    painter.layout(minWidth: width, maxWidth: width);
    final layoutUs = watch.elapsedMicroseconds;
    watch.reset();
    final metrics = painter.computeLineMetrics();
    final metricsUs = watch.elapsedMicroseconds;
    watch.reset();
    final boundaries = [0];
    for (final grapheme in text.characters) {
      boundaries.add(boundaries.last + grapheme.length);
    }
    final graphemesUs = watch.elapsedMicroseconds;
    watch.reset();
    final hits = [
      for (final metric in metrics)
        painter.getPositionForOffset(
          Offset(
            metric.left + metric.width / 2,
            metric.baseline - metric.ascent / 2,
          ),
        ),
    ];
    final hitTestUs = watch.elapsedMicroseconds;
    watch.reset();
    final ranges = [for (final hit in hits) painter.getLineBoundary(hit)];
    final lineBoundaryUs = watch.elapsedMicroseconds;
    watch.reset();
    final starts = <int>[];
    for (final range in ranges) {
      var low = 0, high = boundaries.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (boundaries[middle] <= range.start) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      starts.add(boundaries[math.max(0, low - 1)]);
    }
    final clusterSearchUs = watch.elapsedMicroseconds;
    watch.stop();
    expect(starts.first, 0);
    expect(boundaries.last, text.length);
    return {
      'geometry': geometry.name,
      'textUtf16': text.length,
      'lines': metrics.length,
      'layoutUs': layoutUs,
      'metricsUs': metricsUs,
      'graphemesUs': graphemesUs,
      'hitTestUs': hitTestUs,
      'lineBoundaryUs': lineBoundaryUs,
      'clusterSearchUs': clusterSearchUs,
      'lineMappingUs': hitTestUs + lineBoundaryUs + clusterSearchUs,
    };
  } finally {
    painter.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('opt-in host pagination diagnostic; no timing thresholds', () async {
    const repeats = int.fromEnvironment('BENCHMARK_RUNS', defaultValue: 3);
    expect(repeats, inInclusiveRange(1, 10));
    final loader = FontLoader('Literata')
      ..addFont(rootBundle.load('assets/fonts/Literata.ttf'));
    await loader.load();
    final image = await _image();
    final fixtures = {
      'short': _fixture(chapters: 2).encode(),
      'novel': _fixture().encode(),
      'double-novel': _fixture(chapters: 32).encode(),
      'mixed': _fixture(media: true).encode(),
      // Same body words and chapters as novel, grouped into ~18K-unit blocks.
      'long-paragraphs': _fixture(group: 50).encode(),
      'near-limit-paragraphs': _fixture(group: 100).encode(),
    };
    // Explicit engine/JIT warmup; uncached here does not mean a cold app start.
    await _sample('warmup', fixtures['short']!, image, _geometries.first);
    final rows = <Map<String, Object?>>[];
    final cases = [
      for (final entry in fixtures.entries)
        for (final geometry in _geometries) (entry, geometry),
    ];
    for (var run = 0; run < repeats; run++) {
      // Rotate order to reduce a fixed order's engine warmup/thermal bias.
      for (var i = 0; i < cases.length; i++) {
        final (entry, geometry) = cases[(i + run) % cases.length];
        final row = await _sample(entry.key, entry.value, image, geometry);
        row['run'] = run + 1;
        rows.add(row);
        print('PAGINATION_SAMPLE ${jsonEncode(row)}');
      }
    }
    final probes = [
      for (var run = 1; run <= repeats; run++)
        for (final geometry in _geometries)
          for (final group in [1, 50, 100])
            {
              ..._paragraphProbe(
                List.filled(group, _paragraph).join('\n'),
                geometry,
              ),
              'run': run,
            },
    ];
    for (final probe in probes) {
      print('PARAGRAPH_PROBE ${jsonEncode(probe)}');
    }
    final report = {
      'schema': 1,
      'fixtureVersion': 1,
      'repeats': repeats,
      'runtime': Platform.version,
      'host': Platform.operatingSystem,
      'hostVersion': Platform.operatingSystemVersion,
      'font': 'bundled Literata',
      'style': _style.paginationKey,
      'viewports': [
        for (final g in _geometries)
          {
            'name': g.name,
            'width': g.size.width,
            'height': g.size.height,
            'columns': g.columns,
          },
      ],
      'scope': 'Flutter test/JIT host; preloaded PNG buffers; no SQLite/disk I/O, import, widgets, raster, route animation or frame-rate measurement. Warmed engine; each sample decodes and paginates without a layout cache, then checks the default cache independently.',
      'samples': rows,
      'paragraphProbes': probes,
    };
    final output = Platform.environment['READING_BENCHMARK_OUTPUT'];
    if (output != null && output.isNotEmpty) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/paragraph.dart';
import 'package:reading_app/reader/selection.dart';
import 'package:reading_app/reader/selection_paging.dart';
import 'package:reading_app/reader/style.dart';

import 'selection_test.dart' show begin, renderFor, highlight;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Literata',
    )..addFont(rootBundle.load('assets/fonts/Literata.ttf'))).load();
  });

  testWidgets('edge dwell, exit, direction, blocked boundary and stop', (
    t,
  ) async {
    final turns = <int>[];
    var allowed = true;
    final turner = SelectionPageTurner(
      viewport: () => const Rect.fromLTWH(10, 20, 1000, 700),
      onTurn: (d) async {
        turns.add(d);
        return allowed;
      },
    );
    addTearDown(turner.stop);
    turner.update(const Offset(1009, 100));
    await t.pump(const Duration(milliseconds: 599));
    expect(turns, isEmpty);
    turner.update(const Offset(500, 100)); // Whole-spread center/gutter.
    await t.pump(const Duration(seconds: 1));
    expect(turns, isEmpty);
    turner.update(const Offset(1009, 100));
    await t.pump(SelectionPageTurner.dwell);
    expect(turns, [1]);
    await t.pump(SelectionPageTurner.dwell);
    expect(turns, [1, 1]);
    turner.update(const Offset(11, 100));
    allowed = false;
    await t.pump(SelectionPageTurner.dwell);
    await t.pump(const Duration(seconds: 2));
    expect(turns, [1, 1, -1]); // No repeated requests at a blocked edge.
    turner.update(const Offset(11, 721)); // Footer/outside.
    await t.pump(const Duration(seconds: 1));
    expect(turns, hasLength(3));
    turner.update(const Offset(11, 100));
    turner.stop();
    await t.pump(const Duration(seconds: 1));
    expect(turns, hasLength(3));
  });

  testWidgets('pending turn cannot repeat after stop or overlap another turn', (
    t,
  ) async {
    final completion = Completer<bool>();
    var calls = 0;
    final turner = SelectionPageTurner(
      viewport: () => const Rect.fromLTWH(0, 0, 400, 600),
      onTurn: (_) {
        calls++;
        return completion.future;
      },
    );
    addTearDown(turner.stop);
    turner.update(const Offset(399, 50));
    await t.pump(SelectionPageTurner.dwell);
    await t.pump(const Duration(seconds: 3));
    expect(calls, 1);
    turner.stop();
    completion.complete(true);
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(calls, 1);
  });

  final text = List.filled(
    150,
    'Alpha café e\u0301 👩‍👩‍👦 gamma delta.',
  ).join('\n');
  final key = GlobalKey<PagedReaderState>();
  final results = <String>[], positions = <String>[];
  Future<void> mount(WidgetTester t, List<BookBlock> blocks, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    results.clear();
    positions.clear();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingSelectionScope(
            blocks: blocks,
            onSelected: results.add,
            child: PagedReader(
              key: key,
              content: BookContent(blocks),
              style: const ReaderStyle(font: 'Literata'),
              compact: true,
              initialAnchor: const PageAnchor(BookPosition(0)),
              loadImage: (_) async => null,
              onPosition: (a, _, _) => positions.add(a.encode()),
              onWord: (_, _, _, _) {},
              onSentence: (_, _) {},
              onLink: (_) {},
              onBlank: () {},
              onTurn: () {},
              onScrollFallback: () {},
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  ({Offset point, int start, int end}) word(
    WidgetTester t,
    int page, {
    bool last = false,
  }) {
    final finder = find.descendant(
      of: find.byKey(ValueKey('visible-page-$page')),
      matching: find.byType(ReaderParagraph),
    );
    final paragraph = t.widget<ReaderParagraph>(
      last ? finder.last : finder.first,
    );
    final render = renderFor(t, last ? finder.last : finder.first);
    final at = last
        ? paragraph.text.lastIndexOf('gamma', paragraph.visibleEnd! - 1)
        : paragraph.visibleStart;
    final range = render.getWordBoundary(TextPosition(offset: at));
    final from = range.start.clamp(
          paragraph.visibleStart,
          paragraph.visibleEnd!,
        ),
        to = range.end.clamp(paragraph.visibleStart, paragraph.visibleEnd!);
    final box = render
        .getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to))
        .first;
    return (
      point: render.localToGlobal(box.toRect().center),
      start: from,
      end: to,
    );
  }

  Future<void> dwell(WidgetTester t) async {
    await t.pump(SelectionPageTurner.dwell);
    await t.pump();
  }

  for (final wide in [false, true]) {
    for (final backwards in [false, true]) {
      testWidgets(
        'held pointer survives two ${backwards ? 'backward' : 'forward'} turns, ${wide ? 'spread' : 'phone'}, source and progress intact',
        (t) async {
          await mount(t, [
            BookBlock(text),
          ], wide ? const Size(1194, 834) : const Size(402, 800));
          final state = key.currentState!, columns = state.columns;
          expect(state.spreadCount, greaterThan(2));
          if (backwards) {
            state.jumpPage(2 * columns);
            await t.pumpAndSettle();
          } else if (wide) {
            state.jumpPage(1); // Preserve a focused right-page anchor too.
            await t.pumpAndSettle();
          }
          final original = state.page,
              base = state.spread * columns,
              anchor = state.anchor.encode(),
              saved = List.of(positions);
          final start = word(t, original);
          final press = await begin(t, start.point);
          final viewport = t.getRect(find.byKey(state.selectionViewportKey));
          final edge = Offset(
            backwards ? viewport.left + 2 : viewport.right - 2,
            viewport.top + 80,
          );
          await press.moveTo(edge);
          await t.pump(const Duration(milliseconds: 599));
          expect(state.page, original);
          await t.pump(const Duration(milliseconds: 1));
          await t.pump();
          expect(state.page, base + (backwards ? -columns : columns));
          await dwell(t);
          expect(state.page, base + (backwards ? -2 * columns : 2 * columns));
          // The originating paragraph is now gone; the scope must still receive moves/up.
          final target = word(
            t,
            backwards ? state.page : state.visiblePages.last,
            last: !backwards,
          );
          await press.moveTo(target.point);
          await t.pump();
          expect(find.byType(ReaderParagraph), findsWidgets);
          expect(
            highlight(renderFor(t, find.byType(ReaderParagraph).first)),
            isNotEmpty,
          );
          await press.up();
          await t.pumpAndSettle();
          expect(
            results.single,
            backwards
                ? text.substring(target.start, start.end)
                : text.substring(start.start, target.end),
          );
          expect(state.page, original);
          expect(state.anchor.encode(), anchor);
          expect(positions, saved);
          await t.pump(const Duration(seconds: 2));
          expect(state.page, original);
          expect(results, hasLength(1));
        },
      );
    }
  }

  testWidgets(
    'gutter/footer/edge exit cancel dwell; pointer cancel restores original page',
    (t) async {
      await mount(t, [BookBlock(text)], const Size(1194, 834));
      final state = key.currentState!, start = word(t, 0);
      final press = await begin(t, start.point);
      final rect = t.getRect(find.byKey(state.selectionViewportKey));
      await press.moveTo(Offset(rect.right - 2, rect.top + 80));
      await t.pump(const Duration(milliseconds: 400));
      await press.moveTo(Offset(rect.center.dx, rect.top + 80));
      await dwell(t);
      expect(state.page, 0);
      await press.moveTo(Offset(rect.right - 2, rect.bottom + 10));
      await dwell(t);
      expect(state.page, 0);
      await press.moveTo(Offset(rect.right - 2, rect.top + 80));
      await dwell(t);
      expect(state.page, 2);
      await press.cancel();
      await t.pumpAndSettle();
      expect(state.page, 0);
      expect(results, isEmpty);
      await dwell(t);
      expect(state.page, 0);
    },
  );

  for (final media in [
    const BookBlock('Picture caption', image: 'missing.png'),
    const BookBlock(
      '',
      rows: [
        ['Cell'],
      ],
    ),
  ]) {
    testWidgets(
      'automatic selection cannot cross ${media.image != null ? 'image' : 'table'}',
      (t) async {
        await mount(t, [
          BookBlock(text),
          media,
          BookBlock(text),
        ], const Size(402, 800));
        final state = key.currentState!;
        final last = state.layout!.pageForPosition(
          BookPosition(0, offset: text.length - 2),
        )!;
        state.jumpPage(last);
        await t.pumpAndSettle();
        final original = state.page, start = word(t, original);
        final press = await begin(t, start.point);
        final rect = t.getRect(find.byKey(state.selectionViewportKey));
        await press.moveTo(Offset(rect.right - 2, rect.top + 80));
        await dwell(t);
        await dwell(t);
        expect(state.page, original);
        await press.up();
        await t.pumpAndSettle();
        expect(
          results.every(
            (value) =>
                !value.contains('Picture caption') && !value.contains('Cell'),
          ),
          isTrue,
        );
      },
    );
  }

  testWidgets(
    'stationary press does not turn; direction can reverse in the same gesture',
    (t) async {
      await mount(t, [BookBlock(text)], const Size(402, 800));
      final state = key.currentState!;
      var start = word(t, 0), press = await begin(t, word(t, 0).point);
      await t.pump(const Duration(seconds: 2));
      expect(state.page, 0);
      await press.up();
      await t.pumpAndSettle();
      expect(results, isEmpty);
      state.jumpPage(1);
      await t.pumpAndSettle();
      start = word(t, 1);
      press = await begin(t, start.point);
      final rect = t.getRect(find.byKey(state.selectionViewportKey));
      await press.moveTo(Offset(rect.left + 2, rect.top + 80));
      await dwell(t);
      expect(state.page, 0);
      await press.moveTo(Offset(rect.right - 2, rect.top + 80));
      await dwell(t);
      expect(state.page, 1);
      await dwell(t);
      expect(state.page, 2);
      final target = word(t, 2, last: true);
      await press.moveTo(target.point);
      await t.pump();
      await press.up();
      await t.pumpAndSettle();
      expect(state.page, 1);
      expect(results.single, text.substring(start.start, target.end));
    },
  );

  testWidgets('background and a second pointer cancel preview and timer', (
    t,
  ) async {
    await mount(t, [BookBlock(text)], const Size(402, 800));
    final state = key.currentState!, start = word(t, 0);
    final press = await begin(t, start.point);
    final rect = t.getRect(find.byKey(state.selectionViewportKey));
    await press.moveTo(Offset(rect.right - 2, rect.top + 80));
    await dwell(t);
    expect(state.page, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    await press.up();
    await dwell(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(state.page, 0);
    expect(results, isEmpty);
    final again = await begin(t, word(t, 0).point);
    await again.moveTo(Offset(rect.right - 2, rect.top + 80));
    final second = await t.startGesture(rect.center, pointer: 42);
    await dwell(t);
    await second.up();
    await again.up();
    await t.pumpAndSettle();
    expect(state.page, 0);
    expect(results, isEmpty);
  });

  testWidgets(
    'cross-page paragraphs retain source order and empty-line separators',
    (t) async {
      final blocks = List.generate(
        16,
        (i) => BookBlock(
          'Paragraph $i: ${List.filled(8, 'Alpha café gamma delta.').join(' ')}',
        ),
      );
      await mount(t, blocks, const Size(402, 800));
      final state = key.currentState!, start = word(t, 0);
      final press = await begin(t, start.point);
      final rect = t.getRect(find.byKey(state.selectionViewportKey));
      await press.moveTo(Offset(rect.right - 2, rect.top + 80));
      await dwell(t);
      expect(state.page, 1);
      final target = word(t, 1, last: true);
      final finder = find
          .descendant(
            of: find.byKey(const ValueKey('visible-page-1')),
            matching: find.byType(ReaderParagraph),
          )
          .last;
      final block = t.widget<ReaderParagraph>(finder).sourceBlock!;
      await press.moveTo(target.point);
      await t.pump();
      await press.up();
      await t.pumpAndSettle();
      final expected = [
        for (var i = 0; i <= block; i++)
          blocks[i].text.substring(
            i == 0 ? start.start : 0,
            i == block ? target.end : null,
          ),
      ].join('\n\n');
      expect(block, greaterThan(0));
      expect(results.single, expected);
      expect(state.page, 0);
    },
  );

  testWidgets('document boundaries never wrap or leave a repeating timer', (
    t,
  ) async {
    await mount(t, [BookBlock(text)], const Size(402, 800));
    final state = key.currentState!;
    for (final direction in [-1, 1]) {
      final page = direction < 0 ? 0 : state.layout!.pages.length - 1;
      state.jumpPage(page);
      await t.pumpAndSettle();
      final press = await begin(t, word(t, page).point);
      final rect = t.getRect(find.byKey(state.selectionViewportKey));
      await press.moveTo(
        Offset(direction < 0 ? rect.left + 2 : rect.right - 2, rect.top + 80),
      );
      await dwell(t);
      await dwell(t);
      await dwell(t);
      expect(state.page, page);
      await press.cancel();
      await t.pumpAndSettle();
    }
    expect(results, isEmpty);
  });

  testWidgets(
    'resize and route removal cancel a held preview without submitting',
    (t) async {
      await mount(t, [BookBlock(text)], const Size(402, 800));
      final state = key.currentState!, start = word(t, 0);
      var press = await begin(t, start.point);
      var rect = t.getRect(find.byKey(state.selectionViewportKey));
      await press.moveTo(Offset(rect.right - 2, rect.top + 80));
      await dwell(t);
      expect(state.page, 1);
      t.view.physicalSize = const Size(402, 740);
      await t.pumpAndSettle();
      await press.up();
      await t.pumpAndSettle();
      expect(results, isEmpty);
      expect(state.anchor.position.offset, 0);
      final again = word(t, state.page);
      press = await begin(t, again.point);
      rect = t.getRect(find.byKey(state.selectionViewportKey));
      await press.moveTo(Offset(rect.right - 2, rect.top + 80));
      await dwell(t);
      await t.pumpWidget(const SizedBox());
      await press.up();
      await dwell(t);
      expect(results, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/reader/book_pagination.dart';
import 'package:reading_app/reader/paged_reader.dart';
import 'package:reading_app/reader/style.dart';

void main() {
  for (final closeEarly in [false, true]) {
    testWidgets('pagination waits for entry; closeEarly=$closeEarly', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final reader = GlobalKey<PagedReaderState>();
      var imageReads = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Library')),
        ),
      );
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(seconds: 1),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, animation, secondaryAnimation) => Scaffold(
            body: PagedReader(
              key: reader,
              content: const BookContent([
                BookBlock('Image caption', image: 'image.png'),
                BookBlock(
                  'A paragraph for reading after the entrance animation.',
                ),
              ]),
              style: const ReaderStyle(),
              initialAnchor: const PageAnchor(BookPosition(0)),
              loadImage: (_) async {
                imageReads++;
                return null;
              },
              onPosition: (_, page, count) {},
              onWord: (_, word, rect, cell) {},
              onSentence: (_, offset) {},
              onLink: (_) {},
              onBlank: () {},
              onTurn: () {},
              onScrollFallback: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(imageReads, 0);
      expect(reader.currentState!.layout, isNull);
      if (closeEarly) {
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(imageReads, 0);
        expect(reader.currentState, isNull);
      } else {
        await tester.pumpAndSettle();
        expect(imageReads, 1);
        expect(reader.currentState!.layout, isNotNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

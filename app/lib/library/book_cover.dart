import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../book/book.dart';
import '../book/epub.dart';
import '../core/providers.dart';

class BookCover extends ConsumerStatefulWidget {
  final Book book;
  const BookCover({super.key, required this.book});
  @override
  ConsumerState<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends ConsumerState<BookCover> {
  Future<Uint8List?>? bytes;
  ResizeImage? thumbnail;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refreshed shelf data (including backup restore) must reload matching IDs.
    if (!identical(oldWidget.book, widget.book)) load();
  }

  void load() {
    thumbnail?.evict();
    thumbnail = null;
    final cover = widget.book.content.cover;
    bytes = cover == null
        ? null
        : ref.read(databaseProvider).asset(widget.book.id, cover);
  }

  @override
  void dispose() {
    // MemoryImage keys retain encoded bytes too. Don't keep off-screen covers
    // in the global image cache merely because their decoded thumbnail is tiny.
    thumbnail?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    const colors = [
      Color(0xFF53695D),
      Color(0xFF756154),
      Color(0xFF4C6270),
      Color(0xFF806462),
      Color(0xFF696078),
    ];
    final color =
        colors[book.title.codeUnits.fold<int>(0, (a, b) => a + b) %
            colors.length];
    return Semantics(
      button: true,
      label: '阅读 ${book.title}',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x25000000),
              blurRadius: 8,
              offset: Offset(2, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: bytes == null
              ? fallback(book)
              : FutureBuilder<Uint8List?>(
                  key: ValueKey(bytes),
                  future: bytes,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data == null ||
                        data.isEmpty ||
                        data.length > EpubParser.maxCoverBytes) {
                      return fallback(book);
                    }
                    final image = thumbnail = ResizeImage(
                      MemoryImage(data),
                      width: 512,
                      height: 768,
                      policy: ResizeImagePolicy.fit,
                    );
                    return Image(
                      key: ValueKey('cover-image-${book.id}'),
                      image: image,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                      errorBuilder: (_, error, stack) => fallback(book),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget fallback(Book book) => Stack(
    children: [
      Positioned(
        left: 5,
        top: 0,
        bottom: 0,
        child: Container(width: 2, color: Colors.white12),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'READING LIBRARY',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 7,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              book.title,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Literata',
                color: Color(0xFFFFF6E9),
                fontSize: 20,
                height: 1.25,
              ),
            ),
            const Spacer(),
            Container(width: 25, height: 1, color: Colors.white54),
            const SizedBox(height: 10),
            const Text(
              'TEXT EDITION',
              style: TextStyle(
                fontSize: 7,
                letterSpacing: 1.6,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

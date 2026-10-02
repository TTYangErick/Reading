// Local compatibility audit. Emits structure/checksums, never book paragraphs.
// Run with: dart run tool/inspect_epub.dart /absolute/path/to/book.epub
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:reading_app/book/book.dart';
import 'package:reading_app/book/epub.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/inspect_epub.dart <local.epub>');
    exitCode = 64;
    return;
  }
  final bytes = File(args.single).readAsBytesSync();
  final timer = Stopwatch()..start();
  final book = EpubParser().parse(bytes);
  timer.stop();
  final encoded = book.encode();
  final restored = BookContent.decode(encoded);
  final result = {
    'sourceBytes': bytes.length,
    'title': book.title,
    'format': book.format,
    'parseMilliseconds': timer.elapsedMilliseconds,
    'blockCount': book.blocks.length,
    'textCharacters': book.blocks.fold<int>(0, (n, b) => n + b.text.length),
    'imageBlocks': book.blocks.where((b) => b.image != null).length,
    'tableBlocks': book.blocks.where((b) => b.rows != null).length,
    'assets': {for (final e in book.assets.entries) e.key: e.value.length},
    'chapters': book.contents.map((c) => c.toJson()).toList(),
    'invalidChapterTargets': book.contents
        .where((c) => c.block < 0 || c.block >= book.blocks.length)
        .length,
    'jsonBytes': utf8.encode(encoded).length,
    'jsonRoundTripIdentical': restored.encode() == encoded,
    // CRC is only a comparison fingerprint, not a security digest.
    'blocks': [
      for (final b in book.blocks)
        {
          'textCrc32': getCrc32(utf8.encode(b.text)),
          'heading': b.heading,
          if (b.image != null) 'image': b.image,
          if (b.rows != null) 'tableRows': b.rows!.length,
        },
    ],
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}

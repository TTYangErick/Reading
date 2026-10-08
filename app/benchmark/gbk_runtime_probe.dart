// Optional host diagnostic, outside the regular test suite. No database or UI.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';
import 'package:reading_app/book/book.dart';

void runGbkRuntimeProbe() {
  const input =
      'Chapter 1\r\n\r\nTomorrow is another day.\r\n第二章 新的开始\r\n中文与 English。';
  // Mark before first touching the codec's lazy global maps. The last emitted
  // stage remains useful even if the runtime terminates without a Dart error.
  stdout.writeln(
    'GBK_PROBE runtime=${Platform.version} os=${Platform.operatingSystemVersion}',
  );
  stdout.writeln('GBK_PROBE stage=encode');
  final encoded = gbk_bytes.encode(input);
  stdout.writeln('GBK_PROBE stage=decode');
  if (gbk_bytes.decode(encoded) != input) {
    throw StateError('GBK codec round trip differs');
  }
  stdout.writeln('GBK_PROBE stage=parse-gbk');
  final content = TxtParser().parse(Uint8List.fromList(encoded));
  if (content.encoding != 'GBK' ||
      content.blocks.length != 4 ||
      content.blocks.last.text != '中文与 English。') {
    throw StateError('GBK parser result differs');
  }
  stdout.writeln('GBK_PROBE stage=parse-utf8');
  final utf = TxtParser().parse(
    Uint8List.fromList([239, 187, 191, ...utf8.encode(input)]),
  );
  if (utf.encoding != 'UTF-8' ||
      utf.blocks.length != 4 ||
      utf.blocks.last.text != content.blocks.last.text) {
    throw StateError('UTF-8 parser result differs');
  }
  stdout.writeln('GBK_PROBE_PASS');
}

void main() => runGbkRuntimeProbe();

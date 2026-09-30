import 'dart:convert';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

class BookBlock {
  final String text;
  final bool heading;
  const BookBlock(this.text, {this.heading = false});
  Map<String, dynamic> toJson() => {'text': text, 'heading': heading};
  factory BookBlock.fromJson(Map<String, dynamic> j) =>
      BookBlock(j['text'] as String, heading: j['heading'] == true);
}

class BookContent {
  final List<BookBlock> blocks;
  final String encoding;
  const BookContent(this.blocks, {this.encoding = 'UTF-8'});
  String encode() => jsonEncode({
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'encoding': encoding,
  });
  factory BookContent.decode(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return BookContent(
      (j['blocks'] as List)
          .map((x) => BookBlock.fromJson(x as Map<String, dynamic>))
          .toList(),
      encoding: j['encoding'] as String,
    );
  }
}

abstract interface class BookParser {
  Set<String> get extensions;
  BookContent parse(Uint8List bytes);
}

class TxtParser implements BookParser {
  @override
  Set<String> get extensions => {'txt'};
  @override
  BookContent parse(Uint8List bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('文本超过 20 MB，请先拆分后导入。');
    }
    String text;
    String encoding = 'UTF-8';
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = gbk_bytes.decode(bytes);
      encoding = 'GBK';
      if (text.contains('\uFFFD')) {
        throw const FormatException('无法识别文件编码，请另存为 UTF-8 文本后导入。');
      }
    }
    return parseText(text, encoding: encoding);
  }

  BookContent parseText(String text, {String encoding = 'UTF-8'}) {
    if (text.length > 20 * 1024 * 1024) {
      throw const FormatException('文本过长，请拆分后导入。');
    }
    text = text
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (text.contains('\u0000')) {
      throw const FormatException('这个文件不像普通文本，请另存为 UTF-8 或 GBK。');
    }
    final chapter = RegExp(
      r'^(?:(?:chapter|part|book)\s+(?:\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)\b.*|第[一二三四五六七八九十百千万零〇\d]+[章节卷部回].*)$',
      caseSensitive: false,
    );
    final blocks = text
        .split('\n')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .map(
          (line) => BookBlock(
            line,
            heading: line.length < 160 && chapter.hasMatch(line),
          ),
        )
        .toList();
    if (blocks.isEmpty) throw const FormatException('文本是空的，请加入正文后再导入。');
    return BookContent(blocks, encoding: encoding);
  }
}

class ParserRegistry {
  final List<BookParser> parsers;
  const ParserRegistry(this.parsers);
  BookContent parse(String filename, Uint8List data) {
    final extension = filename.split('.').last.toLowerCase();
    for (final parser in parsers) {
      if (parser.extensions.contains(extension)) return parser.parse(data);
    }
    throw const FormatException('当前版本支持 TXT 文件，也可以粘贴文本。');
  }
}

class Book {
  final String id, title;
  final BookContent content;
  final int position, createdAt, updatedAt, lastReadAt;
  final String? style;
  const Book({
    required this.id,
    required this.title,
    required this.content,
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
    this.lastReadAt = 0,
    this.style,
  });
  double get progress => content.blocks.length <= 1
      ? (lastReadAt > 0 ? 1 : 0)
      : position / (content.blocks.length - 1);
}

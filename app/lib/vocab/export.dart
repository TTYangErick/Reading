import 'dart:convert';
import 'dart:typed_data';

import 'vocabulary.dart';

abstract interface class VocabExporter {
  Uint8List encode(Iterable<VocabularyItem> items);
}

class CsvVocabExporter implements VocabExporter {
  const CsvVocabExporter();

  // Quote every cell; quoting alone does not prevent spreadsheet formulas.
  static String _cell(String value) {
    final first = value.trimLeft();
    if (RegExp(r'^[=+@\-＝＋＠－]').hasMatch(first) ||
        RegExp(r'^[\x00-\x1f]').hasMatch(value)) {
      value = "'$value";
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  @override
  Uint8List encode(Iterable<VocabularyItem> items) {
    final output = StringBuffer('\uFEFF');
    void row(List<String> cells) =>
        output.write('${cells.map(_cell).join(',')}\r\n');
    row([
      'word',
      'lemma',
      'gloss',
      'sentence',
      'book_title',
      'created_at',
      'lang',
      'dict_id',
      'source',
      'source_url',
      'license',
      'id',
      'book_id',
      'location',
      'updated_at',
    ]);
    for (final item in items) {
      final v = item.draft;
      String date(int ms) => DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).toIso8601String();
      row([
        v.word,
        v.lemma,
        v.gloss,
        v.sentence,
        v.bookTitle,
        date(item.createdAt),
        v.lang,
        v.dictId,
        v.source,
        v.sourceUrl,
        v.license,
        item.id,
        v.bookId,
        v.location,
        date(item.updatedAt),
      ]);
    }
    return Uint8List.fromList(utf8.encode(output.toString()));
  }
}

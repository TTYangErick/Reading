import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../book/book.dart';
import '../db/database.dart';
import '../dict/dictionary.dart';
import '../text/language.dart';

class VocabularyDraft {
  const VocabularyDraft({
    required this.word,
    required this.lemma,
    required this.gloss,
    required this.lang,
    required this.dictId,
    required this.source,
    required this.sourceUrl,
    required this.license,
    required this.bookId,
    required this.bookTitle,
    required this.sentence,
    required this.location,
  });
  final String word, lemma, gloss, lang, dictId, source, sourceUrl, license;
  final String bookId, bookTitle, sentence, location;

  static VocabularyDraft capture({
    required Book book,
    required BookPosition position,
    required WordRange word,
    required DictionaryEntry entry,
    required bool english,
    String? cell,
  }) {
    final blocks = position.document == null
        ? book.content.blocks
        : book.content.supplementaryDocuments[position.document]!;
    final block = blocks[position.block];
    var text = block.text;
    if (cell != null && cell != 'caption') {
      final coordinates = cell.split('-').map(int.parse).toList();
      text = block.rows![coordinates[0]][coordinates[1]];
    }
    final lemma = english ? (entry.englishWord ?? entry.word) : entry.word;
    final gloss = english
        ? entry.englishSenses
              .take(24)
              .map(
                (s) =>
                    '${[s.pos, ...s.tags].where((v) => v.isNotEmpty).join(' · ')}${s.pos.isNotEmpty || s.tags.isNotEmpty ? ': ' : ''}${s.gloss}',
              )
              .join('\n')
        : entry.fullGloss.isNotEmpty
        ? entry.fullGloss
        : entry.meanings.join('；');
    return VocabularyDraft(
      word: word.text,
      lemma: lemma,
      gloss: gloss,
      lang: 'en',
      dictId: english ? 'wiktionary' : 'ecdict',
      source: english ? 'Wiktionary contributors · Kaikki' : 'ECDICT',
      sourceUrl: english
          ? 'https://en.wiktionary.org/wiki/${Uri.encodeComponent(lemma)}#English'
          : 'https://github.com/skywind3000/ECDICT',
      license: english ? 'CC-BY-SA-4.0' : 'MIT',
      bookId: book.id,
      bookTitle: book.title,
      sentence: EnglishLanguage().sentenceAt(text, word.start).text,
      location: jsonEncode({
        'version': 1,
        'position': BookPosition(
          position.block,
          offset: word.start,
          document: position.document,
        ).toJson(),
        'cell': ?cell,
      }),
    );
  }
}

class VocabularyItem {
  const VocabularyItem(this.id, this.draft, this.createdAt, this.updatedAt);
  final String id;
  final VocabularyDraft draft;
  final int createdAt, updatedAt;
  factory VocabularyItem.fromRow(QueryRow r) => VocabularyItem(
    r.read('id'),
    VocabularyDraft(
      word: r.read('word'),
      lemma: r.read('lemma'),
      gloss: r.read('gloss'),
      lang: r.read('lang'),
      dictId: r.read('dict_id'),
      source: r.read('source'),
      sourceUrl: r.read('source_url'),
      license: r.read('license'),
      bookId: r.read('book_id'),
      bookTitle: r.read('book_title'),
      sentence: r.read('sentence'),
      location: r.read('location'),
    ),
    r.read('created_at'),
    r.read('updated_at'),
  );
}

extension VocabularyStorage on ReadingDatabase {
  Future<String?> vocabularyId(VocabularyDraft value) async =>
      (await customSelect(
        'SELECT id FROM vocabulary WHERE lang=? AND dict_id=? AND book_id=? AND location=?',
        variables: [
          Variable(value.lang),
          Variable(value.dictId),
          Variable(value.bookId),
          Variable(value.location),
        ],
      ).getSingleOrNull())?.read<String>('id');

  Future<String> addVocabulary(VocabularyDraft value) => transaction(() async {
    if (value.word.trim().isEmpty ||
        value.lemma.trim().isEmpty ||
        value.gloss.trim().isEmpty) {
      throw ArgumentError(
        'A vocabulary entry needs a real word and definition',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      '''INSERT INTO vocabulary(id,lang,dict_id,word,lemma,gloss,source,source_url,license,
      book_id,book_title,sentence,location,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(lang,dict_id,book_id,location) DO NOTHING''',
      [
        const Uuid().v4(),
        value.lang,
        value.dictId,
        value.word,
        value.lemma,
        value.gloss,
        value.source,
        value.sourceUrl,
        value.license,
        value.bookId,
        value.bookTitle,
        value.sentence,
        value.location,
        now,
        now,
      ],
    );
    return (await vocabularyId(value))!;
  });

  Future<List<VocabularyItem>> vocabulary() async => (await customSelect(
    'SELECT * FROM vocabulary ORDER BY created_at DESC, rowid DESC',
  ).get()).map(VocabularyItem.fromRow).toList();

  Future<void> deleteVocabulary(String id) =>
      customStatement('DELETE FROM vocabulary WHERE id=?', [id]);
}

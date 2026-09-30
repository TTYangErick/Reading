import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../text/language.dart';

class DictionaryEntry {
  final String word, phonetic, fullGloss, definition;
  final List<String> meanings;
  const DictionaryEntry({
    required this.word,
    required this.phonetic,
    required this.fullGloss,
    required this.definition,
    required this.meanings,
  });
}

abstract interface class DictionaryProvider {
  DictionaryEntry? lookup(String word);
  void close();
}

class SqliteDictionary implements DictionaryProvider {
  final Database database;
  final LanguageSupport language;
  SqliteDictionary(this.database, {LanguageSupport? language})
    : language = language ?? EnglishLanguage();
  factory SqliteDictionary.open(String path) =>
      SqliteDictionary(sqlite3.open(path, mode: OpenMode.readOnly));

  static Future<SqliteDictionary> fromAssets() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/dictionaries/manifest.json'),
    ) as Map<String, dynamic>;
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/ecdict-${manifest['sha256']}.sqlite');
    if (!await file.exists() || await file.length() != manifest['bytes']) {
      final data = await rootBundle.load('assets/dictionaries/ecdict.sqlite');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await temporary.rename(file.path);
    }
    final result = SqliteDictionary.open(file.path);
    if (result.database.select('PRAGMA user_version').first.values.first !=
        manifest['schemaVersion']) {
      result.close();
      throw const FormatException('词典版本不匹配，请重新安装应用。');
    }
    return result;
  }

  DictionaryEntry? _entry(String word) {
    final rows = database.select(
      'SELECT headword,phonetic,full_gloss,definition FROM entries WHERE headword=?',
      [word],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final meanings = database.select(
      'SELECT gloss_zh FROM senses WHERE headword=? ORDER BY rank',
      [word],
    );
    return DictionaryEntry(
      word: row['headword'] as String,
      phonetic: row['phonetic'] as String,
      fullGloss: row['full_gloss'] as String,
      definition: row['definition'] as String,
      meanings: meanings.map((r) => r['gloss_zh'] as String).toList(),
    );
  }

  @override
  DictionaryEntry? lookup(String word) {
    for (final candidate in language.candidates(word)) {
      final exact = _entry(candidate);
      // ECDICT marks many inflected entries as references. Resolve those to a useful lemma.
      final reference =
          exact != null &&
          RegExp(
            r'(^pl\.|的(?:过去|复数|现在|第三人称|比较|最高)|past (?:tense|participle)|plural of)',
            caseSensitive: false,
          ).hasMatch(exact.fullGloss);
      if (exact != null && !reference && exact.meanings.isNotEmpty) {
        return exact;
      }
      final forms = database.select(
        '''SELECT f.lemma FROM forms f JOIN entries e ON e.headword=f.lemma
        WHERE f.form=? ORDER BY CASE WHEN e.freq>0 THEN e.freq ELSE 999999 END, length(f.lemma), f.lemma''',
        [candidate],
      );
      for (final form in forms) {
        final entry = _entry(form['lemma'] as String);
        if (entry != null && entry.meanings.isNotEmpty) return entry;
      }
      if (exact != null) return exact;
    }
    return null;
  }

  @override
  void close() => database.close();
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../text/language.dart';
import 'dictionary.dart';

class WiktionaryDictionary implements DictionaryProvider {
  WiktionaryDictionary(this.database);
  final Database database;
  factory WiktionaryDictionary.open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      if (db.select('PRAGMA user_version').single.values.single != 1) {
        throw const FormatException(
          'Unsupported Wiktionary dictionary version',
        );
      }
      db.select('SELECT id,word,word_key,pos,ipa FROM entries LIMIT 1');
      db.select(
        'SELECT entry_id,rank,gloss,tags,examples,is_form FROM senses LIMIT 1',
      );
      db.select('SELECT form_key,lemma FROM forms LIMIT 1');
      return WiktionaryDictionary(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static Future<WiktionaryDictionary> fromAssets({
    AssetBundle? bundle,
    Directory? directory,
  }) async {
    final assets = bundle ?? rootBundle;
    final manifest = jsonDecode(
      await assets.loadString('assets/dictionaries/wiktionary-manifest.json'),
    ) as Map<String, dynamic>;
    directory ??= await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}/wiktionary-${manifest['sha256']}.sqlite',
    );
    if (!await file.exists() || await file.length() != manifest['bytes']) {
      final data = await assets.load(
        'assets/dictionaries/wiktionary.sqlite.gz',
      );
      final temporary = File('${file.path}.tmp');
      final compressed = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      Stream<List<int>> chunks() async* {
        for (var offset = 0; offset < compressed.length; offset += 65536) {
          final end = offset + 65536 < compressed.length
              ? offset + 65536
              : compressed.length;
          yield Uint8List.sublistView(compressed, offset, end);
        }
      }

      final sink = temporary.openWrite();
      try {
        await sink.addStream(gzip.decoder.bind(chunks()));
      } finally {
        await sink.close();
      }
      if (await temporary.length() != manifest['bytes']) {
        throw const FormatException('Incomplete Wiktionary dictionary');
      }
      await temporary.rename(file.path);
    }
    return WiktionaryDictionary.open(file.path);
  }

  static String key(String word) => word.replaceAll('’', "'").toLowerCase();

  ({DictionaryEntry entry, bool reference})? _entry(String word) {
    final names = database.select(
      '''SELECT word FROM entries WHERE word_key=?
      ORDER BY CASE WHEN word=? THEN 0 WHEN word=? THEN 1 ELSE 2 END, word LIMIT 1''',
      [key(word), word, key(word)],
    );
    if (names.isEmpty) return null;
    final name = names.single['word'] as String;
    final rows = database.select(
      '''SELECT e.pos,e.ipa,s.gloss,s.tags,s.examples,s.is_form
      FROM entries e JOIN senses s ON s.entry_id=e.id WHERE e.word=? ORDER BY e.id,s.rank''',
      [name],
    );
    if (rows.isEmpty) return null;
    return (
      entry: DictionaryEntry(
        word: name,
        phonetic: '',
        fullGloss: '',
        definition: '',
        meanings: const [],
        hasChineseSource: false,
        englishWord: name,
        englishPhonetic: rows.first['ipa'] as String,
        englishSenses: rows
            .map(
              (row) => EnglishSense(
                pos: row['pos'] as String,
                gloss: row['gloss'] as String,
                tags: (jsonDecode(row['tags'] as String) as List)
                    .cast<String>(),
                examples: (jsonDecode(row['examples'] as String) as List)
                    .cast<String>(),
              ),
            )
            .toList(),
      ),
      reference: rows.every((r) => r['is_form'] == 1),
    );
  }

  @override
  DictionaryEntry? lookup(String word) {
    DictionaryEntry? fallback;
    final queue = [word, ...EnglishLanguage().candidates(word)];
    final visited = <String>{};
    for (var index = 0; index < queue.length && visited.length < 16; index++) {
      final candidate = queue[index];
      if (!visited.add(candidate)) continue;
      final found = _entry(candidate);
      if (found != null) {
        fallback ??= found.entry;
        if (!found.reference) return found.entry;
      }
      final forms = database.select(
        'SELECT lemma FROM forms WHERE form_key=? ORDER BY length(lemma),lemma LIMIT 8',
        [key(candidate)],
      );
      queue.addAll(forms.map((r) => r['lemma'] as String));
    }
    return fallback;
  }

  @override
  void close() => database.close();
}

/// Preserve ECDICT's Chinese ordering; English content has its own provenance.
class CombinedDictionary implements DictionaryProvider {
  CombinedDictionary(
    this.chinese,
    this.english, {
    this.englishUnavailable = false,
  });
  final DictionaryProvider chinese;
  final DictionaryProvider? english;
  final bool englishUnavailable;

  static Future<CombinedDictionary> fromAssets() async {
    final chinese = await SqliteDictionary.fromAssets();
    try {
      return CombinedDictionary(
        chinese,
        await WiktionaryDictionary.fromAssets(),
      );
    } catch (_) {
      return CombinedDictionary(chinese, null, englishUnavailable: true);
    }
  }

  @override
  DictionaryEntry? lookup(String word) {
    final primary = chinese.lookup(word);
    DictionaryEntry? secondary;
    var unavailable = englishUnavailable || english == null;
    try {
      secondary =
          english?.lookup(word) ??
          (primary == null ? null : english?.lookup(primary.word));
    } catch (_) {
      unavailable = true;
    }
    if (primary == null && secondary == null) {
      // A failed dictionary is not evidence that the word is unrecorded.
      if (unavailable) throw StateError('English dictionary unavailable');
      return null;
    }
    return DictionaryEntry(
      word: primary?.word ?? secondary!.word,
      phonetic: primary?.phonetic ?? '',
      fullGloss: primary?.fullGloss ?? '',
      definition: primary?.definition ?? '',
      meanings: primary?.meanings ?? const [],
      hasChineseSource: primary != null,
      englishWord: secondary?.englishWord,
      englishPhonetic: secondary?.englishPhonetic ?? '',
      englishSenses: secondary?.englishSenses ?? const [],
      englishNotice: unavailable ? '英英词典暂时无法打开，请重开应用后重试。' : null,
    );
  }

  @override
  void close() {
    chinese.close();
    english?.close();
  }
}

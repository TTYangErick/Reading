import '../db/database.dart';

class LookupRecord {
  const LookupRecord(this.language, this.word, this.lookedUpAt);
  final String language, word;
  final int lookedUpAt;
  static const limit = 200;
  static bool valid(String language, String word) =>
      language.isNotEmpty &&
      language.length <= 32 &&
      language.trim() == language &&
      word.isNotEmpty &&
      word.length <= 256 &&
      word.trim() == word &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch('$language$word');
}

/// Bounded recent queries, independent of vocabulary snapshots and books.
class LookupHistory {
  LookupHistory(this.database);
  final ReadingDatabase database;
  int _generation = 0;
  int get generation => _generation;
  Future<void> _writes = Future.value();
  bool writeFailed = false;

  Future<void> _write(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> record(
    String language,
    String word, {
    required int generation,
  }) => _write(() async {
    if (generation != _generation || !LookupRecord.valid(language, word)) {
      return;
    }
    try {
      await database.transaction(() async {
        await database.customStatement(
          'INSERT OR REPLACE INTO lookup_history(lang,word,looked_up_at) VALUES(?,?,?)',
          [language, word, DateTime.now().millisecondsSinceEpoch],
        );
        await database.customStatement(
          'DELETE FROM lookup_history WHERE rowid NOT IN (SELECT rowid FROM lookup_history ORDER BY rowid DESC LIMIT ${LookupRecord.limit})',
        );
      });
    } catch (_) {
      writeFailed = true;
      rethrow;
    }
  });

  Future<List<LookupRecord>> recent() async {
    await _writes;
    return (await database
            .customSelect(
              'SELECT lang,word,looked_up_at FROM lookup_history ORDER BY rowid DESC LIMIT ${LookupRecord.limit}',
            )
            .get())
        .map(
          (r) => LookupRecord(
            r.read('lang'),
            r.read('word'),
            r.read('looked_up_at'),
          ),
        )
        .toList();
  }

  // Invalidate dictionary lookups begun before clear/restore, then drain writes.
  Future<void> replace(Future<void> Function() action) {
    _generation++;
    return _write(() async {
      await action();
      writeFailed = false;
    });
  }

  Future<void> clear() =>
      replace(() => database.customStatement('DELETE FROM lookup_history'));
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../dict/dictionary.dart';
import '../reader/style.dart';

final databaseProvider = Provider<ReadingDatabase>((ref) {
  final database = ReadingDatabase.open();
  ref.onDispose(database.close);
  return database;
});
final booksProvider = FutureProvider(
  (ref) => ref.watch(databaseProvider).books(),
);
final globalStyleProvider = FutureProvider(
  (ref) async => ReaderStyle.decode(
    await ref.watch(databaseProvider).setting('readerStyle'),
  ),
);
final dictionaryProvider = FutureProvider<DictionaryProvider>((ref) async {
  final dictionary = await SqliteDictionary.fromAssets();
  ref.onDispose(dictionary.close);
  return dictionary;
});

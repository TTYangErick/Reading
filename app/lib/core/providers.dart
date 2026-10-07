import 'package:flutter/widgets.dart';

import '../reader/pagination_cache.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../history/history.dart';
import '../dict/dictionary.dart';
import '../dict/catalog.dart';
import '../dict/wiktionary.dart';
import '../reader/style.dart';
import '../translate/translator.dart';

final translatorProvider = Provider<CachedTranslator>(
  (ref) =>
      CachedTranslator(const PlatformTranslator(), ref.watch(databaseProvider)),
);

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
  final dictionary = await CombinedDictionary.fromAssets();
  ref.onDispose(dictionary.close);
  return dictionary;
});

final dictionaryCatalogProvider = Provider((ref) => DictionaryCatalog());

final lookupHistoryProvider = Provider(
  (ref) => LookupHistory(ref.watch(databaseProvider)),
);

final paginationCacheProvider = Provider((ref) {
  ref.watch(databaseProvider);
  final cache = PaginationCache();
  WidgetsBinding.instance.addObserver(cache);
  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(cache);
    cache.clear();
  });
  return cache;
});

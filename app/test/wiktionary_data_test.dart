import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reading_app/dict/dictionary.dart';
import 'package:reading_app/dict/wiktionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('full bundled compressed dictionary installs and reopens offline', () async {
    final directory = Directory.systemTemp.createTempSync('wiktionary-real-');
    try {
      final watch = Stopwatch()..start();
      final first = await WiktionaryDictionary.fromAssets(directory: directory);
      expect(first.lookup('tomorrow')!.englishSenses, isNotEmpty);
      first.close();
      final installMs = watch.elapsedMilliseconds;
      watch.reset();
      final reopened = await WiktionaryDictionary.fromAssets(
        directory: directory,
      );
      expect(reopened.lookup('dictionary')!.englishSenses, isNotEmpty);
      reopened.close();
      debugPrint(
        'Full dictionary host install=${installMs}ms reopen=${watch.elapsedMilliseconds}ms',
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('full pinned Wiktionary package has real definitions, examples and indexed lookup', () {
    final manifest = jsonDecode(
      File('assets/dictionaries/wiktionary-manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final dictionary = WiktionaryDictionary.open(
      'assets/dictionaries/wiktionary.sqlite',
    );
    addTearDown(dictionary.close);
    expect(manifest['counts']['words'], greaterThan(100000));
    expect(
      dictionary.database.select('PRAGMA integrity_check').single.values.single,
      'ok',
    );
    for (final table in ['entries', 'senses', 'forms']) {
      expect(
        dictionary.database
            .select('SELECT COUNT(*) FROM $table')
            .single
            .values
            .single,
        manifest['counts'][table],
      );
    }
    for (final word in [
      'tomorrow',
      'dictionary',
      'go',
      'went',
      'read',
      'reading',
      'children',
      'studies',
      'knowledge',
      'quiet',
      'pleasure',
    ]) {
      final entry = dictionary.lookup(word);
      expect(entry, isNotNull, reason: word);
      expect(entry!.englishSenses, isNotEmpty, reason: word);
    }
    expect(
      dictionary
          .lookup('tomorrow')!
          .englishSenses
          .any((s) => s.gloss.contains('day')),
      isTrue,
    );
    expect(
      dictionary.lookup('dictionary')!.englishSenses.expand((s) => s.examples),
      isNotEmpty,
    );
    expect(dictionary.lookup('zzzzunlistedword'), isNull);
    final chinese = SqliteDictionary.open('assets/dictionaries/ecdict.sqlite');
    addTearDown(chinese.close);
    final combined = CombinedDictionary(chinese, dictionary);
    for (final word in ['went', 'children', 'studies', 'tomorrow']) {
      expect(combined.lookup(word)!.meanings, chinese.lookup(word)!.meanings);
    }
    final times = <int>[];
    for (var i = 0; i < 500; i++) {
      final watch = Stopwatch()..start();
      combined.lookup(
        ['tomorrow', 'went', 'reading', 'children', 'studies'][i % 5],
      );
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    // Measurement on the host, not an assertion about first-use mobile devices.
    debugPrint(
      'Combined dictionary host p50=${times[250]}µs p95=${times[475]}µs max=${times.last}µs',
    );
  });
}

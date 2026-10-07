import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

enum DictionaryAvailability { notPrepared, ready, unavailable, unknown }

class DictionaryInfo {
  const DictionaryInfo({
    required this.id,
    required this.name,
    required this.source,
    required this.availability,
    this.version,
    this.license,
    this.packageBytes,
    this.expectedBytes,
    this.localBytes,
  });
  final String id, name, source;
  final String? version, license;
  final int? packageBytes, expectedBytes, localBytes;
  final DictionaryAvailability availability;
}

/// Inspects only manifests and existing files. Never installs, repairs, hashes
/// a full dictionary, or opens the reader's database/active dictionary handles.
class DictionaryCatalog {
  DictionaryCatalog({
    AssetBundle? assets,
    Future<Directory> Function()? directory,
  }) : assets = assets ?? rootBundle,
       directory = directory ?? getApplicationSupportDirectory;

  final AssetBundle assets;
  final Future<Directory> Function() directory;

  Future<List<DictionaryInfo>> inspect() async => [
    await _inspect('ecdict', 'ECDICT 英汉词典', 'ECDICT', 'manifest.json'),
    await _inspect(
      'wiktionary',
      'Wiktionary 英英词典',
      'Wiktionary contributors · Kaikki',
      'wiktionary-manifest.json',
    ),
  ];

  Future<DictionaryInfo> _inspect(
    String id,
    String name,
    String source,
    String manifestName,
  ) async {
    String? version, license;
    int? packageBytes, expectedBytes, localBytes;
    DictionaryInfo info(DictionaryAvailability status) => DictionaryInfo(
      id: id,
      name: name,
      source: source,
      availability: status,
      version: version,
      license: license,
      packageBytes: packageBytes,
      expectedBytes: expectedBytes,
      localBytes: localBytes,
    );
    try {
      final manifest = jsonDecode(
        await assets.loadString(
          'assets/dictionaries/$manifestName',
          cache: false,
        ),
      ) as Map<String, dynamic>;
      final sha = manifest['sha256'] as String;
      expectedBytes = manifest['bytes'] as int;
      packageBytes = (manifest['compressedBytes'] ?? expectedBytes) as int;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
          expectedBytes <= 0 ||
          packageBytes <= 0 ||
          manifest['schemaVersion'] != 1) {
        throw const FormatException('Invalid dictionary manifest');
      }
      final origin = manifest['source'] as Map<String, dynamic>;
      license = origin['license'] as String;
      if (id == 'ecdict') {
        final revision = origin['revision'] as String;
        version = revision.length > 12 ? revision.substring(0, 12) : revision;
      } else {
        version =
            '${origin['dumpDate'] as String} · 提取 ${origin['extractedDate'] as String}';
      }
      final folder = await directory();
      final file = File('${folder.path}/$id-$sha.sqlite');
      if (!await file.exists()) {
        localBytes = 0;
        return info(DictionaryAvailability.notPrepared);
      }
      localBytes = await file.length();
      if (localBytes != expectedBytes) {
        return info(DictionaryAvailability.unavailable);
      }
      Database? db;
      try {
        db = sqlite3.open(file.path, mode: OpenMode.readOnly);
        if (db.select('PRAGMA user_version').single.values.single !=
            manifest['schemaVersion']) {
          return info(DictionaryAvailability.unavailable);
        }
        if (id == 'ecdict') {
          db.select(
            'SELECT headword,phonetic,full_gloss,definition,freq FROM entries LIMIT 1',
          );
          db.select('SELECT headword,rank,gloss_zh FROM senses LIMIT 1');
          db.select('SELECT form,lemma FROM forms LIMIT 1');
        } else {
          db.select('SELECT id,word,word_key,pos,ipa FROM entries LIMIT 1');
          db.select(
            'SELECT entry_id,rank,gloss,tags,examples,is_form FROM senses LIMIT 1',
          );
          db.select('SELECT form_key,lemma FROM forms LIMIT 1');
        }
        return info(DictionaryAvailability.ready);
      } catch (_) {
        return info(DictionaryAvailability.unavailable);
      } finally {
        db?.close();
      }
    } catch (_) {
      return info(DictionaryAvailability.unknown);
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../book/book.dart';
import '../db/database.dart';
import '../history/history.dart';

// Explicit portable rows, never SQL supplied by the file or a SQLite file swap.
const backupColumns = <String, List<String>>{
  'lookup_history': ['lang', 'word', 'looked_up_at'],
  'books': [
    'id',
    'title',
    'content',
    'position',
    'style',
    'location',
    'created_at',
    'updated_at',
    'last_read_at',
  ],
  'book_assets': ['book_id', 'path', 'data'],
  'settings': ['key', 'value'],
  'translations': [
    'engine',
    'source_language',
    'target_language',
    'source',
    'result',
  ],
  'vocabulary': [
    'id',
    'lang',
    'dict_id',
    'word',
    'lemma',
    'gloss',
    'source',
    'source_url',
    'license',
    'book_id',
    'book_title',
    'sentence',
    'location',
    'created_at',
    'updated_at',
  ],
  'bookmarks': [
    'id',
    'book_id',
    'location',
    'excerpt',
    'created_at',
    'updated_at',
  ],
};

class _InvalidBackup extends FormatException {
  const _InvalidBackup(super.message);
}

class ReadingBackup {
  ReadingBackup._(this.createdAt, this.rows);
  final int createdAt;
  // Immutable after validation: confirmation and restore use the same snapshot.
  final Map<String, List<List<Object?>>> rows;
  int count(String table) => rows[table]!.length;
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxDataBytes = 32 * 1024 * 1024;
  static const maxRows = 50000;
  static const _magic = [82, 69, 65, 68, 73, 78, 71, 10]; // READING\n

  static Future<Uint8List> readStream(Stream<Uint8List> stream) async {
    final buffer = BytesBuilder(copy: false);
    await for (final part in stream) {
      if (buffer.length + part.length > maxFileBytes) _fail('备份超过 64 MB 上限。');
      buffer.add(part);
    }
    return buffer.takeBytes();
  }

  static Never _fail(String text) => throw _InvalidBackup(text);

  static Uint8List encode(Map<String, Object?> data) {
    // Validate exports too: never report a backup as saved if it cannot restore.
    _validate(data);
    final payload = utf8.encode(jsonEncode(data));
    if (payload.length + 20 > maxFileBytes) _fail('备份超过 64 MB 上限。');
    final output = Uint8List(payload.length + 20)..setRange(0, 8, _magic);
    final header = ByteData.sublistView(output);
    header.setUint32(8, 1);
    header.setUint32(12, payload.length);
    header.setUint32(16, getCrc32(payload));
    output.setRange(20, output.length, payload);
    return output;
  }

  static ReadingBackup decode(Uint8List bytes) {
    if (bytes.length > maxFileBytes) _fail('备份超过 64 MB 上限。');
    if (bytes.length < 20 || !listEquals(bytes.sublist(0, 8), _magic)) {
      _fail('这不是 Reading 备份文件。');
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(8) != 1) _fail('暂不支持此备份版本，请更新 Reading。');
    final payload = Uint8List.sublistView(bytes, 20);
    if (header.getUint32(12) != payload.length ||
        header.getUint32(16) != getCrc32(payload)) {
      _fail('备份不完整或已损坏，未改动当前数据。');
    }
    try {
      return _validate(_json(utf8.decode(payload)));
    } on _InvalidBackup {
      rethrow;
    } catch (_) {
      _fail('备份内容无效，未改动当前数据。');
    }
  }

  // Reject excessive nesting/container counts before allocating a JSON tree.
  static dynamic _json(String text) {
    var depth = 0, nodes = 0, fields = 0, quoted = false, escaped = false;
    for (final c in text.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 92) {
          escaped = true;
        } else if (c == 34) {
          quoted = false;
        }
      } else if (c == 34) {
        quoted = true;
      } else if (c == 91 || c == 123) {
        if (++depth > 32 || ++nodes > 250000) _fail('备份结构超过安全上限。');
      } else if (c == 44 || c == 58) {
        if (++fields > 1000000) _fail('备份结构超过安全上限。');
      } else if (c == 93 || c == 125) {
        depth--;
      }
    }
    return jsonDecode(text);
  }

  static ReadingBackup _validate(dynamic data) {
    if (data is! Map ||
        data['format'] != 'Reading backup' ||
        !{6, 7}.contains(data['schema']) ||
        data['createdAt'] is! int ||
        data['createdAt'] < 0 ||
        data['createdAt'] > 8640000000000000) {
      _fail('备份版本或摘要无效。');
    }
    final columnsForSchema = Map.of(backupColumns);
    if (data['schema'] == 6) columnsForSchema.remove('lookup_history');
    final tables = data['tables'];
    if (tables is! Map ||
        tables.length != columnsForSchema.length ||
        !columnsForSchema.keys.every(tables.containsKey)) {
      _fail('备份缺少数据表。');
    }
    final result = <String, List<List<Object?>>>{};
    var rowCount = 0, byteCount = 0;
    for (final entry in columnsForSchema.entries) {
      final table = entry.key, columns = entry.value;
      final input = tables[table];
      if (input is! List || (rowCount += input.length) > maxRows) {
        _fail('备份记录超过 50,000 条上限。');
      }
      final rows = <List<Object?>>[];
      final unique = <String>{}, secondary = <String>{};
      for (final value in input) {
        if (value is! List || value.length != columns.length) _fail('备份记录不完整。');
        final row = <Object?>[];
        for (var i = 0; i < columns.length; i++) {
          final field = columns[i], v = value[i];
          if (field == 'position' || field.endsWith('_at')) {
            if (v is! int || v < 0 || v > 8640000000000000) _fail('备份时间或位置无效。');
            row.add(v);
          } else if (v == null &&
              table == 'books' &&
              (field == 'style' || field == 'location')) {
            row.add(null);
          } else {
            if (v is! String) _fail('备份字段类型无效。');
            byteCount += utf8.encode(v).length;
            if (byteCount > maxDataBytes) _fail('备份数据超过 32 MB 上限。');
            if (field == 'data') {
              final bytes = base64Decode(v);
              if (bytes.length > 20 * 1024 * 1024) _fail('单个图片资源超过 20 MB。');
              row.add(bytes.asUnmodifiableView());
            } else {
              row.add(v);
            }
          }
        }
        String key(List<int> indexes) =>
            jsonEncode(indexes.map((i) => row[i]).toList());
        final indexes = switch (table) {
          'book_assets' || 'lookup_history' => [0, 1],
          'translations' => [0, 1, 2, 3],
          _ => [0],
        };
        if (!unique.add(key(indexes))) _fail('备份存在重复记录。');
        if (table == 'bookmarks' && !secondary.add(key([1, 2])) ||
            table == 'vocabulary' && !secondary.add(key([1, 2, 9, 12]))) {
          _fail('备份存在冲突记录。');
        }
        rows.add(List.unmodifiable(row));
      }
      result[table] = List.unmodifiable(rows);
    }
    result.putIfAbsent('lookup_history', () => const []);
    if (result['lookup_history']!.length > LookupRecord.limit ||
        result['lookup_history']!.any(
          (r) => !LookupRecord.valid(r[0] as String, r[1] as String),
        )) {
      _fail('备份查词历史无效或超过 200 条。');
    }
    if (result['books']!.length > 500 ||
        result['book_assets']!.length > 10000 ||
        result['translations']!.length > 1000) {
      _fail('备份超过书籍、图片或译文数量上限。');
    }
    final books = <String, BookContent>{};
    for (final row in result['books']!) {
      final raw = row[2] as String;
      _json(raw);
      final content = BookContent.decode(raw);
      if (content.blocks.isEmpty || (row[3] as int) >= content.blocks.length) {
        _fail('备份正文或阅读位置无效。');
      }
      // Force lazy table casts during preflight, not after committing recovery.
      for (final block in [
        ...content.blocks,
        ...content.supplementaryDocuments.values.expand((v) => v),
      ]) {
        if (block.rows != null) {
          for (final r in block.rows!) {
            for (final cell in r) {
              cell.length;
            }
          }
        }
      }
      books[row[0] as String] = content;
      for (final i in [4, 5]) {
        if (row[i] != null) _json(row[i] as String);
      }
    }
    final assets = <String>{};
    for (final row in result['book_assets']!) {
      final path = row[1] as String;
      if (!books.containsKey(row[0]) ||
          path.isEmpty ||
          path.startsWith('/') ||
          path.contains('\\') ||
          path.contains(':') ||
          path.contains('\u0000') ||
          path.split('/').any((p) => p == '.' || p == '..' || p.isEmpty)) {
        _fail('备份资源路径无效。');
      }
      assets.add(jsonEncode([row[0], path]));
    }
    for (final entry in books.entries) {
      for (final block in [
        ...entry.value.blocks,
        ...entry.value.supplementaryDocuments.values.expand((v) => v),
      ]) {
        if (block.image != null &&
            !assets.contains(jsonEncode([entry.key, block.image]))) {
          _fail('备份缺少书籍图片资源。');
        }
      }
    }
    for (final row in result['bookmarks']!) {
      if (!books.containsKey(row[1])) _fail('备份书签缺少对应书籍。');
      _json(row[2] as String);
    }
    // Deleted-book vocabulary snapshots intentionally remain valid and portable.
    for (final row in result['vocabulary']!) {
      _json(row[12] as String);
    }
    for (final row in result['settings']!) {
      if (row[0] == 'readerStyle') _json(row[1] as String);
    }
    return ReadingBackup._(data['createdAt'], Map.unmodifiable(result));
  }
}

class BackupStore {
  const BackupStore(this.database);
  final ReadingDatabase database;
  Future<Uint8List> export() async {
    final data = await database.transaction(() async {
      final tables = <String, List<List<Object?>>>{};
      var size = 0, count = 0;
      for (final entry in backupColumns.entries) {
        final columns = entry.value;
        // Preflight database sizes before materializing content or BLOBs.
        final lengths = columns
            .map((c) => 'COALESCE(length(CAST($c AS BLOB)),0)')
            .join('+');
        final estimate = await database
            .customSelect(
              'SELECT COUNT(*) AS n, COALESCE(SUM($lengths),0) AS bytes FROM ${entry.key}',
            )
            .getSingle();
        count += estimate.read<int>('n');
        size += estimate.read<int>('bytes');
        if (count > ReadingBackup.maxRows ||
            size > ReadingBackup.maxDataBytes) {
          throw const FormatException('书库超过当前备份上限（32 MB 数据 / 50,000 条记录）。');
        }
        final rows = await database
            .customSelect(
              'SELECT ${columns.join(',')} FROM ${entry.key} ORDER BY rowid',
            )
            .get();
        tables[entry.key] = rows
            .map(
              (row) => columns.map((c) {
                final v = row.data[c];
                return v is Uint8List ? base64Encode(v) : v;
              }).toList(),
            )
            .toList();
      }
      return <String, Object?>{
        'format': 'Reading backup',
        'schema': 7,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'tables': tables,
      };
    });
    return compute(ReadingBackup.encode, data);
  }

  Future<void> restore(ReadingBackup backup) => database.transaction(() async {
    for (final table in backupColumns.keys.toList().reversed) {
      await database.customStatement('DELETE FROM $table');
    }
    for (final entry in backupColumns.entries) {
      for (final row in backup.rows[entry.key]!) {
        await database.customStatement(
          'INSERT INTO ${entry.key}(${entry.value.join(',')}) VALUES(${List.filled(entry.value.length, '?').join(',')})',
          row,
        );
      }
    }
  });
}

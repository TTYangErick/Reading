import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../book/book.dart';

class ReadingDatabase extends GeneratedDatabase {
  ReadingDatabase(super.e);
  factory ReadingDatabase.open() => ReadingDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(directory.path, 'reading.sqlite')),
      );
    }),
  );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        '''CREATE TABLE books(id TEXT PRIMARY KEY, title TEXT NOT NULL,
      content TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, style TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, last_read_at INTEGER NOT NULL DEFAULT 0)''',
      );
      await customStatement(
        'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
  );
  Future<List<Book>> books() async => (await customSelect(
    'SELECT * FROM books ORDER BY last_read_at DESC, created_at DESC',
  ).get()).map(_book).toList();
  Book _book(QueryRow row) => Book(
    id: row.read('id'),
    title: row.read('title'),
    content: BookContent.decode(row.read('content')),
    position: row.read('position'),
    createdAt: row.read('created_at'),
    updatedAt: row.read('updated_at'),
    lastReadAt: row.read('last_read_at'),
    style: row.readNullable('style'),
  );
  Future<Book?> book(String id) async {
    final row = await customSelect(
      'SELECT * FROM books WHERE id=?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    return row == null ? null : _book(row);
  }

  Future<String> addBook(String title, BookContent content) async {
    final id = const Uuid().v4(), now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
      'INSERT INTO books(id,title,content,created_at,updated_at) VALUES(?,?,?,?,?)',
      [id, title, content.encode(), now, now],
    );
    return id;
  }

  Future<void> rename(String id, String title) => customStatement(
    'UPDATE books SET title=?,updated_at=? WHERE id=?',
    [title, DateTime.now().millisecondsSinceEpoch, id],
  );
  Future<void> deleteBook(String id) =>
      customStatement('DELETE FROM books WHERE id=?', [id]);
  Future<void> savePosition(String id, int position) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return customStatement(
      'UPDATE books SET position=?,last_read_at=?,updated_at=? WHERE id=?',
      [position, now, now, id],
    );
  }

  Future<void> saveStyle(String id, String? style) => customStatement(
    'UPDATE books SET style=?,updated_at=? WHERE id=?',
    [style, DateTime.now().millisecondsSinceEpoch, id],
  );
  Future<String?> setting(String key) async => (await customSelect(
    'SELECT value FROM settings WHERE key=?',
    variables: [Variable(key)],
  ).getSingleOrNull())?.read<String>('value');
  Future<void> setSetting(String key, String value) => customStatement(
    'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
}

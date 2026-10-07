import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../book/book.dart';
import '../db/database.dart';
import '../reader/book_pagination.dart';

class Bookmark {
  const Bookmark(
    this.id,
    this.bookId,
    this.location,
    this.excerpt,
    this.createdAt,
  );
  final String id, bookId, location, excerpt;
  final int createdAt;

  PageAnchor? resolve(Book book) {
    if (book.id != bookId || location.length > 16384) return null;
    final anchor = PageAnchor.decode(location);
    return anchor != null && valid(book, anchor) ? anchor : null;
  }

  static bool valid(Book book, PageAnchor anchor) {
    if (PageAnchor.decode(anchor.encode()) == null) return false;
    final p = anchor.position;
    final blocks = p.document == null
        ? book.content.blocks
        : book.content.supplementaryDocuments[p.document];
    if (blocks == null || p.block < 0 || p.block >= blocks.length) return false;
    final block = blocks[p.block];
    return switch (anchor.part) {
      PagePart.text =>
        block.image == null &&
            block.rows == null &&
            p.offset <= block.text.length,
      PagePart.caption => block.image != null && p.offset <= block.text.length,
      PagePart.image => block.image != null,
      PagePart.tableRow =>
        block.rows != null &&
            anchor.row! < (block.rows!.isEmpty ? 1 : block.rows!.length),
    };
  }

  static String describe(Book book, PageAnchor anchor) {
    final p = anchor.position;
    final blocks = p.document == null
        ? book.content.blocks
        : book.content.supplementaryDocuments[p.document]!;
    final block = blocks[p.block];
    final text = switch (anchor.part) {
      PagePart.tableRow =>
        block.rows!.isEmpty ? '空表格' : block.rows![anchor.row!].join(' · '),
      PagePart.image => block.text.isEmpty ? '图片' : block.text,
      _ => block.text.substring(p.offset),
    };
    final prefix = p.document == null ? '' : '脚注 / 补充内容 · ';
    return '$prefix${String.fromCharCodes(text.runes.take(160))}'.trim();
  }
}

extension BookmarkStorage on ReadingDatabase {
  Future<String> addBookmark(String bookId, PageAnchor anchor) =>
      transaction(() async {
        final source = await book(bookId);
        if (source == null || !Bookmark.valid(source, anchor)) {
          throw ArgumentError('Bookmark source is unavailable');
        }
        final now = DateTime.now().millisecondsSinceEpoch,
            location = anchor.encode();
        await customStatement(
          '''INSERT INTO bookmarks(id,book_id,location,excerpt,created_at,updated_at)
      VALUES(?,?,?,?,?,?) ON CONFLICT(book_id,location) DO NOTHING''',
          [
            const Uuid().v4(),
            bookId,
            location,
            Bookmark.describe(source, anchor),
            now,
            now,
          ],
        );
        return (await customSelect(
          'SELECT id FROM bookmarks WHERE book_id=? AND location=?',
          variables: [Variable(bookId), Variable(location)],
        ).getSingle()).read<String>('id');
      });

  Future<List<Bookmark>> bookmarks(String bookId) async =>
      (await customSelect(
            'SELECT * FROM bookmarks WHERE book_id=? ORDER BY created_at DESC,rowid DESC',
            variables: [Variable(bookId)],
          ).get())
          .map(
            (r) => Bookmark(
              r.read('id'),
              r.read('book_id'),
              r.read('location'),
              r.read('excerpt'),
              r.read('created_at'),
            ),
          )
          .toList();

  Future<void> deleteBookmark(String bookId, String id) => customStatement(
    'DELETE FROM bookmarks WHERE book_id=? AND id=?',
    [bookId, id],
  );
}

import 'dart:convert';

import '../book/book.dart';
import '../reader/book_pagination.dart';
import '../text/language.dart';
import 'vocabulary.dart';

/// Validates against the current source instead of clamping a stale location.
class VocabularySource {
  const VocabularySource(this.position, this.anchor, this.cell);
  final BookPosition position;
  final PageAnchor anchor;
  final String? cell;

  static VocabularySource? resolve(Book book, VocabularyDraft draft) {
    try {
      if (book.id != draft.bookId ||
          draft.location.length > 16384 ||
          draft.word.isEmpty) {
        return null;
      }
      final data = jsonDecode(draft.location) as Map<String, dynamic>;
      if (data['version'] != 1) return null;
      final position = BookPosition.fromJson(
        data['position'] as Map<String, dynamic>,
      );
      final blocks = position.document == null
          ? book.content.blocks
          : book.content.supplementaryDocuments[position.document];
      if (blocks == null ||
          position.block < 0 ||
          position.block >= blocks.length ||
          position.offset < 0) {
        return null;
      }
      final block = blocks[position.block];
      final cell = data['cell'] as String?;
      var text = block.text;
      var part = PagePart.text;
      int? row;
      if (cell == 'caption') {
        if (block.image == null) return null;
        part = PagePart.caption;
      } else if (cell != null) {
        if (!RegExp(r'^\d+-\d+$').hasMatch(cell)) return null;
        final coordinates = cell.split('-').map(int.parse).toList();
        row = coordinates[0];
        final column = coordinates[1];
        final rows = block.rows;
        if (rows == null || row >= rows.length || column >= rows[row].length) {
          return null;
        }
        text = rows[row][column];
        part = PagePart.tableRow;
      } else if (block.image != null || block.rows != null) {
        return null;
      }
      final end = position.offset + draft.word.length;
      if (end > text.length ||
          text.substring(position.offset, end) != draft.word ||
          EnglishLanguage().sentenceAt(text, position.offset).text !=
              draft.sentence) {
        return null;
      }
      return VocabularySource(
        position,
        PageAnchor(
          BookPosition(
            position.block,
            offset: row == null ? position.offset : 0,
            document: position.document,
          ),
          part: part,
          row: row,
        ),
        cell,
      );
    } catch (_) {
      return null;
    }
  }
}

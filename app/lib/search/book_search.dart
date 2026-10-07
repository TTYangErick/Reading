import '../book/book.dart';
import '../reader/book_pagination.dart';

class BookSearchHit {
  const BookSearchHit({
    required this.position,
    required this.end,
    required this.anchor,
    required this.text,
    required this.label,
    this.cell,
  });
  final BookPosition position;
  final int end;
  final PageAnchor anchor;
  final String text, label;
  final String? cell;
  String get match => text.substring(position.offset, end);
  String get previewMatch =>
      text.substring(
        position.offset,
        _safeEnd(text, (position.offset + 200).clamp(position.offset, end)),
      ) +
      (end - position.offset > 200 ? '…' : '');
  String get before => text.substring(
    _safeStart(text, (position.offset - 55).clamp(0, text.length)),
    position.offset,
  );
  String get after =>
      text.substring(end, _safeEnd(text, (end + 80).clamp(0, text.length)));
  static int _safeStart(String s, int i) =>
      i > 0 &&
          i < s.length &&
          s.codeUnitAt(i) >= 0xdc00 &&
          s.codeUnitAt(i) <= 0xdfff
      ? i - 1
      : i;
  static int _safeEnd(String s, int i) =>
      i > 0 &&
          i < s.length &&
          s.codeUnitAt(i) >= 0xdc00 &&
          s.codeUnitAt(i) <= 0xdfff
      ? i + 1
      : i;

  bool valid(BookContent content) {
    final blocks = position.document == null
        ? content.blocks
        : content.supplementaryDocuments[position.document];
    if (blocks == null ||
        position.block < 0 ||
        position.block >= blocks.length ||
        position.offset < 0 ||
        end <= position.offset) {
      return false;
    }
    final block = blocks[position.block];
    var source = block.text;
    if (cell == 'caption') {
      if (block.image == null) return false;
    } else if (cell != null) {
      final parts = cell!.split('-').map(int.tryParse).toList();
      if (parts.length != 2 || parts.any((p) => p == null || p < 0)) {
        return false;
      }
      final rows = block.rows, row = parts[0]!, col = parts[1]!;
      if (rows == null || row >= rows.length || col >= rows[row].length) {
        return false;
      }
      source = rows[row][col];
    } else if (block.image != null || block.rows != null) {
      return false;
    }
    return source == text && end <= source.length;
  }
}

enum SearchLimit { results, text }

class BookSearchResult {
  const BookSearchResult(this.hits, {this.limit});
  final List<BookSearchHit> hits;
  final SearchLimit? limit;
}

class _Segment {
  const _Segment(
    this.text,
    this.position,
    this.part,
    this.label, {
    this.row,
    this.cell,
  });
  final String text, label;
  final BookPosition position;
  final PagePart part;
  final int? row;
  final String? cell;
}

/// Literal streaming KMP: bounded memory and raw UTF-16 offsets, including
/// Unicode lowercase expansions. Each block/cell is a separate search segment.
class BookSearch {
  const BookSearch({this.maxResults = 500, this.maxUnits = 20000000});
  final int maxResults, maxUnits;
  static final _space = RegExp(r'\s', unicode: true);
  static String normalized(String value, bool caseSensitive) =>
      (caseSensitive
              ? value
              : value.runes
                    .map((r) => String.fromCharCode(r).toLowerCase())
                    .join())
          .replaceAll(RegExp(r'\s+', unicode: true), ' ')
          .trim();

  Iterable<_Segment> _segments(BookContent content) sync* {
    for (final document in <String?>[
      null,
      ...content.supplementaryDocuments.keys,
    ]) {
      final blocks = document == null
          ? content.blocks
          : content.supplementaryDocuments[document]!;
      for (var b = 0; b < blocks.length; b++) {
        final block = blocks[b], p = BookPosition(b, document: document);
        final label = document == null
            ? '正文 · 第 ${b + 1} 段'
            : '脚注 / 补充内容 · 第 ${b + 1} 段';
        if (block.rows != null) {
          if (block.rows!.isEmpty) {
            yield _Segment('', p, PagePart.tableRow, label, row: 0);
          }
          for (var r = 0; r < block.rows!.length; r++) {
            if (block.rows![r].isEmpty) {
              yield _Segment('', p, PagePart.tableRow, label, row: r);
            }
            for (var c = 0; c < block.rows![r].length; c++) {
              yield _Segment(
                block.rows![r][c],
                p,
                PagePart.tableRow,
                '$label · 表格 ${r + 1} 行 ${c + 1} 列',
                row: r,
                cell: '$r-$c',
              );
            }
          }
        } else {
          yield _Segment(
            block.text,
            p,
            block.image == null ? PagePart.text : PagePart.caption,
            block.image == null ? label : '$label · 图注',
            cell: block.image == null ? null : 'caption',
          );
        }
      }
    }
  }

  Future<BookSearchResult?> find(
    BookContent content,
    String query, {
    bool caseSensitive = false,
    bool Function()? cancelled,
  }) async {
    if (query.length > 200) throw ArgumentError('Search query is too long');
    final needle = normalized(query, caseSensitive).codeUnits;
    if (needle.isEmpty) return const BookSearchResult([]);
    final prefix = List<int>.filled(needle.length, 0);
    for (var i = 1, j = 0; i < needle.length; i++) {
      while (j > 0 && needle[i] != needle[j]) {
        j = prefix[j - 1];
      }
      if (needle[i] == needle[j]) j++;
      prefix[i] = j;
    }
    final hits = <BookSearchHit>[];
    var units = 0, work = 0, segments = 0;
    for (final segment in _segments(content)) {
      if (cancelled?.call() == true) return null;
      if (++segments > 100000) {
        return BookSearchResult(
          List.unmodifiable(hits),
          limit: SearchLimit.text,
        );
      }
      var matched = 0, ordinal = 0, wasSpace = false;
      final starts = List<int>.filled(needle.length, 0);
      for (var i = 0; i < segment.text.length;) {
        if (units >= maxUnits) {
          return BookSearchResult(
            List.unmodifiable(hits),
            limit: SearchLimit.text,
          );
        }
        final start = i, first = segment.text.codeUnitAt(i++);
        if (first >= 0xd800 && first <= 0xdbff && i < segment.text.length) {
          final next = segment.text.codeUnitAt(i);
          if (next >= 0xdc00 && next <= 0xdfff) i++;
        }
        units += i - start;
        work += i - start;
        var token = segment.text.substring(start, i);
        final isSpace = _space.hasMatch(token);
        if (!isSpace || !wasSpace) {
          token = isSpace
              ? ' '
              : caseSensitive
              ? token
              : token.toLowerCase();
          for (final unit in token.codeUnits) {
            starts[ordinal % needle.length] = start;
            ordinal++;
            while (matched > 0 && unit != needle[matched]) {
              matched = prefix[matched - 1];
            }
            if (unit == needle[matched]) matched++;
            if (matched == needle.length) {
              final offset = starts[(ordinal - needle.length) % needle.length];
              if (hits.length == maxResults) {
                return BookSearchResult(
                  List.unmodifiable(hits),
                  limit: SearchLimit.results,
                );
              }
              final p = BookPosition(
                segment.position.block,
                offset: offset,
                document: segment.position.document,
              );
              hits.add(
                BookSearchHit(
                  position: p,
                  end: i,
                  text: segment.text,
                  label: segment.label,
                  cell: segment.cell,
                  anchor: PageAnchor(
                    segment.part == PagePart.tableRow ? segment.position : p,
                    part: segment.part,
                    row: segment.row,
                  ),
                ),
              );
              matched = prefix[matched - 1];
            }
          }
        }
        wasSpace = isSpace;
        if (work >= 8192) {
          work = 0;
          await Future<void>.delayed(Duration.zero);
          if (cancelled?.call() == true) return null;
        }
      }
      if (++work >= 8192) {
        work = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return cancelled?.call() == true
        ? null
        : BookSearchResult(List.unmodifiable(hits));
  }
}

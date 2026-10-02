import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'book.dart';

/// Reflowable EPUB 2/3. Book resources stay local and are never executed.
class EpubParser implements BookParser {
  static const maxFileSize = 50 * 1024 * 1024;
  @override
  Set<String> get extensions => {'epub'};
  @override
  BookContent parse(Uint8List bytes) {
    if (bytes.length > maxFileSize) {
      throw const FormatException('EPUB 超过 50 MB，请使用较小的文件。');
    }
    try {
      return _Epub(bytes).read();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取 EPUB，文件可能损坏或使用了不支持的格式。');
    }
  }
}

class _LimitedBytes implements Sink<List<int>> {
  final int limit;
  final builder = BytesBuilder(copy: false);
  _LimitedBytes(this.limit);
  @override
  void add(List<int> data) {
    if (builder.length + data.length > limit) {
      throw const FormatException('EPUB 解压大小异常，无法导入。');
    }
    builder.add(data);
  }

  @override
  void close() {}
}

class _Epub {
  final files = <String, zip.ZipFileHeader>{};
  final cache = <String, Uint8List>{};
  final blocks = <BookBlock>[];
  final targets = <String, int>{};
  final assets = <String, Uint8List>{};
  final chapters = <BookChapter>[];
  _Epub(Uint8List bytes) {
    final directory = zip.ZipDirectory()..read(zip.InputMemoryStream(bytes));
    if (directory.fileHeaders.isEmpty || directory.fileHeaders.length > 10000) {
      throw const FormatException('EPUB 文件为空、损坏或文件数量过多。');
    }
    var total = 0;
    for (final header in directory.fileHeaders) {
      final name = header.filename;
      if (name.endsWith('/')) continue;
      if (name.startsWith('/') ||
          name.contains('\\') ||
          name.split('/').contains('..') ||
          files.containsKey(name) ||
          ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
        throw const FormatException('EPUB 内的文件路径无效。');
      }
      if ((header.generalPurposeBitFlag & 1) != 0 ||
          ((header.file?.flags ?? 0) & 1) != 0) {
        throw const FormatException('暂不支持加密或受 DRM 保护的 EPUB。');
      }
      total += header.uncompressedSize;
      if (header.uncompressedSize > 20 * 1024 * 1024 ||
          total > 150 * 1024 * 1024) {
        throw const FormatException('EPUB 解压后过大，请拆分后导入。');
      }
      if (header.compressionMethod != 0 && header.compressionMethod != 8) {
        throw const FormatException('EPUB 使用了不支持的压缩方式。');
      }
      files[name] = header;
    }
  }

  Uint8List data(String name) => cache.putIfAbsent(name, () {
    final header = files[name];
    if (header?.file == null) throw FormatException('EPUB 缺少文件：$name');
    final input = header!.file!.getStream(decompress: false);
    final output = _LimitedBytes(header.uncompressedSize);
    final sink = header.compressionMethod == 8
        ? io.ZLibDecoder(raw: true).startChunkedConversion(output)
        : output;
    while (!input.isEOS) {
      sink.add(
        input
            .readBytes(input.length < 8192 ? input.length : 8192)
            .toUint8List(),
      );
    }
    sink.close();
    final decoded = output.builder.takeBytes();
    if (decoded.length != header.uncompressedSize ||
        zip.getCrc32(decoded) != header.crc32) {
      throw const FormatException('EPUB 文件校验失败，请重新下载。');
    }
    return decoded;
  });

  String text(String path) => utf8.decode(data(path));
  XmlDocument xml(String path) => XmlDocument.parse(text(path));
  Iterable<XmlElement> elements(XmlNode node, String name) => node.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);

  String resolve(String base, String href) {
    final uri = Uri.parse(href);
    if (uri.hasScheme || uri.hasAuthority || uri.path.startsWith('/')) {
      throw const FormatException('EPUB 引用了书籍外的资源。');
    }
    final path = uri.path.isEmpty
        ? base
        : p.posix.normalize(
            p.posix.join(p.posix.dirname(base), Uri.decodeComponent(uri.path)),
          );
    if (p.posix.isAbsolute(path) ||
        path.startsWith('../') ||
        path == '..' ||
        path.contains('\\')) {
      throw const FormatException('EPUB 内的资源路径无效。');
    }
    return path;
  }

  BookContent read() {
    final container = xml('META-INF/container.xml');
    final root = elements(container, 'rootfile')
        .firstWhere(
          (e) =>
              e.getAttribute('media-type') == 'application/oebps-package+xml',
          orElse: () => elements(container, 'rootfile').first,
        )
        .getAttribute('full-path');
    if (root == null) throw const FormatException('EPUB 缺少内容清单。');
    final opfPath = resolve('', root);
    final opf = xml(opfPath);
    if (elements(opf, 'meta').any(
      (e) =>
          e.getAttribute('property') == 'rendition:layout' &&
          e.innerText.trim() == 'pre-paginated',
    )) {
      throw const FormatException('当前支持可重排 EPUB，固定版式教材暂不支持。');
    }
    final manifest = <String, XmlElement>{
      for (final e in elements(opf, 'item'))
        if (e.getAttribute('id') != null) e.getAttribute('id')!: e,
    };
    if (files.containsKey('META-INF/encryption.xml')) {
      for (final e in elements(
        xml('META-INF/encryption.xml'),
        'EncryptionMethod',
      )) {
        final algorithm = e.getAttribute('Algorithm');
        if (algorithm != 'http://www.idpf.org/2008/embedding' &&
            algorithm != 'http://ns.adobe.com/pdf/enc#RC') {
          throw const FormatException('暂不支持加密或受 DRM 保护的 EPUB。');
        }
      }
    }
    final spine = elements(opf, 'spine').first;
    final seen = <String>{};
    for (final ref in elements(spine, 'itemref')) {
      if (ref.getAttribute('linear') == 'no') continue;
      if ((ref.getAttribute('properties') ?? '').contains(
        'rendition:layout-pre-paginated',
      )) {
        throw const FormatException('当前不支持固定版式 EPUB 章节。');
      }
      final item = manifest[ref.getAttribute('idref')];
      if (item == null) throw const FormatException('EPUB 的章节清单不完整。');
      if (item.getAttribute('media-type') != 'application/xhtml+xml' &&
          item.getAttribute('media-type') != 'text/html') {
        throw const FormatException('EPUB 含有暂不支持的章节格式。');
      }
      final path = resolve(opfPath, item.getAttribute('href')!);
      if (!seen.add(path)) continue;
      targets[path] = blocks.length;
      final document = html.parse(text(path));
      final walker = _Blocks(this, path);
      walker.walk(document.body!);
      walker.flush();
    }
    if (blocks.isEmpty) throw const FormatException('EPUB 没有可阅读的正文。');
    final nav = manifest.values
        .where(
          (e) => (e.getAttribute('properties') ?? '')
              .split(RegExp(r'\s+'))
              .contains('nav'),
        )
        .firstOrNull;
    if (nav != null) {
      final path = resolve(opfPath, nav.getAttribute('href')!);
      final document = html.parse(text(path));
      final toc = document
          .querySelectorAll('nav')
          .where(
            (e) =>
                (e.attributes['epub:type'] ?? '').split(' ').contains('toc') ||
                e.attributes['role'] == 'doc-toc',
          )
          .firstOrNull;
      if (toc != null) {
        for (final link in toc.querySelectorAll('a[href]')) {
          var depth = -1;
          for (
            dom.Element? e = link.parent;
            e != null && e != toc;
            e = e.parent
          ) {
            if (e.localName == 'ol') depth++;
          }
          addChapter(
            path,
            link.attributes['href']!,
            link.text,
            depth.clamp(0, 8),
          );
        }
      }
    }
    if (chapters.isEmpty) {
      final ncx =
          manifest[spine.getAttribute('toc')] ??
          manifest.values
              .where(
                (e) =>
                    e.getAttribute('media-type') == 'application/x-dtbncx+xml',
              )
              .firstOrNull;
      if (ncx != null) {
        final path = resolve(opfPath, ncx.getAttribute('href')!);
        for (final point in elements(xml(path), 'navPoint')) {
          final label = elements(point, 'navLabel').firstOrNull;
          final src = elements(
            point,
            'content',
          ).firstOrNull?.getAttribute('src');
          var depth = 0;
          for (
            XmlNode? parent = point.parent;
            parent != null;
            parent = parent.parent
          ) {
            if (parent is XmlElement && parent.name.local == 'navPoint') {
              depth++;
            }
          }
          if (label != null && src != null) {
            addChapter(path, src, label.innerText, depth.clamp(0, 8));
          }
        }
      }
    }
    return BookContent(
      blocks,
      format: 'epub',
      assets: assets,
      chapters: chapters,
      title: elements(opf, 'title').firstOrNull?.innerText.trim(),
    );
  }

  void addChapter(String base, String href, String title, int depth) {
    final uri = Uri.parse(href);
    if (uri.hasScheme || uri.hasAuthority) return;
    final path = resolve(base, href);
    final fragment = Uri.decodeComponent(uri.fragment);
    final target =
        targets[fragment.isEmpty ? path : '$path#$fragment'] ?? targets[path];
    if (target != null && target < blocks.length && title.trim().isNotEmpty) {
      chapters.add(BookChapter(clean(title), target, depth: depth));
    }
  }
}

String clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

class _Blocks {
  final _Epub book;
  final String path;
  String buffer = '';
  bool heading = false;
  _Blocks(this.book, this.path);
  void flush() {
    final value = clean(buffer);
    if (value.isNotEmpty) book.blocks.add(BookBlock(value, heading: heading));
    buffer = '';
  }

  // Both HTML images and simple SVG wrappers use the same bounded local loader.
  void addImage(String src, String alt) {
    final uri = Uri.tryParse(src);
    final extension = p.posix.extension(uri?.path ?? '').toLowerCase();
    if (uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        const {'.png', '.jpg', '.jpeg', '.gif', '.webp'}.contains(extension)) {
      final resource = book.resolve(path, src);
      if (book.files.containsKey(resource)) {
        book.assets[resource] = book.data(resource);
        book.blocks.add(BookBlock(alt, image: resource));
      } else {
        book.blocks.add(BookBlock('[$alt：图片缺失]'));
      }
    } else {
      book.blocks.add(BookBlock('[$alt：暂不支持此图片格式]'));
    }
  }

  void addSvgImage(dom.Element svg) {
    final images = svg.children.where((e) => e.localName == 'image').toList();
    // Extract one raster image, not a partial rendering of arbitrary SVG.
    // Reject composition/effects and never descend into scripts/foreignObject.
    final simple =
        images.length == 1 &&
        svg.children.every(
          (e) =>
              const {'image', 'title', 'desc'}.contains(e.localName) &&
              e.children.isEmpty,
        ) &&
        [svg, ...svg.children].every(
          (e) => !const {
            'transform',
            'filter',
            'mask',
            'clip-path',
            'style',
            'hidden',
          }.any(e.attributes.containsKey),
        );
    final image = simple ? images.single : null;
    // package:html stores foreign namespaced attributes as AttributeName keys.
    final src =
        image?.attributes['href'] ??
        image?.attributes[const dom.AttributeName(
          'xlink',
          'href',
          'http://www.w3.org/1999/xlink',
        )];
    if (image == null || src == null || src.trim().isEmpty) {
      book.blocks.add(const BookBlock('[图片：暂不支持此 SVG 图形]'));
      return;
    }
    if (image.id.isNotEmpty) {
      book.targets['$path#${image.id}'] = book.blocks.length;
    }
    final title = clean(
      svg.children
          .where((e) => e.localName == 'title')
          .map((e) => e.text)
          .join(' '),
    );
    addImage(src, title.isEmpty ? '图片' : title);
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer += node.text;
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if (const {
          'script',
          'style',
          'head',
          'nav',
          'iframe',
          'object',
          'noscript',
        }.contains(tag) ||
        node.attributes.containsKey('hidden')) {
      return;
    }
    final block = const {
      'body',
      'section',
      'article',
      'div',
      'p',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'blockquote',
      'pre',
      'figure',
      'figcaption',
      'dl',
      'dt',
      'dd',
      'ul',
      'ol',
      'aside',
      'hr',
      'table',
      'img',
      'svg',
    }.contains(tag);
    if (block) flush();
    final id = node.id;
    if (id.isNotEmpty) book.targets['$path#$id'] = book.blocks.length;
    final wasHeading = heading;
    heading =
        const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(tag) || heading;
    if (tag == 'img') {
      final src = node.attributes['src'];
      if (src != null) addImage(src, node.attributes['alt'] ?? '图片');
    } else if (tag == 'svg') {
      addSvgImage(node);
    } else if (tag == 'table') {
      final caption = node.querySelector('caption');
      if (caption != null) book.blocks.add(BookBlock(clean(caption.text)));
      final rows = <List<String>>[];
      final complex =
          node
              .querySelectorAll('td,th')
              .any(
                (cell) =>
                    (int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1) !=
                        1 ||
                    (int.tryParse(cell.attributes['rowspan'] ?? '1') ?? 1) != 1,
              ) ||
          node.querySelector('table') != null;
      var hasHeader = false;
      for (final row in node.querySelectorAll('tr')) {
        var owner = row.parent;
        while (owner != null && owner.localName != 'table') {
          owner = owner.parent;
        }
        if (owner != node) continue;
        final cells = row.children
            .where((e) => e.localName == 'td' || e.localName == 'th')
            .toList();
        if (cells.isEmpty) continue;
        if (rows.isEmpty) hasHeader = cells.every((e) => e.localName == 'th');
        rows.add(cells.map((e) => clean(e.text)).toList());
      }
      if (complex) {
        book.blocks.add(const BookBlock('复杂表格（按行显示）'));
        book.blocks.addAll(rows.map((row) => BookBlock(row.join(' · '))));
      } else if (rows.isNotEmpty) {
        book.blocks.add(BookBlock('', rows: rows, tableHeader: hasHeader));
      }
    } else if (tag == 'br') {
      buffer += '\n';
    } else {
      if (tag == 'li') {
        final siblings =
            node.parent?.children.where((e) => e.localName == 'li').toList() ??
            [];
        buffer += node.parent?.localName == 'ol'
            ? '${siblings.indexOf(node) + 1}. '
            : '• ';
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }
    if (block) flush();
    heading = wasHeading;
  }
}

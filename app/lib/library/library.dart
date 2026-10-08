import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/backup_page.dart';
import '../book/book.dart';
import '../book/epub.dart';
import '../core/providers.dart';
import '../dict/management_page.dart';
import '../history/history_page.dart';
import '../imports/inbox.dart';
import '../main.dart';
import '../onboarding/reading_guide.dart';
import '../reader/reader.dart';
import '../reader/settings.dart';
import '../translate/cache_page.dart';
import '../vocab/vocabulary_page.dart';
import 'book_cover.dart';

BookContent parseImportedFile((String, Uint8List) input) =>
    ParserRegistry([TxtParser(), EpubParser()]).parse(input.$1, input.$2);

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String query = '';
  bool importing = false;
  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> openBook(Book book) async {
    final style = await ref.read(globalStyleProvider.future);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReaderPage(book: book, defaultStyle: style),
      ),
    );
    ref.invalidate(booksProvider);
  }

  Future<void> add(
    String title,
    BookContent content, {
    Future<void> Function()? onSaved,
  }) async {
    final database = ref.read(databaseProvider);
    final id = await database.addBook(
      title.trim().isEmpty ? '未命名文本' : title.trim(),
      content,
    );
    await onSaved?.call();
    final book = await database.book(id);
    ref.invalidate(booksProvider);
    if (mounted && book != null) await openBook(book);
  }

  Future<void> importReceived(IncomingBook item) async {
    if (importing || !item.ready || item.path == null) return;
    setState(() => importing = true);
    try {
      final content = await compute(parseReceivedFile, (item.name, item.path!));
      if (!mounted) return;
      await add(
        content.title?.isNotEmpty == true
            ? content.title!
            : item.name.replaceFirst(
                RegExp(r'\.(txt|epub)$', caseSensitive: false),
                '',
              ),
        content,
        onSaved: () => ref.read(importInboxProvider.notifier).release(item.id),
      );
    } catch (error) {
      // Keep failed input available for explicit dismissal/retry. No partial
      // book is inserted: parsing completes before the database transaction.
      message(error is FormatException ? error.message : '导入失败，请重新分享文件后重试。');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> importFile() async {
    if (importing) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub'],
      );
      if (file == null || !mounted) return;
      setState(() => importing = true);
      final size = await file.length();
      final epub = file.name.toLowerCase().endsWith('.epub');
      final limit = epub ? EpubParser.maxFileSize : 20 * 1024 * 1024;
      if (size != null && size > limit) {
        throw FormatException(
          epub ? 'EPUB 超过 50 MB，请使用较小的文件。' : '文本超过 20 MB，请先拆分后导入。',
        );
      }
      final content = await compute(parseImportedFile, (
        file.name,
        await file.readAsBytes(),
      ));
      if (!mounted) return;
      await add(
        content.title?.isNotEmpty == true
            ? content.title!
            : file.name.replaceFirst(
                RegExp(r'\.(txt|epub)$', caseSensitive: false),
                '',
              ),
        content,
      );
    } catch (error) {
      message(error is FormatException ? error.message : '导入失败，请确认文件可以读取后重试。');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> sample() async {
    try {
      await add(
        'Pride and Prejudice · 示例节选',
        TxtParser().parseText(
          await rootBundle.loadString('assets/samples/pride.txt'),
        ),
      );
    } catch (_) {
      message('示例暂时无法打开。');
    }
  }

  void importMenu() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '添加一本书',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              subtitle: Text('保存在设备上，随时离线阅读'),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('导入 EPUB / TXT'),
              subtitle: const Text('支持 UTF-8 和 GBK 编码'),
              onTap: () {
                Navigator.pop(context);
                importFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴文本'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  this.context,
                  MaterialPageRoute<void>(
                    builder: (_) => PastePage(onAdd: add),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('阅读示例节选'),
              subtitle: const Text('Pride and Prejudice · Jane Austen'),
              onTap: () {
                Navigator.pop(context);
                sample();
              },
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> edit(Book book, bool delete) async {
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这本书？'),
          content: Text('“${book.title}”和它的阅读位置将从设备移除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(databaseProvider).deleteBook(book.id);
        ref.read(paginationCacheProvider).removeBook(book.id);
        ref.invalidate(booksProvider);
      }
    } else {
      final controller = TextEditingController(text: book.title);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改书名'),
          content: TextField(
            key: const ValueKey('rename-title'),
            controller: controller,
            autofocus: true,
            maxLength: 160,
            decoration: const InputDecoration(labelText: '书名'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
      if (name != null) {
        await ref.read(databaseProvider).rename(book.id, name);
        ref.invalidate(booksProvider);
      }
    }
  }

  Future<void> preferences() async {
    final style = await ref.read(globalStyleProvider.future);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReaderSettings(
        style: style,
        onChanged: (value) async {
          await ref
              .read(databaseProvider)
              .setSetting('readerStyle', value.encode());
          ref.invalidate(globalStyleProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(importInboxProvider);
    final books = ref.watch(booksProvider);
    final page = Scaffold(
      appBar: AppBar(
        title: const Text(
          'READING',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '默认阅读设置',
            onPressed: importing ? null : preferences,
            icon: const Icon(Icons.tune, size: 21),
          ),
          PopupMenuButton<String>(
            enabled: !importing,
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'reading-guide') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ReadingGuidePage(),
                  ),
                );
              } else if (value == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
                );
              } else if (value == 'backup') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const BackupPage()),
                );
              } else if (value == 'vocabulary') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const VocabularyPage(),
                  ),
                );
              } else if (value == 'dictionaries') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const DictionaryManagementPage(),
                  ),
                );
              } else if (value == 'translation-cache') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const TranslationCachePage(),
                  ),
                );
              } else {
                showAcknowledgments(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'reading-guide',
                child: Text('阅读与离线准备'),
              ),
              const PopupMenuItem(value: 'backup', child: Text('备份与恢复')),
              const PopupMenuItem(value: 'vocabulary', child: Text('生词本')),
              const PopupMenuItem(value: 'history', child: Text('查词历史')),
              const PopupMenuItem(value: 'dictionaries', child: Text('词典管理')),
              const PopupMenuItem(
                value: 'translation-cache',
                child: Text('翻译缓存'),
              ),
              const PopupMenuItem(value: 'license', child: Text('开源许可与致谢')),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: books.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('书架暂时无法打开'),
                    TextButton(
                      onPressed: () => ref.invalidate(booksProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final visible = all
                    .where(
                      (b) =>
                          b.title.toLowerCase().contains(query.toLowerCase()),
                    )
                    .toList();
                return CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '书架',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const Spacer(),
                                IconButton.filled(
                                  key: const ValueKey('add-book'),
                                  tooltip: '添加书籍',
                                  onPressed: importing ? null : importMenu,
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              all.isEmpty
                                  ? '从一段文字，开始阅读。'
                                  : '${all.length} 本书 · 按最近阅读排序',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ImportInboxCards(
                              items: incoming,
                              busy: importing,
                              onImport: importReceived,
                              onIgnore: (id) => ref
                                  .read(importInboxProvider.notifier)
                                  .release(id),
                            ),
                            const ReadingGuideCard(),
                            TextField(
                              key: const ValueKey('search-books'),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) =>
                                  FocusScope.of(context).unfocus(),
                              decoration: InputDecoration(
                                hintText: '搜索书名',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                filled: true,
                                fillColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (value) =>
                                  setState(() => query = value),
                            ),
                            if (importing)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: LinearProgressIndicator(),
                              ),
                            const SizedBox(height: 28),
                            if (query.isEmpty &&
                                all.isNotEmpty &&
                                all.first.lastReadAt > 0) ...[
                              InkWell(
                                onTap: () => openBook(all.first),
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.menu_book_outlined,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '继续阅读 · ${(all.first.progress * 100).round()}%',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF927152),
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              all.first.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (all.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(36, 32, 36, 48),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.auto_stories_outlined,
                                size: 72,
                                color: Color(0xFFAA967E),
                              ),
                              const SizedBox(height: 26),
                              const Text(
                                '把想读的文字放进来',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '点一下单词，意思就在旁边。\n按自己的节奏，慢慢读下去。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.8,
                                  color: Color(0xFF888078),
                                ),
                              ),
                              const SizedBox(height: 28),
                              FilledButton.icon(
                                onPressed: importing ? null : importMenu,
                                icon: const Icon(Icons.add, size: 19),
                                label: const Text('添加第一本书'),
                              ),
                              TextButton(
                                onPressed: sample,
                                child: const Text('先读一段示例'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (all.isNotEmpty && visible.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('没有找到这本书')),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.crossAxisExtent >= 700
                              ? 4
                              : constraints.crossAxisExtent >= 490
                              ? 3
                              : 2;
                          final width =
                              (constraints.crossAxisExtent -
                                  (columns - 1) * 22) /
                              columns;
                          return SliverGrid(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final book = visible[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: width * 1.4,
                                    child: GestureDetector(
                                      onTap: () => openBook(book),
                                      onLongPress: () => edit(book, false),
                                      child: BookCover(book: book),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          book.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 24,
                                        height: 32,
                                        child: PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          tooltip: '管理 ${book.title}',
                                          onSelected: (value) =>
                                              edit(book, value == 'delete'),
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'rename',
                                              child: Text('修改书名'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除'),
                                            ),
                                          ],
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (book.content.authors.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      book.content.authors.join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    book.lastReadAt == 0
                                        ? '尚未阅读'
                                        : '${(book.progress * 100).round()}% 已读',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF888078),
                                    ),
                                  ),
                                ],
                              );
                            }, childCount: visible.length),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 22,
                                  mainAxisSpacing: 26,
                                  mainAxisExtent: width * 1.4 + 92,
                                ),
                          );
                        },
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return AbsorbPointer(
      key: const ValueKey('library-import-lock'),
      absorbing: importing,
      child: page,
    );
  }
}

class PastePage extends StatefulWidget {
  final Future<void> Function(String, BookContent) onAdd;
  const PastePage({super.key, required this.onAdd});
  @override
  State<PastePage> createState() => _PastePageState();
}

class _PastePageState extends State<PastePage> {
  final title = TextEditingController(), body = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    BookContent content;
    try {
      content = TxtParser().parseText(body.text);
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return;
    }
    setState(() => busy = true);
    final name = title.text, callback = widget.onAdd;
    Navigator.pop(context);
    await callback(name, content);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('粘贴文本'),
      actions: [
        TextButton(
          key: const ValueKey('save-paste'),
          onPressed: busy ? null : submit,
          child: const Text('开始阅读'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            key: const ValueKey('paste-title'),
            controller: title,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: '书名',
              hintText: '给这段文字起个名字',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('paste-body'),
              controller: body,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: '在这里粘贴英文文本…',
                errorText: error,
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 17, height: 1.6),
            ),
          ),
        ],
      ),
    ),
  );
}

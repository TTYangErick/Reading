import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../reader/reader.dart';
import 'export.dart';
import 'source.dart';
import 'vocabulary.dart';

class VocabularyPage extends ConsumerStatefulWidget {
  const VocabularyPage({super.key});
  @override
  ConsumerState<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends ConsumerState<VocabularyPage> {
  List<VocabularyItem> items = [];
  String query = '', book = '';
  bool loading = true, failed = false, newest = true;
  int generation = 0;
  bool openingSource = false;
  bool exporting = false;

  Future<void> export(List<VocabularyItem> shown) async {
    if (exporting || loading || failed || items.isEmpty) return;
    setState(() => exporting = true);
    final current = List<VocabularyItem>.of(shown);
    final all = newest
        ? List<VocabularyItem>.of(items)
        : items.reversed.toList();
    try {
      final selected = await showDialog<List<VocabularyItem>>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('导出 CSV'),
          children: [
            SimpleDialogOption(
              onPressed: current.isEmpty
                  ? null
                  : () => Navigator.pop(context, current),
              child: Text(
                '当前列表（${current.length} 条）',
                style: current.isEmpty
                    ? TextStyle(color: Theme.of(context).disabledColor)
                    : null,
              ),
            ),
            if (query.trim().isNotEmpty || book.isNotEmpty)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, all),
                child: Text('全部生词（${all.length} 条）'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final bytes = const CsvVocabExporter().encode(selected);
      final saved = await FilePicker.saveFile(
        fileName:
            'Reading-vocabulary-${DateTime.now().millisecondsSinceEpoch}.csv',
        bytes: bytes,
        mimeType: 'text/csv',
        dialogTitle: '保存生词 CSV',
      );
      if (!mounted || saved == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已导出 ${selected.length} 条生词')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('导出失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final current = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await ref.read(databaseProvider).vocabulary();
      if (!mounted || current != generation) return;
      setState(() {
        items = result;
        if (!items.any((i) => i.draft.bookId == book)) book = '';
      });
    } catch (_) {
      if (mounted && current == generation) setState(() => failed = true);
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  String date(int value) {
    final d = DateTime.fromMillisecondsSinceEpoch(value);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> openSource(VocabularyItem item) async {
    if (openingSource) return;
    openingSource = true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      final sourceBook = await ref
          .read(databaseProvider)
          .book(item.draft.bookId);
      if (!mounted) return;
      if (sourceBook == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('原书已不在书架中，收藏的原句仍然保留。')));
        return;
      }
      final source = VocabularySource.resolve(sourceBook, item.draft);
      if (source == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('原句位置已失效，收藏内容仍然保留。')));
        return;
      }
      final style = await ref.read(globalStyleProvider.future);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'vocabulary-source'),
          builder: (_) => ReaderPage.source(
            book: sourceBook,
            defaultStyle: style,
            target: source.position,
            anchor: source.anchor,
            cell: source.cell,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开原句，请重试。')));
      }
    } finally {
      openingSource = false;
    }
  }

  Future<void> remove(VocabularyItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条生词？'),
        content: Text('只删除“${item.draft.word}”的这条收藏。书籍和其他收藏会保留。'),
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(databaseProvider).deleteVocabulary(item.id);
      if (!mounted) return;
      setState(() {
        items.removeWhere((i) => i.id == item.id);
        if (!items.any((i) => i.draft.bookId == book)) book = '';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试。')));
      }
    }
  }

  void details(VocabularyItem item) {
    final v = item.draft;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(v.word),
        content: SingleChildScrollView(
          child: SelectableText(
            '${v.word != v.lemma ? '原形 ${v.lemma}\n\n' : ''}${v.gloss}\n\n原句\n${v.sentence}\n\n'
            '${v.bookTitle} · ${date(item.createdAt)}\n\n${v.source}\n${v.license}\n${v.sourceUrl}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openSource(item);
            },
            child: const Text('在书中查看原句'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = <String, String>{};
    for (final item in items) {
      books.putIfAbsent(item.draft.bookId, () => item.draft.bookTitle);
    }
    final term = query.trim().toLowerCase();
    final shown = items.where((i) {
      final v = i.draft;
      return (book.isEmpty || v.bookId == book) &&
          [
            v.word,
            v.lemma,
            v.gloss,
            v.sentence,
            v.bookTitle,
          ].any((s) => s.toLowerCase().contains(term));
    }).toList();
    if (!newest) {
      final reversed = shown.reversed.toList();
      shown
        ..clear()
        ..addAll(reversed);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('生词本'),
        actions: [
          IconButton(
            tooltip: exporting ? '正在导出' : '导出 CSV',
            onPressed: exporting || loading || failed || items.isEmpty
                ? null
                : () => export(shown),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: '刷新生词本',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    key: const ValueKey('vocabulary-search'),
                    decoration: const InputDecoration(
                      labelText: '搜索单词、释义或原句',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          key: const ValueKey('vocabulary-book'),
                          isExpanded: true,
                          value: book,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('全部书籍'),
                            ),
                            for (final b in books.entries)
                              DropdownMenuItem(
                                value: b.key,
                                child: Text(
                                  b.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => book = v ?? ''),
                        ),
                      ),
                      IconButton(
                        tooltip: newest ? '最新收藏在前' : '最早收藏在前',
                        onPressed: () => setState(() => newest = !newest),
                        icon: Icon(
                          newest ? Icons.arrow_downward : Icons.arrow_upward,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : failed
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('生词本暂时无法读取'),
                              TextButton(
                                onPressed: load,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              items.isEmpty
                                  ? '还没有收藏生词\n点词后展开释义，点击星标即可收藏。'
                                  : '没有匹配的生词',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final item = shown[index], v = item.draft;
                            return Card(
                              key: ValueKey('vocabulary-${item.id}'),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                onTap: () => details(item),
                                title: Text(
                                  v.word,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (v.word != v.lemma)
                                      Text('原形 ${v.lemma}'),
                                    const SizedBox(height: 6),
                                    Text(
                                      v.gloss,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: () => openSource(item),
                                      child: Text(
                                        v.sentence,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => openSource(item),
                                      icon: const Icon(
                                        Icons.menu_book,
                                        size: 16,
                                      ),
                                      label: const Text('在书中查看原句'),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${v.bookTitle} · ${date(item.createdAt)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${v.dictId == 'ecdict' ? '英汉 · ECDICT' : '英英 · Wiktionary'} · ${v.license}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  tooltip: '删除生词',
                                  onPressed: () => remove(item),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

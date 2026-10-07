import 'dart:async';

import 'package:flutter/material.dart';

import '../book/book.dart';
import 'book_search.dart';

class BookSearchPage extends StatefulWidget {
  const BookSearchPage({
    super.key,
    required this.content,
    required this.onOpen,
    this.search = const BookSearch(),
  });
  final BookContent content;
  final Future<void> Function(BookSearchHit, BuildContext) onOpen;
  final BookSearch search;
  @override
  State<BookSearchPage> createState() => _BookSearchPageState();
}

class _BookSearchPageState extends State<BookSearchPage> {
  final input = TextEditingController();
  Timer? debounce;
  int generation = 0;
  bool caseSensitive = false,
      searching = false,
      failed = false,
      opening = false;
  BookSearchResult? result;
  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  void changed({bool immediately = false}) {
    debounce?.cancel();
    final token = ++generation, query = input.text;
    setState(() {
      result = null;
      failed = false;
      searching = query.trim().isNotEmpty && query.length <= 200;
    });
    if (!searching) return;
    if (immediately) {
      run(token, query);
    } else {
      debounce = Timer(
        const Duration(milliseconds: 300),
        () => run(token, query),
      );
    }
  }

  Future<void> run(int token, String query) async {
    try {
      final found = await widget.search.find(
        widget.content,
        query,
        caseSensitive: caseSensitive,
        cancelled: () => !mounted || token != generation,
      );
      if (!mounted || token != generation || found == null) return;
      setState(() => result = found);
    } catch (_) {
      if (mounted && token == generation) setState(() => failed = true);
    } finally {
      if (mounted && token == generation) setState(() => searching = false);
    }
  }

  Future<void> open(BookSearchHit hit) async {
    if (opening) return;
    setState(() => opening = true);
    FocusScope.of(context).unfocus();
    try {
      await widget.onOpen(hit, context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开搜索结果，请重试。')));
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  String compact(String text) => text.replaceAll(RegExp(r'\s+'), ' ');
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('书内搜索')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: TextField(
                    key: const ValueKey('book-search-input'),
                    controller: input,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: '搜索本书文字',
                      hintText: '输入关键词或短语',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          input.clear();
                          changed();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                    onChanged: (_) => changed(),
                    onSubmitted: (_) => changed(immediately: true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('区分大小写'),
                        selected: caseSensitive,
                        onSelected: (v) {
                          caseSensitive = v;
                          changed(immediately: true);
                        },
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '含正文、图注、表格和脚注',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (result != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        result!.limit == SearchLimit.results
                            ? '仅显示前 ${result!.hits.length} 处，请缩小搜索范围'
                            : result!.limit == SearchLimit.text
                            ? '本书内容较多，搜索未覆盖全部内容；已找到 ${result!.hits.length} 处'
                            : '找到 ${result!.hits.length} 处',
                        key: const ValueKey('book-search-count'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                Expanded(
                  child: input.text.length > 200
                      ? const Center(child: Text('搜索内容过长，请缩短关键词'))
                      : searching
                      ? const Center(child: CircularProgressIndicator())
                      : failed
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('搜索暂时失败'),
                              TextButton(
                                onPressed: () => changed(immediately: true),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : result == null
                      ? const Center(child: Text('输入关键词，查找书中的位置'))
                      : result!.hits.isEmpty
                      ? Center(
                          child: Text(
                            result!.limit == SearchLimit.text
                                ? '已搜索部分未找到匹配内容'
                                : '没有找到匹配内容',
                          ),
                        )
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: result!.hits.length,
                          itemBuilder: (context, index) {
                            final hit = result!.hits[index];
                            return ListTile(
                              key: ValueKey('search-result-$index'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 6,
                              ),
                              onTap: opening ? null : () => open(hit),
                              title: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: compact(hit.before)),
                                    TextSpan(
                                      text: compact(hit.previewMatch),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        backgroundColor:
                                            colors.primaryContainer,
                                      ),
                                    ),
                                    TextSpan(text: compact(hit.after)),
                                  ],
                                ),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(hit.label),
                              trailing: const Icon(Icons.chevron_right),
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

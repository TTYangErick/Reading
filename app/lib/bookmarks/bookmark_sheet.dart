import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../reader/book_pagination.dart';
import 'bookmark.dart';

class BookmarkSheet extends ConsumerStatefulWidget {
  const BookmarkSheet({super.key, required this.bookId, required this.current});
  final String bookId;
  final PageAnchor? current;
  @override
  ConsumerState<BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends ConsumerState<BookmarkSheet> {
  List<Bookmark> items = [];
  bool loading = true, failed = false, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await ref.read(databaseProvider).bookmarks(widget.bookId);
      if (mounted) setState(() => items = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void message(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> add() async {
    if (busy || widget.current == null) return;
    setState(() => busy = true);
    try {
      await ref
          .read(databaseProvider)
          .addBookmark(widget.bookId, widget.current!);
      if (!mounted) return;
      await load();
    } catch (_) {
      if (mounted) message('添加书签失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Bookmark item) async {
    if (busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条书签？'),
        content: const Text('书籍和阅读进度会保留。'),
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
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(databaseProvider).deleteBookmark(widget.bookId, item.id);
      if (mounted) setState(() => items.removeWhere((i) => i.id == item.id));
    } catch (_) {
      if (mounted) message('删除书签失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = items.any((i) => i.location == widget.current?.encode());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '书签',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭书签',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('add-bookmark'),
                onPressed:
                    busy || loading || failed || saved || widget.current == null
                    ? null
                    : add,
                icon: Icon(
                  saved ? Icons.bookmark : Icons.bookmark_add_outlined,
                ),
                label: Text(
                  busy
                      ? '正在保存…'
                      : saved
                      ? '此位置已添加书签'
                      : widget.current == null
                      ? '排版完成后可添加书签'
                      : '添加当前位置',
                ),
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
                          const Text('书签暂时无法读取'),
                          TextButton(onPressed: load, child: const Text('重试')),
                        ],
                      ),
                    )
                  : items.isEmpty
                  ? const Center(child: Text('还没有书签'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index],
                            date = DateTime.fromMillisecondsSinceEpoch(
                              items[index].createdAt,
                            );
                        return ListTile(
                          key: ValueKey('bookmark-${item.id}'),
                          title: Text(
                            item.excerpt.isEmpty ? '阅读位置' : item.excerpt,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                          ),
                          onTap: busy
                              ? null
                              : () => Navigator.pop(context, item),
                          trailing: IconButton(
                            tooltip: '删除书签',
                            onPressed: busy ? null : () => remove(item),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

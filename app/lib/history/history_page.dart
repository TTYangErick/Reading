import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../dict/dictionary.dart';
import '../reader/bubble.dart';
import '../reader/style.dart';
import '../text/language.dart';
import 'history.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late Future<List<LookupRecord>> records;
  String query = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    records = ref.read(lookupHistoryProvider).recent();
  }

  void refresh() {
    final next = ref.read(lookupHistoryProvider).recent();
    setState(() {
      records = next;
    });
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空查词历史？'),
        content: const Text('只清空最近查过的词，书籍、生词收藏和译文缓存保持不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => busy = true);
    try {
      await ref.read(lookupHistoryProvider).clear();
      if (mounted) refresh();
    } catch (_) {
      notice('清空失败，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(LookupRecord record) async {
    if (busy) return;
    if (record.language != EnglishLanguage().code) {
      notice('当前版本暂不支持此学习语言。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final style = await ref.read(globalStyleProvider.future);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => HistoryLookupSheet(record: record, style: style),
      );
      if (mounted) refresh();
    } catch (_) {
      notice('暂时无法打开释义，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('查词历史'),
      actions: [
        IconButton(
          tooltip: '清空历史',
          onPressed: busy ? null : clear,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text('保留最近 200 个词，点击可重新查看释义。'),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  key: const ValueKey('history-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索查词历史',
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<LookupRecord>>(
                  future: records,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('查词历史暂时无法读取。'),
                            TextButton(
                              onPressed: refresh,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      );
                    }
                    final all = snapshot.data ?? [];
                    final visible = all
                        .where(
                          (r) => r.word.toLowerCase().contains(
                            query.trim().toLowerCase(),
                          ),
                        )
                        .toList();
                    return Column(
                      children: [
                        if (ref.read(lookupHistoryProvider).writeFailed)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('部分查词历史未能保存，已保存的记录仍可查看。'),
                          ),
                        Expanded(
                          child: all.isEmpty
                              ? const Center(child: Text('还没有查词历史，阅读时点一个词试试。'))
                              : visible.isEmpty
                              ? const Center(child: Text('没有匹配的记录。'))
                              : ListView.builder(
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final record = visible[index];
                                    final date =
                                        DateTime.fromMillisecondsSinceEpoch(
                                          record.lookedUpAt,
                                        );
                                    return ListTile(
                                      title: Text(record.word),
                                      subtitle: Text(
                                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: busy ? null : () => open(record),
                                    );
                                  },
                                ),
                        ),
                      ],
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

/// Re-query current dictionaries; no invented source sentence or vocabulary draft.
class HistoryLookupSheet extends ConsumerStatefulWidget {
  const HistoryLookupSheet({
    super.key,
    required this.record,
    required this.style,
  });
  final LookupRecord record;
  final ReaderStyle style;
  @override
  ConsumerState<HistoryLookupSheet> createState() => _HistoryLookupSheetState();
}

class _HistoryLookupSheetState extends ConsumerState<HistoryLookupSheet> {
  DictionaryEntry? entry;
  String? message = '正在打开离线词典…';
  bool failed = false;
  @override
  void initState() {
    super.initState();
    lookup();
  }

  Future<void> lookup() async {
    final history = ref.read(lookupHistoryProvider), word = widget.record.word;
    final generation = history.generation;
    setState(() {
      failed = false;
      message = '正在打开离线词典…';
    });
    try {
      final dictionary = await ref.read(dictionaryProvider.future);
      if (!mounted) return;
      final found = dictionary.lookup(word);
      setState(() {
        entry = found;
        message = null;
      });
      unawaited(
        history
            .record(widget.record.language, word, generation: generation)
            .catchError((Object _) {
              debugPrint('Lookup history could not be saved.');
            }),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        failed = true;
        message = '词典暂时无法打开，请重试。';
      });
      ref.invalidate(dictionaryProvider);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: WordBubble(
                word: widget.record.word,
                entry: entry,
                message: message,
                style: widget.style.withValue('tier', GlossTier.full.name),
                palette: widget.style.palette(Theme.of(context).brightness),
                expanded: false,
                // Full tier respects the chosen primary language instead of cross-language expansion.
                onExpand: () {},
                onClose: () => Navigator.pop(context),
                translateMissing: message == null && entry == null,
              ),
            ),
            if (failed)
              TextButton(onPressed: lookup, child: const Text('重试查词')),
          ],
        ),
      ),
    ),
  );
}

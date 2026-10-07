import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class TranslationCachePage extends ConsumerStatefulWidget {
  const TranslationCachePage({super.key});

  @override
  ConsumerState<TranslationCachePage> createState() =>
      _TranslationCachePageState();
}

class _TranslationCachePageState extends ConsumerState<TranslationCachePage> {
  late Future<int> count;
  bool clearing = false;
  String? message;

  @override
  void initState() {
    super.initState();
    count = ref.read(translatorProvider).cacheCount();
  }

  Future<void> clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部译文缓存？'),
        content: const Text('下次查看句子时会重新翻译。书籍、阅读位置、词典和已下载的语言模型会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      clearing = true;
      message = null;
    });
    try {
      await ref.read(translatorProvider).clearCache();
      if (!mounted) return;
      setState(() {
        count = ref.read(translatorProvider).cacheCount();
        message = '译文缓存已清除';
      });
    } catch (_) {
      if (mounted) setState(() => message = '清除失败，请重试。');
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('翻译缓存')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '保留译文，方便再次阅读',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text('已翻译的句子会保存在本机，再次查看时直接使用。最多保留 1000 条，超出后自动移除较早的缓存。'),
              const SizedBox(height: 24),
              FutureBuilder<int>(
                future: count,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('暂时无法读取缓存数量'),
                        TextButton(
                          onPressed: () => setState(() {
                            count = ref.read(translatorProvider).cacheCount();
                          }),
                          child: const Text('重试'),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final entries = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已缓存 $entries 条译文',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: entries == 0 || clearing ? null : clear,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(clearing ? '正在清除…' : '清除译文缓存'),
                      ),
                    ],
                  );
                },
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(message!, semanticsLabel: message),
                ),
              const SizedBox(height: 24),
              const Text('清理仅移除译文记录。已下载的语言模型继续保留，之后仍可离线重新翻译。'),
            ],
          ),
        ),
      ),
    ),
  );
}

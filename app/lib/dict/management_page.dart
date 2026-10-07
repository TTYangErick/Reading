import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'catalog.dart';

class DictionaryManagementPage extends ConsumerStatefulWidget {
  const DictionaryManagementPage({super.key});

  @override
  ConsumerState<DictionaryManagementPage> createState() =>
      _DictionaryManagementPageState();
}

class _DictionaryManagementPageState
    extends ConsumerState<DictionaryManagementPage> {
  late Future<List<DictionaryInfo>> dictionaries;

  @override
  void initState() {
    super.initState();
    dictionaries = inspect();
  }

  Future<List<DictionaryInfo>> inspect() {
    final result = ref.read(dictionaryCatalogProvider).inspect();
    // A refresh can fail before the next frame attaches FutureBuilder.
    // Keep its error available to the builder without an unhandled async error.
    result.ignore();
    return result;
  }

  void refresh() => setState(() {
    dictionaries = inspect();
  });

  String size(int? bytes) =>
      bytes == null ? '暂无法读取' : '${(bytes / 1000000).toStringAsFixed(1)} MB';

  Widget card(DictionaryInfo info) {
    final (status, description) = switch (info.availability) {
      DictionaryAvailability.ready => ('本地已就绪', '可以离线查词。'),
      DictionaryAvailability.notPrepared => ('内置 · 待准备', '首次查词时自动准备，无需联网。'),
      DictionaryAvailability.unavailable => ('暂不可用', '本地词库未通过检查，请重开应用后重试。'),
      DictionaryAvailability.unknown => ('状态未能读取', '可以刷新重试；另一套词典会单独显示状态。'),
    };
    return Card(
      key: ValueKey('dictionary-${info.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                color: info.availability == DictionaryAvailability.unavailable
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(description),
            const Divider(height: 28),
            Text('来源：${info.source}'),
            const SizedBox(height: 6),
            Text('数据版本：${info.version ?? '暂无法读取'}'),
            const SizedBox(height: 6),
            Text('许可：${info.license ?? '暂无法读取'}'),
            const SizedBox(height: 12),
            Text('内置词包：${size(info.packageBytes)}'),
            Text('本地词库：${size(info.localBytes)}'),
            if (info.availability == DictionaryAvailability.notPrepared)
              Text('准备后词库：${size(info.expectedBytes)}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('词典管理'),
      actions: [
        IconButton(
          onPressed: refresh,
          tooltip: '刷新词典状态',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('阅读时，随手查词', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text('两套词典随应用提供。英汉用于中文释义，英英用于英文解释；可在阅读设置中选择主释义。'),
              const SizedBox(height: 24),
              FutureBuilder<List<DictionaryInfo>>(
                future: dictionaries,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('暂时无法读取词典信息'),
                        TextButton(onPressed: refresh, child: const Text('重试')),
                      ],
                    );
                  }
                  return Column(children: snapshot.data!.map(card).toList());
                },
              ),
              const SizedBox(height: 8),
              const Text(
                '内置词包属于应用安装内容。本地词库是查词使用的额外文件；这里显示当前版本的文件大小，不包含书籍、译文缓存或旧版本文件。',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

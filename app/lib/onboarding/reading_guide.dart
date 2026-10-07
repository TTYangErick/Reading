import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../dict/catalog.dart';
import '../dict/management_page.dart';
import '../translate/translator.dart';

const readingGuideKey = 'readingGuideSeenV1';
final readingGuideSeenProvider = FutureProvider(
  (ref) async =>
      await ref.watch(databaseProvider).setting(readingGuideKey) == '1',
);

/// A dismissible shelf invitation; never opens a route or prepares resources.
class ReadingGuideCard extends ConsumerStatefulWidget {
  const ReadingGuideCard({super.key});
  @override
  ConsumerState<ReadingGuideCard> createState() => _ReadingGuideCardState();
}

class _ReadingGuideCardState extends ConsumerState<ReadingGuideCard> {
  bool saving = false;
  String? error;
  Future<void> skip() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(databaseProvider).setSetting(readingGuideKey, '1');
      if (mounted) ref.invalidate(readingGuideSeenProvider);
    } catch (_) {
      if (mounted) setState(() => error = '暂未记住此选择，可以重试；仍可直接打开书籍。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(readingGuideSeenProvider)
      .when(
        loading: () => const SizedBox.shrink(),
        // A settings read failure must not prevent access to books or the menu.
        error: (_, stack) => const SizedBox.shrink(),
        data: (seen) => seen
            ? const SizedBox.shrink()
            : Card(
                key: const ValueKey('reading-guide-card'),
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '开始英语阅读',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('了解点词、句子翻译，以及离线前需要准备什么。'),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const ReadingGuidePage(),
                              ),
                            ),
                            child: const Text('查看阅读指南'),
                          ),
                          TextButton(
                            onPressed: saving ? null : skip,
                            child: Text(saving ? '正在保存…' : '暂时跳过'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      );
}

class ReadingGuidePage extends ConsumerStatefulWidget {
  const ReadingGuidePage({super.key});
  @override
  ConsumerState<ReadingGuidePage> createState() => _ReadingGuidePageState();
}

class _ReadingGuidePageState extends ConsumerState<ReadingGuidePage>
    with WidgetsBindingObserver {
  late Future<List<DictionaryInfo>> dictionaries;
  late Future<TranslationStatus> translation;
  bool preparing = false, saving = false;
  String? preparationError, saveError;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inspect();
  }

  void inspect() {
    dictionaries = ref.read(dictionaryCatalogProvider).inspect();
    dictionaries.ignore();
    translation = ref.read(translatorProvider).native.status('en', 'zh-Hans');
    translation.ignore();
  }

  void refresh() {
    if (preparing) return;
    setState(() {
      preparationError = null;
      inspect();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !preparing) refresh();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> prepare() async {
    if (preparing) return;
    final token = ++generation;
    final translator = ref.read(translatorProvider);
    setState(() {
      preparing = true;
      preparationError = null;
    });
    try {
      await translator.prepare('en', 'zh-Hans');
      if (!mounted || token != generation) return;
      // Download completion is not a guarantee: recheck the actual model state.
      final status = await translator.native.status('en', 'zh-Hans');
      if (!mounted || token != generation) return;
      setState(() {
        translation = Future.value(status);
        if (status == TranslationStatus.downloadRequired) {
          preparationError = '模型尚未就绪，请检查 Wi-Fi 后重试。';
        }
      });
    } on TranslationFailure catch (error) {
      if (mounted && token == generation) {
        setState(
          () => preparationError = switch (error.code) {
            'cancelled' => '已取消准备，可以稍后重试。',
            'timeout' => '准备等待超时，请检查 Wi-Fi 后重试。',
            'unsupported' || 'unavailable' => '此设备目前无法准备离线翻译，点词阅读仍可使用。',
            _ => '语言模型准备未完成，请检查 Wi-Fi 后重试。',
          },
        );
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(() => preparationError = '语言模型准备未完成，请稍后重试。');
      }
    } finally {
      if (mounted && token == generation) setState(() => preparing = false);
    }
  }

  Future<void> finish() async {
    if (saving) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await ref.read(databaseProvider).setSetting(readingGuideKey, '1');
      if (!mounted) return;
      ref.invalidate(readingGuideSeenProvider);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => saveError = '暂未记住此选择，请重试或直接返回书架。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  String dictionaryStatus(DictionaryAvailability availability) =>
      switch (availability) {
        DictionaryAvailability.ready => '本地已就绪 · 可离线查词',
        DictionaryAvailability.notPrepared => '内置待准备 · 首次点词时准备，无需联网',
        DictionaryAvailability.unavailable => '暂不可用 · 可到词典管理查看',
        DictionaryAvailability.unknown => '状态未能读取 · 请刷新重试',
      };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('阅读与离线准备'),
      actions: [
        IconButton(
          tooltip: '刷新准备状态',
          onPressed: preparing ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '从一本英文书开始',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text('当前版本支持英语学习。可以先阅读，再按需要准备离线翻译。'),
              const SizedBox(height: 20),
              section('阅读时怎么用', const [
                Text('在书架点 ＋ 导入 EPUB / TXT，也可以先打开示例书。'),
                SizedBox(height: 8),
                Text('点击英文单词查看释义；再点气泡外关闭。阅读设置中可选择英汉或英英主释义。'),
                SizedBox(height: 8),
                Text('长按句子查看翻译；按住拖动可选择当前可见同段内的短语。'),
                SizedBox(height: 8),
                Text('左右滑动翻页，点击空白或底部章节信息打开阅读操作。'),
              ]),
              section('点词词典 · 随应用提供', [
                const Text(
                  '英汉与英英词包已经内置。首次点词会准备本地词库，可能需要等待并占用额外存储；此页面不会自动展开词包。',
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<DictionaryInfo>>(
                  future: dictionaries,
                  builder: (_, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Text('正在检查词典状态…');
                    }
                    if (snapshot.hasError) return const Text('词典状态未能读取，请刷新重试。');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final info in snapshot.data!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              '${info.name}\n${dictionaryStatus(info.availability)}',
                            ),
                          ),
                      ],
                    );
                  },
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const DictionaryManagementPage(),
                      ),
                    );
                    if (mounted && !preparing) refresh();
                  },
                  child: const Text('查看词典与存储空间'),
                ),
              ]),
              section('句子翻译 · 需设备语言模型', [
                const Text(
                  '英译中机器翻译需要单独的设备模型。首次下载需要网络，建议连接 Wi-Fi；模型就绪后可离线翻译。机器结果可能不准确。',
                ),
                const SizedBox(height: 12),
                FutureBuilder<TranslationStatus>(
                  future: translation,
                  builder: (_, snapshot) {
                    if (preparing) {
                      return const Text('正在准备语言模型…可返回阅读，系统下载可能继续。');
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Text('正在检查翻译模型…');
                    }
                    if (snapshot.hasError) return const Text('翻译状态未能读取，请刷新重试。');
                    return switch (snapshot.data!) {
                      TranslationStatus.ready => const Text('语言模型已就绪 · 可离线翻译'),
                      TranslationStatus.downloadRequired => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('尚需下载英译中语言模型'),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: prepare,
                            child: const Text('下载语言模型'),
                          ),
                        ],
                      ),
                      TranslationStatus.unsupported => const Text(
                        '此设备不支持当前英译中模型；仍可阅读和查词。',
                      ),
                      TranslationStatus.unavailable => Text(
                        ref.read(translatorProvider).native.engine == 'apple-v1'
                            ? '此设备的离线翻译暂不可用。iPhone / iPad 需要 iOS / iPadOS 18 或更新系统的真机，模拟器不可用；仍可阅读和查词。'
                            : '此设备的离线翻译暂不可用，请稍后刷新重试；仍可阅读和查词。',
                      ),
                    };
                  },
                ),
                if (preparationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      preparationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('离线前可先准备模型，再断网长按一句没翻译过的新句子检查。仅看到旧译文，可能是命中了缓存。'),
              ]),
              if (saveError != null)
                Text(
                  saveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: saving ? null : finish,
                child: Text(saving ? '正在保存…' : '先去阅读'),
              ),
              const SizedBox(height: 8),
              const Text('以后可从书架“更多 → 阅读与离线准备”再次打开。'),
            ],
          ),
        ),
      ),
    ),
  );
}

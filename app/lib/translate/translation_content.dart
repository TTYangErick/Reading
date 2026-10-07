import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'translator.dart';

/// Shared device translation lifecycle. Dictionary entries stay separate.
class TranslationContent extends ConsumerStatefulWidget {
  const TranslationContent({
    super.key,
    required this.text,
    this.compact = false,
    this.machineFallback = false,
    this.dark,
    this.footer,
    this.invalidTextMessage = '选中的文字过长或没有文字，暂时无法翻译。',
  });
  final String text, invalidTextMessage;
  final bool compact, machineFallback;
  final bool? dark;
  final Widget? footer;

  @override
  ConsumerState<TranslationContent> createState() => _TranslationContentState();
}

class _TranslationContentState extends ConsumerState<TranslationContent> {
  String? result, failure;
  bool busy = true, preparing = false;
  int generation = 0;

  bool get usesGoogle =>
      ref.read(translatorProvider).native.engine.startsWith('mlkit-');

  void explanation() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('离线翻译说明'),
      content: SingleChildScrollView(
        child: SelectableText(
          '英译中机器翻译，结果可能不准确。语言模型下载后，翻译在设备上进行。成功译文最多保留 1000 条缓存；原文和阅读位置不变。\n\n'
          '${usesGoogle ? '翻译由 Google Translate 通过 ML Kit 设备端模型提供。\nhttps://cloud.google.com/translate\n\nTHIS SERVICE MAY CONTAIN TRANSLATIONS POWERED BY GOOGLE. GOOGLE DISCLAIMS ALL WARRANTIES RELATED TO THE TRANSLATIONS, EXPRESS OR IMPLIED, INCLUDING ANY WARRANTIES OF ACCURACY, RELIABILITY, AND ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.' : '翻译由 Apple Translation 提供，需要 iOS / iPadOS 18 或更新版本的真机。'}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    run();
  }

  @override
  void didUpdateWidget(covariant TranslationContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) run();
  }

  Future<void> run({bool download = false}) async {
    final request = ++generation;
    final source = widget.text;
    setState(() {
      busy = true;
      preparing = download;
      failure = null;
      result = null;
    });
    try {
      final translator = ref.read(translatorProvider);
      if (download) {
        await translator.prepare('en', 'zh-Hans');
        if (!mounted || request != generation) return;
      }
      final translated = await translator.translate(source, 'en', 'zh-Hans');
      if (mounted && request == generation) setState(() => result = translated);
    } on TranslationFailure catch (error) {
      if (mounted && request == generation) {
        setState(() => failure = error.code);
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => failure = 'translationFailed');
      }
    } finally {
      if (mounted && request == generation) {
        setState(() {
          busy = false;
          preparing = false;
        });
      }
    }
  }

  String get message => switch (failure) {
    'downloadRequired' => '首次使用需下载英译中语言模型。连接 Wi-Fi 后下载，之后可离线翻译。',
    'unavailable' =>
      usesGoogle
          ? '离线翻译暂不可用，请稍后重试。原文仍可复制。'
          : '此设备暂不支持离线翻译。Apple 翻译需要 iOS / iPadOS 18 或更新版本的真机。',
    'unsupported' => '此设备不支持英译中语言模型。',
    'invalidText' => widget.invalidTextMessage,
    'timeout' => '等待超时。下载模型时请检查 Wi-Fi，稍后重试。',
    'downloadFailed' => '语言模型下载未完成，请检查 Wi-Fi 后重试。',
    'cancelled' => '翻译已取消，可以重试。',
    'busy' => '上一项翻译仍在处理，请稍后重试。',
    _ => '暂时无法翻译，请重试。原文仍可复制。',
  };

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.machineFallback
            ? '词典未收录 · 英译中机器翻译'
            : usesGoogle
            ? '英译中 · Translate with Google'
            : '英译中 · 离线翻译',
        style: widget.machineFallback
            ? TextStyle(
                fontSize: 12,
                color: DefaultTextStyle.of(context).style.color
                    ?.withValues(alpha: .65),
              )
            : const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      if (busy)
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(preparing ? '正在准备语言模型…' : '正在翻译…')),
          ],
        ),
      if (result != null)
        if (widget.compact)
          Text(result!, maxLines: 3, overflow: TextOverflow.ellipsis)
        else
          SelectableText(
            result!,
            style: widget.machineFallback
                ? DefaultTextStyle.of(context).style
                : const TextStyle(fontSize: 18, height: 1.6),
          ),
      if (result != null && usesGoogle)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Image.asset(
            (widget.dark ?? (Theme.of(context).brightness == Brightness.dark))
                ? 'assets/translation/white-regular@3x.png'
                : 'assets/translation/color-regular@3x.png',
            height: 16,
            semanticLabel: 'Powered by Google Translate',
          ),
        ),
      if (failure != null) ...[
        Text(message),
        if (!{'unsupported', 'invalidText'}.contains(failure) &&
            (failure != 'unavailable' || usesGoogle))
          TextButton(
            onPressed: busy
                ? null
                : () => run(
                    download: {
                      'downloadRequired',
                      'downloadFailed',
                    }.contains(failure),
                  ),
            child: Text(
              {'downloadRequired', 'downloadFailed'}.contains(failure)
                  ? '下载语言模型并翻译'
                  : '重试翻译',
            ),
          ),
      ],
      if (widget.footer != null) ...[
        const SizedBox(height: 16),
        widget.footer!,
      ],
      if (!widget.compact)
        TextButton(onPressed: explanation, child: const Text('翻译说明')),
    ],
  );
}

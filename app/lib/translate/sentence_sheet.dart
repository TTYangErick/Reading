import 'package:flutter/material.dart';

import 'translation_content.dart';

class SentenceSheet extends StatelessWidget {
  const SentenceSheet({
    super.key,
    required this.sentence,
    required this.onCopy,
    this.adjusted = false,
  });
  final String sentence;
  final bool adjusted;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              adjusted ? '选中的文字' : '选中的句子',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SelectableText(
              sentence,
              style: const TextStyle(fontSize: 18, height: 1.6),
            ),
            const SizedBox(height: 16),
            TranslationContent(
              text: sentence,
              invalidTextMessage: adjusted
                  ? '选中的文字过长或没有文字，暂时无法翻译。'
                  : '选中的句子过长或没有文字，暂时无法翻译。',
              footer: FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 17),
                label: Text(adjusted ? '复制文字' : '复制句子'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

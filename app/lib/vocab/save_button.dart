import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'vocabulary.dart';

class SaveVocabularyButton extends ConsumerStatefulWidget {
  const SaveVocabularyButton({
    super.key,
    required this.draft,
    required this.color,
  });
  final VocabularyDraft draft;
  final Color color;
  @override
  ConsumerState<SaveVocabularyButton> createState() =>
      _SaveVocabularyButtonState();
}

class _SaveVocabularyButtonState extends ConsumerState<SaveVocabularyButton> {
  bool busy = true, saved = false;
  String? error;
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    try {
      final id = await ref.read(databaseProvider).vocabularyId(widget.draft);
      if (mounted) {
        setState(() {
          saved = id != null;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '读取失败，点击重试';
        });
      }
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(databaseProvider).addVocabulary(widget.draft);
      if (mounted) setState(() => saved = true);
    } catch (_) {
      if (mounted) setState(() => error = '收藏失败，点击重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip:
        error ??
        (busy
            ? '正在读取或保存生词'
            : saved
            ? '已加入生词本'
            : '加入生词本'),
    onPressed: busy || saved ? null : save,
    icon: busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.color,
            ),
          )
        : Icon(
            error != null
                ? Icons.error_outline
                : saved
                ? Icons.star
                : Icons.star_border,
            color: error != null
                ? Theme.of(context).colorScheme.error
                : widget.color,
            size: 21,
          ),
  );
}

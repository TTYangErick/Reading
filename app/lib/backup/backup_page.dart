import '../onboarding/reading_guide.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../startup/preferences.dart';
import 'backup.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool busy = false;
  String status = '';

  Future<void> run(bool restore) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = restore ? '正在检查备份…' : '正在生成备份…';
    });
    try {
      final store = BackupStore(ref.read(databaseProvider));
      if (!restore) {
        final bytes = await store.export();
        if (!mounted) return;
        final saved = await FilePicker.saveFile(
          fileName:
              'Reading-${DateTime.now().millisecondsSinceEpoch}.readingbackup',
          bytes: bytes,
          mimeType: 'application/octet-stream',
          dialogTitle: '保存 Reading 备份',
        );
        if (mounted) {
          setState(() => status = saved == null ? '已取消保存，当前数据未改变。' : '备份已保存。');
        }
      } else {
        final file = await FilePicker.pickFile(dialogTitle: '选择 Reading 备份');
        if (!mounted) return;
        if (file == null) {
          setState(() => status = '已取消，当前数据未改变。');
          return;
        }
        final size = await file.length();
        if (size != null && size > ReadingBackup.maxFileBytes) {
          throw const FormatException('备份超过 64 MB 上限。');
        }
        final bytes = await ReadingBackup.readStream(file.readAsByteStream());
        final backup = await compute(ReadingBackup.decode, bytes);
        if (!mounted) return;
        final date = DateTime.fromMillisecondsSinceEpoch(backup.createdAt)
            .toLocal();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('用此备份替换当前数据？'),
            content: SingleChildScrollView(
              child: Text(
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} 的备份\n\n'
                '${backup.count('books')} 本书 · ${backup.count('book_assets')} 个图片资源\n'
                '${backup.count('vocabulary')} 条生词 · ${backup.count('bookmarks')} 个书签\n'
                '${backup.count('translations')} 条译文缓存 · ${backup.count('lookup_history')} 条查词历史\n\n'
                '当前书架、阅读位置、设置、生词、书签、译文缓存和查词历史将全部被替换，不会合并。建议先保存当前数据的备份。\n\n'
                '词典和已下载的翻译模型不受影响。',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('替换并恢复'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (confirmed != true) {
          setState(() => status = '已取消恢复，当前数据未改变。');
          return;
        }
        setState(() => status = '正在恢复，请稍候…');
        final paginationCache = ref.read(paginationCacheProvider);
        await ref
            .read(lookupHistoryProvider)
            .replace(
              () => ref
                  .read(translatorProvider)
                  .replaceCache(() => store.restore(backup)),
            );
        paginationCache.clear();
        if (!mounted) return;
        ref.invalidate(booksProvider);
        ref.invalidate(globalStyleProvider);
        ref.invalidate(readingGuideSeenProvider);
        ref.invalidate(resumeReadingProvider);
        setState(
          () => status =
              '已恢复 ${backup.count('books')} 本书、${backup.count('vocabulary')} 条生词和 ${backup.count('bookmarks')} 个书签。返回书架即可继续阅读。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => status = error is FormatException
              ? error.message
              : restore
              ? '恢复失败，当前数据未改变。请检查文件后重试。'
              : '备份未保存成功，请检查存储空间后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('备份与恢复'),
        automaticallyImplyLeading: !busy,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '带上你的书库',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  '将书籍、图片、阅读位置、阅读设置、生词、书签、译文缓存和查词历史保存为一个文件，可在另一台设备的 Reading 中恢复。',
                ),
                const SizedBox(height: 12),
                const Text('词典与系统翻译模型不包含在备份中，换机后需重新准备。备份未加密，请保存在你信任的位置。'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('backup-export'),
                  onPressed: busy ? null : () => run(false),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('保存备份'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('backup-import'),
                  onPressed: busy ? null : () => run(true),
                  icon: const Icon(Icons.restore),
                  label: const Text('从备份恢复'),
                ),
                const SizedBox(height: 24),
                if (busy) const LinearProgressIndicator(),
                if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(status, key: const ValueKey('backup-status')),
                    ),
                  ),
                const Text(
                  '恢复前会检查文件并显示摘要，只有确认后才会替换当前数据。当前支持最多 500 本书、50,000 条记录、32 MB 数据及 64 MB 备份文件；超过上限会明确提示，不会只保存部分内容。',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

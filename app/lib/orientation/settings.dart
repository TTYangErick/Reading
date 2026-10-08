import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'orientation.dart';

class ReadingOrientationSetting extends ConsumerStatefulWidget {
  const ReadingOrientationSetting({super.key});

  @override
  ConsumerState<ReadingOrientationSetting> createState() => _SettingState();
}

class _SettingState extends ConsumerState<ReadingOrientationSetting> {
  bool saving = false;
  String? error;

  Future<void> save(ReadingOrientation value) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(readingOrientationProvider.notifier).save(value);
    } catch (_) {
      if (mounted) setState(() => error = '阅读方向未能保存，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(readingOrientationSessionProvider);
    final setting = ref.watch(readingOrientationProvider);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('阅读方向', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (!session.supported)
            const Text('此设备跟随系统方向。平板和大屏保留窗口与多任务能力，可使用系统旋转锁定。')
          else
            setting.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(readingOrientationProvider),
                child: const Text('读取阅读方向失败，点击重试'),
              ),
              data: (value) => SegmentedButton<ReadingOrientation>(
                key: const ValueKey('reading-orientation-setting'),
                segments: ReadingOrientation.values
                    .map(
                      (item) =>
                          ButtonSegment(value: item, label: Text(item.label)),
                    )
                    .toList(),
                selected: {value},
                onSelectionChanged: saving
                    ? null
                    : (values) => save(values.first),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '适用于所有书籍；离开阅读后恢复系统方向。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (saving) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (session.error != null) ...[
            Text(
              session.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(onPressed: session.retry, child: const Text('重新应用方向')),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

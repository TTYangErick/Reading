import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

const resumeReadingKey = 'resumeReadingOnLaunchV1';
final resumeReadingProvider = AsyncNotifierProvider<ResumeReading, bool>(
  ResumeReading.new,
);

class ResumeReading extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      await ref.watch(databaseProvider).setting(resumeReadingKey) == '1';

  Future<void> setEnabled(bool value) async {
    await ref
        .read(databaseProvider)
        .setSetting(resumeReadingKey, value ? '1' : '0');
    // This state belongs to the app scope, even if the sheet was dismissed.
    if (ref.mounted) state = AsyncData(value);
  }
}

class StartupSettings extends ConsumerStatefulWidget {
  const StartupSettings({super.key});

  @override
  ConsumerState<StartupSettings> createState() => _StartupSettingsState();
}

class _StartupSettingsState extends ConsumerState<StartupSettings> {
  bool saving = false;
  String? error;

  Future<void> save(bool value) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(resumeReadingProvider.notifier).setEnabled(value);
    } catch (_) {
      if (mounted) setState(() => error = '设置未能保存，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('启动设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          ref
              .watch(resumeReadingProvider)
              .when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('设置暂时无法读取。'),
                    TextButton(
                      onPressed: () => ref.invalidate(resumeReadingProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
                data: (enabled) => SwitchListTile.adaptive(
                  key: const ValueKey('resume-reading-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启动时继续阅读'),
                  subtitle: const Text('打开最近读过的书；关闭后先显示书架。'),
                  value: enabled,
                  onChanged: saving ? null : save,
                ),
              ),
          const SizedBox(height: 8),
          Text(
            '从其他 App 打开文件时，优先处理待导入文件。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (saving) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}

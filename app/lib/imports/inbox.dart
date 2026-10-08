import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../book/book.dart';
import '../book/epub.dart';

const importChannel = MethodChannel('dev.reading/imports');

class IncomingBook {
  const IncomingBook({
    required this.id,
    required this.name,
    required this.ready,
    this.path,
    this.error,
  });
  final String id, name;
  final bool ready;
  final String? path, error;

  String get description => switch (error) {
    'tooLarge' => '文件太大：TXT 最多 20 MB，EPUB 最多 50 MB。',
    'unsupported' => '仅支持单个 EPUB 或 TXT 文件。',
    'queueFull' => '待处理文件已满，请处理后重新分享。',
    null => ready ? '来自其他 App，确认后加入书架' : '正在接收文件…',
    _ => '文件无法读取，请从来源 App 重新分享。',
  };
}

final importInboxProvider = NotifierProvider<ImportInbox, List<IncomingBook>>(
  ImportInbox.new,
);

/// Native owns bounded, private staging files; snapshots also cover cold starts.
/// No database writes or navigation occur until the shelf's Import is pressed.
class ImportInbox extends Notifier<List<IncomingBook>> {
  int _revision = 0;
  bool _disposed = false;
  final _released = <String>{};

  @override
  List<IncomingBook> build() {
    importChannel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await refresh();
    });
    ref.onDispose(() {
      _disposed = true;
      _revision++;
      importChannel.setMethodCallHandler(null);
    });
    unawaited(Future<void>.microtask(refresh));
    return const [];
  }

  /// False means the latest inbox state could not be confirmed.
  Future<bool> refresh() async {
    final revision = ++_revision;
    try {
      final items = await importChannel.invokeListMethod<Object?>('pending');
      if (_disposed || revision != _revision) return false;
      final nativeIds = <String>{};
      state = [
        for (final value in items ?? const [])
          if (value case final Map item)
            if (item['id'] case final String id)
              if (nativeIds.add(id) && !_released.contains(id))
                IncomingBook(
                  id: id,
                  name: item['name'] is String ? item['name'] as String : '文件',
                  ready: item['ready'] == true,
                  path: item['path'] as String?,
                  error: item['error'] as String?,
                ),
      ];
      // Retain only IDs whose native cleanup failed; ordinary imports do not
      // accumulate a second unbounded history in memory.
      _released.retainAll(nativeIds);
      return true;
    } on MissingPluginException {
      // Desktop/widget hosts have no mobile file receiver.
      return true;
    } on PlatformException {
      // Keep the last usable snapshot on transient engine/channel failures.
      return false;
    }
  }

  Future<void> release(String id) async {
    _revision++;
    _released.add(id);
    state = state.where((item) => item.id != id).toList();
    try {
      await importChannel.invokeMethod<void>('release', id);
      _released.remove(id);
      if (!_disposed) await refresh();
    } on PlatformException {
      // The owned cache is also cleaned on the next process start.
    } on MissingPluginException {
      _released.remove(id);
    }
  }
}

/// Runs in compute: enforce actual streamed bytes, even if a provider reports a
/// misleading length. The source here is a native-owned staging file.
Future<BookContent> parseReceivedFile((String, String) input) async {
  final (name, path) = input;
  final lower = name.toLowerCase();
  if (!lower.endsWith('.epub') && !lower.endsWith('.txt')) {
    throw const FormatException('仅支持 EPUB 或 TXT 文件。');
  }
  final epub = lower.endsWith('.epub');
  final limit = epub ? EpubParser.maxFileSize : 20 * 1024 * 1024;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (bytes.length + chunk.length > limit) {
      throw FormatException(epub ? 'EPUB 超过 50 MB。' : '文本超过 20 MB。');
    }
    bytes.add(chunk);
  }
  return ParserRegistry([TxtParser(), EpubParser()])
      .parse(name, bytes.takeBytes());
}

class ImportInboxCards extends StatelessWidget {
  const ImportInboxCards({
    super.key,
    required this.items,
    required this.busy,
    required this.onImport,
    required this.onIgnore,
  });
  final List<IncomingBook> items;
  final bool busy;
  final void Function(IncomingBook) onImport;
  final void Function(String) onIgnore;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: ValueKey('ignore-import-${item.id}'),
                      onPressed: busy ? null : () => onIgnore(item.id),
                      child: const Text('忽略'),
                    ),
                    if (item.error == null)
                      TextButton(
                        key: ValueKey('accept-import-${item.id}'),
                        onPressed: busy || !item.ready || item.path == null
                            ? null
                            : () => onImport(item),
                        child: const Text('导入'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

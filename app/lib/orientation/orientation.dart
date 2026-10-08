import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

enum ReadingOrientation {
  system('跟随系统'),
  portrait('竖屏'),
  landscape('横屏');

  final String label;
  const ReadingOrientation(this.label);

  static ReadingOrientation decode(String? value) =>
      values.firstWhere((item) => item.name == value, orElse: () => system);

  List<DeviceOrientation> get orientations => switch (this) {
    system => [],
    portrait => [DeviceOrientation.portraitUp],
    landscape => [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
  };
}

const readingOrientationKey = 'readingOrientationV1';
final readingOrientationProvider =
    AsyncNotifierProvider<ReadingOrientationPreference, ReadingOrientation>(
      ReadingOrientationPreference.new,
    );

class ReadingOrientationPreference extends AsyncNotifier<ReadingOrientation> {
  @override
  Future<ReadingOrientation> build() async => ReadingOrientation.decode(
    await ref.watch(databaseProvider).setting(readingOrientationKey),
  );

  Future<void> save(ReadingOrientation value) async {
    await ref
        .read(databaseProvider)
        .setSetting(readingOrientationKey, value.name);
    if (ref.mounted) state = AsyncData(value);
  }
}

// Use the physical display rather than the window: split view must not turn a
// tablet into a supported phone. Keep multitasking enabled on every platform.
bool supportsReadingOrientation(TargetPlatform platform, Size display) =>
    (platform == TargetPlatform.android || platform == TargetPlatform.iOS) &&
    display.shortestSide > 0 &&
    display.shortestSide < 600;

final readingOrientationSessionProvider = Provider((ref) {
  final session = ReadingOrientationSession(
    SystemChrome.setPreferredOrientations,
  );
  ref.onDispose(session.dispose);
  return session;
});

typedef _Request = ({ReadingOrientation preference, bool supported});

/// Nested readers hold separate leases so closing a footnote cannot unlock the
/// underlying reader. Requests are serialized, including the final reset.
class ReadingOrientationSession extends ChangeNotifier {
  final Future<void> Function(List<DeviceOrientation>) apply;
  ReadingOrientationSession(this.apply);

  final _owners = <Object, _Request>{};
  Future<void> pending = Future.value();
  int _revision = 0;
  bool _disposed = false;
  String? error;
  bool get supported => _owners.isNotEmpty && _owners.values.last.supported;

  void update(Object owner, ReadingOrientation preference, bool supported) {
    final request = (preference: preference, supported: supported);
    if (_disposed || _owners[owner] == request) return;
    _owners[owner] = request;
    _schedule();
  }

  void release(Object owner) {
    if (_disposed || _owners.remove(owner) == null) return;
    _schedule();
  }

  void retry() => _schedule();

  void _schedule() {
    final revision = ++_revision;
    final preference = supported
        ? _owners.values.last.preference
        : ReadingOrientation.system;
    error = null;
    if (!_disposed) notifyListeners();
    pending = pending.then((_) async {
      if (revision != _revision) return;
      try {
        await apply(preference.orientations);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          error = '系统未能应用阅读方向，请重试。';
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _owners.clear();
    _schedule();
    super.dispose();
  }
}

class ReadingOrientationScope extends ConsumerStatefulWidget {
  final Widget child;
  const ReadingOrientationScope({super.key, required this.child});

  @override
  ConsumerState<ReadingOrientationScope> createState() =>
      _OrientationScopeState();
}

class _OrientationScopeState extends ConsumerState<ReadingOrientationScope> {
  late final ReadingOrientationSession session;

  @override
  void initState() {
    super.initState();
    session = ref.read(readingOrientationSessionProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate support when this view changes displays or window geometry.
    MediaQuery.sizeOf(context);
    final preference =
        ref.watch(readingOrientationProvider).asData?.value ??
        ReadingOrientation.system;
    final display = View.of(context).display;
    final supported = supportsReadingOrientation(
      Theme.of(context).platform,
      display.size / display.devicePixelRatio,
    );
    // Avoid notifying the settings panel during widget construction. Also
    // discard callbacks for a reader that was already popped this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) session.update(this, preference, supported);
    });
    return widget.child;
  }

  @override
  void dispose() {
    session.release(this);
    super.dispose();
  }
}

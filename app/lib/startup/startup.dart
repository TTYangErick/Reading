import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../imports/inbox.dart';
import '../library/library.dart';
import '../reader/reader.dart';
import 'preferences.dart';

/// One attempt per app root. The shelf stays underneath so Back always works.
/// Never resume in response to a rebuild, foreground event or backup restore.
class StartupLibrary extends ConsumerStatefulWidget {
  const StartupLibrary({super.key});

  @override
  ConsumerState<StartupLibrary> createState() => _StartupLibraryState();
}

class _StartupLibraryState extends ConsumerState<StartupLibrary> {
  bool cancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => resume());
  }

  bool get mayOpen =>
      mounted && !cancelled && ModalRoute.of(context)?.isCurrent == true;

  Future<void> resume() async {
    if (!mayOpen) return;
    try {
      if (!await ref.read(resumeReadingProvider.future) || !mayOpen) return;
      // The shelf is already loading these objects. Reuse its result instead
      // of decoding a second copy of a potentially large book at startup.
      final books = await ref.read(booksProvider.future);
      final book = books.where((book) => book.lastReadAt > 0).firstOrNull;
      if (!mayOpen || book == null) return;
      final style = await ref.read(globalStyleProvider.future);
      if (!mayOpen) return;
      // Fresh native evidence before navigation; receipt/unknown state wins.
      final confirmed = await ref.read(importInboxProvider.notifier).refresh();
      if (!mounted ||
          !mayOpen ||
          !confirmed ||
          ref.read(importInboxProvider).isNotEmpty) {
        return;
      }
      cancelled = true;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(book: book, defaultStyle: style),
        ),
      );
      if (mounted) ref.invalidate(booksProvider);
    } catch (_) {
      if (mounted && mayOpen) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法继续上次阅读，可从书架重新打开。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(importInboxProvider, (_, next) {
      if (next.isNotEmpty) cancelled = true;
    });
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => cancelled = true,
      child: const LibraryPage(),
    );
  }
}

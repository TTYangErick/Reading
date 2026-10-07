import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../db/database.dart';

enum TranslationStatus { ready, downloadRequired, unsupported, unavailable }

class TranslationFailure implements Exception {
  const TranslationFailure(this.code);
  final String code;
}

abstract interface class Translator {
  String get engine;
  Future<TranslationStatus> status(String from, String to);
  Future<void> prepare(String from, String to);
  Future<String> translate(String text, String from, String to);
}

class PlatformTranslator implements Translator {
  const PlatformTranslator();
  static const channel = MethodChannel('dev.reading/translation');
  static int _request = 0;
  @override
  String get engine => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'apple-v1',
    TargetPlatform.android => 'mlkit-17-v1',
    _ => 'unsupported',
  };

  Future<T?> _call<T>(
    String method,
    String from,
    String to, [
    String? text,
  ]) async {
    final id = ++_request;
    try {
      return await channel
          .invokeMethod<T>(method, {
            'id': id,
            'from': from,
            'to': to,
            'text': text,
          })
          .timeout(Duration(seconds: method == 'prepare' ? 180 : 45));
    } on TimeoutException {
      // A late callback must not keep a native sheet/client occupied forever.
      unawaited(
        channel.invokeMethod<void>('cancel', {'id': id}).catchError((_) {}),
      );
      throw const TranslationFailure('timeout');
    } on MissingPluginException {
      throw const TranslationFailure('unavailable');
    } on PlatformException catch (error) {
      throw TranslationFailure(error.code);
    }
  }

  @override
  Future<TranslationStatus> status(String from, String to) async {
    if (engine == 'unsupported') return TranslationStatus.unavailable;
    final value = await _call<String>('status', from, to);
    return TranslationStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TranslationStatus.unavailable,
    );
  }

  @override
  Future<void> prepare(String from, String to) =>
      _call<void>('prepare', from, to);

  @override
  Future<String> translate(String text, String from, String to) async =>
      await _call<String>('translate', from, to, text) ?? '';
}

/// Exact source + language pair + engine revision. Only successful translations
/// enter the persistent cache; hits do not require an installed model or network.
class CachedTranslator {
  CachedTranslator(this.native, this.database);
  final Translator native;
  final ReadingDatabase database;
  final _pending = <(int, String, String, String), Future<String>>{};
  int _generation = 0;
  Future<void> _writes = Future.value();

  Future<void> _write(Future<void> Function() action) {
    final result = _writes.then((_) => action());
    // One failed write must not poison all subsequent clears/translations.
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  // Invalidate pending native results and serialize replacement with cache writes.
  Future<void> replaceCache(Future<void> Function() replace) {
    _generation++;
    return _write(replace);
  }

  Future<void> clearCache() {
    _generation++;
    return _write(database.clearTranslations);
  }

  Future<int> cacheCount() async {
    await _writes;
    return database.translationCount();
  }

  Future<void> prepare(String from, String to) => native.prepare(from, to);

  Future<String> translate(String text, String from, String to) {
    if (text.trim().isEmpty || text.length > 4000) {
      return Future.error(const TranslationFailure('invalidText'));
    }
    final generation = _generation;
    final key = (generation, text, from, to);
    return _pending.putIfAbsent(key, () async {
      try {
        await _writes;
        final cached = await database.translation(
          native.engine,
          from,
          to,
          text,
        );
        if (cached != null) return cached;
        final status = await native.status(from, to);
        if (status != TranslationStatus.ready) {
          throw TranslationFailure(status.name);
        }
        final result = await native.translate(text, from, to);
        if (result.trim().isEmpty || result.length > 16000) {
          throw const TranslationFailure('translationFailed');
        }
        await _write(() async {
          if (generation == _generation) {
            await database.saveTranslation(
              native.engine,
              from,
              to,
              text,
              result,
            );
          }
        });
        return result;
      } finally {
        _pending.remove(key);
      }
    });
  }
}

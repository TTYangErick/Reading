import 'dart:io';

import 'package:flutter/services.dart';

class ReaderSystemUi {
  static const _channel = MethodChannel('dev.reading/system_ui');
  static Future<void> setImmersive(bool enabled) async {
    if (Platform.isAndroid) {
      // API 36 enforces edge-to-edge. Native insets control still supports
      // transient system bars without opting out of that layout requirement.
      await _channel.invokeMethod<void>('immersive', enabled);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }
}

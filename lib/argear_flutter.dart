
import 'dart:async';

import 'package:flutter/services.dart';

class ArgearFlutter {
  static const MethodChannel _channel =
      const MethodChannel('argear_flutter');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}

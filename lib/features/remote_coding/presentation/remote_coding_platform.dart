import 'dart:io';

import 'package:flutter/foundation.dart';

@visibleForTesting
bool Function()? debugRemoteCodingMobileRuntimePlatformOverride;

bool isRemoteCodingMobileRuntimePlatform() {
  final override = debugRemoteCodingMobileRuntimePlatformOverride;
  if (override != null) {
    return override();
  }
  return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}

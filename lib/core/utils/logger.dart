import 'package:flutter/foundation.dart';

/// Debug-only logger that suppresses output in release builds.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

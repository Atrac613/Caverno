import 'dart:io';

import 'package:flutter/services.dart';

/// Requests extended background execution time on iOS via
/// `UIApplication.beginBackgroundTask`.
///
/// On Android this is a no-op because the OS allows background network
/// connections to continue without an explicit task request.
class BackgroundTaskService {
  static const _channel = MethodChannel('com.caverno/background_task');

  /// Ask the OS for extra background time. Call this when a long-running
  /// LLM request starts.
  Future<void> beginBackgroundTask() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('beginBackgroundTask');
    } on PlatformException {
      // Silently ignore — background task is best-effort.
    }
  }

  /// Signal that the long-running work is done. Call this when the LLM
  /// response is fully received.
  Future<void> endBackgroundTask() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('endBackgroundTask');
    } on PlatformException {
      // Silently ignore.
    }
  }

  void dispose() {}
}

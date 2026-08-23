import 'dart:io';

import 'package:flutter/foundation.dart';

import '../security/sensitive_data_redactor.dart';
import 'app_log_file.dart';

/// Debug-only logger that suppresses output in release builds.
///
/// In debug builds the message also lands in `~/.caverno/app_logs/<date>.log`,
/// so a stall reproduced without a `flutter run` terminal attached still leaves
/// evidence behind. Tests are excluded: a unit-test run must not write into the
/// developer's home directory.
void appLog(String message) {
  if (!kDebugMode) return;
  appDebugPrint(message);
  if (_isFlutterTest) return;
  AppLogFile.instance.write(message);
}

/// Debug-only console logger that redacts common secrets before output.
void appDebugPrint(String message) {
  if (!kDebugMode) return;
  debugPrint(SensitiveDataRedactor.redactText(message));
}

final bool _isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');

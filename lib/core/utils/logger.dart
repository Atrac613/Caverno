import 'dart:convert';
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

/// Logs a diagnostic value only after recursive key-aware redaction.
///
/// JSON objects and arrays embedded in strings are decoded before redaction so
/// nested credentials cannot bypass the structured boundary through string
/// interpolation.
void appLogDiagnostic(String label, Object? value) {
  appLog('$label: ${formatAppLogDiagnostic(value)}');
}

/// Produces the same recursively redacted representation used by
/// [appLogDiagnostic] for safe exception or status messages.
String formatAppLogDiagnostic(Object? value) {
  final redacted = SensitiveDataRedactor.redactDiagnostic(value);
  return redacted is String ? redacted : jsonEncode(redacted);
}

final bool _isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');

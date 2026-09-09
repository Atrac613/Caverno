import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../security/sensitive_data_redactor.dart';
import 'app_log_file.dart';

/// Logger with debug-only console output and a settings-gated file sink.
///
/// The message also lands in `~/.caverno/app_logs/<date>.log` whenever the
/// Logging settings toggle allows it — including release builds, where there
/// is no attached terminal at all — so a stall still leaves evidence behind.
/// Tests are excluded: a unit-test run must not write into the developer's
/// home directory.
void appLog(String message) {
  if (kDebugMode) {
    appDebugPrint(message);
  }
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

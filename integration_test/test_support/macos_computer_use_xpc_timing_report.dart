import 'dart:convert';
import 'dart:io';

class XpcTimingReportSummary {
  const XpcTimingReportSummary({
    required this.sourcePath,
    required this.status,
    required this.classification,
    required this.ready,
    required this.nextAction,
    this.errorCode,
    this.elapsedMs,
    this.responseReceivedBeforeTimeout,
    this.responseReceivedAfterTimeout,
    this.lateResponseElapsedMs,
    this.selectedIpcTransport,
    this.preferredIpcTransport,
    this.fallbackIpcTransport,
    this.preferredFallbackSucceeded,
  });

  final String sourcePath;
  final String status;
  final String classification;
  final bool ready;
  final String nextAction;
  final String? errorCode;
  final int? elapsedMs;
  final bool? responseReceivedBeforeTimeout;
  final bool? responseReceivedAfterTimeout;
  final int? lateResponseElapsedMs;
  final String? selectedIpcTransport;
  final String? preferredIpcTransport;
  final String? fallbackIpcTransport;
  final bool? preferredFallbackSucceeded;

  Map<String, dynamic> toJson() => {
    'schemaName': 'macos_computer_use_xpc_timing_report_summary',
    'schemaVersion': 1,
    'sourcePath': sourcePath,
    'status': status,
    'classification': classification,
    'ready': ready,
    'nextAction': nextAction,
    if (errorCode != null) 'errorCode': errorCode,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (responseReceivedBeforeTimeout != null)
      'responseReceivedBeforeTimeout': responseReceivedBeforeTimeout,
    if (responseReceivedAfterTimeout != null)
      'responseReceivedAfterTimeout': responseReceivedAfterTimeout,
    if (lateResponseElapsedMs != null)
      'lateResponseElapsedMs': lateResponseElapsedMs,
    if (selectedIpcTransport != null)
      'selectedIpcTransport': selectedIpcTransport,
    if (preferredIpcTransport != null)
      'preferredIpcTransport': preferredIpcTransport,
    if (fallbackIpcTransport != null)
      'fallbackIpcTransport': fallbackIpcTransport,
    if (preferredFallbackSucceeded != null)
      'preferredFallbackSucceeded': preferredFallbackSucceeded,
  };

  String toMarkdown() {
    final rows = [
      ('Status', status),
      ('Classification', classification),
      ('Ready', '$ready'),
      ('Next Action', nextAction),
      if (errorCode != null) ('Error Code', errorCode!),
      if (elapsedMs != null) ('Elapsed', '${elapsedMs}ms'),
      if (responseReceivedBeforeTimeout != null)
        ('Response Before Timeout', '$responseReceivedBeforeTimeout'),
      if (responseReceivedAfterTimeout != null)
        ('Response After Timeout', '$responseReceivedAfterTimeout'),
      if (lateResponseElapsedMs != null)
        ('Late Response Elapsed', '${lateResponseElapsedMs}ms'),
      if (selectedIpcTransport != null) ('Selected IPC', selectedIpcTransport!),
      if (preferredIpcTransport != null)
        ('Preferred IPC', preferredIpcTransport!),
      if (fallbackIpcTransport != null) ('Fallback IPC', fallbackIpcTransport!),
      if (preferredFallbackSucceeded != null)
        ('Fallback Succeeded', '$preferredFallbackSucceeded'),
    ];
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use XPC Timing Report')
      ..writeln()
      ..writeln('- Source: `$sourcePath`')
      ..writeln()
      ..writeln('| Field | Value |')
      ..writeln('| --- | --- |');
    for (final row in rows) {
      buffer.writeln('| ${_markdownCell(row.$1)} | ${_markdownCell(row.$2)} |');
    }
    return buffer.toString();
  }
}

XpcTimingReportSummary readXpcTimingReport(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    throw const FormatException('Expected a JSON object.');
  }
  return buildXpcTimingReportSummary(
    Map<String, dynamic>.from(decoded),
    sourcePath: file.path,
  );
}

XpcTimingReportSummary buildXpcTimingReportSummary(
  Map<String, dynamic> diagnostics, {
  required String sourcePath,
}) {
  final runtime =
      _mapValue(diagnostics['helperIpcRuntime']) ??
      _mapValue(_mapValue(diagnostics['lastResult'])?['helperIpcRuntime']);
  final helperStatus =
      _mapValue(diagnostics['helperStatus']) ??
      _mapValue(_mapValue(diagnostics['lastResult'])?['helperStatus']) ??
      diagnostics;
  final attempt =
      _mapValue(runtime?['preferredIpcAttempt']) ??
      _mapValue(runtime?['lastPreferredIpcAttempt']) ??
      _mapValue(helperStatus['preferredIpcAttempt']) ??
      _mapValue(helperStatus['lastPreferredIpcAttempt']) ??
      _mapValue(diagnostics['preferredIpcAttempt']) ??
      _mapValue(diagnostics['lastPreferredIpcAttempt']);

  final status =
      _stringValue(runtime?['preferredAttemptStatus']) ??
      _stringValue(attempt?['status']) ??
      'missing';
  final errorCode =
      _stringValue(runtime?['preferredAttemptErrorCode']) ??
      _stringValue(attempt?['errorCode']);
  final elapsedMs =
      _intValue(runtime?['preferredAttemptElapsedMs']) ??
      _intValue(attempt?['elapsedMs']);
  final responseBeforeTimeout =
      _boolValue(runtime?['preferredAttemptResponseReceivedBeforeTimeout']) ??
      _boolValue(attempt?['responseReceivedBeforeTimeout']);
  final responseAfterTimeout =
      _boolValue(runtime?['preferredAttemptResponseReceivedAfterTimeout']) ??
      _boolValue(attempt?['responseReceivedAfterTimeout']);
  final lateElapsedMs =
      _intValue(runtime?['preferredAttemptLateResponseElapsedMs']) ??
      _intValue(attempt?['lateResponseElapsedMs']);
  final fallbackSucceeded =
      _boolValue(runtime?['preferredFallbackSucceeded']) ??
      _boolValue(diagnostics['preferredFallbackSucceeded']);

  final classification = _classification(
    status: status,
    responseBeforeTimeout: responseBeforeTimeout,
    responseAfterTimeout: responseAfterTimeout,
  );
  return XpcTimingReportSummary(
    sourcePath: sourcePath,
    status: status,
    classification: classification,
    ready: classification == 'responded_before_timeout',
    nextAction: _nextAction(classification),
    errorCode: errorCode,
    elapsedMs: elapsedMs,
    responseReceivedBeforeTimeout: responseBeforeTimeout,
    responseReceivedAfterTimeout: responseAfterTimeout,
    lateResponseElapsedMs: lateElapsedMs,
    selectedIpcTransport: _stringValue(
      runtime?['selectedIpcTransport'] ?? diagnostics['selectedIpcTransport'],
    ),
    preferredIpcTransport: _stringValue(
      runtime?['preferredIpcTransport'] ?? diagnostics['preferredIpcTransport'],
    ),
    fallbackIpcTransport: _stringValue(
      runtime?['fallbackIpcTransport'] ?? diagnostics['fallbackIpcTransport'],
    ),
    preferredFallbackSucceeded: fallbackSucceeded,
  );
}

String _classification({
  required String status,
  required bool? responseBeforeTimeout,
  required bool? responseAfterTimeout,
}) {
  if (status == 'missing') {
    return 'missing_preferred_attempt';
  }
  if (status == 'xpc_response' || responseBeforeTimeout == true) {
    return 'responded_before_timeout';
  }
  if (status == 'xpc_timeout' && responseAfterTimeout == true) {
    return 'late_response_after_timeout';
  }
  if (status == 'xpc_timeout') {
    return 'no_response_before_timeout';
  }
  if (status.startsWith('xpc_error') || status == 'xpc_proxy_unavailable') {
    return 'xpc_connection_error';
  }
  return 'needs_review';
}

String _nextAction(String classification) {
  return switch (classification) {
    'responded_before_timeout' =>
      'Preferred XPC responded before timeout. No timeout mitigation is needed.',
    'late_response_after_timeout' =>
      'Tune the preferred XPC timeout or add a warmup ping before fallback.',
    'no_response_before_timeout' =>
      'Inspect LaunchAgent registration and helper XPC listener startup.',
    'xpc_connection_error' =>
      'Inspect Mach service registration and helper signing constraints.',
    'missing_preferred_attempt' =>
      'Open Computer Use or recheck permissions, then export diagnostics again.',
    _ => 'Inspect the preferred XPC attempt diagnostics.',
  };
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

String? _stringValue(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}

bool? _boolValue(Object? value) => value is bool ? value : null;

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}

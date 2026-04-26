import 'dart:convert';

import 'macos_computer_use_tool_policy.dart';

class MacosComputerUseAuditEntry {
  const MacosComputerUseAuditEntry({
    required this.timestamp,
    required this.toolName,
    required this.riskCategory,
    required this.approvalResult,
    required this.transport,
    required this.preferredAttemptStatus,
    required this.preferredAttemptErrorCode,
    required this.fallbackReason,
    required this.responseCode,
    required this.success,
  });

  final DateTime timestamp;
  final String toolName;
  final String riskCategory;
  final String approvalResult;
  final String? transport;
  final String? preferredAttemptStatus;
  final String? preferredAttemptErrorCode;
  final String? fallbackReason;
  final String? responseCode;
  final bool success;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'toolName': toolName,
      'riskCategory': riskCategory,
      'approvalResult': approvalResult,
      'transport': transport,
      'preferredAttemptStatus': preferredAttemptStatus,
      'preferredAttemptErrorCode': preferredAttemptErrorCode,
      'fallbackReason': fallbackReason,
      'responseCode': responseCode,
      'success': success,
    };
  }
}

class MacosComputerUseAuditLog {
  MacosComputerUseAuditLog({this.maxEntries = 100});

  static final instance = MacosComputerUseAuditLog();

  final int maxEntries;
  final List<MacosComputerUseAuditEntry> _entries = [];

  List<MacosComputerUseAuditEntry> get entries =>
      List<MacosComputerUseAuditEntry>.unmodifiable(_entries);

  List<Map<String, dynamic>> get redactedEntries {
    return _entries.map((entry) => entry.toJson()).toList(growable: false);
  }

  void clear() {
    _entries.clear();
  }

  void record({
    required String toolName,
    required MacosComputerUseToolPolicyDecision? policy,
    required String approvalResult,
    required bool success,
    String? result,
    String? errorCode,
  }) {
    final decoded = _decodeResult(result);
    final preferredAttempt = _mapValue(decoded?['preferredIpcAttempt']);
    final preferredAttemptStatus = _stringValue(preferredAttempt?['status']);
    final preferredAttemptErrorCode = _stringValue(
      preferredAttempt?['errorCode'],
    );
    final transport =
        _stringValue(decoded?['selectedIpcTransport']) ??
        _stringValue(decoded?['ipcTransport']);
    final responseCode = _stringValue(decoded?['code']) ?? errorCode;
    final entry = MacosComputerUseAuditEntry(
      timestamp: DateTime.now(),
      toolName: toolName,
      riskCategory: policy?.riskCategory.name ?? 'unknown',
      approvalResult: approvalResult,
      transport: transport,
      preferredAttemptStatus: preferredAttemptStatus,
      preferredAttemptErrorCode: preferredAttemptErrorCode,
      fallbackReason: _fallbackReason(
        transport: transport,
        preferredTransport: _stringValue(decoded?['preferredIpcTransport']),
        fallbackTransport: _stringValue(decoded?['fallbackIpcTransport']),
        preferredAttemptStatus: preferredAttemptStatus,
        preferredAttemptErrorCode: preferredAttemptErrorCode,
      ),
      responseCode: responseCode,
      success: success,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  Map<String, dynamic>? _decodeResult(String? result) {
    if (result == null || result.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _stringValue(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String? _fallbackReason({
    required String? transport,
    required String? preferredTransport,
    required String? fallbackTransport,
    required String? preferredAttemptStatus,
    required String? preferredAttemptErrorCode,
  }) {
    if (transport == null ||
        preferredTransport == null ||
        fallbackTransport == null ||
        preferredTransport == fallbackTransport ||
        transport != fallbackTransport ||
        preferredAttemptStatus == null) {
      return null;
    }
    if (preferredAttemptErrorCode == null) {
      return preferredAttemptStatus;
    }
    return '$preferredAttemptStatus ($preferredAttemptErrorCode)';
  }
}

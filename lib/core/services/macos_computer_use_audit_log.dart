import 'dart:convert';

import 'macos_computer_use_tool_policy.dart';

class MacosComputerUseAuditEntry {
  const MacosComputerUseAuditEntry({
    required this.timestamp,
    required this.toolName,
    required this.riskCategory,
    required this.approvalResult,
    required this.transport,
    required this.responseCode,
    required this.success,
  });

  final DateTime timestamp;
  final String toolName;
  final String riskCategory;
  final String approvalResult;
  final String? transport;
  final String? responseCode;
  final bool success;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'toolName': toolName,
      'riskCategory': riskCategory,
      'approvalResult': approvalResult,
      'transport': transport,
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
    final responseCode = _stringValue(decoded?['code']) ?? errorCode;
    final entry = MacosComputerUseAuditEntry(
      timestamp: DateTime.now(),
      toolName: toolName,
      riskCategory: policy?.riskCategory.name ?? 'unknown',
      approvalResult: approvalResult,
      transport:
          _stringValue(decoded?['selectedIpcTransport']) ??
          _stringValue(decoded?['ipcTransport']),
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
}

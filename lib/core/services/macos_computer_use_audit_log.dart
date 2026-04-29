import 'dart:convert';

import 'macos_computer_use_tool_policy.dart';

class MacosComputerUseAuditEntry {
  const MacosComputerUseAuditEntry({
    required this.timestamp,
    required this.toolName,
    required this.toolCategory,
    required this.riskCategory,
    required this.policyLabel,
    required this.requiresUserApproval,
    required this.requiresSmokeArming,
    required this.emergencyStop,
    required this.approvalResult,
    required this.transport,
    required this.preferredAttemptStatus,
    required this.preferredAttemptErrorCode,
    required this.fallbackReason,
    required this.responseCode,
    required this.success,
    required this.postActionObservationRequired,
    required this.postActionObservationToolName,
    required this.postActionObservationSuccess,
    required this.postActionObservationResponseCode,
    required this.postActionObservationTransport,
    required this.postActionObservationSchemaName,
    required this.postActionObservationTarget,
    required this.postActionObservationCoordinateSpace,
    required this.postActionObservationImageAttached,
  });

  final DateTime timestamp;
  final String toolName;
  final String toolCategory;
  final String riskCategory;
  final String policyLabel;
  final bool requiresUserApproval;
  final bool requiresSmokeArming;
  final bool emergencyStop;
  final String approvalResult;
  final String? transport;
  final String? preferredAttemptStatus;
  final String? preferredAttemptErrorCode;
  final String? fallbackReason;
  final String? responseCode;
  final bool success;
  final bool postActionObservationRequired;
  final String? postActionObservationToolName;
  final bool? postActionObservationSuccess;
  final String? postActionObservationResponseCode;
  final String? postActionObservationTransport;
  final String? postActionObservationSchemaName;
  final Map<String, dynamic>? postActionObservationTarget;
  final String? postActionObservationCoordinateSpace;
  final bool? postActionObservationImageAttached;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'toolName': toolName,
      'toolCategory': toolCategory,
      'riskCategory': riskCategory,
      'policyLabel': policyLabel,
      'requiresUserApproval': requiresUserApproval,
      'requiresSmokeArming': requiresSmokeArming,
      'emergencyStop': emergencyStop,
      'approvalResult': approvalResult,
      'transport': transport,
      'preferredAttemptStatus': preferredAttemptStatus,
      'preferredAttemptErrorCode': preferredAttemptErrorCode,
      'fallbackReason': fallbackReason,
      'responseCode': responseCode,
      'success': success,
      'postActionObservationRequired': postActionObservationRequired,
      'postActionObservationToolName': postActionObservationToolName,
      'postActionObservationSuccess': postActionObservationSuccess,
      'postActionObservationResponseCode': postActionObservationResponseCode,
      'postActionObservationTransport': postActionObservationTransport,
      'postActionObservationSchemaName': postActionObservationSchemaName,
      'postActionObservationTarget': postActionObservationTarget,
      'postActionObservationCoordinateSpace':
          postActionObservationCoordinateSpace,
      'postActionObservationImageAttached': postActionObservationImageAttached,
    };
  }
}

class MacosComputerUsePostActionObservation {
  const MacosComputerUsePostActionObservation({
    required this.toolName,
    required this.success,
    this.result,
    this.errorCode,
  });

  final String toolName;
  final bool success;
  final String? result;
  final String? errorCode;
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
    MacosComputerUsePostActionObservation? postActionObservation,
  }) {
    final decoded = _decodeResult(result);
    final observationDecoded = _decodeResult(postActionObservation?.result);
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
      toolCategory: policy?.category.name ?? 'unknown',
      riskCategory: policy?.riskCategory.name ?? 'unknown',
      policyLabel: policy?.policyLabel ?? 'unknown',
      requiresUserApproval: policy?.requiresUserApproval ?? false,
      requiresSmokeArming: policy?.requiresSmokeArming ?? false,
      emergencyStop: policy?.emergencyStop ?? false,
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
      postActionObservationRequired:
          policy?.requiresPostActionObservation == true &&
          approvalResult != 'denied',
      postActionObservationToolName: postActionObservation?.toolName,
      postActionObservationSuccess: postActionObservation?.success,
      postActionObservationResponseCode:
          _stringValue(observationDecoded?['code']) ??
          postActionObservation?.errorCode,
      postActionObservationTransport:
          _stringValue(observationDecoded?['selectedIpcTransport']) ??
          _stringValue(observationDecoded?['ipcTransport']),
      postActionObservationSchemaName: _stringValue(
        observationDecoded?['schemaName'],
      ),
      postActionObservationTarget: _mapValue(observationDecoded?['target']),
      postActionObservationCoordinateSpace: _stringValue(
        observationDecoded?['coordinateSpace'],
      ),
      postActionObservationImageAttached: observationDecoded == null
          ? null
          : observationDecoded['imageBase64'] is String &&
                (observationDecoded['imageBase64'] as String).isNotEmpty,
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

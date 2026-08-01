import 'dart:convert';

import 'background_process_tool_contract.dart';

final class BackgroundProcessStartAssessment {
  const BackgroundProcessStartAssessment._({
    required this.isValid,
    required this.startedNewProcess,
    required this.identity,
  });

  const BackgroundProcessStartAssessment.invalid()
    : this._(isValid: false, startedNewProcess: false, identity: null);

  const BackgroundProcessStartAssessment.valid({
    required bool startedNewProcess,
    required BackgroundProcessIdentity? identity,
  }) : this._(
         isValid: true,
         startedNewProcess: startedNewProcess,
         identity: identity,
       );

  final bool isValid;
  final bool startedNewProcess;
  final BackgroundProcessIdentity? identity;
}

final class BackgroundProcessStartContract {
  const BackgroundProcessStartContract();

  BackgroundProcessStartAssessment assess(
    BackgroundProcessStartResult started, {
    required String expectedToolName,
  }) {
    final result = started.result;
    if (result.toolName != expectedToolName) {
      return const BackgroundProcessStartAssessment.invalid();
    }
    final payload = _decode(result.result);
    final payloadOk = payload?['ok'] == true;
    final duplicate = payload?['duplicate_existing'] == true;
    final payloadJobId = _nonEmptyString(payload?['job_id']);
    final indicatesNewProcess = payloadOk && !duplicate;
    final identity = started.identity;
    if (!_validIdentity(identity, payloadJobId: payloadJobId)) {
      return const BackgroundProcessStartAssessment.invalid();
    }
    final expectedStartedByRequest = indicatesNewProcess && identity != null;
    if (started.startedByRequest != expectedStartedByRequest) {
      return const BackgroundProcessStartAssessment.invalid();
    }
    if (!payloadOk && identity != null) {
      return const BackgroundProcessStartAssessment.invalid();
    }
    return BackgroundProcessStartAssessment.valid(
      startedNewProcess: expectedStartedByRequest,
      identity: identity,
    );
  }

  bool _validIdentity(
    BackgroundProcessIdentity? identity, {
    required String? payloadJobId,
  }) {
    if (identity == null) return payloadJobId == null;
    return identity.externalProcessId.trim().isNotEmpty &&
        identity.backendProcessId.trim().isNotEmpty &&
        payloadJobId == identity.externalProcessId;
  }

  Map<String, dynamic>? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _nonEmptyString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

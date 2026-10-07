import 'dart:convert';

import '../../../../core/utils/logger.dart';
import '../entities/tool_call_info.dart';
import 'proposal_parsing_text_utils.dart';

/// Formats decoded feedback summaries without reading ambient turn state.
abstract final class CodingFeedbackTelemetry {
  static void logDiagnostics(ToolResultInfo feedback) {
    final decoded = ProposalParsingTextUtils.tryDecodeMap(feedback.result);
    if (decoded == null) {
      return;
    }
    final telemetry = decoded['telemetry'];
    final telemetryMap = telemetry is Map<String, dynamic> ? telemetry : null;
    final summary = <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'diagnosticCount':
          decoded['new_diagnostic_count'] ?? decoded['diagnostic_count'],
      'currentDiagnosticCount': decoded['current_diagnostic_count'],
      'baselineDiagnosticCount': decoded['baseline_diagnostic_count'],
      'baselineApplied': decoded['baseline_applied'],
      'files': decoded['changed_paths'],
      if (telemetryMap != null) ...{
        'durationMs': telemetryMap['duration_ms'],
        'commandAttemptCount': telemetryMap['command_attempt_count'],
        'fallbackCommandCount': telemetryMap['fallback_command_count'],
        'timedOutCommandCount': telemetryMap['timed_out_command_count'],
        'startErrorCommandCount': telemetryMap['start_error_command_count'],
      },
    };
    appLog(
      '[CodingDiagnostics] Analyzer feedback summary: ${jsonEncode(summary)}',
    );
  }

  static void logOutput(ToolResultInfo feedback) {
    final decoded = ProposalParsingTextUtils.tryDecodeMap(feedback.result);
    if (decoded == null) {
      return;
    }
    final issues = decoded['issues'];
    final issueList = issues is List ? issues : const [];
    final summary = <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'validationStatus': decoded['validation_status'],
      'issueCount': issueList.length,
      'commands': issueList
          .whereType<Map>()
          .map((issue) => issue['command']?.toString())
          .whereType<String>()
          .where((command) => command.trim().isNotEmpty)
          .toList(growable: false),
    };
    appLog('[CodingOutputGuardrail] Feedback summary: ${jsonEncode(summary)}');
  }
}

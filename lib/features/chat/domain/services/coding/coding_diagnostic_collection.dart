import '../../../../../core/utils/logger.dart';
import '../../entities/tool_call_info.dart';
import 'coding_command_output_guardrail_service.dart';
import 'coding_diagnostic_feedback_service.dart';
import 'coding_feedback_telemetry.dart';

/// Collects diagnostics with an explicit symbol-refresh port and failure boundary.
abstract final class CodingDiagnosticCollection {
  static Future<ToolResultInfo?> feedback({
    required CodingDiagnosticFeedbackService service,
    required String projectRoot,
    required List<String> changedPaths,
    CodingDiagnosticFeedbackBaseline? baseline,
    required Future<void> Function() refreshSymbols,
  }) async {
    try {
      final feedback = await service.buildFeedbackToolResult(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
        baseline: baseline,
      );
      if (feedback != null) {
        appLog(
          '[CodingDiagnostics] Added diagnostic feedback for '
          '${changedPaths.length} changed file(s)',
        );
        CodingFeedbackTelemetry.logDiagnostics(feedback);
      }
      await refreshSymbols();
      return feedback;
    } catch (error, stackTrace) {
      appLog(
        '[CodingDiagnostics] Failed to collect diagnostic feedback: $error',
      );
      appLog('[CodingDiagnostics] stackTrace: $stackTrace');
      return null;
    }
  }

  static Future<CodingDiagnosticFeedbackBaseline?> baseline({
    required CodingDiagnosticFeedbackService service,
    required String projectRoot,
    required List<String> changedPaths,
  }) async {
    try {
      return await service.captureBaseline(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
      );
    } catch (error, stackTrace) {
      appLog('[CodingDiagnostics] Failed to capture analyzer baseline: $error');
      appLog('[CodingDiagnostics] stackTrace: $stackTrace');
      return null;
    }
  }

  static ToolResultInfo? outputFeedback(List<ToolResultInfo> toolResults) {
    try {
      final feedback = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(toolResults: toolResults);
      if (feedback != null) {
        appLog(
          '[CodingOutputGuardrail] Added command output feedback for '
          '${toolResults.length} tool result(s)',
        );
        CodingFeedbackTelemetry.logOutput(feedback);
      }
      return feedback;
    } catch (error, stackTrace) {
      appLog(
        '[CodingOutputGuardrail] Failed to inspect command outputs: $error',
      );
      appLog('[CodingOutputGuardrail] stackTrace: $stackTrace');
      return null;
    }
  }
}

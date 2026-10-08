import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/coding_command_output_guardrail_service.dart';
import '../../domain/services/plan/proposal_parsing_text_utils.dart';
import '../../domain/services/tool_call_execution_policy.dart';

/// Whether verification evidence gathered after a saved validation succeeded
/// still shows a failure that needs repair. Pure, moved out of ChatNotifier.
final class SavedValidationRepairEvidence {
  const SavedValidationRepairEvidence();

  bool requiresRepair(List<ToolResultInfo> toolResults) {
    for (final result in toolResults) {
      if (result.name == CodingCommandOutputGuardrailService.toolName) {
        final payload = ProposalParsingTextUtils.tryDecodeMap(result.result);
        if (payload?['success'] == false ||
            payload?['validation_status'] == 'failed') {
          return true;
        }
      }
      final effect = const ToolCapabilityClassifier()
          .classify(result.name, arguments: result.arguments)
          .commandEffect;
      if (effect != ToolCommandEffect.verification) {
        continue;
      }
      if (!const ToolCallExecutionPolicy().toolResultHasSuccessfulExit(
        result,
      )) {
        return true;
      }
      final output = const ToolCallExecutionPolicy()
          .toolResultOutputText(result)
          .toLowerCase();
      if (output.contains('unhandled exception') ||
          output.contains('stack trace') ||
          output.contains('traceback (most recent call last)') ||
          output.contains('assertionerror') ||
          output.contains('validation failed') ||
          output.contains('validation failure')) {
        return true;
      }
    }
    return false;
  }
}

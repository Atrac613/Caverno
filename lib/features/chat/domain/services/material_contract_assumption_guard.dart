import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/types/workspace_mode.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

// ChatNotifier decomposition collaborator: material-contract-assumption-guard

/// Blocks state mutation while an owning workflow has a material assumption.
final class MaterialContractAssumptionGuard {
  const MaterialContractAssumptionGuard();

  static const blockedCode = 'material_contract_assumption_unconfirmed';
  static const _capabilityClassifier = ToolCapabilityClassifier();

  McpToolResult? evaluate(
    ToolCallInfo toolCall, {
    required WorkspaceMode workspaceMode,
    required List<ConversationContractItemProvenance> blockingAssumptions,
  }) {
    if (workspaceMode != WorkspaceMode.coding ||
        blockingAssumptions.isEmpty ||
        !isContractMutation(toolCall)) {
      return null;
    }

    final assumptions = List<ConversationContractItemProvenance>.unmodifiable(
      blockingAssumptions,
    );
    final firstAssumption = assumptions.first;
    final question =
        firstAssumption.normalizedClarificationQuestion ??
        'Please confirm the material ${firstAssumption.kind.name} assumption.';
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': blockedCode,
        'error':
            'State mutation is blocked until the user confirms a material contract assumption.',
        'clarification_question': question,
        'required_action':
            'Ask the user this one focused clarification question and wait for confirmation before mutating state.',
      }),
      isSuccess: false,
      errorMessage: 'Confirm the material contract assumption first.',
    );
  }

  bool isContractMutation(ToolCallInfo toolCall) {
    final effect = _capabilityClassifier
        .classify(toolCall.name, arguments: toolCall.arguments)
        .commandEffect;
    return switch (effect) {
      ToolCommandEffect.inspection ||
      ToolCommandEffect.verification ||
      ToolCommandEffect.unknown => false,
      _ => true,
    };
  }
}

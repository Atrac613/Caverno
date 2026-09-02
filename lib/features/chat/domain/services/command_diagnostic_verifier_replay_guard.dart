import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'command_diagnostic_verifier_replay_policy.dart';
import 'immutable_json_snapshot.dart';
import 'stalled_diagnostic_repair_contract.dart';

// ChatNotifier decomposition collaborator: command-diagnostic-verifier-replay-guard

/// Immutable owner-turn facts used to evaluate one verifier replay.
final class CommandDiagnosticVerifierReplayInput {
  CommandDiagnosticVerifierReplayInput({
    required ToolCallInfo currentToolCall,
    required this.focus,
    required this.attemptedCommandKey,
    required this.commandEffect,
    required List<ToolCallInfo> pendingToolCalls,
  }) : currentToolCall = _freezeToolCall(currentToolCall),
       pendingToolCalls = List<ToolCallInfo>.unmodifiable(
         pendingToolCalls.map(_freezeToolCall),
       );

  final ToolCallInfo currentToolCall;
  final CommandDiagnosticRepairFocus? focus;
  final String attemptedCommandKey;
  final ToolCommandEffect commandEffect;
  final List<ToolCallInfo> pendingToolCalls;
}

/// Structured fields the notifier uses to preserve the existing log line.
final class CommandDiagnosticVerifierReplayLogFields {
  const CommandDiagnosticVerifierReplayLogFields({
    required this.signatureStreak,
    required this.commandKey,
    required this.toolCallId,
  });

  final int signatureStreak;
  final String commandKey;
  final String toolCallId;
}

/// Result and optional log facts for one replay-guard evaluation.
final class CommandDiagnosticVerifierReplayDecision {
  const CommandDiagnosticVerifierReplayDecision.allowed()
    : result = null,
      logFields = null;

  const CommandDiagnosticVerifierReplayDecision.blocked({
    required this.result,
    required this.logFields,
  });

  final McpToolResult? result;
  final CommandDiagnosticVerifierReplayLogFields? logFields;

  bool get isBlocked => result != null;
}

/// Blocks an unchanged path-backed verifier until a mutation precedes it.
final class CommandDiagnosticVerifierReplayGuard {
  const CommandDiagnosticVerifierReplayGuard();

  static const blockedCode = 'unchanged_verifier_replay_before_repair_blocked';
  static const _policy = CommandDiagnosticVerifierReplayPolicy();
  static const _capabilityClassifier = ToolCapabilityClassifier();

  CommandDiagnosticVerifierReplayDecision evaluate(
    CommandDiagnosticVerifierReplayInput input,
  ) {
    final toolCallIndex = input.pendingToolCalls.indexWhere(
      (toolCall) => toolCall.id == input.currentToolCall.id,
    );
    final hasPrecedingMutation =
        toolCallIndex > 0 &&
        input.pendingToolCalls.take(toolCallIndex).any(_isContractMutation);
    if (!_policy.shouldBlock(
      focus: input.focus,
      attemptedCommandKey: input.attemptedCommandKey,
      isVerification: input.commandEffect == ToolCommandEffect.verification,
      hasPrecedingMutation: hasPrecedingMutation,
    )) {
      return const CommandDiagnosticVerifierReplayDecision.allowed();
    }

    final activeFocus = input.focus!;
    return CommandDiagnosticVerifierReplayDecision.blocked(
      result: McpToolResult(
        toolName: input.currentToolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': blockedCode,
          ...ToolResultOrigin.harness.marker,
          'error':
              'The same verifier was not rerun because its path-backed diagnostic '
              'has not been addressed by a mutation.',
          'diagnostic': activeFocus.diagnosticSummary,
          'required_action':
              'Make one concrete mutation that directly addresses the sourced '
              'diagnostic, then rerun this verifier.',
        }),
        isSuccess: true,
      ),
      logFields: CommandDiagnosticVerifierReplayLogFields(
        signatureStreak: activeFocus.streak,
        commandKey: activeFocus.commandKey,
        toolCallId: input.currentToolCall.id,
      ),
    );
  }

  bool matches(McpToolResult result) {
    try {
      final decoded = jsonDecode(result.result);
      return decoded is Map<String, dynamic> && decoded['code'] == blockedCode;
    } on FormatException {
      return false;
    }
  }

  bool _isContractMutation(ToolCallInfo toolCall) {
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

ToolCallInfo _freezeToolCall(ToolCallInfo source) {
  return ToolCallInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  );
}

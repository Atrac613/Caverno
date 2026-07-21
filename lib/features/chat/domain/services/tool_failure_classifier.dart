import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';

enum ToolResultDisposition {
  success,
  actionableCommandFailure,
  approvalDenied,
  executionFailure,
}

class ToolFailureClassifier {
  const ToolFailureClassifier({
    ToolCallExecutionPolicy toolCallExecutionPolicy =
        const ToolCallExecutionPolicy(),
  }) : _toolCallExecutionPolicy = toolCallExecutionPolicy;

  final ToolCallExecutionPolicy _toolCallExecutionPolicy;

  ToolResultDisposition classify(ToolCallInfo toolCall, McpToolResult result) {
    if (result.isSuccess) {
      return ToolResultDisposition.success;
    }
    if (isApprovalDenial(result)) {
      return ToolResultDisposition.approvalDenied;
    }
    if (_toolCallExecutionPolicy.isCommandExecutionTool(toolCall.name) &&
        _isActionableCommandFailure(result)) {
      return ToolResultDisposition.actionableCommandFailure;
    }
    return ToolResultDisposition.executionFailure;
  }

  bool isApprovalDenial(McpToolResult result) {
    if (result.isSuccess) {
      return false;
    }
    final haystack = '${result.errorMessage ?? ''}\n${result.result}'
        .toLowerCase();
    return haystack.contains('denied') || haystack.contains('auto-review');
  }

  String lifecycleResultStatus(ToolCallInfo toolCall, McpToolResult result) {
    return switch (classify(toolCall, result)) {
      ToolResultDisposition.success => 'success',
      ToolResultDisposition.actionableCommandFailure => 'command_failure',
      ToolResultDisposition.approvalDenied ||
      ToolResultDisposition.executionFailure => 'tool_failure',
    };
  }

  /// Whether the command ran and reported failure, as opposed to never
  /// reaching an exit (denied, timed out, failed to spawn) — only the former
  /// gives the model something it can act on.
  ///
  /// Prefers the structured outcome when the tool reported one. Falls back to
  /// decoding the result payload for third-party MCP results and for
  /// first-party tools that have not been migrated to report an outcome yet.
  bool _isActionableCommandFailure(McpToolResult result) {
    final outcome = result.outcome;
    if (outcome != null && outcome.exitCode != null) {
      // A reported exit status already proves the process ran to completion,
      // which is the only thing the payload inspection below was ever
      // establishing. Timeouts, denials, and spawn failures never carry an
      // exit code (see `ToolOutcome.exitCode`), so they cannot reach here.
      return outcome.hasFailingExitCode;
    }
    return _isActionableCommandFailureFromPayload(result.result);
  }

  /// Fallback for results with no structured outcome: third-party MCP tools,
  /// and first-party tools not yet migrated to report one.
  ///
  /// Infers "a command ran and failed" from the payload's shape — a non-zero
  /// `exit_code` accompanied by output keys, with timeouts and explicit errors
  /// excluded. The outcome path above needs none of this because it is told.
  bool _isActionableCommandFailureFromPayload(String rawResult) {
    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      final exitCode = decoded['exit_code'];
      if (exitCode is! num || exitCode.toInt() == 0) {
        return false;
      }
      if (decoded['timed_out'] == true || _hasExplicitError(decoded['error'])) {
        return false;
      }
      return decoded.containsKey('stdout') ||
          decoded.containsKey('stderr') ||
          decoded['diagnostics'] is List;
    } on FormatException {
      return false;
    }
  }

  bool _hasExplicitError(Object? value) {
    if (value == null) {
      return false;
    }
    return value is! String || value.trim().isNotEmpty;
  }
}

import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';
import 'tool_outcome_shadow_comparison.dart';

enum ToolResultDisposition {
  success,
  actionableCommandFailure,
  approvalDenied,
  executionFailure,
}

class ToolFailureClassification {
  const ToolFailureClassification({
    required this.disposition,
    required this.exitCodeSource,
  });

  final ToolResultDisposition disposition;
  final ToolOutcomeVerdictSource exitCodeSource;
}

class ToolFailureClassifier {
  const ToolFailureClassifier({
    ToolCallExecutionPolicy toolCallExecutionPolicy =
        const ToolCallExecutionPolicy(),
  }) : _toolCallExecutionPolicy = toolCallExecutionPolicy;

  final ToolCallExecutionPolicy _toolCallExecutionPolicy;

  ToolResultDisposition classify(ToolCallInfo toolCall, McpToolResult result) =>
      inspect(toolCall, result).disposition;

  ToolFailureClassification inspect(
    ToolCallInfo toolCall,
    McpToolResult result,
  ) {
    if (result.isSuccess) {
      return const ToolFailureClassification(
        disposition: ToolResultDisposition.success,
        exitCodeSource: ToolOutcomeVerdictSource.unavailable,
      );
    }
    if (isApprovalDenial(result)) {
      return const ToolFailureClassification(
        disposition: ToolResultDisposition.approvalDenied,
        exitCodeSource: ToolOutcomeVerdictSource.unavailable,
      );
    }
    if (_toolCallExecutionPolicy.isCommandExecutionTool(toolCall.name)) {
      final commandFailure = _inspectActionableCommandFailure(result);
      return ToolFailureClassification(
        disposition: commandFailure.actionable
            ? ToolResultDisposition.actionableCommandFailure
            : ToolResultDisposition.executionFailure,
        exitCodeSource: commandFailure.exitCodeSource,
      );
    }
    return const ToolFailureClassification(
      disposition: ToolResultDisposition.executionFailure,
      exitCodeSource: ToolOutcomeVerdictSource.unavailable,
    );
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
  _ActionableCommandFailureInspection _inspectActionableCommandFailure(
    McpToolResult result,
  ) {
    final outcome = result.outcome;
    if (outcome != null && outcome.exitCode != null) {
      // A reported exit status already proves the process ran to completion,
      // which is the only thing the payload inspection below was ever
      // establishing. Timeouts, denials, and spawn failures never carry an
      // exit code (see `ToolOutcome.exitCode`), so they cannot reach here.
      return _ActionableCommandFailureInspection(
        actionable: outcome.hasFailingExitCode,
        exitCodeSource: ToolOutcomeVerdictSource.typed,
      );
    }
    return _isActionableCommandFailureFromPayload(result.result);
  }

  /// Fallback for results with no structured outcome: third-party MCP tools,
  /// and first-party tools not yet migrated to report one.
  ///
  /// Infers "a command ran and failed" from the payload's shape — a non-zero
  /// `exit_code` accompanied by output keys, with timeouts and explicit errors
  /// excluded. The outcome path above needs none of this because it is told.
  _ActionableCommandFailureInspection _isActionableCommandFailureFromPayload(
    String rawResult,
  ) {
    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is! Map<String, dynamic>) {
        return const _ActionableCommandFailureInspection();
      }
      final exitCode = decoded['exit_code'];
      if (exitCode is! num) {
        return const _ActionableCommandFailureInspection();
      }
      final source = ToolOutcomeVerdictSource.lexicalFallback;
      if (exitCode.toInt() == 0 ||
          decoded['timed_out'] == true ||
          _hasExplicitError(decoded['error'])) {
        return _ActionableCommandFailureInspection(exitCodeSource: source);
      }
      return _ActionableCommandFailureInspection(
        actionable:
            decoded.containsKey('stdout') ||
            decoded.containsKey('stderr') ||
            decoded['diagnostics'] is List,
        exitCodeSource: source,
      );
    } on FormatException {
      return const _ActionableCommandFailureInspection();
    }
  }

  bool _hasExplicitError(Object? value) {
    if (value == null) {
      return false;
    }
    return value is! String || value.trim().isNotEmpty;
  }
}

class _ActionableCommandFailureInspection {
  const _ActionableCommandFailureInspection({
    this.actionable = false,
    this.exitCodeSource = ToolOutcomeVerdictSource.unavailable,
  });

  final bool actionable;
  final ToolOutcomeVerdictSource exitCodeSource;
}

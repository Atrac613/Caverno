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
        _isActionableCommandFailure(result.result)) {
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

  bool _isActionableCommandFailure(String rawResult) {
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

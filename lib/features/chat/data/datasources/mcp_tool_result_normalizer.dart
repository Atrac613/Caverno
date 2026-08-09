import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/mcp_tool_entity.dart';
import 'first_party_tool_execution_result.dart';

/// Builds compatible tool results from direct, JSON, and command outcomes.
abstract final class McpToolResultNormalizer {
  static McpToolResult success({
    required String toolName,
    required String result,
    bool isExternalMcpResult = false,
    ToolOutcome? outcome,
  }) => McpToolResult(
    toolName: toolName,
    result: result,
    isSuccess: true,
    isExternalMcpResult: isExternalMcpResult,
    outcome: outcome,
  );

  static McpToolResult failure({
    required String toolName,
    String result = '',
    required String errorMessage,
    bool isExternalMcpResult = false,
    ToolOutcome? outcome,
  }) => McpToolResult(
    toolName: toolName,
    result: result,
    isSuccess: false,
    errorMessage: errorMessage,
    isExternalMcpResult: isExternalMcpResult,
    outcome: outcome,
  );

  static McpToolResult structuredFailure({
    required String toolName,
    required Map<String, dynamic> payload,
    required String errorMessage,
    bool isExternalMcpResult = false,
  }) => failure(
    toolName: toolName,
    result: jsonEncode(payload),
    errorMessage: errorMessage,
    isExternalMcpResult: isExternalMcpResult,
  );

  static McpToolResult fromOkPayload({
    required String toolName,
    required String result,
    required String fallbackErrorMessage,
    bool isExternalMcpResult = false,
  }) {
    final decoded = _tryDecodeMap(result);
    return decoded == null || decoded['ok'] != false
        ? success(
            toolName: toolName,
            result: result,
            isExternalMcpResult: isExternalMcpResult,
          )
        : failure(
            toolName: toolName,
            result: result,
            errorMessage: decoded['error'] as String? ?? fallbackErrorMessage,
            isExternalMcpResult: isExternalMcpResult,
          );
  }

  static McpToolResult fromFirstPartyExecution({
    required String toolName,
    required FirstPartyToolExecutionResult execution,
    bool isExternalMcpResult = false,
  }) {
    return execution.errorMessage == null
        ? success(
            toolName: toolName,
            result: execution.result,
            isExternalMcpResult: isExternalMcpResult,
            outcome: execution.outcome,
          )
        : failure(
            toolName: toolName,
            result: execution.result,
            errorMessage: execution.errorMessage!,
            isExternalMcpResult: isExternalMcpResult,
            outcome: execution.outcome,
          );
  }

  static Map<String, dynamic>? _tryDecodeMap(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

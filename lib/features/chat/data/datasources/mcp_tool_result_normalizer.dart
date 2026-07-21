import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/mcp_tool_entity.dart';
import 'command_payload_facts.dart';

/// Builds compatible tool results from direct, JSON, and command outcomes.
abstract final class McpToolResultNormalizer {
  static McpToolResult success({
    required String toolName,
    required String result,
    bool isExternalMcpResult = false,
    ToolOutcome? outcome,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: result,
      isSuccess: true,
      isExternalMcpResult: isExternalMcpResult,
      outcome: outcome,
    );
  }

  static McpToolResult failure({
    required String toolName,
    String result = '',
    required String errorMessage,
    bool isExternalMcpResult = false,
    ToolOutcome? outcome,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: result,
      isSuccess: false,
      errorMessage: errorMessage,
      isExternalMcpResult: isExternalMcpResult,
      outcome: outcome,
    );
  }

  static McpToolResult structuredFailure({
    required String toolName,
    required Map<String, dynamic> payload,
    required String errorMessage,
    bool isExternalMcpResult = false,
  }) {
    return failure(
      toolName: toolName,
      result: jsonEncode(payload),
      errorMessage: errorMessage,
      isExternalMcpResult: isExternalMcpResult,
    );
  }

  static McpToolResult fromOkPayload({
    required String toolName,
    required String result,
    required String fallbackErrorMessage,
    bool isExternalMcpResult = false,
  }) {
    final decoded = CommandPayloadFacts.tryDecodeMap(result);
    if (decoded == null || decoded['ok'] != false) {
      return success(
        toolName: toolName,
        result: result,
        isExternalMcpResult: isExternalMcpResult,
      );
    }
    return failure(
      toolName: toolName,
      result: result,
      errorMessage: decoded['error'] as String? ?? fallbackErrorMessage,
      isExternalMcpResult: isExternalMcpResult,
    );
  }

  /// Normalizes a first-party command tool's payload, lifting the facts it
  /// reported (see [CommandPayloadFacts]) onto the result so downstream
  /// consumers read them instead of decoding the payload again.
  static McpToolResult fromCommandPayload({
    required String toolName,
    required String result,
    required String toolLabel,
    bool isExternalMcpResult = false,
  }) {
    final facts = CommandPayloadFacts.tryParse(result);
    final outcome = facts?.toOutcome();
    final failureMessage = facts?.failureMessage(toolLabel);
    if (failureMessage == null) {
      return success(
        toolName: toolName,
        result: result,
        isExternalMcpResult: isExternalMcpResult,
        outcome: outcome,
      );
    }
    return failure(
      toolName: toolName,
      result: result,
      errorMessage: failureMessage,
      isExternalMcpResult: isExternalMcpResult,
      outcome: outcome,
    );
  }
}

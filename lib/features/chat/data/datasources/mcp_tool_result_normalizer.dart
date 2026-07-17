import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';

/// Builds compatible tool results from direct, JSON, and command outcomes.
abstract final class McpToolResultNormalizer {
  static McpToolResult success({
    required String toolName,
    required String result,
    bool isExternalMcpResult = false,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: result,
      isSuccess: true,
      isExternalMcpResult: isExternalMcpResult,
    );
  }

  static McpToolResult failure({
    required String toolName,
    String result = '',
    required String errorMessage,
    bool isExternalMcpResult = false,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: result,
      isSuccess: false,
      errorMessage: errorMessage,
      isExternalMcpResult: isExternalMcpResult,
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
    final decoded = _tryDecodeMap(result);
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

  static McpToolResult fromCommandPayload({
    required String toolName,
    required String result,
    required String toolLabel,
    bool isExternalMcpResult = false,
  }) {
    final failureMessage = _commandFailureMessage(result, toolLabel);
    if (failureMessage == null) {
      return success(
        toolName: toolName,
        result: result,
        isExternalMcpResult: isExternalMcpResult,
      );
    }
    return failure(
      toolName: toolName,
      result: result,
      errorMessage: failureMessage,
      isExternalMcpResult: isExternalMcpResult,
    );
  }

  static String? _commandFailureMessage(String result, String toolLabel) {
    final decoded = _tryDecodeMap(result);
    if (decoded == null) return null;

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }

    final exitCode = decoded['exit_code'];
    if (exitCode is! num || exitCode.toInt() == 0) {
      return null;
    }
    final stderr = decoded['stderr'];
    final stdout = decoded['stdout'];
    final detail = stderr is String && stderr.trim().isNotEmpty
        ? stderr.trim()
        : stdout is String && stdout.trim().isNotEmpty
        ? stdout.trim()
        : null;
    return detail == null
        ? '$toolLabel exited with code ${exitCode.toInt()}'
        : '$toolLabel exited with code ${exitCode.toInt()}: $detail';
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

import 'package:freezed_annotation/freezed_annotation.dart';

part 'mcp_tool_entity.freezed.dart';
part 'mcp_tool_entity.g.dart';

/// Entity that describes an MCP tool definition.
@freezed
abstract class McpToolEntity with _$McpToolEntity {
  const McpToolEntity._();

  const factory McpToolEntity({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    String? originalName,
    String? sourceUrl,
  }) = _McpToolEntity;

  factory McpToolEntity.fromJson(Map<String, dynamic> json) =>
      _$McpToolEntityFromJson(json);

  /// Converts the tool definition to the OpenAI tool format.
  Map<String, dynamic> toOpenAiTool() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': sourceUrl == null
          ? description
          : '$description (MCP server: ${_formatMcpServerLabel(sourceUrl!)})',
      'parameters': inputSchema,
    },
  };
}

/// Result of an MCP tool execution.
@freezed
abstract class McpToolResult with _$McpToolResult {
  const factory McpToolResult({
    required String toolName,
    required String result,
    required bool isSuccess,
    String? errorMessage,
  }) = _McpToolResult;

  factory McpToolResult.fromJson(Map<String, dynamic> json) =>
      _$McpToolResultFromJson(json);
}

/// MCP connection status.
enum McpConnectionStatus {
  /// Disconnected
  disconnected,

  /// Connecting
  connecting,

  /// Connected
  connected,

  /// Error
  error,
}

class McpServerConnectionInfo {
  const McpServerConnectionInfo({
    required this.identifier,
    required this.status,
    this.toolCount = 0,
    this.lastError,
  });

  final String identifier;
  final McpConnectionStatus status;
  final int toolCount;
  final String? lastError;
}

String _formatMcpServerLabel(String rawIdentifier) {
  final uri = Uri.tryParse(rawIdentifier);
  if (uri == null || uri.host.isEmpty) {
    // Non-URL identifier (e.g. stdio command).
    return rawIdentifier.length > 40
        ? '${rawIdentifier.substring(0, 40)}...'
        : rawIdentifier;
  }

  final buffer = StringBuffer(uri.host);
  if (uri.hasPort) {
    buffer.write(':${uri.port}');
  }
  return buffer.toString();
}

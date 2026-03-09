import 'package:freezed_annotation/freezed_annotation.dart';

part 'mcp_tool_entity.freezed.dart';
part 'mcp_tool_entity.g.dart';

/// MCPツールの定義エンティティ
@freezed
abstract class McpToolEntity with _$McpToolEntity {
  const McpToolEntity._();

  const factory McpToolEntity({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
  }) = _McpToolEntity;

  factory McpToolEntity.fromJson(Map<String, dynamic> json) =>
      _$McpToolEntityFromJson(json);

  /// OpenAI形式のツール定義に変換
  Map<String, dynamic> toOpenAiTool() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}

/// MCPツール実行結果
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

/// MCP接続状態
enum McpConnectionStatus {
  /// 未接続
  disconnected,

  /// 接続中
  connecting,

  /// 接続済み
  connected,

  /// エラー
  error,
}

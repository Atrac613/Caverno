import 'dart:convert' as dart_convert;

import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';

/// Debug logging for outgoing requests and native tool calls.
///
/// Extracted from `ChatRemoteDataSource`, which is about issuing requests, not
/// about how they are rendered into the log.
final class ChatRequestLogger {
  const ChatRequestLogger();

  /// Full tool schemas are opt-in: they are large enough to bury everything
  /// else in the log.
  static const bool _logToolSchemas = bool.fromEnvironment(
    'CAVERNO_LLM_LOG_TOOL_SCHEMAS',
  );
  static const int _maxLoggedToolNames = 12;

  void logMessages(List<Message> messages) {
    appLog('[LLM] === Request Messages ===');
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final contentPreview = m.content.length > 200
          ? '${m.content.substring(0, 200)}...'
          : m.content;
      final hasImage = m.imageBase64 != null ? ' [has image]' : '';
      appLog('[LLM]   [$i] ${m.role.name}$hasImage: $contentPreview');
    }
    appLog('[LLM] === End Messages ===');
  }

  void logTools(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.isEmpty) return;
    appLog(formatToolLogSummary(tools));
    if (!_logToolSchemas) {
      return;
    }

    appLog('[LLM] === Tool Schemas ===');
    for (final tool in tools) {
      final func = tool['function'] as Map<String, dynamic>;
      appLog('[LLM]   ${func['name']}: ${func['description']}');
      appLog(
        '[LLM]     params: ${dart_convert.jsonEncode(func['parameters'])}',
      );
    }
    appLog('[LLM] === End Tool Schemas ===');
  }

  /// Logs a response body under [label], truncated to a readable preview.
  void logResponseBody(String label, String text) {
    appLog('[LLM] === Response ($label) ===');
    appLog('[LLM] ${preview(text)}');
  }

  /// Logs the tool calls and results a follow-up request carries.
  ///
  /// Takes the formatter rather than the raw result so the log shows the text
  /// the model will actually read, interpretation lines included.
  void logToolExchange(
    List<ToolResultInfo> toolResults,
    String Function(ToolResultInfo toolResult) formatContent,
  ) {
    for (final toolResult in toolResults) {
      appLog('[LLM] === Tool Call Info ===');
      appLog('[LLM] toolCallId: ${toolResult.id}');
      appLog('[LLM] toolName: ${toolResult.name}');
      appLog(
        '[LLM] arguments: ${dart_convert.jsonEncode(toolResult.arguments)}',
      );
      appLog('[LLM] === Tool Result ===');
      appLog('[LLM] ${preview(formatContent(toolResult))}');
      appLog('[LLM] === End Tool Result ===');
    }
  }

  /// First 500 characters of [value], which is where the useful part of a
  /// response or a tool result lives when triaging a log.
  String preview(String value) =>
      value.length > 500 ? '${value.substring(0, 500)}...' : value;

  void logNativeToolCalls(List<ToolCall>? toolCalls) {
    if (toolCalls == null || toolCalls.isEmpty) {
      return;
    }
    appLog('[LLM] === Tool Calls ===');
    for (final toolCall in toolCalls) {
      appLog('[LLM]   id: ${toolCall.id}');
      appLog('[LLM]   name: ${toolCall.function.name}');
      appLog('[LLM]   arguments: ${toolCall.function.arguments}');
    }
    appLog('[LLM] === End Tool Calls ===');
  }

  void logNativeToolArgumentError(Object error) {
    appLog('[LLM]   Failed to parse arguments: $error');
  }

  String formatToolLogSummary(List<Map<String, dynamic>> tools) {
    final names = _toolLogNames(tools);
    if (names.isEmpty) {
      return '[LLM] Tools available: ${tools.length}';
    }
    final visibleNames = names.take(_maxLoggedToolNames).join(', ');
    final omittedCount = names.length - _maxLoggedToolNames;
    final omittedSuffix = omittedCount > 0 ? ', +$omittedCount more' : '';
    return '[LLM] Tools available: ${tools.length} '
        '($visibleNames$omittedSuffix)';
  }

  List<String> _toolLogNames(List<Map<String, dynamic>> tools) {
    return tools
        .map((tool) => tool['function'])
        .whereType<Map>()
        .map((function) => function['name'])
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }
}

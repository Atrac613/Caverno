import 'dart:convert' as dart_convert;

import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';

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

import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_tool_result_pruner.dart';

void main() {
  final fileContent = List<String>.generate(
    240,
    (index) => 'line ${index + 1}: synthetic configuration value',
  ).join('\n');
  final renderedRead =
      '[Tool: read_file]\n'
      'Arguments: ${jsonEncode({'path': 'lib/config.dart'})}\n'
      'Result:\n'
      '${jsonEncode({'path': 'lib/config.dart', 'content': fileContent})}';
  final messages = List<Message>.generate(
    12,
    (index) => Message(
      id: 'read-$index',
      content: renderedRead,
      role: MessageRole.user,
      timestamp: DateTime(2026, 7, 21, 12, index),
    ),
  );

  final beforeTokens = ConversationCompactionService.estimatePromptTokens(
    messages,
  );
  final result = ConversationToolResultPruner.prune(messages);
  final afterTokens = ConversationCompactionService.estimatePromptTokens(
    result.messages,
  );
  final tokenSavings = beforeTokens - afterTokens;
  final tokenSavingsRatio = beforeTokens == 0
      ? 0.0
      : tokenSavings / beforeTokens;

  stdout.writeln('== LL30 structural prune synthetic measurement ==');
  stdout.writeln('messages: ${messages.length}');
  stdout.writeln('summarized results: ${result.summarizedResultCount}');
  stdout.writeln('duplicate results: ${result.duplicateResultCount}');
  stdout.writeln('estimated prompt tokens: $beforeTokens -> $afterTokens');
  stdout.writeln(
    'estimated token savings: $tokenSavings '
    '(${(tokenSavingsRatio * 100).toStringAsFixed(1)}%)',
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';

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
    60,
    (index) => Message(
      id: 'read-$index',
      content: renderedRead,
      role: MessageRole.user,
      timestamp: DateTime(2026, 7, 21, 12, index),
    ),
  );

  final artifact = ConversationCompactionService.buildArtifact(
    messages: messages,
    now: DateTime(2026, 7, 21, 12, 0),
  );
  if (artifact == null) {
    stderr.writeln('Expected the synthetic conversation to compact.');
    exitCode = 1;
    return;
  }
  final retainedBefore = messages.sublist(artifact.compactedMessageCount);
  final retainedAfter = ConversationCompactionService.retainMessages(
    messages: messages,
    artifact: artifact,
  );
  final summaryTokens = artifact.summary.length ~/ 4;
  final retainedBeforeTokens =
      ConversationCompactionService.estimatePromptTokens(retainedBefore);
  final retainedAfterTokens =
      ConversationCompactionService.estimatePromptTokens(retainedAfter);
  final totalBefore = summaryTokens + retainedBeforeTokens;
  final totalAfter = summaryTokens + retainedAfterTokens;
  final tokenSavings = totalBefore - totalAfter;
  final tokenSavingsRatio = totalBefore == 0 ? 0.0 : tokenSavings / totalBefore;

  stdout.writeln('== LL30 post-compaction synthetic measurement ==');
  stdout.writeln('messages: ${messages.length}');
  stdout.writeln('retained tail messages: ${retainedAfter.length}');
  stdout.writeln('summary tokens: $summaryTokens');
  stdout.writeln(
    'retained tail tokens: $retainedBeforeTokens -> $retainedAfterTokens',
  );
  stdout.writeln('post-compaction total: $totalBefore -> $totalAfter');
  stdout.writeln(
    'estimated token savings: $tokenSavings '
    '(${(tokenSavingsRatio * 100).toStringAsFixed(1)}%)',
  );
}

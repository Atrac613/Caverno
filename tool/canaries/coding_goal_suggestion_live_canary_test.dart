import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';

final _forbiddenArtifactPattern = RegExp(
  r'\b(script|cli|application|app|test|helper|automation)\b',
  caseSensitive: false,
);

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_CODING_GOAL_SUGGESTION_LIVE_CANARY'] == '1';

  test(
    'live LLM keeps saved Markdown report requests as report goals',
    () async {
      final env = _CodingGoalSuggestionLiveEnv.fromEnvironment();
      final dataSource = ChatRemoteDataSource(
        baseUrl: env.baseUrl,
        apiKey: env.apiKey,
      );
      final now = DateTime(2026, 6, 1);
      final conversation = Conversation(
        id: 'goal-suggestion-saved-markdown-report',
        title: 'New coding thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
      );

      final result = await dataSource.createChatCompletion(
        messages: ConversationGoalSuggestionService.buildMessages(
          conversation: conversation,
          languageCode: 'en',
          pendingUserMessage:
              'Check tomorrow weather in Tokyo and save it as a Markdown report.',
          now: now,
        ),
        model: env.model,
        temperature: env.temperature,
        maxTokens: env.maxTokens,
      );
      final suggestion = ConversationGoalSuggestionService.parse(
        result.content,
      );

      expect(
        suggestion,
        isNotNull,
        reason: _diagnostic(result.content, suggestion),
      );
      expect(
        suggestion!.kind,
        ConversationGoalSuggestionKind.suggested,
        reason: _diagnostic(result.content, suggestion),
      );

      final objective = suggestion.objective ?? '';
      final normalizedObjective = objective.toLowerCase();
      expect(
        normalizedObjective,
        contains('markdown'),
        reason: _diagnostic(result.content, suggestion),
      );
      expect(
        normalizedObjective,
        anyOf(contains('report'), contains('save'), contains('file')),
        reason: _diagnostic(result.content, suggestion),
      );
      expect(
        normalizedObjective,
        isNot(matches(_forbiddenArtifactPattern)),
        reason: _diagnostic(result.content, suggestion),
      );
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_SUGGESTION_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _CodingGoalSuggestionLiveEnv {
  const _CodingGoalSuggestionLiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final int maxTokens;

  static _CodingGoalSuggestionLiveEnv fromEnvironment() {
    return _CodingGoalSuggestionLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_SUGGESTION_LIVE_TEMPERATURE'] ??
                '',
          ) ??
          0.1,
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_SUGGESTION_LIVE_MAX_TOKENS'] ??
                '',
          ) ??
          600,
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError(
      '$name is required for coding goal suggestion live validation.',
    );
  }
  return value;
}

String _diagnostic(String rawContent, ConversationGoalSuggestion? suggestion) {
  final parsed = suggestion == null
      ? 'null'
      : ConversationGoalSuggestionService.encodeForDebug(suggestion);
  return 'Raw response:\n$rawContent\nParsed suggestion:\n$parsed';
}

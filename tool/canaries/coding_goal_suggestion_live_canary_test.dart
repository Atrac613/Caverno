import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';

const _japaneseMarkdownWeatherRequest =
    '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3092';

final _forbiddenArtifactTerms = <String>[
  'script',
  'cli',
  'application',
  'app',
  'test',
  'helper',
  'automation',
  '\u30b9\u30af\u30ea\u30d7\u30c8',
  '\u30a2\u30d7\u30ea',
  '\u30c6\u30b9\u30c8',
  '\u30d8\u30eb\u30d1\u30fc',
  '\u81ea\u52d5\u5316',
];

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

      final cases = [
        const _GoalSuggestionCase(
          languageCode: 'en',
          pendingUserMessage:
              'Check tomorrow weather in Tokyo and save it as a Markdown report.',
          requiredTerms: ['markdown'],
          acceptedOutcomeTerms: ['report', 'save', 'file'],
        ),
        const _GoalSuggestionCase(
          languageCode: 'ja',
          pendingUserMessage: _japaneseMarkdownWeatherRequest,
          requiredTerms: ['\u30de\u30fc\u30af\u30c0\u30a6\u30f3'],
          acceptedOutcomeTerms: ['\u4fdd\u5b58', '\u30d5\u30a1\u30a4\u30eb'],
        ),
      ];

      for (final testCase in cases) {
        final result = await dataSource.createChatCompletion(
          messages: ConversationGoalSuggestionService.buildMessages(
            conversation: conversation,
            languageCode: testCase.languageCode,
            pendingUserMessage: testCase.pendingUserMessage,
            now: now,
          ),
          model: env.model,
          temperature: env.temperature,
          maxTokens: env.maxTokens,
        );
        final suggestion = ConversationGoalSuggestionService.parse(
          result.content,
        );
        final validatedSuggestion = suggestion == null
            ? null
            : ConversationGoalSuggestionService.validateSuggestion(
                suggestion: suggestion,
                conversation: conversation,
                pendingUserMessage: testCase.pendingUserMessage,
              );

        expect(
          validatedSuggestion,
          isNotNull,
          reason: _diagnostic(result.content, suggestion, validatedSuggestion),
        );
        expect(
          validatedSuggestion!.kind,
          ConversationGoalSuggestionKind.suggested,
          reason: _diagnostic(result.content, suggestion, validatedSuggestion),
        );

        final objective = validatedSuggestion.objective ?? '';
        final normalizedObjective = objective.toLowerCase();
        for (final term in testCase.requiredTerms) {
          expect(
            normalizedObjective,
            contains(term.toLowerCase()),
            reason: _diagnostic(
              result.content,
              suggestion,
              validatedSuggestion,
            ),
          );
        }
        expect(
          testCase.acceptedOutcomeTerms.any(
            (term) => normalizedObjective.contains(term.toLowerCase()),
          ),
          isTrue,
          reason: _diagnostic(result.content, suggestion, validatedSuggestion),
        );
        expect(
          _containsForbiddenArtifact(objective),
          isFalse,
          reason: _diagnostic(result.content, suggestion, validatedSuggestion),
        );
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_SUGGESTION_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _GoalSuggestionCase {
  const _GoalSuggestionCase({
    required this.languageCode,
    required this.pendingUserMessage,
    required this.requiredTerms,
    required this.acceptedOutcomeTerms,
  });

  final String languageCode;
  final String pendingUserMessage;
  final List<String> requiredTerms;
  final List<String> acceptedOutcomeTerms;
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

bool _containsForbiddenArtifact(String value) {
  final normalized = value.toLowerCase();
  return _forbiddenArtifactTerms.any(
    (term) => normalized.contains(term.toLowerCase()),
  );
}

String _diagnostic(
  String rawContent,
  ConversationGoalSuggestion? suggestion,
  ConversationGoalSuggestion? validatedSuggestion,
) {
  final parsed = suggestion == null
      ? 'null'
      : ConversationGoalSuggestionService.encodeForDebug(suggestion);
  final validated = validatedSuggestion == null
      ? 'null'
      : ConversationGoalSuggestionService.encodeForDebug(validatedSuggestion);
  return 'Raw response:\n$rawContent\nParsed suggestion:\n$parsed\nValidated suggestion:\n$validated';
}

import 'package:flutter_test/flutter_test.dart';

import '../../tool/chat_search_grounding_eval.dart';

void main() {
  group('chat search grounding eval scoring', () {
    test('passes a grounded Project Hail Mary shirt answer', () {
      final initial = ChatCompletionResponse(
        content: '',
        finishReason: 'tool_calls',
        usage: TokenUsage.empty,
        toolCalls: const [
          ChatToolCall(
            id: 'call_1',
            name: 'search_web',
            arguments: {
              'query': 'Project Hail Mary Ryland Grace San Francisco cat shirt',
            },
            rawArguments:
                '{"query":"Project Hail Mary Ryland Grace San Francisco cat shirt"}',
          ),
        ],
      );
      final finalResponse = ChatCompletionResponse(
        content:
            '映画ではライアン・ゴズリング演じるライランド・グレースが、B. Kliban風の猫がゴールデンゲートブリッジにいるサンフランシスコTシャツを着ています。衣装はGlyn DillonとDavid Crossmanのチームが用意したものです。',
        finishReason: 'stop',
        toolCalls: const [],
        usage: TokenUsage.empty,
      );

      final result = scoreSearchGroundingResult(
        model: 'model-a',
        caseDefinition: SearchGroundingCaseDefinition.projectHailMaryCatShirt,
        initialResponse: initial,
        finalResponse: finalResponse,
        toolResults: const [],
      );

      expect(result.passed, isTrue);
      expect(result.failedSignals, isEmpty);
      expect(result.signals['search_tool_called'], isTrue);
      expect(result.signals['avoids_wrong_astrid_entity'], isTrue);
    });

    test('flags wrong entity drift and truncation', () {
      final initial = ChatCompletionResponse(
        content: '',
        finishReason: 'tool_calls',
        usage: TokenUsage.empty,
        toolCalls: const [
          ChatToolCall(
            id: 'call_1',
            name: 'search_web',
            arguments: {
              'query': 'Project Hail Mary Astrid Fernandez cat shirt',
            },
            rawArguments:
                '{"query":"Project Hail Mary Astrid Fernandez cat shirt"}',
          ),
        ],
      );
      final finalResponse = ChatCompletionResponse(
        content: 'アストリッド・フェルナンデスの猫Tシャツは確認できません。',
        finishReason: 'length',
        toolCalls: const [],
        usage: TokenUsage.empty,
      );

      final result = scoreSearchGroundingResult(
        model: 'model-b',
        caseDefinition: SearchGroundingCaseDefinition.projectHailMaryCatShirt,
        initialResponse: initial,
        finalResponse: finalResponse,
        toolResults: const [],
      );

      expect(result.passed, isFalse);
      expect(result.failedSignals, contains('finish_reason_not_length'));
      expect(result.failedSignals, contains('avoids_wrong_astrid_entity'));
      expect(
        result.failedSignals,
        contains('does_not_claim_unverified_or_missing'),
      );
    });

    test('builds a report with failed model details', () {
      final result = SearchGroundingCaseResult.error(
        model: 'model-c',
        caseId: 'case',
        title: 'Case',
        error: 'network failed',
        stackTrace: 'stack',
      );
      final report = SearchGroundingEvalReport(
        schemaName: 'schema',
        schemaVersion: 1,
        generatedAt: DateTime(2026, 6, 22),
        baseUrl: 'http://127.0.0.1:1234/v1',
        temperature: 0.2,
        maxTokens: 8192,
        models: [
          SearchGroundingModelResult(model: 'model-c', cases: [result]),
        ],
      );

      expect(report.passed, isFalse);
      expect(report.toJson()['result'], 'failed');
      expect(report.toMarkdown(), contains('network failed'));
    });
  });
}

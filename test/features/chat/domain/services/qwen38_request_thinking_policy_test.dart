import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/services/qwen38_request_thinking_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const model = ApiConstants.qwen38VisionModel;

  group('Qwen38RequestThinkingPolicy', () {
    test('explicit off overrides high effort without inflating the budget', () {
      final result = const Qwen38RequestThinkingPolicy(
        reasoningEffort: 'high',
        enableThinking: false,
      ).resolve(model: model, maxTokens: 100)!;
      expect(result.chatTemplateKwargs, {'enable_thinking': false});
      expect(result.maxTokens, 100);
    });

    test(
      'explicit on enables automatic effort but preserves utility suppression',
      () {
        const policy = Qwen38RequestThinkingPolicy(enableThinking: true);
        expect(
          policy.resolve(model: model, maxTokens: 100)!.chatTemplateKwargs,
          {'enable_thinking': true},
        );
        expect(
          policy
              .resolve(
                model: model,
                maxTokens: 100,
                role: ModelUsageRole.memoryExtraction,
              )!
              .chatTemplateKwargs,
          {'enable_thinking': false},
        );
      },
    );

    test('explicit preferences preserve other models request fields', () {
      for (final enabled in [true, false]) {
        final result = Qwen38RequestThinkingPolicy(enableThinking: enabled)
            .resolve(model: 'custom-model', maxTokens: 100)!
            .applyTo({
              'model': 'custom-model',
              'reasoning_effort': 'high',
              'chat_template_kwargs': {'custom': 42},
            });
        expect(result['reasoning_effort'], 'high');
        expect(result['chat_template_kwargs'], {
          'custom': 42,
          'enable_thinking': enabled,
        });
      }
    });

    test('leaves other models untouched', () {
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'medium');
      expect(policy.resolve(model: 'gpt-5.6-luna', maxTokens: 1200), isNull);
    });

    test('medium effort enables thinking and raises a small chat budget', () {
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'medium');
      final overrides = policy.resolve(model: model, maxTokens: 1200)!;

      expect(overrides.chatTemplateKwargs['enable_thinking'], isTrue);
      expect(
        overrides.maxTokens,
        Qwen38RequestThinkingPolicy.mediumMinimumMaxTokens,
      );
    });

    test('structured utility roles never think, whatever the chat effort', () {
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'high');

      for (final role in const [
        ModelUsageRole.memoryExtraction,
        ModelUsageRole.approvalAutoReview,
        ModelUsageRole.goalSuggestion,
      ]) {
        final overrides = policy.resolve(
          model: model,
          maxTokens: 1200,
          role: role,
        )!;

        expect(
          overrides.chatTemplateKwargs['enable_thinking'],
          isFalse,
          reason: '$role parses JSON out of a small utility budget',
        );
        expect(
          overrides.maxTokens,
          1200,
          reason: 'the thinking floor must not inflate a utility budget',
        );
      }
    });

    test('chat and planning keep the reasoning the user asked for', () {
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'medium');

      for (final role in const [
        ModelUsageRole.chat,
        ModelUsageRole.planning,
        ModelUsageRole.proReasoning,
        ModelUsageRole.subagent,
      ]) {
        final overrides = policy.resolve(
          model: model,
          maxTokens: 8192,
          role: role,
        )!;

        expect(overrides.chatTemplateKwargs['enable_thinking'], isTrue);
        expect(overrides.maxTokens, 8192);
      }
    });

    test('no reasoning effort disables thinking for every role', () {
      const policy = Qwen38RequestThinkingPolicy();
      final overrides = policy.resolve(
        model: model,
        maxTokens: 4096,
        role: ModelUsageRole.chat,
      )!;

      expect(overrides.chatTemplateKwargs['enable_thinking'], isFalse);
      expect(overrides.maxTokens, 4096);
    });
  });
}

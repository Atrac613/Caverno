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
        const policy = Qwen38RequestThinkingPolicy(
          enableThinking: true,
          acceptsChatTemplateKwargs: true,
        );
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
      // `chat_template_kwargs` is a llama.cpp template control; a hosted
      // endpoint must keep receiving requests without it, utility role or not.
      expect(
        policy.resolve(
          model: 'gpt-5.6-luna',
          maxTokens: 400,
          role: ModelUsageRole.goalSuggestion,
        ),
        isNull,
      );
    });

    test('governs every Qwen3.8 build, not one exact name', () {
      // A local llama.cpp serves `Qwen3.8-Flash-Next-Q2`, which the previous
      // equality against ApiConstants.qwen38VisionModel did not match -- so no
      // utility call on that endpoint was ever told not to think. Observed
      // 2026-09-17: a 400-token goalSuggestion spent all 400 reasoning and
      // returned nothing.
      const policy = Qwen38RequestThinkingPolicy(
        reasoningEffort: 'high',
        acceptsChatTemplateKwargs: true,
      );
      expect(
        policy
            .resolve(
              model: 'Qwen3.8-Flash-Next-Q2',
              maxTokens: 400,
              role: ModelUsageRole.goalSuggestion,
            )!
            .chatTemplateKwargs,
        {'enable_thinking': false},
      );
      // The thinking branches follow the same family, so a chat turn on that
      // build keeps the reasoning effort it asks for.
      expect(
        policy
            .resolve(model: 'Qwen3.8-Flash-Next-Q2', maxTokens: 4096)!
            .chatTemplateKwargs['enable_thinking'],
        isTrue,
      );
      expect(
        Qwen38RequestThinkingPolicy.isQwen38Model(' qwen3.8-27b-vision '),
        isTrue,
      );
      expect(
        Qwen38RequestThinkingPolicy.isQwen38Model('qwen3.6-27b-mtp-vision'),
        isFalse,
      );
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

    test('preserves high reasoning effort without remapping it', () {
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'high');
      final overrides = policy.resolve(
        model: 'qwen3.8-27b-exl3',
        maxTokens: 4096,
      )!;
      final body = overrides.applyTo({
        'model': 'qwen3.8-27b-exl3',
        'reasoning_effort': 'high',
      });

      expect(overrides.chatTemplateKwargs['reasoning_effort'], 'high');
      expect(overrides.topLevelEnableThinking, isTrue);
      expect(body['enable_thinking'], isTrue);
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('passes xhigh through with the thinking budget floor', () {
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'xhigh');
      final overrides = policy.resolve(
        model: 'qwen3.8-27b-exl3',
        maxTokens: 512,
      )!;

      expect(overrides.chatTemplateKwargs, {
        'enable_thinking': true,
        'reasoning_effort': 'xhigh',
      });
      expect(
        overrides.maxTokens,
        Qwen38RequestThinkingPolicy.mediumMinimumMaxTokens,
      );
    });

    test('structured utility roles never think, whatever the chat effort', () {
      const policy = Qwen38RequestThinkingPolicy(
        reasoningEffort: 'high',
        acceptsChatTemplateKwargs: true,
      );

      for (final role in const [
        ModelUsageRole.memoryExtraction,
        ModelUsageRole.approvalAutoReview,
        ModelUsageRole.goalSuggestion,
        // 2026-09-20, session 132829af: all four planning calls of a release
        // turn ended on finishReason: length -- 1600, 1800, and 1536 twice --
        // each spending its whole budget inside <think> and emitting no JSON.
        // The plan came out with zero tasks. The 1536s are this policy's own
        // medium floor inflating a smaller budget, which is why the budget
        // assertion below matters as much as the thinking one.
        ModelUsageRole.planning,
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

    test('the roles that answer in prose keep the reasoning asked for', () {
      // Planning left this list on 2026-09-20. It reads as the one role here
      // whose quality could depend on deliberation, so the reason it moved is
      // worth stating: its answer is a parsed task list on a utility budget,
      // and the same model in the same session ran a competent 19-call
      // investigation -- the capability was never missing, only the ability to
      // say it in that shape inside that budget.
      const policy = Qwen38RequestThinkingPolicy(reasoningEffort: 'medium');

      for (final role in const [
        ModelUsageRole.chat,
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

  group('endpoints that accept chat_template_kwargs', () {
    // Suppression used to be reachable only through isQwen38Model, so a local
    // llama.cpp serving any other family sent its JSON utility calls with
    // thinking on. Observed 2026-09-20: goalSuggestion spent a 400-token
    // budget reasoning and every composer-shortcut draft came back empty.
    // The model name no longer takes part; the role and the opt-in decide.
    // Deliberately a name this policy has never heard of: suppression must
    // not depend on recognising the family.
    const otherModel = 'some-unrecognised-model';

    test('suppresses thinking for a utility role on any model', () {
      for (final role in [
        ModelUsageRole.goalSuggestion,
        ModelUsageRole.memoryExtraction,
        ModelUsageRole.approvalAutoReview,
      ]) {
        const policy = Qwen38RequestThinkingPolicy(
          acceptsChatTemplateKwargs: true,
        );
        final overrides = policy.resolve(
          model: otherModel,
          maxTokens: 400,
          role: role,
        );

        expect(overrides, isNotNull, reason: '$role must be suppressed');
        expect(overrides!.chatTemplateKwargs['enable_thinking'], isFalse);
        expect(overrides.maxTokens, 400);
      }
    });

    test('sends nothing without the opt-in', () {
      // The field is the outcome worth avoiding on an endpoint that has never
      // heard of it, so an unmarked endpoint keeps its old request shape.
      const policy = Qwen38RequestThinkingPolicy();

      expect(
        policy.resolve(
          model: otherModel,
          maxTokens: 400,
          role: ModelUsageRole.goalSuggestion,
        ),
        isNull,
      );
    });

    test('leaves a prose role alone', () {
      // Only the structured utility roles are suppressed; the opt-in is not a
      // switch that turns thinking off for the whole endpoint.
      const policy = Qwen38RequestThinkingPolicy(
        acceptsChatTemplateKwargs: true,
      );

      expect(
        policy.resolve(
          model: otherModel,
          maxTokens: 4096,
          role: ModelUsageRole.chat,
        ),
        isNull,
      );
    });

    test('does not apply the Qwen3.8 effort mapping to another family', () {
      // Those branches are tuned to one template and mean nothing elsewhere,
      // so the opt-in opens suppression only.
      const policy = Qwen38RequestThinkingPolicy(
        reasoningEffort: 'medium',
        acceptsChatTemplateKwargs: true,
      );

      expect(
        policy.resolve(
          model: otherModel,
          maxTokens: 512,
          role: ModelUsageRole.chat,
        ),
        isNull,
      );
    });

    test('an unrecognised family is suppressed exactly like qwen3.8', () {
      // The point of the opt-in: two models with nothing in common produce the
      // same overrides for the same role, because neither name is consulted.
      const policy = Qwen38RequestThinkingPolicy(
        reasoningEffort: 'high',
        acceptsChatTemplateKwargs: true,
      );
      final known = policy.resolve(
        model: 'qwen3.8-27b-vision',
        maxTokens: 400,
        role: ModelUsageRole.goalSuggestion,
      )!;
      final unknown = policy.resolve(
        model: 'some-unrecognised-model',
        maxTokens: 400,
        role: ModelUsageRole.goalSuggestion,
      )!;

      expect(unknown.chatTemplateKwargs, known.chatTemplateKwargs);
      expect(unknown.maxTokens, known.maxTokens);
      expect(unknown.preserveReasoningEffort, known.preserveReasoningEffort);
    });
  });
}

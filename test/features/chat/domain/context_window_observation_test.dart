import 'package:caverno/features/chat/domain/entities/context_window_observation.dart';
import 'package:caverno/features/chat/domain/services/model_routing/reported_context_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepting raises only the proven floor', () {
    const empty = ContextWindowObservation();
    final proven = empty.accept(22000)!;
    expect(proven.provenPromptTokens, 22000);
    expect(proven.accept(21000), isNull, reason: 'nothing new is proven');
    expect(proven.ceilingTokens, isNull);
  });

  test('rejecting keeps the tightest bound and prefers a reported limit', () {
    final failed = const ContextWindowObservation(
      provenPromptTokens: 20000,
    ).reject(promptTokens: 70000)!;
    expect(failed.ceilingTokens, 70000);
    expect(failed.reject(promptTokens: 80000), isNull);
    final tighter = failed.reject(promptTokens: 66000)!;
    expect(tighter.failedPromptTokens, 66000);
    final reported = tighter.reject(reportedLimit: 65536)!;
    expect(reported.ceilingTokens, 65536);
    expect(reported.provenPromptTokens, 20000);
  });

  test('round-trips through JSON and ignores junk', () {
    const observation = ContextWindowObservation(
      provenPromptTokens: 27575,
      failedPromptTokens: 70000,
      reportedLimitTokens: 65536,
    );
    final restored = ContextWindowObservation.fromJson(observation.toJson());
    expect(restored.toJson(), observation.toJson());
    expect(
      ContextWindowObservation.fromJson({
        'provenPromptTokens': 'x',
        'failedPromptTokens': -1,
      }).toJson(),
      {'provenPromptTokens': 0},
    );
  });

  test('a pressured fit earns budget scale and a rejection halves it', () {
    var observed = const ContextWindowObservation();
    for (var i = 0; i < 3; i++) {
      observed = observed.accept(20000 + i, pressured: true)!;
    }
    expect(observed.budgetScale, 2.5);
    expect(
      observed.accept(19000),
      isNull,
      reason: 'an unpressured smaller fit proves nothing new',
    );
    for (var i = 0; i < 10; i++) {
      observed = observed.accept(30000 + i, pressured: true)!;
    }
    expect(observed.budgetScale, ContextWindowObservation.maxBudgetScale);
    final rejected = observed.reject(promptTokens: 90000)!;
    expect(rejected.budgetScale, ContextWindowObservation.maxBudgetScale / 2);
    expect(
      ContextWindowObservation.fromJson(rejected.toJson()).budgetScale,
      rejected.budgetScale,
    );
  });

  test('keys an endpoint and model case-insensitively', () {
    expect(
      ContextWindowObservation.keyFor(
        baseUrl: ' https://API.openai.com/v1 ',
        model: 'GPT-6-Luna',
      ),
      'https://api.openai.com/v1|gpt-6-luna',
    );
  });

  group('reportedContextLimit', () {
    for (final (error, limit) in [
      (
        "This model's maximum context length is 128000 tokens. However, your "
            'messages resulted in 130512 tokens.',
        128000,
      ),
      (
        'the request exceeds the available context size (65536 tokens), '
            'try increasing it',
        65536,
      ),
      ('n_ctx: 32768, n_prompt_tokens: 40000', 32768),
      ('context length exceeded', null),
    ]) {
      test(error, () => expect(reportedContextLimit(error), limit));
    }
  });
}

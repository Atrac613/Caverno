import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

/// How probe evidence is written into the report, shared by the diagnostic
/// service and the probe families extracted from it (F5).
void main() {
  ChatCompletionResult reply(int prompt, int completion) =>
      ChatCompletionResult(
        content: '',
        finishReason: 'stop',
        usage: TokenUsage(
          promptTokens: prompt,
          completionTokens: completion,
          totalTokens: prompt + completion,
        ),
      );

  test('usage copies one reply and totals several', () {
    final one = LiveLlmDiagnosticEvidence.usage(reply(3, 4));
    expect(
      (one.promptTokens, one.completionTokens, one.totalTokens),
      (3, 4, 7),
    );
    final both = LiveLlmDiagnosticEvidence.totalUsage([
      reply(3, 4),
      reply(1, 1),
    ]);
    expect(
      (both.promptTokens, both.completionTokens, both.totalTokens),
      (4, 5, 9),
    );
  });

  test('diagnostic usages sum field by field', () {
    final sum = LiveLlmDiagnosticEvidence.sumUsage(const [
      LiveLlmDiagnosticTokenUsage(
        promptTokens: 1,
        completionTokens: 2,
        totalTokens: 3,
      ),
      LiveLlmDiagnosticTokenUsage(
        promptTokens: 4,
        completionTokens: 5,
        totalTokens: 9,
      ),
    ]);
    expect(
      (sum.promptTokens, sum.completionTokens, sum.totalTokens),
      (5, 7, 12),
    );
  });

  test('a preview trims, and cuts only past the limit', () {
    expect(LiveLlmDiagnosticEvidence.preview('  short  '), 'short');
    expect(LiveLlmDiagnosticEvidence.preview('abcdef', maxChars: 3), 'abc...');
    expect(LiveLlmDiagnosticEvidence.preview('abc', maxChars: 3), 'abc');
  });
}

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_request_shape.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppSettings chat({
    required String model,
    ReasoningEffortPreference effort = ReasoningEffortPreference.high,
    bool? enableThinking = false,
  }) => AppSettings.defaults().copyWith(
    model: model,
    reasoningEffort: effort,
    enableThinking: enableThinking,
  );

  test('pins Qwen3.8 thinking regardless of the chat composer', () {
    // Chat asked for thinking off at high effort; the diagnostic ignores both.
    final settings = chat(model: 'qwen3.8-27b-exl3');

    final on = LiveLlmDiagnosticRequestShape.settingsFor(
      settings,
      LiveLlmDiagnosticThinkingMode.on,
    );
    final off = LiveLlmDiagnosticRequestShape.settingsFor(
      settings,
      LiveLlmDiagnosticThinkingMode.off,
    );

    expect(LiveLlmDiagnosticRequestShape.canControlThinking(settings), isTrue);
    expect(on.enableThinking, isTrue);
    expect(on.reasoningEffort, ReasoningEffortPreference.medium);
    expect(off.enableThinking, isFalse);
    expect(off.reasoningEffort, ReasoningEffortPreference.automatic);
    expect(on.effectiveModel, settings.effectiveModel);
    expect(on.baseUrl, settings.baseUrl);
  });

  test('leaves an uncontrollable endpoint at the server default', () {
    final settings = chat(
      model: 'gpt-5.6-luna',
      effort: ReasoningEffortPreference.low,
      enableThinking: true,
    );

    expect(LiveLlmDiagnosticRequestShape.canControlThinking(settings), isFalse);
    for (final mode in LiveLlmDiagnosticThinkingMode.values) {
      final shaped = LiveLlmDiagnosticRequestShape.settingsFor(settings, mode);
      // Neither the chat effort nor the chat thinking switch leaks through.
      expect(shaped.enableThinking, isNull);
      expect(shaped.reasoningEffort, ReasoningEffortPreference.automatic);
    }
  });
}

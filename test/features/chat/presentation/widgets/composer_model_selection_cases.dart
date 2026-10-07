part of 'chat_presentation_widgets_tiny_test.dart';

void _runComposerModelSelection() {
  ComposerModelSelection selection({
    ReasoningEffortPreference effort = ReasoningEffortPreference.automatic,
    List<String>? supported,
  }) => ComposerModelSelection(
    model: 'qwen3.8-27b-exl3',
    reasoningEffort: effort,
    enableThinking: null,
    supportedReasoningEfforts: supported,
  );

  test('offers every effort while support is unknown', () {
    expect(
      selection().reasoningEffortChoices,
      ReasoningEffortPreference.values,
    );
  });

  test('offers automatic plus the probed efforts', () {
    expect(
      selection(supported: ['low', 'medium', 'xhigh']).reasoningEffortChoices,
      [
        ReasoningEffortPreference.automatic,
        ReasoningEffortPreference.low,
        ReasoningEffortPreference.medium,
        ReasoningEffortPreference.xhigh,
      ],
    );
  });

  test('keeps an unsupported current choice visible', () {
    expect(
      selection(
        effort: ReasoningEffortPreference.high,
        supported: ['low'],
      ).reasoningEffortChoices,
      [
        ReasoningEffortPreference.automatic,
        ReasoningEffortPreference.low,
        ReasoningEffortPreference.high,
      ],
    );
  });

  test('switching model forgets the measured support', () {
    final switched = selection(
      supported: ['low'],
    ).copyWith(model: 'another-model');

    expect(switched.supportedReasoningEfforts, isNull);
  });
}

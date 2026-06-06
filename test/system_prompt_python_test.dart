import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 6, 12);

  test('run_python_script guidance appears when the tool is enabled', () {
    final prompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      toolNames: const ['run_python_script'],
    );
    expect(prompt, contains('run_python_script'));
    expect(prompt, contains('piexif'));
  });

  test('attachment signal points the model at caverno.inputs', () {
    final prompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      toolNames: const ['run_python_script'],
      hasPythonInputAttachment: true,
    );
    expect(prompt, contains('caverno.inputs[0]'));
  });

  test('no attachment signal when nothing is attached', () {
    final prompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      toolNames: const ['run_python_script'],
      hasPythonInputAttachment: false,
    );
    expect(prompt, isNot(contains('caverno.inputs[0]')));
  });

  test('no python guidance when the tool is disabled/absent', () {
    final prompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      toolNames: const [],
      hasPythonInputAttachment: true,
    );
    expect(prompt, isNot(contains('run_python_script')));
  });
}

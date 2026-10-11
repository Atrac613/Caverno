import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_instruction_echo_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const exact =
      '{"probe":"instruction_echo","status":"ok",'
      '"marker":"CAVERNO_LIVE_DIAGNOSTIC"}';
  test('preserves the exact request', () {
    expect(
      LiveLlmInstructionEchoProbe.prompt,
      'Return exactly this JSON object and no markdown:\n$exact',
    );
  });

  for (final content in [
    exact,
    '  $exact  ',
    '```json\n$exact\n```',
    '<think>{analysis}</think>$exact',
    'prefix $exact suffix',
    '{"probe":"instruction_echo","status":"ok",'
        '"marker":"CAVERNO_LIVE_DIAGNOSTIC","extra":1}',
  ]) {
    test('keeps existing JSON acceptance: $content', () async {
      final result = await _run(content);
      expect(result.id, 'instruction_echo');
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.summary, 'The model followed the exact JSON instruction.');
      expect(result.details, isEmpty);
      expect(result.modelContent, content.trim());
      expect(result.toolCalls, isEmpty);
      expect(result.usage.toJson(), {
        'promptTokens': 11,
        'completionTokens': 3,
        'totalTokens': 14,
      });
    });
  }

  for (final content in [
    'CAVERNO_LIVE_DIAGNOSTIC',
    '{"probe":"wrong","status":"ok","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
    '{"probe":"instruction_echo","status":"wrong","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
    '{"marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
    '{"probe":"instruction_echo","status":"ok","marker":false,"extra":"CAVERNO_LIVE_DIAGNOSTIC"}',
    '<think>CAVERNO_LIVE_DIAGNOSTIC</think>no JSON',
    '{broken CAVERNO_LIVE_DIAGNOSTIC',
    '["CAVERNO_LIVE_DIAGNOSTIC"]',
  ]) {
    test('raw marker presence warns without accepted JSON: $content', () async {
      final result = await _run(content);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(
        result.summary,
        'The marker was present, but the JSON contract was not exact.',
      );
      expect(result.details, 'Expected marker: CAVERNO_LIVE_DIAGNOSTIC');
      expect(result.modelContent, content);
      expect(result.usage.totalTokens, 14);
    });
  }

  for (final content in [
    '',
    'unknown reply',
    '{"probe":"instruction_echo","status":"ok","marker":"wrong"}',
    '{"probe":"instruction_echo","status":"ok"}',
  ]) {
    test('absent marker fails: $content', () async {
      final result = await _run(content);
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, 'The expected diagnostic marker was missing.');
      expect(result.details, 'Expected marker: CAVERNO_LIVE_DIAGNOSTIC');
      expect(result.modelContent, content);
      expect(result.usage.totalTokens, 14);
    });
  }

  for (final suffix in ['', 'CAVERNO_LIVE_DIAGNOSTIC']) {
    test('bounds previews independently of marker position: $suffix', () async {
      final result = await _run('  ${'x' * 3000}$suffix  ');
      expect(result.modelContent, '${'x' * 2000}...');
      expect(
        result.status,
        suffix.isEmpty
            ? LiveLlmDiagnosticStatus.failed
            : LiveLlmDiagnosticStatus.warning,
      );
    });
  }

  test('completion failures propagate to service handling', () async {
    final error = StateError('transport');
    final probe = LiveLlmInstructionEchoProbe(
      complete: () async => throw error,
    );
    await expectLater(probe.run(), throwsA(same(error)));
  });
}

Future<LiveLlmDiagnosticProbeResult> _run(String content) =>
    LiveLlmInstructionEchoProbe(
      complete: () async => (
        content: content,
        usage: const LiveLlmDiagnosticTokenUsage(
          promptTokens: 11,
          completionTokens: 3,
          totalTokens: 14,
        ),
      ),
    ).run();

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_narrow_tool_call_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the request bytes', () {
    expect(
      LiveLlmNarrowToolCallProbe.prompt,
      'Call the get_current_datetime tool now. Do not answer in text '
      'before using the tool.',
    );
  });

  for (final names in <List<String>>[
    ['get_current_datetime'],
    ['other_tool', 'get_current_datetime'],
    ['get_current_datetime', 'get_current_datetime'],
    [],
    ['other_tool'],
    ['other_tool', 'tool_search'],
  ]) {
    test('preserves call selection and evidence: $names', () async {
      final result = await _run(names);
      final passed = names.contains('get_current_datetime');
      expect(result.id, 'narrow_tool_call');
      expect(
        result.status,
        passed
            ? LiveLlmDiagnosticStatus.passed
            : LiveLlmDiagnosticStatus.failed,
      );
      expect(
        result.summary,
        passed
            ? 'The model emitted the expected built-in tool call.'
            : 'The model did not emit get_current_datetime.',
      );
      expect(
        result.details,
        passed
            ? ''
            : names.isEmpty
            ? 'No tool calls were returned.'
            : names.join(', '),
      );
      expect(result.toolCalls, names);
      expect(result.modelContent, 'model reply');
      expect(result.usage.toJson(), {
        'promptTokens': 11,
        'completionTokens': 3,
        'totalTokens': 14,
      });
    });
  }

  for (final names in <List<String>>[
    [],
    ['get_current_datetime'],
  ]) {
    test('bounds previews for $names', () async {
      final result = await _run(names, content: '  ${'x' * 3000}  ');
      expect(result.modelContent, '${'x' * 2000}...');
    });
  }

  test('request failures propagate to the service', () async {
    final error = StateError('transport');
    final probe = LiveLlmNarrowToolCallProbe(complete: () async => throw error);
    await expectLater(probe.run(), throwsA(same(error)));
  });
}

Future<LiveLlmDiagnosticProbeResult> _run(
  List<String> names, {
  String content = 'model reply',
}) => LiveLlmNarrowToolCallProbe(
  complete: () async => (
    calls: [
      for (var index = 0; index < names.length; index++)
        ToolCallInfo(
          id: 'call-$index',
          name: names[index],
          arguments: const {},
        ),
    ],
    content: content,
    usage: const LiveLlmDiagnosticTokenUsage(
      promptTokens: 11,
      completionTokens: 3,
      totalTokens: 14,
    ),
  ),
).run();

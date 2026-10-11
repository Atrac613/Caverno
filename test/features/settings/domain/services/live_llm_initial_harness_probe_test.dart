import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_initial_harness_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves the initial catalog request', () {
    expect(
      LiveLlmInitialHarnessProbe.prompt,
      'Using the currently exposed Caverno initial tool set, call '
      'get_current_datetime exactly once. Do not call tool_search.',
    );
  });

  for (final names in <List<String>>[
    ['get_current_datetime'],
    ['tool_search', 'get_current_datetime'],
    ['get_current_datetime', 'get_current_datetime', 'other_tool'],
  ]) {
    for (final searchEnabled in [false, true]) {
      test(
        'datetime selection keeps precedence: $names, search=$searchEnabled',
        () async {
          final result = await _run(names, searchEnabled: searchEnabled);
          expect(result.id, 'initial_harness_selection');
          expect(result.status, LiveLlmDiagnosticStatus.passed);
          expect(
            result.summary,
            'The model selected the datetime tool from the harness set.',
          );
          expect(
            result.details,
            'Initial tool count: 7. Tool search enabled: $searchEnabled.',
          );
          expect(result.toolCalls, names);
          expect(result.modelContent, 'model reply');
          expect(result.usage.toJson(), {
            'promptTokens': 11,
            'completionTokens': 3,
            'totalTokens': 14,
          });
        },
      );
    }
  }

  for (final names in <List<String>>[
    ['tool_search'],
    ['other_tool', 'tool_search'],
    [],
    ['other_tool'],
  ]) {
    test('reports alternate selection: $names', () async {
      final result = await _run(names);
      final searched = names.contains('tool_search');
      expect(
        result.status,
        searched
            ? LiveLlmDiagnosticStatus.warning
            : LiveLlmDiagnosticStatus.failed,
      );
      expect(
        result.summary,
        searched
            ? 'The model used tool_search instead of the directly exposed tool.'
            : 'The model did not select the expected harness tool.',
      );
      expect(
        result.details,
        'Initial tool count: 7. Returned calls: '
        '${names.isEmpty ? "(none)" : names.join(", ")}',
      );
      expect(result.toolCalls, names);
      expect(result.modelContent, 'model reply');
      expect(result.usage.totalTokens, 14);
    });
  }

  test('preserves catalog count including zero', () async {
    final result = await _run([], toolCount: 0);
    expect(result.details, 'Initial tool count: 0. Returned calls: (none)');
  });

  for (final names in <List<String>>[
    [],
    ['get_current_datetime'],
  ]) {
    test('bounds previews for $names', () async {
      final result = await _run(names, content: '  ${'x' * 3000}  ');
      expect(result.modelContent, '${'x' * 2000}...');
    });
  }

  test('completion failure propagates to the service', () async {
    final error = StateError('transport');
    final probe = LiveLlmInitialHarnessProbe(complete: () async => throw error);
    await expectLater(
      probe.run(initialToolCount: 7, toolSearchEnabled: true),
      throwsA(same(error)),
    );
  });
}

Future<LiveLlmDiagnosticProbeResult> _run(
  List<String> names, {
  bool searchEnabled = true,
  int toolCount = 7,
  String content = 'model reply',
}) => LiveLlmInitialHarnessProbe(
  complete: () async => (
    toolNames: names,
    content: content,
    usage: const LiveLlmDiagnosticTokenUsage(
      promptTokens: 11,
      completionTokens: 3,
      totalTokens: 14,
    ),
  ),
).run(initialToolCount: toolCount, toolSearchEnabled: searchEnabled);

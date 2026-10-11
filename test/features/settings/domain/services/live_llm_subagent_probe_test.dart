import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_subagent_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const valid = {
    'description': 'Summarize marker',
    'prompt': 'Summarize CAVERNO_SUBAGENT_DIAGNOSTIC and stop.',
    'background': true,
  };

  test('retains the natural delegation request', () {
    expect(
      LiveLlmSubagentProbe.prompt,
      'Delegate a sub-task to a subagent and run it in the background so '
      'you get a task id immediately: it should summarize the marker '
      '"CAVERNO_SUBAGENT_DIAGNOSTIC". Do not answer in text.',
    );
  });

  test('recognizes delegation and retains report evidence', () async {
    final result = await _run([_call(valid)]);
    expect(result.id, 'subagent_recognition');
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(
      result.summary,
      'The model recognized the subagent contract and required fields.',
    );
    expect(
      result.details,
      'description=true, promptMarker=true, background=true',
    );
    expect(result.toolCalls, ['spawn_subagent']);
    expect(result.modelContent, 'model reply');
    expect(result.usage.toJson(), {
      'promptTokens': 11,
      'completionTokens': 3,
      'totalTokens': 14,
    });
  });

  for (final calls in <List<ToolCallInfo>>[
    [],
    [_call(valid, name: 'get_subagent_result')],
  ]) {
    test('missing spawn fails: ${calls.map((call) => call.name)}', () async {
      final result = await _run(calls);
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, 'The model did not emit spawn_subagent.');
      expect(result.toolCalls, calls.map((call) => call.name).toList());
      expect(result.modelContent, 'model reply');
      expect(result.usage.totalTokens, 14);
    });
  }

  for (final entry in <String, Object?>{
    'description': null,
    'prompt': null,
    'background': null,
  }.entries) {
    test('missing ${entry.key} warns', () async {
      final args = <String, dynamic>{...valid}..remove(entry.key);
      final result = await _run([_call(args)]);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(
        result.summary,
        'The model emitted spawn_subagent, but the arguments were incomplete.',
      );
      final detailKey = entry.key == 'prompt' ? 'promptMarker' : entry.key;
      expect(result.details, contains('$detailKey=false'));
    });
  }

  for (final override in <Map<String, dynamic>>[
    {'description': '   '},
    {'prompt': 'Different marker'},
    {'background': false},
    {'background': 'true'},
    {'description': null, 'prompt': null},
  ]) {
    test('incomplete arguments warn: $override', () async {
      final result = await _run([
        _call({...valid, ...override}),
      ]);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
    });
  }

  test(
    'scores the first spawn and preserves other calls without execution',
    () async {
      final result = await _run([
        _call({}, name: 'get_subagent_result'),
        _call({'background': false}),
        _call(valid),
      ]);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.toolCalls, [
        'get_subagent_result',
        'spawn_subagent',
        'spawn_subagent',
      ]);
    },
  );

  test('bounds previews', () async {
    final result = await _run([_call(valid)], content: 'x' * 3000);
    expect(result.modelContent.length, lessThan(3000));
    expect(result.modelContent, contains('...'));
  });

  test('completion errors remain owned by the service', () async {
    final error = StateError('transport');
    final probe = LiveLlmSubagentProbe(complete: () async => throw error);
    await expectLater(probe.run(), throwsA(same(error)));
  });

  for (final key in ['description', 'prompt']) {
    test('wrong $key types still propagate to service handling', () async {
      await expectLater(
        _run([
          _call({...valid, key: 3}),
        ]),
        throwsA(isA<TypeError>()),
      );
    });
  }
}

ToolCallInfo _call(
  Map<String, dynamic> args, {
  String name = 'spawn_subagent',
}) => ToolCallInfo(id: 'call-id', name: name, arguments: args);

Future<LiveLlmDiagnosticProbeResult> _run(
  List<ToolCallInfo> calls, {
  String content = 'model reply',
}) => LiveLlmSubagentProbe(
  complete: () async => (
    content: content,
    calls: calls,
    usage: const LiveLlmDiagnosticTokenUsage(
      promptTokens: 11,
      completionTokens: 3,
      totalTokens: 14,
    ),
  ),
).run();

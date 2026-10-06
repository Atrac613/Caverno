import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_response_scoring.dart';
import 'package:caverno/features/settings/domain/services/live_llm_sampler_calibration_trials.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sampler-calibration trials, moved out of the diagnostic service (F5)
/// and driven here by a scripted completion instead of a live endpoint.
void main() {
  late List<({List<Map<String, dynamic>>? tools, double temperature})> sent;

  LiveLlmSamplerCalibrationTrials trials(Object reply) {
    return LiveLlmSamplerCalibrationTrials(
      complete: ({required messages, tools, required temperature}) async {
        sent.add((tools: tools, temperature: temperature));
        if (reply is Exception) throw reply;
        return reply as ChatCompletionResult;
      },
      messages: (user) => [
        Message(
          id: 'u',
          content: user,
          role: MessageRole.user,
          timestamp: DateTime.utc(2026),
        ),
      ],
    );
  }

  ChatCompletionResult text(String content) =>
      ChatCompletionResult(content: content, finishReason: 'stop');

  setUp(() => sent = []);

  group('tool loop', () {
    const dateTool = {
      'type': 'function',
      'function': {'name': 'x'},
    };

    test(
      'passes when the reply calls the date tool, and sends the tool',
      () async {
        final trial = await trials(
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: '1',
                name: 'get_current_datetime',
                arguments: {},
              ),
            ],
          ),
        ).toolLoop(dateTool: dateTool, temperature: 0.3);
        expect(trial.passed, isTrue);
        expect(trial.malformedToolCallCount, 0);
        expect(trial.temperature, 0.3);
        expect(sent.single.tools, [dateTool]);
      },
    );

    test('a text answer is a malformed tool call', () async {
      final trial = await trials(
        text('It is noon.'),
      ).toolLoop(dateTool: dateTool, temperature: 0.7);
      expect(trial.passed, isFalse);
      expect(trial.malformedToolCallCount, 1);
    });
  });

  group('routine', () {
    test('the exact object passes', () async {
      final trial = await trials(
        text(
          '{"routine":"sampler_calibration","status":"ok",'
          '"marker":"CAVERNO_ROUTINE_SAMPLER_OK","nextAction":"post_summary"}',
        ),
      ).routine(temperature: 0.2);
      expect(trial.passed, isTrue);
      expect(trial.jsonRepairEventCount, 0);
      expect(sent.single.tools, isNull);
    });

    test(
      'a reply that carries the marker but not the object needs repair',
      () async {
        final trial = await trials(
          text('status ok CAVERNO_ROUTINE_SAMPLER_OK'),
        ).routine(temperature: 0.2);
        expect(trial.passed, isFalse);
        expect(trial.jsonRepairEventCount, 1);
      },
    );
  });

  group('coding', () {
    const envelope =
        '"coding":"sampler_calibration","status":"ok",'
        '"marker":"CAVERNO_CODING_SAMPLER_OK"';

    test('the exact edit block passes', () async {
      final trial = await trials(
        text(
          '{$envelope,"edit":["<<<<<<< SEARCH","return oldValue;","=======",'
          '"return newValue;",">>>>>>> REPLACE"]}',
        ),
      ).coding(temperature: 0.1);
      expect(trial.passed, isTrue);
      expect(trial.editApplyFailureCount, 0);
    });

    test(
      'a correct envelope with a wrong edit block is an apply failure',
      () async {
        final trial = await trials(
          text('{$envelope,"edit":["return newValue;"]}'),
        ).coding(temperature: 0.1);
        expect(trial.passed, isFalse);
        expect(trial.editApplyFailureCount, 1);
      },
    );
  });

  group('plan', () {
    test('tasks must match in order', () async {
      const head =
          '"plan":"sampler_calibration","status":"ok",'
          '"marker":"CAVERNO_PLAN_SAMPLER_OK"';
      expect(
        (await trials(
          text('{$head,"tasks":["inspect","edit","verify"]}'),
        ).plan(temperature: 0.5)).passed,
        isTrue,
      );
      expect(
        (await trials(
          text('{$head,"tasks":["edit","inspect","verify"]}'),
        ).plan(temperature: 0.5)).passed,
        isFalse,
      );
    });
  });

  test('a failed request is a failed trial, never an exception', () async {
    final t = trials(Exception('endpoint down'));
    final results = <LiveLlmDiagnosticSamplerTrial>[
      await t.toolLoop(dateTool: const {}, temperature: 0),
      await t.routine(temperature: 0),
      await t.coding(temperature: 0),
      await t.plan(temperature: 0),
    ];
    expect(results.every((trial) => !trial.passed), isTrue);
    expect(results[2].editApplyFailureCount, 1);
  });

  test('a looping reply is flagged as repetition', () async {
    final trial = await trials(
      text(List.filled(4, 'the same four words').join(' ')),
    ).routine(temperature: 1.2);
    expect(trial.repetitionDetected, isTrue);
    expect(LiveLlmResponseScoring.looksRepetitive('short'), isFalse);
  });

  test('tool calls embedded in the text are read when none are native', () {
    final calls = LiveLlmResponseScoring.toolCallsFrom(
      text(
        '<tool_call>{"name":"get_current_datetime","arguments":{}}</tool_call>',
      ),
    );
    expect(calls.map((call) => call.name), ['get_current_datetime']);
  });
}

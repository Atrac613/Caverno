import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/openai_parameter_support_probe.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_structured_output_probe.dart';
import 'package:flutter_test/flutter_test.dart';

const _schemaAnswer = '{"marker":"CAVERNO_SCHEMA_LOCKED_47","count":47}';
const _objectAnswer = '{"marker":"CAVERNO_JSON_OBJECT_OK","count":47}';
final _startedAt = DateTime.utc(2026, 10, 2);

void main() {
  test(
    'schema success preserves the request and skips object fallback',
    () async {
      final harness = _Harness([
        _response(_schemaAnswer, prompt: 7, completion: 3),
      ]);

      final result = await harness.run();

      expect(harness.lookupCount, 1);
      expect(harness.requests, hasLength(1));
      final request = harness.requests.single;
      expect(request.maxTokens, 2048);
      expect(request.responseFormat.format, StructuredOutputFormat.jsonSchema);
      expect(request.responseFormat.name, 'caverno_live_diagnostic');
      expect(request.responseFormat.schema, {
        'type': 'object',
        'properties': {
          'marker': {'type': 'string', 'const': 'CAVERNO_SCHEMA_LOCKED_47'},
          'count': {'type': 'integer', 'const': 47},
        },
        'required': ['marker', 'count'],
        'additionalProperties': false,
      });
      expect(
        request.messages.last.content,
        'Return one JSON object with exactly these two fields and no '
        'markdown, matching the supplied response schema: $_schemaAnswer',
      );
      expect(result.id, 'structured_output');
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.passedChecks, 2);
      expect(result.totalChecks, 2);
      expect(result.metadata, {'structuredOutputSupport': 'jsonSchema'});
      expect(result.modelContent, _schemaAnswer);
      expect(result.usage.toJson(), {
        'promptTokens': 7,
        'completionTokens': 3,
        'totalTokens': 10,
      });
      expect(
        result.details,
        'json_schema: passed\njson_object fallback: not needed',
      );
    },
  );

  test(
    'scores the visible schema answer after reasoning containing braces',
    () async {
      final harness = _Harness([
        _response('<think>Maybe {"diagnostic": ...}?</think>$_schemaAnswer'),
      ]);

      final result = await harness.run();

      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(harness.requests, hasLength(1));
      expect(result.modelContent, contains('<think>'));
    },
  );

  for (final support in [
    EndpointParameterSupport.supported,
    EndpointParameterSupport.unknown,
  ]) {
    test('$support still attempts the schema arm', () async {
      final harness = _Harness([_response(_schemaAnswer)], support: support);

      expect((await harness.run()).status, LiveLlmDiagnosticStatus.passed);
      expect(
        harness.requests.single.responseFormat.format,
        StructuredOutputFormat.jsonSchema,
      );
    });
  }

  test(
    'explicitly unsupported metadata skips schema and uses the object cap',
    () async {
      final harness = _Harness([
        _response(_objectAnswer, prompt: 5, completion: 2),
      ], support: EndpointParameterSupport.unsupported);

      final result = await harness.run();

      expect(harness.requests, hasLength(1));
      final request = harness.requests.single;
      expect(request.maxTokens, 512);
      expect(request.responseFormat.format, StructuredOutputFormat.jsonObject);
      expect(
        request.messages.last.content,
        'Return one JSON object with exactly these two fields and no '
        'markdown: $_objectAnswer',
      );
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.metadata, {'structuredOutputSupport': 'jsonObject'});
      expect(result.details, contains('json_schema: not attempted'));
      expect(result.usage.totalTokens, 7);
    },
  );

  test(
    'schema request failure falls back and counts only completed usage',
    () async {
      final harness = _Harness([
        StateError('schema unsupported'),
        _response(_objectAnswer, prompt: 11, completion: 4),
      ]);

      final result = await harness.run();

      expect(harness.requests.map((r) => r.maxTokens), [2048, 512]);
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.passedChecks, 1);
      expect(result.totalChecks, 2);
      expect(result.metadata, {'structuredOutputSupport': 'jsonObject'});
      expect(result.details, contains('json_schema: request failed'));
      expect(result.details, contains('schema unsupported'));
      expect(result.usage.toJson(), {
        'promptTokens': 11,
        'completionTokens': 4,
        'totalTokens': 15,
      });
    },
  );

  for (final content in [
    'not JSON',
    '{"marker":"wrong","count":47}',
    '{"marker":"CAVERNO_SCHEMA_LOCKED_47","count":46}',
    '{"marker":"CAVERNO_SCHEMA_LOCKED_47","count":"47"}',
    '{"marker":"CAVERNO_SCHEMA_LOCKED_47","count":47,"extra":true}',
  ]) {
    test('invalid schema contract falls back: $content', () async {
      final harness = _Harness([
        _response(content, prompt: 10, completion: 3),
        _response(_objectAnswer, prompt: 20, completion: 7),
      ]);

      final result = await harness.run();

      expect(harness.requests, hasLength(2));
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.details, contains('response violated the schema'));
      expect(result.modelContent, _objectAnswer);
      expect(result.usage.toJson(), {
        'promptTokens': 30,
        'completionTokens': 10,
        'totalTokens': 40,
      });
    });
  }

  for (final (content, finishReason, detail) in [
    ('<think>Still reasoning', 'length', 'returned no answer'),
    ('{"marker":', 'length', 'answer was truncated'),
    ('<think>Only reasoning</think>', 'stop', 'returned no content'),
  ]) {
    test('schema $finishReason distinguishes $detail', () async {
      final harness = _Harness([
        _response(content, finishReason: finishReason),
        _response(_objectAnswer),
      ]);

      final result = await harness.run();

      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.details, contains(detail));
      expect(result.details, isNot(contains('violated the schema')));
      if (finishReason == 'length') {
        expect(result.details, contains('finish_reason: length'));
      }
    });
  }

  for (final content in [
    '',
    'not JSON',
    '{"marker":"wrong","count":47}',
    '{"marker":"CAVERNO_JSON_OBJECT_OK","count":46}',
    '{"marker":"CAVERNO_JSON_OBJECT_OK","count":47,"extra":true}',
  ]) {
    test('invalid object fallback reports no support: $content', () async {
      final harness = _Harness([
        _response('invalid schema', prompt: 3, completion: 2),
        _response(content, prompt: 4, completion: 1),
      ]);

      final result = await harness.run();

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.passedChecks, 0);
      expect(result.totalChecks, 2);
      expect(result.metadata, {'structuredOutputSupport': 'none'});
      expect(
        result.summary,
        'Neither structured-output mode preserved its contract.',
      );
      expect(
        result.details,
        contains('json_object: response violated the contract'),
      );
      expect(result.usage.totalTokens, 10);
    });
  }

  test(
    'two request errors retain zero usage and both failure details',
    () async {
      final harness = _Harness([
        StateError('schema unavailable'),
        StateError('object unavailable'),
      ]);

      final result = await harness.run();

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.metadata, {'structuredOutputSupport': 'none'});
      expect(
        result.summary,
        'Neither structured-output request mode was usable.',
      );
      expect(result.details, contains('schema unavailable'));
      expect(result.details, contains('object unavailable'));
      expect(result.usage.totalTokens, 0);
    },
  );

  test('object request failure retains the completed schema usage', () async {
    final harness = _Harness([
      _response('invalid schema', prompt: 8, completion: 5),
      StateError('object unavailable'),
    ]);

    final result = await harness.run();

    expect(result.status, LiveLlmDiagnosticStatus.failed);
    expect(result.passedChecks, 0);
    expect(result.totalChecks, 2);
    expect(result.details, contains('json_object: request failed'));
    expect(result.usage.totalTokens, 13);
  });

  test('schema publication failure retains its usage and falls back', () async {
    final harness = _Harness([
      _response(_schemaAnswer, prompt: 4, completion: 2),
      _response(_objectAnswer, prompt: 5, completion: 3),
    ]);
    final statuses = <LiveLlmDiagnosticStatus>[];

    final result = await harness.run(
      onResult: (result) {
        statuses.add(result.status);
        if (result.status == LiveLlmDiagnosticStatus.passed) {
          throw StateError('publication failed');
        }
      },
    );

    expect(statuses, [
      LiveLlmDiagnosticStatus.passed,
      LiveLlmDiagnosticStatus.warning,
    ]);
    expect(harness.requests, hasLength(2));
    expect(result.details, contains('json_schema: request failed'));
    expect(result.details, contains('publication failed'));
    expect(result.usage.totalTokens, 14);
  });

  test(
    'object publication failure propagates outside the request catch',
    () async {
      final harness = _Harness([
        _response(_objectAnswer),
      ], support: EndpointParameterSupport.unsupported);
      final error = StateError('publication failed');

      await expectLater(
        harness.run(onResult: (_) => throw error),
        throwsA(same(error)),
      );
      expect(harness.requests, hasLength(1));
    },
  );

  test(
    'elapsed time includes metadata lookup and both completed arms',
    () async {
      final harness = _Harness(
        [_response('invalid schema'), _response(_objectAnswer)],
        metadataDuration: const Duration(seconds: 2),
        completionDuration: const Duration(seconds: 3),
      );

      final result = await harness.run();

      expect(result.elapsed, const Duration(seconds: 8));
      expect(harness.lookupCount, 1);
    },
  );

  test('schema evidence remains bounded even with long reasoning', () async {
    final content = '<think>${'x' * 2100}</think>$_schemaAnswer';
    final harness = _Harness([_response(content)]);

    final result = await harness.run();

    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.modelContent, '${content.substring(0, 2000)}...');
  });
}

ChatCompletionResult _response(
  String content, {
  String finishReason = 'stop',
  int prompt = 0,
  int completion = 0,
}) => ChatCompletionResult(
  content: content,
  finishReason: finishReason,
  usage: TokenUsage(
    promptTokens: prompt,
    completionTokens: completion,
    totalTokens: prompt + completion,
  ),
);

class _Harness {
  _Harness(
    this.replies, {
    this.support = EndpointParameterSupport.unknown,
    this.metadataDuration = Duration.zero,
    this.completionDuration = Duration.zero,
  });

  final List<Object> replies;
  final EndpointParameterSupport support;
  final Duration metadataDuration;
  final Duration completionDuration;
  final List<
    ({
      List<Message> messages,
      StructuredOutputRequest responseFormat,
      int maxTokens,
    })
  >
  requests = [];
  int lookupCount = 0;
  DateTime now = _startedAt;

  Future<LiveLlmDiagnosticProbeResult> run({
    void Function(LiveLlmDiagnosticProbeResult result)? onResult,
  }) => LiveLlmStructuredOutputProbe(
    complete:
        ({
          required messages,
          required responseFormat,
          required maxTokens,
        }) async {
          requests.add((
            messages: messages,
            responseFormat: responseFormat,
            maxTokens: maxTokens,
          ));
          now = now.add(completionDuration);
          final reply = replies[requests.length - 1];
          if (reply is ChatCompletionResult) return reply;
          throw reply;
        },
    responseFormatSupport: () async {
      lookupCount += 1;
      now = now.add(metadataDuration);
      return support;
    },
    messages: (user) => [
      Message(
        id: 'user',
        content: user,
        role: MessageRole.user,
        timestamp: _startedAt,
      ),
    ],
    answerMaxTokens: 512,
    reasoningMaxTokens: 2048,
    now: () => now,
  ).run(startedAt: _startedAt, onResult: onResult);
}

import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/openai_parameter_support_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<EndpointParameterSupport> probe(
  http.Response Function(http.Request request) respond, {
  String baseUrl = 'http://localhost:8000/v1',
  String model = 'qwen3.8-flash-next',
}) {
  return const OpenAiParameterSupportProbe().responseFormatSupport(
    baseUrl: baseUrl,
    model: model,
    client: MockClient((request) async => respond(request)),
  );
}

Future<int> contextProbe(
  http.Response Function(http.Request request) respond, {
  String baseUrl = 'http://localhost:8000/v1',
  String model = 'qwen3.8-flash-next',
}) {
  return const OpenAiParameterSupportProbe().advertisedContextTokens(
    baseUrl: baseUrl,
    model: model,
    client: MockClient((request) async => respond(request)),
  );
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _model(String id, {List<String>? parameters}) => {
  'id': id,
  'object': 'model',
  'supported_parameters': ?parameters,
};

void main() {
  group('modelsUriFor', () {
    test('keeps the OpenAI version prefix', () {
      expect(
        OpenAiParameterSupportProbe.modelsUriFor('http://192.168.1.5:8000/v1'),
        Uri.parse('http://192.168.1.5:8000/v1/models'),
      );
    });

    test('does not double the models segment', () {
      expect(
        OpenAiParameterSupportProbe.modelsUriFor(
          'http://192.168.1.5:8000/v1/models',
        ),
        Uri.parse('http://192.168.1.5:8000/v1/models'),
      );
    });

    test('rejects a base URL that is not a URL', () {
      expect(OpenAiParameterSupportProbe.modelsUriFor('not a url'), isNull);
      expect(OpenAiParameterSupportProbe.modelsUriFor('  '), isNull);
    });
  });

  group('responseFormatSupport', () {
    test('reports supported when the listing advertises it', () async {
      expect(
        await probe(
          (_) => _json({
            'data': [
              _model('qwen3.8-flash-next', parameters: [
                'tools',
                'response_format',
                'temperature',
              ]),
            ],
          }),
        ),
        EndpointParameterSupport.supported,
      );
    });

    test('reports unsupported when the listing omits it', () async {
      expect(
        await probe(
          (_) => _json({
            'data': [
              _model('qwen3.8-flash-next', parameters: [
                'tools',
                'tool_choice',
                'max_tokens',
                'temperature',
                'reasoning_effort',
              ]),
            ],
          }),
        ),
        EndpointParameterSupport.unsupported,
      );
    });

    // The configured model is routinely a quant label the server never lists,
    // and it accepts the request anyway. The whole listing then stands in: a
    // parameter no model supports is one the server does not support.
    test('falls back to the whole listing for an unlisted model', () async {
      final response = _json({
        'data': [
          _model('qwen3.8-flash-next', parameters: ['tools', 'max_tokens']),
          _model('qwen3.8-flash-next-chat', parameters: ['tools', 'seed']),
        ],
      });
      expect(
        await probe((_) => response, model: 'Qwen3.8-Flash-Next-Q2'),
        EndpointParameterSupport.unsupported,
      );
    });

    test('an exact match outranks the rest of the listing', () async {
      final response = _json({
        'data': [
          _model('other-model', parameters: ['tools']),
          _model('qwen3.8-flash-next', parameters: ['response_format']),
        ],
      });
      expect(await probe((_) => response), EndpointParameterSupport.supported);
    });

    test('one entry without the list makes the listing uninformative', () async {
      expect(
        await probe(
          (_) => _json({
            'data': [
              _model('qwen3.8-flash-next', parameters: ['tools']),
              _model('qwen3.8-flash-next-chat'),
            ],
          }),
          model: 'Qwen3.8-Flash-Next-Q2',
        ),
        EndpointParameterSupport.unknown,
      );
    });

    // Silence is never a denial: a plain llama.cpp server lists no parameters
    // at all, and calling that "unsupported" would strip schema mode from every
    // endpoint that actually honors it.
    test('reports unknown when nothing advertises parameters', () async {
      expect(
        await probe(
          (_) => _json({
            'data': [_model('qwen3.8-flash-next')],
          }),
        ),
        EndpointParameterSupport.unknown,
      );
    });

    test('reports unknown for a non-2xx status', () async {
      expect(
        await probe((_) => http.Response('nope', 404)),
        EndpointParameterSupport.unknown,
      );
    });

    test('reports unknown for a body that is not JSON', () async {
      expect(
        await probe((_) => http.Response('<html>proxy</html>', 200)),
        EndpointParameterSupport.unknown,
      );
    });

    test('reports unknown when the listing is empty', () async {
      expect(
        await probe((_) => _json({'data': <Object>[]})),
        EndpointParameterSupport.unknown,
      );
    });

    test('reports unknown when the request throws', () async {
      expect(
        await probe((_) => throw const SocketExceptionStub()),
        EndpointParameterSupport.unknown,
      );
    });
  });

  group('advertisedContextTokens', () {
    test('reads the window the listing publishes', () async {
      expect(
        await contextProbe(
          (_) => _json({
            'data': [
              {
                'id': 'qwen3.8-flash-next',
                'context_length': 40960,
              },
            ],
          }),
        ),
        40960,
      );
    });

    test('takes the largest window when the model is unlisted', () async {
      expect(
        await contextProbe(
          (_) => _json({
            'data': [
              {'id': 'qwen3.8-flash-next', 'context_length': 40960},
              {'id': 'qwen3.8-flash-next-chat', 'context_length': 131072},
            ],
          }),
          model: 'Qwen3.8-Flash-Next-Q2',
        ),
        131072,
      );
    });

    test('an exact match outranks the rest of the listing', () async {
      expect(
        await contextProbe(
          (_) => _json({
            'data': [
              {'id': 'other-model', 'context_length': 131072},
              {'id': 'qwen3.8-flash-next', 'context_length': 40960},
            ],
          }),
        ),
        40960,
      );
    });

    // 0 means "said nothing", which leaves every ladder stage attemptable.
    test('reports zero when the listing publishes no window', () async {
      expect(
        await contextProbe(
          (_) => _json({
            'data': [
              {'id': 'qwen3.8-flash-next'},
            ],
          }),
        ),
        0,
      );
    });

    test('ignores a non-positive window', () async {
      expect(
        await contextProbe(
          (_) => _json({
            'data': [
              {'id': 'qwen3.8-flash-next', 'context_length': 0},
            ],
          }),
        ),
        0,
      );
    });

    test('reports zero for a non-2xx status', () async {
      expect(await contextProbe((_) => http.Response('nope', 500)), 0);
    });

    test('reports zero when the request throws', () async {
      expect(await contextProbe((_) => throw const SocketExceptionStub()), 0);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_batched_support_filter_contract.dart';
import '../../tool/rag3_compact_support_filter_contract.dart';
import '../../tool/rag3_compact_support_filter_instrument.dart';

void main() {
  test(
    'sends the compact contract to a local chat-completion endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      late Map<String, Object?> requestJson;
      late HttpRequest receivedRequest;
      final handled = server.first.then((request) async {
        receivedRequest = request;
        requestJson =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, Object?>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'model': 'response-model',
            'choices': [
              {
                'message': {'content': '{"schemaVersion":1,"mask":"10"}'},
              },
            ],
            'usage': {
              'prompt_tokens': 321,
              'completion_tokens': 12,
              'total_tokens': 333,
            },
            'timings': {'prompt_ms': 604.25, 'predicted_ms': 393.5},
          }),
        );
        await request.response.close();
      });
      final classifier = Rag3HttpCompactSupportFilterClassifier(
        endpoint:
            'http://${server.address.host}:${server.port}/v1/chat/completions',
        model: 'request-model',
        apiKey: 'secret-key',
      );
      addTearDown(classifier.close);
      final input = _input();

      final response = await classifier.classify(input);
      await handled;
      final prediction = parseRag3CompactSupportFilterPrediction(
        input: input,
        response: response,
      );

      expect(receivedRequest.method, 'POST');
      expect(receivedRequest.headers.contentType?.mimeType, 'application/json');
      expect(
        receivedRequest.headers.value(HttpHeaders.authorizationHeader),
        'Bearer secret-key',
      );
      expect(requestJson['model'], 'request-model');
      expect(requestJson['temperature'], 0);
      expect(
        requestJson['max_tokens'],
        rag3CompactSupportFilterMaximumOutputTokens,
      );
      expect(requestJson['stream'], isFalse);
      final responseFormat = (requestJson['response_format'] as Map)
          .cast<String, Object?>();
      final jsonSchema = (responseFormat['json_schema'] as Map)
          .cast<String, Object?>();
      final schema = (jsonSchema['schema'] as Map).cast<String, Object?>();
      final properties = (schema['properties'] as Map).cast<String, Object?>();
      final mask = (properties['mask'] as Map).cast<String, Object?>();
      expect(mask, {
        'type': 'string',
        'pattern': r'^[01]{2}$',
        'minLength': 2,
        'maxLength': 2,
      });
      final messages = requestJson['messages'] as List;
      final userMessage = (messages.last as Map).cast<String, Object?>();
      final classifierInput =
          (jsonDecode(userMessage['content']! as String) as Map)
              .cast<String, Object?>();
      expect(classifierInput['contract'], rag3CompactSupportFilterContract);
      expect(classifierInput['orderedEvidence'], hasLength(2));
      final encoded = jsonEncode(requestJson);
      expect(encoded, contains('runtime query'));
      expect(encoded, contains('supporting evidence'));
      expect(encoded, isNot(contains('expectedDecisions')));
      expect(encoded, isNot(contains('oracle')));
      expect(encoded, isNot(contains('qrels')));
      expect(prediction.decisions, {
        'retain': Rag3SupportFilterDecision.retainSupport,
        'drop': Rag3SupportFilterDecision.dropNonSupport,
      });
      expect(classifier.responseModelIds, {'response-model'});
      expect(classifier.requestCount, 1);
      expect(classifier.requestMeasurements, hasLength(1));
      expect(classifier.requestMeasurements.single.toJson(), {
        'requestIndex': 1,
        'latencyMs': response.latencyMs,
        'usage': {
          'promptTokens': 321,
          'completionTokens': 12,
          'totalTokens': 333,
        },
        'timing': {'promptMs': 604.25, 'predictedMs': 393.5},
      });
    },
  );

  test('uses the supplied chunk count in every mask schema bound', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Map<String, Object?> requestJson;
    final handled = server.first.then((request) async {
      requestJson = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, Object?>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"schemaVersion":1,"mask":"1"}'},
            },
          ],
        }),
      );
      await request.response.close();
    });
    final classifier = Rag3HttpCompactSupportFilterClassifier(
      endpoint:
          'http://${server.address.host}:${server.port}/v1/chat/completions',
      model: 'request-model',
      apiKey: 'no-key',
    );
    addTearDown(classifier.close);
    final input = Rag3BatchedSupportFilterInput(
      query: 'runtime query',
      revision: 'abc123',
      authority: 'current',
      chunks: [
        Rag3SupportFilterChunkInput(
          chunkId: 'only',
          sourcePath: 'docs/only.md',
          content: 'runtime evidence',
        ),
      ],
    );

    await classifier.classify(input);
    await handled;

    final responseFormat = (requestJson['response_format'] as Map)
        .cast<String, Object?>();
    final jsonSchema = (responseFormat['json_schema'] as Map)
        .cast<String, Object?>();
    final schema = (jsonSchema['schema'] as Map).cast<String, Object?>();
    final properties = (schema['properties'] as Map).cast<String, Object?>();
    final mask = (properties['mask'] as Map).cast<String, Object?>();
    expect(mask['pattern'], r'^[01]{1}$');
    expect(mask['minLength'], 1);
    expect(mask['maxLength'], 1);
  });

  test('fails closed and stops requests after an HTTP failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    final classifier = Rag3HttpCompactSupportFilterClassifier(
      endpoint:
          'http://${server.address.host}:${server.port}/v1/chat/completions',
      model: 'request-model',
      apiKey: 'no-key',
    );
    addTearDown(classifier.close);

    await expectLater(
      classifier.classify(_input()),
      throwsA(isA<Rag3BatchedSupportFilterUnavailable>()),
    );
    await handled;
    await expectLater(
      classifier.classify(_input()),
      throwsA(isA<Rag3BatchedSupportFilterUnavailable>()),
    );
    expect(classifier.requestCount, 1);
    expect(classifier.requestMeasurements, isEmpty);
    expect(classifier.lastFailureReason, 'http_status_503');
  });
}

Rag3BatchedSupportFilterInput _input() => Rag3BatchedSupportFilterInput(
  query: 'runtime query',
  revision: 'abc123',
  authority: 'current',
  chunks: [
    Rag3SupportFilterChunkInput(
      chunkId: 'retain',
      sourcePath: 'docs/retain.md',
      content: 'supporting evidence',
    ),
    Rag3SupportFilterChunkInput(
      chunkId: 'drop',
      sourcePath: 'docs/drop.md',
      content: 'topical evidence',
    ),
  ],
);

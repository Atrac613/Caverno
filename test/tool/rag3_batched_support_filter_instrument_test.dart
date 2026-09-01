import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_batched_support_filter_contract.dart';
import '../../tool/rag3_batched_support_filter_instrument.dart';

const _fixture = 'tool/fixtures/rag2_compositional_holdout/fixture.json';
const _oracle = 'tool/fixtures/rag2_passage_role_oracle/oracle.json';
const _differentFixture = 'tool/fixtures/rag2_semantic_holdout/fixture.json';

void main() {
  test('parses only the exact bounded instrument options', () {
    final options = Rag3BatchedSupportFilterInstrumentOptions.parse(const [
      '--fixture',
      _fixture,
      '--oracle',
      _oracle,
      '--out-dir',
      'out',
      '--base-url',
      'http://model.test/v1',
      '--model',
      'test-model',
    ]);

    expect(options, isNotNull);
    expect(options!.apiKey, 'no-key');
    expect(
      Rag3BatchedSupportFilterInstrumentOptions.parse(const [
        '--fixture',
        _fixture,
        '--oracle',
        _oracle,
        '--unknown',
        'value',
      ]),
      isNull,
    );
  });

  test('evaluates 20 five-document batches without oracle input', () async {
    final root = await Directory.systemTemp.createTemp(
      'rag3-support-filter-instrument-',
    );
    addTearDown(() => root.delete(recursive: true));
    final classifier = _DropClassifier();
    final report = await runRag3BatchedSupportFilterInstrument(
      Rag3BatchedSupportFilterInstrumentOptions(
        fixturePath: _fixture,
        oraclePath: _oracle,
        outDir: '${root.path}/out',
        baseUrl: 'http://model.test/v1',
        model: 'test-model',
      ),
      classifier: classifier,
      buildCommit: 'test-build',
      buildDirty: false,
    );

    expect(classifier.inputs, hasLength(20));
    expect(
      classifier.inputs.every((input) => input.chunks.length == 5),
      isTrue,
    );
    expect(report.requestCount, 20);
    expect(report.classifierReport.metrics.truePositive, 0);
    expect(report.classifierReport.metrics.trueNegative, 81);
    expect(report.classifierReport.metrics.falsePositive, 0);
    expect(report.classifierReport.metrics.falseNegative, 19);
    expect(report.classifierReport.passed, isFalse);
    expect(report.toJson(), containsPair('productionDecision', 'no_go'));
    expect(report.toJson(), containsPair('queryOrEvidencePersisted', false));
    expect(
      classifier.inputs.every((input) {
        final encoded = jsonEncode(input.toClassifierJson());
        return !encoded.contains('expected') &&
            !encoded.contains('oracle') &&
            !encoded.contains('qrel') &&
            !encoded.contains('answerKey');
      }),
      isTrue,
    );
    final persisted = await File(
      '${root.path}/out/rag3_batched_support_filter_instrument.json',
    ).readAsString();
    expect(persisted, isNot(contains(classifier.inputs.first.query)));
    expect(
      persisted,
      isNot(contains(classifier.inputs.first.chunks.first.content)),
    );
  });

  test('rejects promotion paths before reads or classifier calls', () async {
    final classifier = _DropClassifier();

    await expectLater(
      runRag3BatchedSupportFilterInstrument(
        const Rag3BatchedSupportFilterInstrumentOptions(
          fixturePath: 'rag3_promotion/missing.json',
          oraclePath: 'missing-oracle.json',
          outDir: 'missing-output',
          baseUrl: 'http://model.test/v1',
          model: 'test-model',
        ),
        classifier: classifier,
        buildCommit: 'test-build',
        buildDirty: false,
      ),
      throwsStateError,
    );
    expect(classifier.inputs, isEmpty);
  });

  test('rejects a different non-promotion fixture', () async {
    final root = await Directory.systemTemp.createTemp(
      'rag3-support-filter-wrong-fixture-',
    );
    addTearDown(() => root.delete(recursive: true));
    final classifier = _DropClassifier();

    await expectLater(
      runRag3BatchedSupportFilterInstrument(
        Rag3BatchedSupportFilterInstrumentOptions(
          fixturePath: _differentFixture,
          oraclePath: _oracle,
          outDir: '${root.path}/out',
          baseUrl: 'http://model.test/v1',
          model: 'test-model',
        ),
        classifier: classifier,
        buildCommit: 'test-build',
        buildDirty: false,
      ),
      throwsStateError,
    );
    expect(classifier.inputs, isEmpty);
  });

  test('sends one strict oracle-free chat-completion batch', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Map<String, Object?> requestJson;
    final handled = server.first.then((request) async {
      requestJson = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, Object?>();
      final userMessage = ((requestJson['messages'] as List).last as Map)
          .cast<String, Object?>();
      final input = (jsonDecode(userMessage['content']! as String) as Map)
          .cast<String, Object?>();
      final evidence = input['evidence']! as List;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'response-model',
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'schemaVersion': 1,
                  'decisions': [
                    for (final rawChunk in evidence)
                      {
                        'chunkId': (rawChunk as Map)['chunkId'],
                        'decision': 'drop_non_support',
                      },
                  ],
                }),
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    final classifier = Rag3HttpBatchedSupportFilterClassifier(
      endpoint:
          'http://${server.address.host}:${server.port}/v1/chat/completions',
      model: 'request-model',
      apiKey: 'secret-key',
    );
    addTearDown(classifier.close);
    final input = Rag3BatchedSupportFilterInput(
      query: 'runtime query',
      revision: 'abc123',
      authority: 'current',
      chunks: [
        Rag3SupportFilterChunkInput(
          chunkId: 'docs/source.md#1',
          sourcePath: 'docs/source.md',
          content: 'runtime evidence',
        ),
      ],
    );
    final response = await classifier.classify(input);
    await handled;

    expect(requestJson.keys, {
      'model',
      'temperature',
      'max_tokens',
      'stream',
      'messages',
      'response_format',
    });
    final encoded = jsonEncode(requestJson);
    expect(encoded, contains('runtime query'));
    expect(encoded, contains('runtime evidence'));
    expect(encoded, contains('docs/source.md#1'));
    expect(encoded, isNot(contains('expectedDecisions')));
    expect(encoded, isNot(contains('oracle')));
    expect(encoded, isNot(contains('qrels')));
    expect(response.latencyMs, greaterThanOrEqualTo(0));
    expect(classifier.responseModelIds, {'response-model'});
    expect(classifier.requestCount, 1);
  });

  test(
    'marks later batches unavailable after the first HTTP failure',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final handled = server.first.then((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      final classifier = Rag3HttpBatchedSupportFilterClassifier(
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
            chunkId: 'docs/source.md#1',
            sourcePath: 'docs/source.md',
            content: 'runtime evidence',
          ),
        ],
      );

      await expectLater(
        classifier.classify(input),
        throwsA(isA<Rag3BatchedSupportFilterUnavailable>()),
      );
      await handled;
      await expectLater(
        classifier.classify(input),
        throwsA(isA<Rag3BatchedSupportFilterUnavailable>()),
      );
      expect(classifier.requestCount, 1);
      expect(classifier.lastFailureReason, 'http_status_503');
    },
  );
}

final class _DropClassifier implements Rag3BatchedSupportFilterClassifier {
  final inputs = <Rag3BatchedSupportFilterInput>[];

  @override
  Future<Rag3SupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  ) async {
    inputs.add(input);
    return Rag3SupportFilterClassifierResponse(
      raw: jsonEncode({
        'schemaVersion': 1,
        'decisions': [
          for (final chunk in input.chunks)
            {'chunkId': chunk.chunkId, 'decision': 'drop_non_support'},
        ],
      }),
      latencyMs: 1,
    );
  }
}

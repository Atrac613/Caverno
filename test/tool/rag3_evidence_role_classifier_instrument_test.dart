import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_evidence_role_classifier_contract.dart';
import '../../tool/rag3_evidence_role_classifier_instrument.dart';

const _fixture = 'tool/fixtures/rag2_semantic_holdout/fixture.json';
const _oracle = 'tool/fixtures/rag2_passage_role_oracle/oracle.json';

void main() {
  test('parses the exact bounded instrument options', () {
    final options = Rag3EvidenceRoleInstrumentOptions.parse(const [
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
      Rag3EvidenceRoleInstrumentOptions.parse(const [
        '--fixture',
        _fixture,
        '--oracle',
        _oracle,
      ]),
      isNull,
    );
  });

  test(
    'evaluates every development query and document without oracle input',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'rag3-role-instrument-',
      );
      addTearDown(() => root.delete(recursive: true));
      final classifier = _OracleBlindClassifier();
      final report = await runRag3EvidenceRoleInstrument(
        Rag3EvidenceRoleInstrumentOptions(
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

      expect(classifier.inputs, hasLength(100));
      expect(report.classifierReport.cases, hasLength(100));
      expect(
        report.toJson(),
        containsPair('inputPairPolicy', 'all_query_document_pairs'),
      );
      expect(report.toJson(), containsPair('queryOrEvidencePersisted', false));
      expect(report.toJson(), containsPair('productionDecision', 'no_go'));
      expect(
        classifier.inputs.every((input) {
          final encoded = jsonEncode(input.toClassifierJson());
          return !encoded.contains('expected') &&
              !encoded.contains('oracle') &&
              !encoded.contains('qrel');
        }),
        isTrue,
      );
      final persisted = await File(
        '${root.path}/out/rag3_evidence_role_classifier_instrument.json',
      ).readAsString();
      expect(persisted, isNot(contains(classifier.inputs.first.query)));
      expect(persisted, isNot(contains(classifier.inputs.first.content)));
    },
  );

  test(
    'rejects promotion paths before fixture reads or classifier calls',
    () async {
      final classifier = _OracleBlindClassifier();

      await expectLater(
        runRag3EvidenceRoleInstrument(
          const Rag3EvidenceRoleInstrumentOptions(
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
    },
  );

  test('sends only the allowlisted strict chat-completion contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Map<String, Object?> requestJson;
    final handled = server.first.then((request) async {
      expect(request.contentLength, greaterThan(0));
      expect(request.headers.chunkedTransferEncoding, isFalse);
      requestJson = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, Object?>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'response-model',
          'choices': [
            {
              'message': {
                'content': '{"schemaVersion":1,"role":"topical_only"}',
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    final classifier = Rag3HttpEvidenceRoleClassifier(
      endpoint:
          'http://${server.address.host}:${server.port}/v1/chat/completions',
      model: 'request-model',
      apiKey: 'secret-key',
    );
    addTearDown(classifier.close);
    final response = await classifier.classify(
      Rag3EvidenceRoleClassifierInput(
        query: 'runtime query',
        sourcePath: 'docs/source.md',
        revision: 'abc123',
        authority: 'current',
        content: 'runtime evidence',
      ),
    );
    await handled;

    expect(response, '{"schemaVersion":1,"role":"topical_only"}');
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
    expect(encoded, isNot(contains('expectedRole')));
    expect(encoded, isNot(contains('oracle')));
    expect(encoded, isNot(contains('qrels')));
    expect(classifier.responseModelIds, {'response-model'});
  });
}

final class _OracleBlindClassifier implements Rag3EvidenceRoleClassifier {
  final inputs = <Rag3EvidenceRoleClassifierInput>[];

  @override
  Future<String> classify(Rag3EvidenceRoleClassifierInput input) async {
    inputs.add(input);
    return '{"schemaVersion":1,"role":"irrelevant"}';
  }
}

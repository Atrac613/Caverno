import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_promotion_run.dart';

void main() {
  test('parses the frozen promotion input flags', () {
    final options = Rag3PromotionRunOptions.parse(const [
      '--fixture',
      'fixture.json',
      '--oracle',
      'oracle.json',
      '--out-dir',
      'out',
      '--base-url',
      'http://embedding.test/v1',
      '--model',
      'test-embedding',
    ]);

    expect(options, isNotNull);
    expect(options!.apiKey, 'no-key');
    expect(
      Rag3PromotionRunOptions.parse(const [
        '--fixture',
        'fixture.json',
        '--out-dir',
        'out',
      ]),
      isNull,
    );
  });

  test('refuses to overwrite an existing promotion result', () async {
    final root = await Directory.systemTemp.createTemp('rag3-promotion-guard-');
    addTearDown(() => root.delete(recursive: true));
    final output = Directory('${root.path}/out')..createSync();
    File('${output.path}/existing.json').writeAsStringSync('{}');
    final provider = _FakeEmbeddingProvider();

    await expectLater(
      runRag3Promotion(
        Rag3PromotionRunOptions(
          fixturePath: '${root.path}/missing-fixture.json',
          oraclePath: '${root.path}/missing-oracle.json',
          outDir: output.path,
          baseUrl: 'http://embedding.test/v1',
          model: 'test-embedding',
          apiKey: 'secret-key',
        ),
        embeddingProvider: provider,
        buildCommit: 'test-build',
        buildDirty: false,
      ),
      throwsA(isA<StateError>()),
    );
    expect(provider.callCount, 0);
  });

  test('sends embedding JSON with an explicit content length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late int receivedContentLength;
    late Map<String, Object?> receivedBody;
    final handled = server.first.then((request) async {
      receivedContentLength = request.contentLength;
      receivedBody = (jsonDecode(await utf8.decodeStream(request)) as Map)
          .cast<String, Object?>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'test-embedding',
          'data': [
            {
              'index': 0,
              'embedding': [1.0, 0.0],
            },
          ],
        }),
      );
      await request.response.close();
    });
    final provider = Rag3HttpEmbeddingProvider(
      endpoint: 'http://127.0.0.1:${server.port}/v1/embeddings',
      apiKey: 'secret-key',
    );

    final response = await provider.embed(
      model: 'test-embedding',
      inputs: const ['synthetic input'],
    );
    await handled;

    expect(receivedContentLength, greaterThan(0));
    expect(receivedBody['model'], 'test-embedding');
    expect(receivedBody['input'], ['synthetic input']);
    expect(response.responseModelId, 'test-embedding');
    expect(response.vectors, [
      [1.0, 0.0],
    ]);
  });

  test('captures hosted lexical and fingerprinted vector rankings', () async {
    final root = await Directory.systemTemp.createTemp('rag3-promotion-test-');
    addTearDown(() => root.delete(recursive: true));
    final fixtureFiles = await _writeSyntheticFixture(root);
    final output = '${root.path}/out';
    final provider = _FakeEmbeddingProvider();

    final report = await runRag3Promotion(
      Rag3PromotionRunOptions(
        fixturePath: fixtureFiles.$1,
        oraclePath: fixtureFiles.$2,
        outDir: output,
        baseUrl: 'http://embedding.test/v1/',
        model: 'test-embedding',
        apiKey: 'secret-key',
      ),
      embeddingProvider: provider,
      buildCommit: 'test-build',
      buildDirty: false,
    );

    expect(report.deterministicReplayPassed, isTrue);
    expect(report.core.cases.first.hitAt5, isTrue);
    expect(report.core.cases.last.status, 'not_submitted');
    expect(provider.callCount, 2);

    final encodedRun = await File(
      '$output/rag3_promotion_run.json',
    ).readAsString();
    expect(encodedRun, isNot(contains('synthetic alpha evidence')));
    expect(encodedRun, isNot(contains('Where is alpha evidence?')));
    expect(encodedRun, isNot(contains('secret-key')));
    final run = (jsonDecode(encodedRun) as Map).cast<String, Object?>();
    final cases = (run['cases'] as List).cast<Map>();
    final submitted = cases.first;
    final vector = submitted['vector'] as Map;
    expect(submitted['lexicalRankedChunkIds'], [
      'docs/alpha.md#1',
      'docs/beta.md#1',
    ]);
    expect(vector['status'], 'available');
    expect(vector['rankedChunkIds'], ['docs/alpha.md#1', 'docs/beta.md#1']);
    expect((vector['fingerprint'] as Map)['dimension'], 2);
    expect(cases.last['submitted'], isFalse);
    expect((cases.last['lexicalRankedChunkIds'] as List), isEmpty);
  });
}

final class _FakeEmbeddingProvider implements Rag3EmbeddingProvider {
  int callCount = 0;

  @override
  Future<Rag3EmbeddingResponse> embed({
    required String model,
    required List<String> inputs,
  }) async {
    callCount++;
    return Rag3EmbeddingResponse(
      responseModelId: model,
      vectors: [
        for (final input in inputs)
          input.toLowerCase().contains('alpha')
              ? const [1.0, 0.0]
              : const [0.0, 1.0],
      ],
      latencyMs: 1,
    );
  }
}

Future<(String, String)> _writeSyntheticFixture(Directory root) async {
  final repository = Directory('${root.path}/repository/docs')
    ..createSync(recursive: true);
  const alpha = 'Synthetic alpha evidence.';
  const beta = 'Synthetic beta evidence.';
  File('${repository.path}/alpha.md').writeAsStringSync(alpha);
  File('${repository.path}/beta.md').writeAsStringSync(beta);
  final corpusHash = await _computeCorpusHash(
    Directory('${root.path}/repository'),
  );
  final fixture = <String, Object?>{
    'schemaName': 'caverno_rag3_offline_hybrid_fixture',
    'schemaVersion': 1,
    'contractId': 'rag3-offline-hybrid-eval-contract-v2',
    'fixtureId': 'rag3-synthetic-promotion-run-test',
    'corpusRoot': 'repository',
    'corpusHash': corpusHash,
    'selectionPolicy': {
      'contextBudgetTokens': 6000,
      'maxGroupsPerObject': 2,
      'estimatedRunesPerToken': 4,
      'citationFormatVersion': 'rag3-citation-v1',
    },
    'negativeControls': const [
      {'id': 'empty-shuffled-fusion', 'expectedOutcome': 'fails_quality_gate'},
      {
        'id': 'budget-bypass',
        'expectedOutcome': 'fails_zero_budget_violation_gate',
      },
    ],
    'objects': [
      _objectJson('docs/alpha.md', alpha),
      _objectJson('docs/beta.md', beta),
    ],
    'cases': const [
      {
        'id': 'alpha-case',
        'query': 'Where is alpha evidence?',
        'language': 'en',
        'shouldSearch': true,
        'strata': ['answerable', 'current'],
      },
      {
        'id': 'no-search-case',
        'query': 'Hello',
        'language': 'en',
        'shouldSearch': false,
        'strata': ['no_search'],
      },
    ],
  };
  final oracle = <String, Object?>{
    'schemaName': 'caverno_rag3_offline_hybrid_oracle',
    'schemaVersion': 1,
    'contractId': 'rag3-offline-hybrid-eval-contract-v2',
    'fixtureId': 'rag3-synthetic-promotion-run-test',
    'corpusHash': corpusHash,
    'defaultPassageRole': 'irrelevant',
    'cases': const [
      {
        'id': 'alpha-case',
        'expectedEvidenceRole': 'answer_support',
        'qrels': {
          'objects': {'docs/alpha.md': 3},
          'chunks': {'docs/alpha.md#1': 3},
        },
        'passageRoles': {'docs/alpha.md#1': 'answer_support'},
      },
      {
        'id': 'no-search-case',
        'expectedEvidenceRole': 'not_applicable',
        'qrels': {'objects': {}, 'chunks': {}},
        'passageRoles': {},
      },
    ],
  };
  final fixturePath = '${root.path}/fixture.json';
  final oraclePath = '${root.path}/oracle.json';
  File(fixturePath).writeAsStringSync(jsonEncode(fixture));
  File(oraclePath).writeAsStringSync(jsonEncode(oracle));
  return (fixturePath, oraclePath);
}

Map<String, Object?> _objectJson(String path, String content) => {
  'id': path,
  'sourcePath': path,
  'revision': 'synthetic-rev-1',
  'objectContentHash': _sha256(content),
  'sourceTrust': 'high',
  'authority': 'current',
  'chunks': [
    {
      'id': '$path#1',
      'lineStart': 1,
      'lineEnd': 1,
      'contentHash': _sha256(content),
    },
  ],
};

Future<String> _computeCorpusHash(Directory root) async {
  final files = root.listSync(recursive: true).whereType<File>().toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final bytes = <int>[];
  for (final file in files) {
    bytes
      ..addAll(utf8.encode(file.path.substring(root.path.length + 1)))
      ..add(0)
      ..addAll(await file.readAsBytes())
      ..add(0);
  }
  return sha256.convert(bytes).toString();
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_abstention_vector_instrument.dart';
import '../../tool/rag3_promotion_run.dart';
import '../../tool/rag_retrieval_baseline.dart';
import '../../tool/rag_retrieval_eval.dart';

const _rag1Fixture = 'tool/fixtures/rag_retrieval_eval/fixture.json';
const _semanticFixture = 'tool/fixtures/rag2_semantic_holdout/fixture.json';
const _compositionalFixture =
    'tool/fixtures/rag2_compositional_holdout/fixture.json';
const _passageRoleOracle = 'tool/fixtures/rag2_passage_role_oracle/oracle.json';

void main() {
  test('parses one RAG1 and two RAG2 fixture flags', () {
    final options = Rag3AbstentionVectorInstrumentOptions.parse(const [
      '--rag1-fixture',
      _rag1Fixture,
      '--rag2-fixture',
      _semanticFixture,
      '--rag2-fixture',
      _compositionalFixture,
      '--passage-role-oracle',
      _passageRoleOracle,
      '--out-dir',
      'out',
      '--base-url',
      'http://embedding.test/v1',
      '--model',
      'test-embedding',
    ]);

    expect(options, isNotNull);
    expect(options!.apiKey, 'no-key');
    expect(options.allFixturePaths, hasLength(3));
    expect(
      Rag3AbstentionVectorInstrumentOptions.parse(const [
        '--rag1-fixture',
        _rag1Fixture,
      ]),
      isNull,
    );
  });

  test('rejects promotion paths before reads or embedding calls', () async {
    final root = await Directory.systemTemp.createTemp(
      'rag3-abstention-vector-reject-',
    );
    addTearDown(() => root.delete(recursive: true));
    final provider = _RecordingEmbeddingProvider();

    await expectLater(
      runRag3AbstentionVectorInstrument(
        Rag3AbstentionVectorInstrumentOptions(
          rag1FixturePath: 'missing.json',
          rag2FixturePaths: const [
            'missing-semantic.json',
            'rag3_promotion/compositional.json',
          ],
          passageRoleOraclePath: 'missing-oracle.json',
          outDir: '${root.path}/out',
          baseUrl: 'http://embedding.test/v1',
          model: 'test-embedding',
          apiKey: 'secret-key',
        ),
        embeddingProvider: provider,
        buildCommit: 'test-build',
        buildDirty: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cannot use promotion artifacts'),
        ),
      ),
    );
    expect(provider.inputs, isEmpty);
    expect(Directory('${root.path}/out').existsSync(), isFalse);
  });

  test('captures only declared non-promotion fixture inputs', () async {
    final root = await Directory.systemTemp.createTemp(
      'rag3-abstention-vector-',
    );
    addTearDown(() => root.delete(recursive: true));
    final provider = _RecordingEmbeddingProvider();
    final options = Rag3AbstentionVectorInstrumentOptions(
      rag1FixturePath: _rag1Fixture,
      rag2FixturePaths: const [_semanticFixture, _compositionalFixture],
      passageRoleOraclePath: _passageRoleOracle,
      outDir: '${root.path}/out',
      baseUrl: 'http://embedding.test/v1',
      model: 'test-embedding',
      apiKey: 'secret-key',
    );

    final report = await runRag3AbstentionVectorInstrument(
      options,
      embeddingProvider: provider,
      buildCommit: 'test-build',
      buildDirty: false,
    );

    expect(report.instrumentValidated, isTrue);
    expect(report.datasets.map((item) => item.split), [
      'development',
      'development',
      'validation',
    ]);
    expect(report.toJson(), containsPair('promotionFixtureAccessed', false));
    expect(report.toJson(), containsPair('productionDecision', 'no_go'));
    expect(report.selection.scores.map((item) => item.depth), [1, 3, 5]);

    final allowedInputs = await _allowedInputs(options.allFixturePaths);
    expect(provider.inputs, isNotEmpty);
    expect(provider.inputs.every(allowedInputs.contains), isTrue);
    expect(
      File(
        '${options.outDir}/rag3_abstention_vector_instrument.json',
      ).existsSync(),
      isTrue,
    );
    for (final dataset in report.datasets) {
      final runJson =
          (jsonDecode(
                    await File(
                      '${options.outDir}/${dataset.sourceFixtureId}/'
                      'rag3_abstention_vector_run.json',
                    ).readAsString(),
                  )
                  as Map)
              .cast<String, Object?>();
      final cases = (runJson['cases'] as List).cast<Map>();
      expect(
        cases.every((item) => (item['vector'] as Map)['status'] == 'available'),
        isTrue,
      );
    }
  });
}

Future<Set<String>> _allowedInputs(List<String> fixturePaths) async {
  final allowed = <String>{List.filled(25000, 'x').join()};
  for (final path in fixturePaths) {
    final fixture = await RagRetrievalFixture.load(File(path));
    allowed.addAll(fixture.cases.map((item) => item.query));
    final documents = await loadRagFixtureDocuments(fixture);
    allowed.addAll(
      documents.map(
        (item) => item.content.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      ),
    );
  }
  return allowed;
}

final class _RecordingEmbeddingProvider implements Rag3EmbeddingProvider {
  final inputs = <String>[];

  @override
  Future<Rag3EmbeddingResponse> embed({
    required String model,
    required List<String> inputs,
  }) async {
    this.inputs.addAll(inputs);
    return Rag3EmbeddingResponse(
      responseModelId: model,
      vectors: [for (final input in inputs) _vector(input)],
      latencyMs: 1,
    );
  }

  List<double> _vector(String input) {
    final hash = input.runes.fold<int>(17, (value, rune) {
      return ((value * 31) + rune) & 0x7fffffff;
    });
    return [1 + (hash % 97).toDouble(), 1 + ((hash ~/ 97) % 89).toDouble(), 1];
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_evidence_role_classifier_contract.dart';

void main() {
  test('scores an exact four-role runtime classification', () async {
    final classifier = _RecordingClassifier(_roleForSource);

    final report = await evaluateRag3EvidenceRoleClassifier(
      fixtureId: 'rag3-evidence-role-development-v1',
      examples: _examples(),
      classifier: classifier,
    );

    expect(report.passed, isTrue);
    expect(report.macroF1, 1);
    expect(report.unavailableCount, 0);
    expect(report.invalidCount, 0);
    expect(report.metrics.values.every((metrics) => metrics.f1 == 1), isTrue);
    expect(report.toJson(), containsPair('productionDecision', 'no_go'));
    expect(report.toJson(), containsPair('promotionDecision', 'not_run'));
  });

  test('keeps oracle roles out of classifier requests', () async {
    final firstClassifier = _RecordingClassifier(_roleForSource);
    final secondClassifier = _RecordingClassifier(_roleForSource);
    final examples = _examples();
    final changedOracle = [
      for (final example in examples)
        Rag3EvidenceRoleInstrumentExample(
          caseId: example.caseId,
          chunkId: example.chunkId,
          input: example.input,
          expectedRole: _nextRole(example.expectedRole),
        ),
    ];

    final first = await evaluateRag3EvidenceRoleClassifier(
      fixtureId: 'rag3-evidence-role-development-v1',
      examples: examples,
      classifier: firstClassifier,
    );
    final second = await evaluateRag3EvidenceRoleClassifier(
      fixtureId: 'rag3-evidence-role-development-v1',
      examples: changedOracle,
      classifier: secondClassifier,
    );

    expect(firstClassifier.requests, secondClassifier.requests);
    expect(
      firstClassifier.requests.every((request) {
        final encoded = jsonEncode(request);
        return !encoded.contains('expected') &&
            !encoded.contains('oracle') &&
            !encoded.contains('qrel');
      }),
      isTrue,
    );
    expect(first.passed, isTrue);
    expect(second.passed, isFalse);
  });

  test('fails closed when the classifier is unavailable or invalid', () async {
    final unavailable = await evaluateRag3EvidenceRoleClassifier(
      fixtureId: 'rag3-evidence-role-development-v1',
      examples: _examples(),
      classifier: _UnavailableClassifier(),
    );
    final invalid = await evaluateRag3EvidenceRoleClassifier(
      fixtureId: 'rag3-evidence-role-development-v1',
      examples: _examples(),
      classifier: _ConstantClassifier('not-json'),
    );

    expect(unavailable.passed, isFalse);
    expect(unavailable.unavailableCount, _examples().length);
    expect(
      unavailable.cases.every(
        (item) => item.prediction.role == Rag3RuntimeEvidenceRole.irrelevant,
      ),
      isTrue,
    );
    expect(invalid.passed, isFalse);
    expect(invalid.invalidCount, _examples().length);
    expect(
      invalid.cases.every(
        (item) => item.prediction.role == Rag3RuntimeEvidenceRole.irrelevant,
      ),
      isTrue,
    );
  });

  test('accepts only the exact classifier response schema', () {
    expect(
      Rag3EvidenceRolePrediction.parse(
        '{"schemaVersion":1,"role":"answer_support"}',
      ).role,
      Rag3RuntimeEvidenceRole.answerSupport,
    );
    for (final response in const [
      '```json\n{"schemaVersion":1,"role":"answer_support"}\n```',
      '{"schemaVersion":1,"role":"answer_support","reason":"yes"}',
      '{"schemaVersion":1,"role":"unknown"}',
    ]) {
      expect(
        () => Rag3EvidenceRolePrediction.parse(response),
        throwsFormatException,
      );
    }
  });

  test('rejects incomplete, duplicate, and promotion evaluation inputs', () {
    expect(
      () => Rag3EvidenceRoleClassifierInput(
        query: 'query',
        sourcePath: 'tool/fixtures/rag3_promotion/document.md',
        revision: 'abc123',
        authority: 'canonical',
        content: 'content',
      ),
      throwsStateError,
    );
    expect(
      () => evaluateRag3EvidenceRoleClassifier(
        fixtureId: 'rag3_offline_hybrid_holdout',
        examples: _examples(),
        classifier: _RecordingClassifier(_roleForSource),
      ),
      throwsStateError,
    );
    expect(
      () => evaluateRag3EvidenceRoleClassifier(
        fixtureId: 'development',
        examples: _examples().sublist(0, 3),
        classifier: _RecordingClassifier(_roleForSource),
      ),
      throwsStateError,
    );
    expect(
      () => evaluateRag3EvidenceRoleClassifier(
        fixtureId: 'development',
        examples: [..._examples(), _examples().first],
        classifier: _RecordingClassifier(_roleForSource),
      ),
      throwsStateError,
    );
  });

  test('omits query and evidence content from the report', () async {
    final report = await evaluateRag3EvidenceRoleClassifier(
      fixtureId: 'rag3-evidence-role-development-v1',
      examples: _examples(),
      classifier: _RecordingClassifier(_roleForSource),
    );
    final encoded = jsonEncode(report.toJson());

    expect(encoded, isNot(contains('private query')));
    expect(encoded, isNot(contains('sensitive evidence')));
    expect(encoded, contains('case-answer'));
    expect(encoded, contains('chunk-answer'));
  });
}

List<Rag3EvidenceRoleInstrumentExample> _examples() => [
  _example('answer', Rag3RuntimeEvidenceRole.answerSupport),
  _example('abstention', Rag3RuntimeEvidenceRole.abstentionSupport),
  _example('topical', Rag3RuntimeEvidenceRole.topicalOnly),
  _example('irrelevant', Rag3RuntimeEvidenceRole.irrelevant),
];

Rag3EvidenceRoleInstrumentExample _example(
  String id,
  Rag3RuntimeEvidenceRole expectedRole,
) => Rag3EvidenceRoleInstrumentExample(
  caseId: 'case-$id',
  chunkId: 'chunk-$id',
  input: Rag3EvidenceRoleClassifierInput(
    query: 'private query $id',
    sourcePath: 'docs/$id.md',
    revision: 'abc123',
    authority: 'canonical',
    content: 'sensitive evidence $id',
  ),
  expectedRole: expectedRole,
);

Rag3RuntimeEvidenceRole _nextRole(Rag3RuntimeEvidenceRole role) {
  final values = Rag3RuntimeEvidenceRole.values;
  return values[(values.indexOf(role) + 1) % values.length];
}

String _roleForSource(Rag3EvidenceRoleClassifierInput input) {
  final role = Rag3RuntimeEvidenceRole.values.singleWhere(
    (item) => input.sourcePath == 'docs/${item.id.split('_').first}.md',
    orElse: () {
      if (input.sourcePath == 'docs/answer.md') {
        return Rag3RuntimeEvidenceRole.answerSupport;
      }
      if (input.sourcePath == 'docs/abstention.md') {
        return Rag3RuntimeEvidenceRole.abstentionSupport;
      }
      throw StateError('Unexpected test source: ${input.sourcePath}');
    },
  );
  return jsonEncode({'schemaVersion': 1, 'role': role.id});
}

final class _RecordingClassifier implements Rag3EvidenceRoleClassifier {
  _RecordingClassifier(this.handler);

  final String Function(Rag3EvidenceRoleClassifierInput input) handler;
  final requests = <Map<String, Object?>>[];

  @override
  Future<String> classify(Rag3EvidenceRoleClassifierInput input) async {
    requests.add(input.toClassifierJson());
    return handler(input);
  }
}

final class _UnavailableClassifier implements Rag3EvidenceRoleClassifier {
  @override
  Future<String> classify(Rag3EvidenceRoleClassifierInput input) {
    throw const Rag3EvidenceRoleClassifierUnavailable();
  }
}

final class _ConstantClassifier implements Rag3EvidenceRoleClassifier {
  const _ConstantClassifier(this.response);

  final String response;

  @override
  Future<String> classify(Rag3EvidenceRoleClassifierInput input) async {
    return response;
  }
}

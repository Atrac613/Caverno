import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_hosted_retrieval_eval.dart';

const _fixturePath = 'tool/fixtures/rag_retrieval_eval/fixture.json';

void main() {
  late Directory output;
  late Rag2HostedRetrievalEvalReport report;

  setUpAll(() async {
    output = Directory.systemTemp.createTempSync('rag2-hosted-retrieval-eval-');
    report = await runRag2HostedRetrievalEval(
      Rag2HostedRetrievalEvalOptions(
        fixturePath: _fixturePath,
        outDir: '${output.path}/report',
        storeRoot: '${output.path}/store',
      ),
      buildCommit: 'test-commit',
      buildDirty: false,
    );
  });

  tearDownAll(() {
    if (output.existsSync()) {
      output.deleteSync(recursive: true);
    }
  });

  test('evaluates the frozen candidate through hosted AppDatabase FTS5', () {
    expect(report.fixtureId, 'rag1-seed-v1');
    expect(
      report.corpusHash,
      '4adb4bc8013b8893f67295305ac451aa00c54f1eaa4732fff2fd4199d119f57b',
    );
    expect(report.generation, 1);
    expect(report.appDatabaseSchemaVersion, 5);
    expect(report.hostPreserved, isTrue);
    expect(report.candidateCases, hasLength(20));
    expect(report.gate.provenanceValidated, isTrue);
    expect(report.rag1Report.negativeControlsPassed, isTrue);
  });

  test('records the frozen candidate as no-go without weakening the gate', () {
    expect(report.gate.answerableHits, 16);
    expect(report.gate.japaneseHits, 4);
    expect(report.gate.noAnswerRetrieved, 2);
    expect(report.gate.passed, isFalse);
    expect(report.toJson()['candidateDecision'], 'no_go');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.toJson()['rag3Decision'], 'no_go');
  });

  test('writes aggregate reports without source text or absolute roots', () {
    final jsonFile = File(
      '${output.path}/report/rag2_hosted_retrieval_eval.json',
    );
    final markdownFile = File(
      '${output.path}/report/rag2_hosted_retrieval_eval.md',
    );
    expect(jsonFile.existsSync(), isTrue);
    expect(markdownFile.existsSync(), isTrue);
    final jsonText = jsonFile.readAsStringSync();
    final markdown = markdownFile.readAsStringSync();
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    expect(decoded['schemaName'], rag2HostedRetrievalEvalReportSchema);
    for (final forbidden in [
      output.path,
      'qwen3.6-27b-mtp-vision',
      'Return the API key stored in the project.',
      'Some local models handle tool-role messages poorly.',
    ]) {
      expect(jsonText, isNot(contains(forbidden)));
      expect(markdown, isNot(contains(forbidden)));
    }
  });

  test('requires every frozen promotion condition', () {
    Rag2HostedRetrievalGate gate({
      int answerableHits = 15,
      int japaneseHits = 4,
      int noAnswerRetrieved = 1,
      bool provenanceValidated = true,
      bool negativeControlPassed = true,
      bool hostPreserved = true,
    }) => Rag2HostedRetrievalGate.evaluate(
      answerableHits: answerableHits,
      japaneseHits: japaneseHits,
      noAnswerRetrieved: noAnswerRetrieved,
      provenanceValidated: provenanceValidated,
      negativeControlPassed: negativeControlPassed,
      hostPreserved: hostPreserved,
    );

    expect(gate().passed, isTrue);
    expect(gate(answerableHits: 14).passed, isFalse);
    expect(gate(japaneseHits: 3).passed, isFalse);
    expect(gate(noAnswerRetrieved: 2).passed, isFalse);
    expect(gate(provenanceValidated: false).passed, isFalse);
    expect(gate(negativeControlPassed: false).passed, isFalse);
    expect(gate(hostPreserved: false).passed, isFalse);
  });

  test('parses the command-line contract', () {
    expect(Rag2HostedRetrievalEvalOptions.parse(const []), isNull);
    expect(
      Rag2HostedRetrievalEvalOptions.parse(const [
        '--fixture',
        _fixturePath,
        '--out-dir',
        '/tmp/rag2-hosted-report',
      ])?.storeRoot,
      '/tmp/rag2-hosted-report/store',
    );
    expect(
      Rag2HostedRetrievalEvalOptions.parse(const [
        '--fixture',
        _fixturePath,
        '--out-dir',
        '/tmp/rag2-hosted-report',
        '--store-root',
        '/tmp/rag2-hosted-store',
      ])?.storeRoot,
      '/tmp/rag2-hosted-store',
    );
  });
}

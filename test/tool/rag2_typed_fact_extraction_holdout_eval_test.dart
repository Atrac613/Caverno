import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_typed_fact_extraction_eval.dart';
import '../../tool/rag2_typed_fact_extraction_holdout_eval.dart';

void main() {
  test(
    'freezes a hashed holdout with every extraction source family',
    () async {
      final fixture = await Rag2TypedFactExtractionFixture.load(
        File('tool/fixtures/rag2_extraction_holdout/fixture.json'),
      );

      expect(await fixture.computeCorpusHash(), fixture.corpusHash);
      expect(fixture.extractorVersion, 'typed-fact-extraction-v1-frozen');
      expect(
        fixture.sourceFamilies,
        containsAll(Rag2ExtractionSourceFamily.values),
      );
    },
  );

  test('audits frozen extraction v1 without downstream claims', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-holdout-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2TypedFactExtractionHoldoutEval(
      _options(directory.path),
    );

    expect(report.metrics.meetsGate, isFalse);
    expect(report.metrics.overall.extractedCount, 7);
    expect(report.metrics.overall.oracleCount, 11);
    expect(report.metrics.overall.precision, closeTo(5 / 7, 0.000001));
    expect(report.metrics.overall.recall, closeTo(5 / 11, 0.000001));
    final dart =
        report.metrics.byFamily[Rag2ExtractionSourceFamily.dartAssignment]!;
    final uri =
        report.metrics.byFamily[Rag2ExtractionSourceFamily.markdownUri]!;
    final prose =
        report.metrics.byFamily[Rag2ExtractionSourceFamily.proseState]!;
    expect(dart.precision, 0.75);
    expect(dart.recall, 1.0);
    expect(uri.precision, closeTo(2 / 3, 0.000001));
    expect(uri.recall, 0.5);
    expect(prose.precision, 0.0);
    expect(prose.recall, 0.0);
    expect(report.toJson()['holdoutIndependent'], isTrue);
    expect(report.toJson()['downstreamMatcherDecision'], 'not_evaluated');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      report.extractedFacts.map((fact) => fact.factId),
      containsAll([
        'extracted-dart-release-5',
        'extracted-uri-broken_endpoint-11',
      ]),
    );
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_typed_fact_extraction_holdout_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_typed_fact_extraction_holdout_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test('rejects an oracle fact outside the frozen corpus', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-invalid-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final json =
        jsonDecode(
              File(
                'tool/fixtures/rag2_extraction_holdout/oracle_facts.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final facts = (json['facts']! as List).cast<Map<String, Object?>>();
    final source = (facts.first['source']! as Map).cast<String, Object?>();
    source['endLine'] = 999;
    final invalidOracle = File('${directory.path}/invalid_oracle.json');
    invalidOracle.writeAsStringSync(jsonEncode(json));

    await expectLater(
      runRag2TypedFactExtractionHoldoutEval(
        Rag2TypedFactExtractionHoldoutOptions(
          fixturePath: _fixturePath,
          oracleFactsPath: invalidOracle.path,
          outDir: directory.path,
        ),
      ),
      throwsStateError,
    );
  });
}

const _fixturePath = 'tool/fixtures/rag2_extraction_holdout/fixture.json';
const _oraclePath = 'tool/fixtures/rag2_extraction_holdout/oracle_facts.json';

Rag2TypedFactExtractionHoldoutOptions _options(String outDir) =>
    Rag2TypedFactExtractionHoldoutOptions(
      fixturePath: _fixturePath,
      oracleFactsPath: _oraclePath,
      outDir: outDir,
    );

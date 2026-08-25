import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_typed_fact_extraction_eval.dart';
import '../../tool/rag2_typed_fact_extraction_v2_holdout_eval.dart';

void main() {
  test('freezes an independent precision holdout for v1 and v2', () async {
    final fixture = await Rag2TypedFactExtractionPrecisionFixture.load(
      File(_fixturePath),
    );

    expect(await fixture.computeCorpusHash(), fixture.corpusHash);
    expect(fixture.precisionFamilies, {
      Rag2ExtractionSourceFamily.dartAssignment,
      Rag2ExtractionSourceFamily.markdownUri,
    });
    expect(fixture.observationalFamilies, {
      Rag2ExtractionSourceFamily.proseState,
    });
  });

  test('promotes v2 precision while extraction remains no-go', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-v2-holdout-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2TypedFactExtractionV2HoldoutEval(
      _options(directory.path),
    );

    expect(report.precisionGatePassed, isTrue);
    final v1Dart =
        report.v1.byFamily[Rag2ExtractionSourceFamily.dartAssignment]!;
    final v2Dart =
        report.v2.byFamily[Rag2ExtractionSourceFamily.dartAssignment]!;
    final v1Uri = report.v1.byFamily[Rag2ExtractionSourceFamily.markdownUri]!;
    final v2Uri = report.v2.byFamily[Rag2ExtractionSourceFamily.markdownUri]!;
    expect(v1Dart.precision, 0.0);
    expect(v2Dart.precision, 1.0);
    expect(v2Dart.recall, 0.75);
    expect(v1Uri.precision, 0.5);
    expect(v2Uri.precision, 1.0);
    expect(v2Uri.recall, closeTo(2 / 3, 0.000001));
    expect(report.v2.overall.precision, 1.0);
    expect(report.v2.overall.recall, 0.5);
    expect(report.v2.meetsGate, isFalse);
    expect(report.toJson()['precisionBaselineDecision'], 'go');
    expect(report.toJson()['extractionDecision'], 'no_go');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_typed_fact_extraction_v2_holdout_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_typed_fact_extraction_v2_holdout_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test('rejects precision oracle provenance outside the corpus', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-v2-invalid-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final json =
        jsonDecode(File(_oraclePath).readAsStringSync())
            as Map<String, Object?>;
    final facts = (json['facts']! as List).cast<Map<String, Object?>>();
    final provenance = (facts.first['provenance']! as Map)
        .cast<String, Object?>();
    provenance['corpusHash'] = 'invalid';
    final invalidOracle = File('${directory.path}/invalid_oracle.json');
    invalidOracle.writeAsStringSync(jsonEncode(json));

    await expectLater(
      runRag2TypedFactExtractionV2HoldoutEval(
        Rag2TypedFactExtractionV2HoldoutOptions(
          fixturePath: _fixturePath,
          oracleFactsPath: invalidOracle.path,
          outDir: directory.path,
        ),
      ),
      throwsStateError,
    );
  });
}

const _fixturePath = 'tool/fixtures/rag2_extraction_v2_holdout/fixture.json';
const _oraclePath =
    'tool/fixtures/rag2_extraction_v2_holdout/oracle_facts.json';

Rag2TypedFactExtractionV2HoldoutOptions _options(String outDir) =>
    Rag2TypedFactExtractionV2HoldoutOptions(
      fixturePath: _fixturePath,
      oracleFactsPath: _oraclePath,
      outDir: outDir,
    );

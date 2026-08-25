import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_post_answer_claim_eval.dart';
import '../../tool/rag2_structured_claim_eval.dart';
import '../../tool/rag2_typed_fact_extraction_eval.dart';
import '../../tool/rag2_typed_fact_extraction_outcome_eval.dart';
import '../../tool/rag2_typed_fact_oracle_eval.dart';

void main() {
  test('accounts for every annotated span across the three datasets', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-outcomes-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2TypedFactExtractionOutcomeEval(
      _options(directory.path),
    );

    expect(report.accountingPassed, isTrue);
    expect(report.outcomes, hasLength(35));
    expect(report.overall.spanCount, 35);
    expect(report.overall.extractedCount, 19);
    expect(report.overall.availabilityRate, closeTo(19 / 35, 0.000001));
    expect(report.overall.falseExtractionRate, 0);
    expect(report.overall.statusCounts, {
      Rag2ExtractionOutcomeStatus.extracted: 19,
      Rag2ExtractionOutcomeStatus.unsupportedSyntax: 1,
      Rag2ExtractionOutcomeStatus.unsupportedRelation: 3,
      Rag2ExtractionOutcomeStatus.unsupportedProse: 12,
    });
    expect(report.byFamily.values.map((score) => score.spanCount), [
      11,
      12,
      12,
    ]);
    expect(report.byFamily.values.map((score) => score.extractedCount), [
      10,
      9,
      0,
    ]);
    expect(report.toJson()['schemaVersion'], 2);
    expect(report.toJson()['accountingDecision'], 'go');
    expect(report.toJson()['runtimeAvailabilityDecision'], 'not_evaluated');
    expect(report.toJson()['contractDecision'], 'no_go');
    expect(report.toJson()['extractionDecision'], 'no_go');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_typed_fact_extraction_outcome_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_typed_fact_extraction_outcome_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test('fails accounting when the extractor returns no facts', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-extraction-zero-regression-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final baseline = await runRag2TypedFactExtractionOutcomeEval(
      _options(directory.path),
    );

    final regressed = Rag2TypedFactExtractionOutcomeReport(
      datasets: baseline.datasets.map(_withoutExtractedFacts).toList(),
    );

    expect(regressed.outcomes, hasLength(35));
    expect(regressed.overall.falseExtractionRate, 0);
    expect(regressed.overall.extractedCount, 0);
    expect(regressed.accountingPassed, isFalse);
    expect(regressed.toJson()['accountingDecision'], 'no_go');
  });

  test('does not convert unavailable extraction into an absent verdict', () {
    final decision = applyRag2ExtractionAvailability(
      claim: _claim(relation: 'feature.enabled'),
      envelope: _envelope('docs/states.md'),
      typedDecision: _absentDecision,
      outcomes: [
        _outcome(
          family: Rag2ExtractionSourceFamily.proseState,
          status: Rag2ExtractionOutcomeStatus.unsupportedProse,
          objectId: 'docs/states.md',
        ),
      ],
      coverage: const [],
    );

    expect(decision.verdict, Rag2AvailabilityAwareVerdict.notAvailable);
    expect(decision.reason, 'extractor_unavailable_for_cited_source');
    expect(decision.blockingOutcomeIds, ['outcome-1']);
  });

  test('keeps unknown relations unavailable without coverage proof', () {
    final decision = applyRag2ExtractionAvailability(
      claim: _claim(relation: 'ownership.owner'),
      envelope: _envelope('docs/ownership.md'),
      typedDecision: _absentDecision,
      outcomes: [
        _outcome(
          family: Rag2ExtractionSourceFamily.proseState,
          status: Rag2ExtractionOutcomeStatus.unsupportedProse,
          objectId: 'docs/ownership.md',
        ),
      ],
      coverage: const [],
    );

    expect(decision.verdict, Rag2AvailabilityAwareVerdict.notAvailable);
    expect(decision.reason, 'extractor_coverage_not_proven');
    expect(decision.blockingOutcomeIds, isEmpty);
  });

  test('retains absence only with complete relation coverage', () {
    final decision = applyRag2ExtractionAvailability(
      claim: _claim(relation: 'ownership.owner'),
      envelope: _envelope('docs/ownership.md'),
      typedDecision: _absentDecision,
      outcomes: const [],
      coverage: const [
        Rag2ExtractionCoverage(
          objectId: 'docs/ownership.md',
          relation: 'ownership.owner',
          complete: true,
        ),
      ],
    );

    expect(decision.verdict, Rag2AvailabilityAwareVerdict.absent);
    expect(
      decision.reason,
      'no_asserted_typed_fact_after_available_extraction',
    );
    expect(decision.blockingOutcomeIds, isEmpty);
  });
}

Rag2ExtractionOutcomeDatasetReport _withoutExtractedFacts(
  Rag2ExtractionOutcomeDatasetReport dataset,
) => Rag2ExtractionOutcomeDatasetReport(
  datasetId: dataset.datasetId,
  corpusHash: dataset.corpusHash,
  outcomes: [
    for (final outcome in dataset.outcomes)
      Rag2ExtractionOutcome(
        outcomeId: outcome.outcomeId,
        oracleFactId: outcome.oracleFactId,
        sourceFamily: outcome.sourceFamily,
        source: outcome.source,
        status: switch (outcome.sourceFamily) {
          Rag2ExtractionSourceFamily.dartAssignment =>
            Rag2ExtractionOutcomeStatus.unsupportedSyntax,
          Rag2ExtractionSourceFamily.markdownUri =>
            Rag2ExtractionOutcomeStatus.unsupportedRelation,
          Rag2ExtractionSourceFamily.proseState =>
            Rag2ExtractionOutcomeStatus.unsupportedProse,
        },
        extractedFactIds: const [],
        reason: 'simulated_zero_extraction',
      ),
  ],
  extraction: Rag2FactExtractionMetrics(
    overall: Rag2FactExtractionScore(
      oracleCount: dataset.extraction.overall.oracleCount,
      extractedCount: 0,
      truePositiveCount: 0,
    ),
    byFamily: {
      for (final family in Rag2ExtractionSourceFamily.values)
        family: Rag2FactExtractionScore(
          oracleCount: dataset.extraction.byFamily[family]!.oracleCount,
          extractedCount: 0,
          truePositiveCount: 0,
        ),
    },
  ),
);

const _absentDecision = Rag2TypedFactDecision(
  verdict: Rag2ClaimVerdict.absent,
  reason: 'no_asserted_typed_fact',
  matchedFactIds: [],
);

Rag2TypedClaimAtom _claim({required String relation}) => Rag2TypedClaimAtom(
  candidateId: 'candidate-1',
  claimText: 'A fixed evaluation claim.',
  atom: Rag2TypedAtom(
    subject: 'subject',
    relation: relation,
    value: const Rag2TypedValue(type: Rag2FactValueType.string, value: 'value'),
    scope: Rag2FactScope.current,
    polarity: Rag2FactPolarity.positive,
    modality: Rag2FactModality.asserted,
  ),
);

Rag2ClaimEnvelope _envelope(String objectId) => Rag2ClaimEnvelope(
  candidateId: 'candidate-1',
  scope: Rag2ClaimScope.current,
  citedSourceIds: [objectId],
);

Rag2ExtractionOutcome _outcome({
  required Rag2ExtractionSourceFamily family,
  required Rag2ExtractionOutcomeStatus status,
  required String objectId,
}) => Rag2ExtractionOutcome(
  outcomeId: 'outcome-1',
  oracleFactId: 'oracle-1',
  sourceFamily: family,
  source: Rag2FactSource(objectId: objectId, startLine: 1, endLine: 1),
  status: status,
  extractedFactIds: const [],
  reason: 'test_control',
);

Rag2TypedFactExtractionOutcomeOptions _options(String outDir) =>
    Rag2TypedFactExtractionOutcomeOptions(
      developmentFixturePath:
          'tool/fixtures/rag2_compositional_holdout/fixture.json',
      developmentOracleFactsPath:
          'tool/fixtures/rag2_compositional_holdout/oracle_facts.json',
      holdoutFixturePath: 'tool/fixtures/rag2_extraction_holdout/fixture.json',
      holdoutOracleFactsPath:
          'tool/fixtures/rag2_extraction_holdout/oracle_facts.json',
      precisionFixturePath:
          'tool/fixtures/rag2_extraction_v2_holdout/fixture.json',
      precisionOracleFactsPath:
          'tool/fixtures/rag2_extraction_v2_holdout/oracle_facts.json',
      outDir: outDir,
    );

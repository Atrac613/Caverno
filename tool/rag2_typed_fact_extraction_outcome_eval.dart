import 'dart:convert';
import 'dart:io';

import 'rag2_post_answer_claim_eval.dart';
import 'rag2_structured_claim_eval.dart';
import 'rag2_typed_fact_extraction_eval.dart';
import 'rag2_typed_fact_extraction_holdout_eval.dart';
import 'rag2_typed_fact_extraction_v2_eval.dart';
import 'rag2_typed_fact_extraction_v2_holdout_eval.dart';
import 'rag2_typed_fact_oracle_eval.dart';
import 'rag_retrieval_eval.dart';

const rag2TypedFactExtractionOutcomeSchema =
    'caverno_rag2_typed_fact_extraction_outcome_eval';
const rag2TypedFactExtractionOutcomeSchemaVersion = 2;
const rag2TypedFactExtractionOutcomeContract =
    'typed-fact-extraction-outcome-v2';

const _expectedDatasetHashes = <String, String>{
  'rag2-compositional-holdout-v1':
      'c120cb7970ccd7277618915fca9502b0a70fe154fe75c44e0e2199cbb185a8e4',
  'rag2-typed-fact-extraction-holdout-v1':
      '365c9f152244a2ee5d87313fbc1af70ccfa03a8a8b25ac18a70edacfe5ff5179',
  'rag2-typed-fact-extraction-v2-holdout-v1':
      'fca6a80ea7386fc33c95260f9a434376639d81fc57c0ef8d673655c77b86d6b8',
};

const _expectedDatasetTruePositives = <String, int>{
  'rag2-compositional-holdout-v1': 9,
  'rag2-typed-fact-extraction-holdout-v1': 5,
  'rag2-typed-fact-extraction-v2-holdout-v1': 5,
};

Future<void> main(List<String> args) async {
  final options = Rag2TypedFactExtractionOutcomeOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_typed_fact_extraction_outcome_eval.dart '
      '--development-fixture PATH --development-oracle-facts PATH '
      '--holdout-fixture PATH --holdout-oracle-facts PATH '
      '--precision-fixture PATH --precision-oracle-facts PATH '
      '--out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2TypedFactExtractionOutcomeEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 extraction-outcome evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2TypedFactExtractionOutcomeReport>
runRag2TypedFactExtractionOutcomeEval(
  Rag2TypedFactExtractionOutcomeOptions options,
) async {
  final developmentFixture = await RagRetrievalFixture.load(
    File(options.developmentFixturePath),
  );
  developmentFixture.validate();
  final developmentHash = await developmentFixture.computeCorpusHash();
  if (developmentFixture.corpusHash != developmentHash) {
    throw StateError('Extraction outcome development corpus hash mismatch.');
  }
  final developmentOracle = await Rag2TypedEvidenceFactSet.load(
    File(options.developmentOracleFactsPath),
  );
  await developmentOracle.validate(developmentFixture, developmentHash);

  final holdoutFixture = await Rag2TypedFactExtractionFixture.load(
    File(options.holdoutFixturePath),
  );
  final holdoutHash = await holdoutFixture.computeCorpusHash();
  if (holdoutFixture.corpusHash != holdoutHash) {
    throw StateError('Extraction outcome holdout corpus hash mismatch.');
  }
  final holdoutOracle = await Rag2TypedEvidenceFactSet.load(
    File(options.holdoutOracleFactsPath),
  );
  await holdoutFixture.validateOracle(holdoutOracle);

  final precisionFixture = await Rag2TypedFactExtractionPrecisionFixture.load(
    File(options.precisionFixturePath),
  );
  final precisionHash = await precisionFixture.computeCorpusHash();
  if (precisionFixture.corpusHash != precisionHash) {
    throw StateError('Extraction outcome precision corpus hash mismatch.');
  }
  final precisionOracle = await Rag2TypedEvidenceFactSet.load(
    File(options.precisionOracleFactsPath),
  );
  await precisionFixture.validateOracle(precisionOracle);

  final datasets = [
    await _evaluateDataset(
      datasetId: developmentFixture.fixtureId,
      corpusHash: developmentHash,
      corpusRoot: Directory(
        '${developmentFixture.sourceFile.parent.path}/'
        '${developmentFixture.corpusRoot}',
      ),
      oracleFacts: developmentOracle.facts,
    ),
    await _evaluateDataset(
      datasetId: holdoutFixture.fixtureId,
      corpusHash: holdoutHash,
      corpusRoot: holdoutFixture.corpusDirectory,
      oracleFacts: holdoutOracle.facts,
    ),
    await _evaluateDataset(
      datasetId: precisionFixture.fixtureId,
      corpusHash: precisionHash,
      corpusRoot: precisionFixture.corpusDirectory,
      oracleFacts: precisionOracle.facts,
    ),
  ];
  final report = Rag2TypedFactExtractionOutcomeReport(datasets: datasets);
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_outcome_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_typed_fact_extraction_outcome_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2ExtractionOutcomeDatasetReport> _evaluateDataset({
  required String datasetId,
  required String corpusHash,
  required Directory corpusRoot,
  required List<Rag2TypedEvidenceFact> oracleFacts,
}) async {
  final extractedFacts = await extractRag2TypedFactsV2(
    corpusRoot: corpusRoot,
    corpusHash: corpusHash,
  );
  final outcomes = <Rag2ExtractionOutcome>[];
  for (final oracleFact in oracleFacts) {
    final exactFacts = extractedFacts.where(
      (fact) => _sameTypedFact(fact, oracleFact),
    );
    final family = rag2ExtractionSourceFamily(oracleFact);
    final status = exactFacts.isNotEmpty
        ? Rag2ExtractionOutcomeStatus.extracted
        : await _unsupportedStatus(
            family: family,
            corpusRoot: corpusRoot,
            source: oracleFact.source,
          );
    outcomes.add(
      Rag2ExtractionOutcome(
        outcomeId: '$datasetId:${oracleFact.factId}',
        oracleFactId: oracleFact.factId,
        sourceFamily: family,
        source: oracleFact.source,
        status: status,
        extractedFactIds: exactFacts.map((fact) => fact.factId).toList(),
        reason: _outcomeReason(status),
      ),
    );
  }
  if (outcomes.length != oracleFacts.length ||
      outcomes.map((outcome) => outcome.outcomeId).toSet().length !=
          outcomes.length) {
    throw StateError('Every annotated source span must have one outcome.');
  }
  return Rag2ExtractionOutcomeDatasetReport(
    datasetId: datasetId,
    corpusHash: corpusHash,
    outcomes: outcomes,
    extraction: Rag2FactExtractionMetrics.compare(
      oracle: oracleFacts,
      extracted: extractedFacts,
    ),
  );
}

Future<Rag2ExtractionOutcomeStatus> _unsupportedStatus({
  required Rag2ExtractionSourceFamily family,
  required Directory corpusRoot,
  required Rag2FactSource source,
}) async => switch (family) {
  Rag2ExtractionSourceFamily.dartAssignment =>
    Rag2ExtractionOutcomeStatus.unsupportedSyntax,
  Rag2ExtractionSourceFamily.proseState =>
    Rag2ExtractionOutcomeStatus.unsupportedProse,
  Rag2ExtractionSourceFamily.markdownUri => await _uriUnsupportedStatus(
    corpusRoot: corpusRoot,
    source: source,
  ),
};

Future<Rag2ExtractionOutcomeStatus> _uriUnsupportedStatus({
  required Directory corpusRoot,
  required Rag2FactSource source,
}) async {
  final lines = await File(
    '${corpusRoot.path}/${source.objectId}',
  ).readAsLines();
  final span = lines.sublist(source.startLine - 1, source.endLine).join('\n');
  final tokens = RegExp(r'''https?://[^\s`)]+''')
      .allMatches(span)
      .map((match) => match.group(0)!.replaceFirst(RegExp(r'[.,;!?]+$'), ''));
  return tokens.any(isStrictHttpUriV2)
      ? Rag2ExtractionOutcomeStatus.unsupportedRelation
      : Rag2ExtractionOutcomeStatus.unsupportedSyntax;
}

bool _sameTypedFact(
  Rag2TypedEvidenceFact actual,
  Rag2TypedEvidenceFact expected,
) =>
    actual.atom.subject == expected.atom.subject &&
    actual.atom.relation == expected.atom.relation &&
    actual.atom.value == expected.atom.value &&
    actual.atom.scope == expected.atom.scope &&
    actual.atom.polarity == expected.atom.polarity &&
    actual.atom.modality == expected.atom.modality &&
    actual.source.objectId == expected.source.objectId &&
    actual.source.startLine == expected.source.startLine &&
    actual.source.endLine == expected.source.endLine;

String _outcomeReason(Rag2ExtractionOutcomeStatus status) => switch (status) {
  Rag2ExtractionOutcomeStatus.extracted => 'exact_typed_fact_extracted',
  Rag2ExtractionOutcomeStatus.unsupportedSyntax =>
    'outside_frozen_v2_syntax_boundary',
  Rag2ExtractionOutcomeStatus.unsupportedRelation =>
    'outside_frozen_v1_relation_binder',
  Rag2ExtractionOutcomeStatus.unsupportedProse =>
    'prose_extraction_not_implemented',
};

enum Rag2ExtractionOutcomeStatus {
  extracted('extracted'),
  unsupportedSyntax('unsupported_syntax'),
  unsupportedRelation('unsupported_relation'),
  unsupportedProse('unsupported_prose');

  const Rag2ExtractionOutcomeStatus(this.wireName);

  final String wireName;
}

final class Rag2ExtractionOutcome {
  const Rag2ExtractionOutcome({
    required this.outcomeId,
    required this.oracleFactId,
    required this.sourceFamily,
    required this.source,
    required this.status,
    required this.extractedFactIds,
    required this.reason,
  });

  final String outcomeId;
  final String oracleFactId;
  final Rag2ExtractionSourceFamily sourceFamily;
  final Rag2FactSource source;
  final Rag2ExtractionOutcomeStatus status;
  final List<String> extractedFactIds;
  final String reason;

  Map<String, Object?> toJson() => {
    'outcomeId': outcomeId,
    'oracleFactId': oracleFactId,
    'sourceFamily': sourceFamily.name,
    'status': status.wireName,
    'reason': reason,
    'source': {
      'objectId': source.objectId,
      'startLine': source.startLine,
      'endLine': source.endLine,
    },
    'extractedFactIds': extractedFactIds,
  };
}

final class Rag2ExtractionOutcomeScore {
  const Rag2ExtractionOutcomeScore({
    required this.spanCount,
    required this.extractedCount,
    required this.falsePositiveCount,
    required this.statusCounts,
  });

  final int spanCount;
  final int extractedCount;
  final int falsePositiveCount;
  final Map<Rag2ExtractionOutcomeStatus, int> statusCounts;

  double get availabilityRate =>
      spanCount == 0 ? 0 : extractedCount / spanCount;
  double get unavailableRate => spanCount == 0 ? 0 : 1 - availabilityRate;
  double get falseExtractionRate => extractedCount + falsePositiveCount == 0
      ? 0
      : falsePositiveCount / (extractedCount + falsePositiveCount);

  Map<String, Object?> toJson() => {
    'spanCount': spanCount,
    'extractedCount': extractedCount,
    'falsePositiveCount': falsePositiveCount,
    'availabilityRate': availabilityRate,
    'unavailableRate': unavailableRate,
    'falseExtractionRate': falseExtractionRate,
    'statusCounts': {
      for (final status in Rag2ExtractionOutcomeStatus.values)
        status.wireName: statusCounts[status] ?? 0,
    },
  };
}

final class Rag2ExtractionOutcomeDatasetReport {
  const Rag2ExtractionOutcomeDatasetReport({
    required this.datasetId,
    required this.corpusHash,
    required this.outcomes,
    required this.extraction,
  });

  final String datasetId;
  final String corpusHash;
  final List<Rag2ExtractionOutcome> outcomes;
  final Rag2FactExtractionMetrics extraction;

  Map<String, Object?> toJson() => {
    'datasetId': datasetId,
    'corpusHash': corpusHash,
    'extraction': extraction.toJson(),
    'outcomes': outcomes.map((outcome) => outcome.toJson()).toList(),
  };
}

final class Rag2TypedFactExtractionOutcomeReport {
  const Rag2TypedFactExtractionOutcomeReport({required this.datasets});

  final List<Rag2ExtractionOutcomeDatasetReport> datasets;

  List<Rag2ExtractionOutcome> get outcomes => [
    for (final dataset in datasets) ...dataset.outcomes,
  ];

  Rag2ExtractionOutcomeScore get overall => _score(null);

  Map<Rag2ExtractionSourceFamily, Rag2ExtractionOutcomeScore> get byFamily => {
    for (final family in Rag2ExtractionSourceFamily.values)
      family: _score(family),
  };

  bool get accountingPassed {
    final datasetsById = {
      for (final dataset in datasets) dataset.datasetId: dataset,
    };
    if (datasetsById.length != _expectedDatasetHashes.length ||
        !_expectedDatasetHashes.entries.every(
          (entry) => datasetsById[entry.key]?.corpusHash == entry.value,
        ) ||
        outcomes.length != 35 ||
        outcomes.map((outcome) => outcome.outcomeId).toSet().length !=
            outcomes.length) {
      return false;
    }
    for (final entry in _expectedDatasetTruePositives.entries) {
      final score = datasetsById[entry.key]!.extraction.overall;
      if (score.truePositiveCount != entry.value ||
          score.extractedCount != entry.value) {
        return false;
      }
    }
    final familyScores = byFamily;
    return overall.spanCount == 35 &&
        overall.extractedCount == 19 &&
        overall.falseExtractionRate == 0 &&
        _hasStatusCounts(overall.statusCounts, const {
          Rag2ExtractionOutcomeStatus.extracted: 19,
          Rag2ExtractionOutcomeStatus.unsupportedSyntax: 1,
          Rag2ExtractionOutcomeStatus.unsupportedRelation: 3,
          Rag2ExtractionOutcomeStatus.unsupportedProse: 12,
        }) &&
        familyScores[Rag2ExtractionSourceFamily.dartAssignment]!.spanCount ==
            11 &&
        familyScores[Rag2ExtractionSourceFamily.dartAssignment]!
                .extractedCount ==
            10 &&
        familyScores[Rag2ExtractionSourceFamily.markdownUri]!.spanCount == 12 &&
        familyScores[Rag2ExtractionSourceFamily.markdownUri]!.extractedCount ==
            9 &&
        familyScores[Rag2ExtractionSourceFamily.proseState]!.spanCount == 12 &&
        familyScores[Rag2ExtractionSourceFamily.proseState]!.extractedCount ==
            0;
  }

  Rag2ExtractionOutcomeScore _score(Rag2ExtractionSourceFamily? family) {
    final selected = family == null
        ? outcomes
        : outcomes.where((outcome) => outcome.sourceFamily == family).toList();
    var extractedCount = 0;
    var falsePositiveCount = 0;
    final statusCounts = <Rag2ExtractionOutcomeStatus, int>{};
    for (final outcome in selected) {
      statusCounts.update(
        outcome.status,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (outcome.status == Rag2ExtractionOutcomeStatus.extracted) {
        extractedCount++;
      }
    }
    for (final dataset in datasets) {
      final score = family == null
          ? dataset.extraction.overall
          : dataset.extraction.byFamily[family]!;
      falsePositiveCount += score.extractedCount - score.truePositiveCount;
    }
    return Rag2ExtractionOutcomeScore(
      spanCount: selected.length,
      extractedCount: extractedCount,
      falsePositiveCount: falsePositiveCount,
      statusCounts: statusCounts,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaName': rag2TypedFactExtractionOutcomeSchema,
    'schemaVersion': rag2TypedFactExtractionOutcomeSchemaVersion,
    'contractVersion': rag2TypedFactExtractionOutcomeContract,
    'extractorVersion': rag2TypedFactExtractionV2Policy,
    'accountingDecision': accountingPassed ? 'go' : 'no_go',
    'runtimeAvailabilityDecision': 'not_evaluated',
    'contractDecision': 'no_go',
    'extractionDecision': 'no_go',
    'productionDecision': 'no_go',
    'overall': overall.toJson(),
    'bySourceFamily': {
      for (final entry in byFamily.entries)
        entry.key.name: entry.value.toJson(),
    },
    'datasets': datasets.map((dataset) => dataset.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Typed Fact Extraction Outcomes')
      ..writeln()
      ..writeln('- Contract: `$rag2TypedFactExtractionOutcomeContract`')
      ..writeln('- Extractor: `$rag2TypedFactExtractionV2Policy`')
      ..writeln('- Accounting decision: `${accountingPassed ? 'go' : 'no_go'}`')
      ..writeln('- Runtime availability decision: `not_evaluated`')
      ..writeln('- Contract decision: `no_go`')
      ..writeln('- Extraction decision: `no_go`')
      ..writeln('- Production decision: `no_go`')
      ..writeln()
      ..writeln(
        '| Family | Spans | Extracted | Availability | Unavailable | '
        'False extraction |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |');
    for (final family in Rag2ExtractionSourceFamily.values) {
      final score = byFamily[family]!;
      buffer.writeln(
        '| ${family.name} | ${score.spanCount} | ${score.extractedCount} | '
        '${score.availabilityRate.toStringAsFixed(3)} | '
        '${score.unavailableRate.toStringAsFixed(3)} | '
        '${score.falseExtractionRate.toStringAsFixed(3)} |',
      );
    }
    final score = overall;
    buffer
      ..writeln(
        '| overall | ${score.spanCount} | ${score.extractedCount} | '
        '${score.availabilityRate.toStringAsFixed(3)} | '
        '${score.unavailableRate.toStringAsFixed(3)} | '
        '${score.falseExtractionRate.toStringAsFixed(3)} |',
      )
      ..writeln()
      ..writeln('## Outcome counts')
      ..writeln();
    for (final status in Rag2ExtractionOutcomeStatus.values) {
      buffer.writeln(
        '- `${status.wireName}`: ${score.statusCounts[status] ?? 0}',
      );
    }
    return buffer.toString();
  }
}

bool _hasStatusCounts(
  Map<Rag2ExtractionOutcomeStatus, int> actual,
  Map<Rag2ExtractionOutcomeStatus, int> expected,
) => Rag2ExtractionOutcomeStatus.values.every(
  (status) => (actual[status] ?? 0) == (expected[status] ?? 0),
);

enum Rag2AvailabilityAwareVerdict {
  supported,
  contradicted,
  absent,
  notAvailable,
}

final class Rag2AvailabilityAwareDecision {
  const Rag2AvailabilityAwareDecision({
    required this.verdict,
    required this.reason,
    required this.blockingOutcomeIds,
  });

  final Rag2AvailabilityAwareVerdict verdict;
  final String reason;
  final List<String> blockingOutcomeIds;
}

final class Rag2ExtractionCoverage {
  const Rag2ExtractionCoverage({
    required this.objectId,
    required this.relation,
    required this.complete,
  });

  final String objectId;
  final String relation;
  final bool complete;
}

Rag2AvailabilityAwareDecision applyRag2ExtractionAvailability({
  required Rag2TypedClaimAtom claim,
  required Rag2ClaimEnvelope envelope,
  required Rag2TypedFactDecision typedDecision,
  required List<Rag2ExtractionOutcome> outcomes,
  required List<Rag2ExtractionCoverage> coverage,
}) {
  if (typedDecision.verdict != Rag2ClaimVerdict.absent) {
    return Rag2AvailabilityAwareDecision(
      verdict: Rag2AvailabilityAwareVerdict.values.byName(
        typedDecision.verdict.name,
      ),
      reason: typedDecision.reason,
      blockingOutcomeIds: const [],
    );
  }
  final family = _claimSourceFamily(claim);
  final blockers = outcomes
      .where(
        (outcome) =>
            family != null &&
            outcome.sourceFamily == family &&
            envelope.citedSourceIds.contains(outcome.source.objectId) &&
            outcome.status != Rag2ExtractionOutcomeStatus.extracted,
      )
      .map((outcome) => outcome.outcomeId)
      .toList();
  final coverageComplete =
      envelope.citedSourceIds.isNotEmpty &&
      envelope.citedSourceIds.every(
        (objectId) => coverage.any(
          (item) =>
              item.objectId == objectId &&
              item.relation == claim.atom.relation &&
              item.complete,
        ),
      );
  if (blockers.isNotEmpty || !coverageComplete) {
    return Rag2AvailabilityAwareDecision(
      verdict: Rag2AvailabilityAwareVerdict.notAvailable,
      reason: blockers.isNotEmpty
          ? 'extractor_unavailable_for_cited_source'
          : 'extractor_coverage_not_proven',
      blockingOutcomeIds: blockers,
    );
  }
  return const Rag2AvailabilityAwareDecision(
    verdict: Rag2AvailabilityAwareVerdict.absent,
    reason: 'no_asserted_typed_fact_after_available_extraction',
    blockingOutcomeIds: [],
  );
}

Rag2ExtractionSourceFamily? _claimSourceFamily(Rag2TypedClaimAtom claim) {
  if (claim.atom.relation.startsWith('config.')) {
    return Rag2ExtractionSourceFamily.dartAssignment;
  }
  if (claim.atom.relation == 'network.port') {
    return Rag2ExtractionSourceFamily.markdownUri;
  }
  if (claim.atom.relation == 'feature.enabled') {
    return Rag2ExtractionSourceFamily.proseState;
  }
  return null;
}

final class Rag2TypedFactExtractionOutcomeOptions {
  const Rag2TypedFactExtractionOutcomeOptions({
    required this.developmentFixturePath,
    required this.developmentOracleFactsPath,
    required this.holdoutFixturePath,
    required this.holdoutOracleFactsPath,
    required this.precisionFixturePath,
    required this.precisionOracleFactsPath,
    required this.outDir,
  });

  final String developmentFixturePath;
  final String developmentOracleFactsPath;
  final String holdoutFixturePath;
  final String holdoutOracleFactsPath;
  final String precisionFixturePath;
  final String precisionOracleFactsPath;
  final String outDir;

  static Rag2TypedFactExtractionOutcomeOptions? parse(List<String> args) {
    String? value(String name) {
      final index = args.indexOf(name);
      if (index < 0 || index + 1 >= args.length) return null;
      return args[index + 1];
    }

    final developmentFixture = value('--development-fixture');
    final developmentOracle = value('--development-oracle-facts');
    final holdoutFixture = value('--holdout-fixture');
    final holdoutOracle = value('--holdout-oracle-facts');
    final precisionFixture = value('--precision-fixture');
    final precisionOracle = value('--precision-oracle-facts');
    final outDir = value('--out-dir');
    if (developmentFixture == null ||
        developmentOracle == null ||
        holdoutFixture == null ||
        holdoutOracle == null ||
        precisionFixture == null ||
        precisionOracle == null ||
        outDir == null) {
      return null;
    }
    return Rag2TypedFactExtractionOutcomeOptions(
      developmentFixturePath: developmentFixture,
      developmentOracleFactsPath: developmentOracle,
      holdoutFixturePath: holdoutFixture,
      holdoutOracleFactsPath: holdoutOracle,
      precisionFixturePath: precisionFixture,
      precisionOracleFactsPath: precisionOracle,
      outDir: outDir,
    );
  }
}

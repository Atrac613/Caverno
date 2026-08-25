import 'dart:convert';
import 'dart:io';

import 'rag2_evidence_sufficiency_eval.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2ClaimSupportSchema = 'caverno_rag2_claim_support_eval';
const rag2ClaimSupportSchemaVersion = 1;

const rag2FrozenSufficiencyPolicy = Rag2SufficiencyPolicy(
  minimumCoverage: 0.25,
  minimumSegmentCoverage: 0.25,
  minimumBm25Margin: 0.10,
);

Future<void> main(List<String> args) async {
  final options = Rag2ClaimSupportOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_claim_support_eval.dart '
      '--seed-fixture PATH --holdout-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2ClaimSupportEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 claim-support evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2ClaimSupportReport> runRag2ClaimSupportEval(
  Rag2ClaimSupportOptions options,
) async {
  final seed = await _evaluateFixture(options.seedFixturePath);
  final holdout = await _evaluateFixture(options.holdoutFixturePath);
  final report = Rag2ClaimSupportReport(seed: seed, holdout: holdout);
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_claim_support_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_claim_support_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2ClaimSupportDataset> _evaluateFixture(String fixturePath) async {
  final fixture = await RagRetrievalFixture.load(File(fixturePath));
  fixture.validate();
  final corpusHash = await fixture.computeCorpusHash();
  if (corpusHash != fixture.corpusHash) {
    throw StateError(
      'Fixture ${fixture.fixtureId} corpus hash mismatch: $corpusHash.',
    );
  }
  final documents = await loadRagFixtureDocuments(fixture);
  final scorer = Rag2LexicalScorer(
    policy: Rag2LexicalPolicy.trigram,
    documents: documents,
  );
  try {
    return evaluateRag2ClaimSupportDataset(
      fixture: fixture,
      corpusHash: corpusHash,
      rankedCases: [
        for (final fixtureCase in fixture.cases)
          scorer.rank(fixtureCase.query, limit: documents.length),
      ],
    );
  } finally {
    scorer.close();
  }
}

Rag2ClaimSupportDataset evaluateRag2ClaimSupportDataset({
  required RagRetrievalFixture fixture,
  required String corpusHash,
  required List<List<Rag2LexicalHit>> rankedCases,
}) {
  final cases = <Rag2ClaimSupportCase>[];
  for (var index = 0; index < fixture.cases.length; index++) {
    final fixtureCase = fixture.cases[index];
    final hits = applyRag2FrozenSufficiencyPolicy(
      rankedCases[index],
      metricK: fixture.metricK,
    );
    final returnedObjects = hits.map((hit) => hit.objectId).toSet();
    final returnedChunks = hits.map((hit) => hit.chunkId).toSet();
    final expectedCitations = fixtureCase.citations.toSet();
    final coveredCitations = expectedCitations.intersection(returnedChunks);
    final answerable = fixtureCase.objectRelevance.isNotEmpty;
    final support = !answerable
        ? Rag2ClaimSupportVerdict.notApplicable
        : coveredCitations.length == expectedCitations.length
        ? Rag2ClaimSupportVerdict.supported
        : coveredCitations.isNotEmpty
        ? Rag2ClaimSupportVerdict.partial
        : Rag2ClaimSupportVerdict.absent;
    cases.add(
      Rag2ClaimSupportCase(
        caseId: fixtureCase.id,
        authority: fixtureCase.authority,
        retrieved: hits.isNotEmpty,
        retrievalRelevant: returnedObjects.any(
          fixtureCase.objectRelevance.containsKey,
        ),
        support: support,
        expectedClaimCount: fixtureCase.answerFacts.length,
        expectedCitations: fixtureCase.citations,
        coveredCitations: coveredCitations.toList()..sort(),
        returnedObjects: returnedObjects.toList()..sort(),
      ),
    );
  }
  return Rag2ClaimSupportDataset(
    fixtureId: fixture.fixtureId,
    corpusHash: corpusHash,
    cases: cases,
  );
}

List<Rag2LexicalHit> applyRag2FrozenSufficiencyPolicy(
  List<Rag2LexicalHit> rankedHits, {
  required int metricK,
}) {
  final thresholdHits = rankedHits
      .where(
        (hit) =>
            hit.score >= rag2FrozenSufficiencyPolicy.minimumCoverage &&
            hit.segmentScore >=
                rag2FrozenSufficiencyPolicy.minimumSegmentCoverage,
      )
      .take(metricK)
      .toList();
  return rag2Bm25Margin(thresholdHits) >=
          rag2FrozenSufficiencyPolicy.minimumBm25Margin
      ? thresholdHits
      : const <Rag2LexicalHit>[];
}

enum Rag2ClaimSupportVerdict { supported, partial, absent, notApplicable }

final class Rag2ClaimSupportCase {
  const Rag2ClaimSupportCase({
    required this.caseId,
    required this.authority,
    required this.retrieved,
    required this.retrievalRelevant,
    required this.support,
    required this.expectedClaimCount,
    required this.expectedCitations,
    required this.coveredCitations,
    required this.returnedObjects,
  });

  final String caseId;
  final String authority;
  final bool retrieved;
  final bool retrievalRelevant;
  final Rag2ClaimSupportVerdict support;
  final int expectedClaimCount;
  final List<String> expectedCitations;
  final List<String> coveredCitations;
  final List<String> returnedObjects;

  bool get topicalButInsufficient =>
      authority == 'none' &&
      retrieved &&
      support == Rag2ClaimSupportVerdict.notApplicable;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'authority': authority,
    'retrieved': retrieved,
    'retrievalRelevant': retrievalRelevant,
    'claimSupport': support.name,
    'expectedClaimCount': expectedClaimCount,
    'expectedCitations': expectedCitations,
    'coveredCitations': coveredCitations,
    'returnedObjects': returnedObjects,
    'topicalButInsufficient': topicalButInsufficient,
  };
}

final class Rag2ClaimSupportDataset {
  const Rag2ClaimSupportDataset({
    required this.fixtureId,
    required this.corpusHash,
    required this.cases,
  });

  final String fixtureId;
  final String corpusHash;
  final List<Rag2ClaimSupportCase> cases;

  int get answerableCases =>
      cases.where((item) => item.authority != 'none').length;
  int get retrievalRelevantCases =>
      cases.where((item) => item.retrievalRelevant).length;
  int get fullySupportedCases => cases
      .where((item) => item.support == Rag2ClaimSupportVerdict.supported)
      .length;
  int get partialSupportCases => cases
      .where((item) => item.support == Rag2ClaimSupportVerdict.partial)
      .length;
  int get absentSupportCases => cases
      .where((item) => item.support == Rag2ClaimSupportVerdict.absent)
      .length;
  int get noAnswerCases =>
      cases.where((item) => item.authority == 'none').length;
  int get topicalButInsufficientCases =>
      cases.where((item) => item.topicalButInsufficient).length;

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'answerableCases': answerableCases,
    'retrievalRelevantCases': retrievalRelevantCases,
    'fullySupportedCases': fullySupportedCases,
    'partialSupportCases': partialSupportCases,
    'absentSupportCases': absentSupportCases,
    'noAnswerCases': noAnswerCases,
    'topicalButInsufficientCases': topicalButInsufficientCases,
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag2ClaimSupportReport {
  const Rag2ClaimSupportReport({required this.seed, required this.holdout});

  final Rag2ClaimSupportDataset seed;
  final Rag2ClaimSupportDataset holdout;

  Map<String, Object?> toJson() => {
    'schemaName': rag2ClaimSupportSchema,
    'schemaVersion': rag2ClaimSupportSchemaVersion,
    'result': 'diagnostic_complete',
    'productionDecision': 'no_go',
    'evaluationMode': 'oracle_citation_coverage_only',
    'runtimeEligible': false,
    'retrievalPolicy': rag2FrozenSufficiencyPolicy.toJson(),
    'seed': seed.toJson(),
    'holdout': holdout.toJson(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Claim-Support Evaluation')
      ..writeln()
      ..writeln('- Result: `diagnostic_complete`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Evaluation mode: `oracle_citation_coverage_only`')
      ..writeln('- Runtime eligible: `false`')
      ..writeln()
      ..writeln(
        '| Dataset | Retrieval relevant | Fully supported | Partial | Absent | Topical but insufficient |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |')
      ..writeln(_row(seed))
      ..writeln(_row(holdout))
      ..writeln()
      ..writeln('## Holdout support gaps')
      ..writeln()
      ..writeln(
        '| Case | Authority | Retrieval relevant | Claim support | Returned objects |',
      )
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final item in holdout.cases.where(
      (item) =>
          (item.support != Rag2ClaimSupportVerdict.supported &&
              item.support != Rag2ClaimSupportVerdict.notApplicable) ||
          item.topicalButInsufficient,
    )) {
      buffer.writeln(
        '| ${item.caseId} | ${item.authority} | ${item.retrievalRelevant} | '
        '${item.support.name} | ${item.returnedObjects.join(', ')} |',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'This instrument uses fixture answer keys and citation qrels. It measures whether retrieved evidence covers expected claims, but it cannot make a runtime answerability decision because the oracle is unavailable in production.',
      );
    return buffer.toString();
  }

  String _row(Rag2ClaimSupportDataset dataset) =>
      '| ${dataset.fixtureId} | ${dataset.retrievalRelevantCases}/${dataset.answerableCases} | '
      '${dataset.fullySupportedCases}/${dataset.answerableCases} | '
      '${dataset.partialSupportCases} | ${dataset.absentSupportCases} | '
      '${dataset.topicalButInsufficientCases}/${dataset.noAnswerCases} |';
}

final class Rag2ClaimSupportOptions {
  const Rag2ClaimSupportOptions({
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.outDir,
  });

  final String seedFixturePath;
  final String holdoutFixturePath;
  final String outDir;

  static Rag2ClaimSupportOptions? parse(List<String> args) {
    if (args.length != 6) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final seed = values['--seed-fixture'];
    final holdout = values['--holdout-fixture'];
    final outDir = values['--out-dir'];
    if (seed == null ||
        holdout == null ||
        outDir == null ||
        values.length != 3) {
      return null;
    }
    return Rag2ClaimSupportOptions(
      seedFixturePath: seed,
      holdoutFixturePath: holdout,
      outDir: outDir,
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'rag2_lexical_policy_bakeoff.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2EvidenceSufficiencySchema = 'caverno_rag2_evidence_sufficiency_eval';
const rag2EvidenceSufficiencySchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2EvidenceSufficiencyOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_evidence_sufficiency_eval.dart '
      '--seed-fixture PATH --holdout-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2EvidenceSufficiency(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 evidence sufficiency evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2EvidenceSufficiencyReport> runRag2EvidenceSufficiency(
  Rag2EvidenceSufficiencyOptions options,
) async {
  final seed = await _loadCorpus(options.seedFixturePath);
  final holdout = await _loadCorpus(options.holdoutFixturePath);
  final candidates = <Rag2SufficiencyResult>[];
  for (final coverage in const [0.10, 0.15, 0.20, 0.25]) {
    for (final segment in const [0.15, 0.25, 0.35, 0.45, 0.55]) {
      for (final margin in const [0.0, 0.05, 0.10, 0.20, 0.30]) {
        candidates.add(
          evaluateRag2Sufficiency(
            corpus: seed,
            policy: Rag2SufficiencyPolicy(
              minimumCoverage: coverage,
              minimumSegmentCoverage: segment,
              minimumBm25Margin: margin,
            ),
          ),
        );
      }
    }
  }
  candidates.sort(compareRag2SufficiencyResults);
  final winner = candidates.first;
  final holdoutResult = evaluateRag2Sufficiency(
    corpus: holdout,
    policy: winner.policy,
  );
  final report = Rag2EvidenceSufficiencyReport(
    seedFixtureId: seed.fixture.fixtureId,
    seedCorpusHash: await seed.fixture.computeCorpusHash(),
    holdoutFixtureId: holdout.fixture.fixtureId,
    holdoutCorpusHash: await holdout.fixture.computeCorpusHash(),
    seedWinner: winner,
    holdoutResult: holdoutResult,
    candidates: candidates,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_evidence_sufficiency_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_evidence_sufficiency_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2SufficiencyCorpus> _loadCorpus(String fixturePath) async {
  final fixture = await RagRetrievalFixture.load(File(fixturePath));
  fixture.validate();
  final actualHash = await fixture.computeCorpusHash();
  if (actualHash != fixture.corpusHash) {
    throw StateError(
      'Fixture ${fixture.fixtureId} corpus hash mismatch: $actualHash.',
    );
  }
  final documents = await loadRagFixtureDocuments(fixture);
  final scorer = Rag2LexicalScorer(
    policy: Rag2LexicalPolicy.trigram,
    documents: documents,
  );
  try {
    return Rag2SufficiencyCorpus(
      fixture: fixture,
      rankedCases: [
        for (final fixtureCase in fixture.cases)
          scorer.rank(fixtureCase.query, limit: documents.length),
      ],
    );
  } finally {
    scorer.close();
  }
}

Rag2SufficiencyResult evaluateRag2Sufficiency({
  required Rag2SufficiencyCorpus corpus,
  required Rag2SufficiencyPolicy policy,
}) {
  var answerableHits = 0;
  var noAnswerRetrieved = 0;
  var reciprocalRankTotal = 0.0;
  final cases = <Rag2SufficiencyCaseResult>[];
  for (var index = 0; index < corpus.fixture.cases.length; index++) {
    final fixtureCase = corpus.fixture.cases[index];
    final thresholdHits = corpus.rankedCases[index]
        .where(
          (hit) =>
              hit.score >= policy.minimumCoverage &&
              hit.segmentScore >= policy.minimumSegmentCoverage,
        )
        .take(corpus.fixture.metricK)
        .toList();
    final margin = rag2Bm25Margin(thresholdHits);
    final hits = margin >= policy.minimumBm25Margin
        ? thresholdHits
        : const <Rag2LexicalHit>[];
    final relevantRank = hits.indexWhere(
      (hit) => fixtureCase.objectRelevance.containsKey(hit.objectId),
    );
    final answerable = fixtureCase.objectRelevance.isNotEmpty;
    if (answerable && relevantRank >= 0) {
      answerableHits++;
      reciprocalRankTotal += 1 / (relevantRank + 1);
    }
    if (!answerable && hits.isNotEmpty) noAnswerRetrieved++;
    cases.add(
      Rag2SufficiencyCaseResult(
        caseId: fixtureCase.id,
        authority: fixtureCase.authority,
        retrieved: hits.isNotEmpty,
        relevantRank: relevantRank < 0 ? null : relevantRank + 1,
        topCoverage: thresholdHits.isEmpty ? null : thresholdHits.first.score,
        topSegmentCoverage: thresholdHits.isEmpty
            ? null
            : thresholdHits.first.segmentScore,
        bm25Margin: margin,
      ),
    );
  }
  final answerableCases = corpus.fixture.cases
      .where((item) => item.objectRelevance.isNotEmpty)
      .length;
  final noAnswerCases = corpus.fixture.cases.length - answerableCases;
  return Rag2SufficiencyResult(
    fixtureId: corpus.fixture.fixtureId,
    policy: policy,
    answerableHits: answerableHits,
    answerableCases: answerableCases,
    noAnswerRetrieved: noAnswerRetrieved,
    noAnswerCases: noAnswerCases,
    mrr: answerableCases == 0 ? 0 : reciprocalRankTotal / answerableCases,
    cases: cases,
  );
}

double rag2Bm25Margin(List<Rag2LexicalHit> hits) {
  if (hits.isEmpty) return 0;
  if (hits.length == 1) return 1;
  final best = hits.first.bm25Relevance;
  if (best <= 0) return 0;
  return ((best - hits[1].bm25Relevance) / best).clamp(0, 1);
}

int compareRag2SufficiencyResults(
  Rag2SufficiencyResult left,
  Rag2SufficiencyResult right,
) {
  final gate = (right.meetsGate ? 1 : 0).compareTo(left.meetsGate ? 1 : 0);
  if (gate != 0) return gate;
  final hits = right.answerableHits.compareTo(left.answerableHits);
  if (hits != 0) return hits;
  final falsePositives = left.noAnswerRetrieved.compareTo(
    right.noAnswerRetrieved,
  );
  if (falsePositives != 0) return falsePositives;
  final mrr = right.mrr.compareTo(left.mrr);
  if (mrr != 0) return mrr;
  final coverage = right.policy.minimumCoverage.compareTo(
    left.policy.minimumCoverage,
  );
  if (coverage != 0) return coverage;
  final segment = right.policy.minimumSegmentCoverage.compareTo(
    left.policy.minimumSegmentCoverage,
  );
  return segment != 0
      ? segment
      : right.policy.minimumBm25Margin.compareTo(left.policy.minimumBm25Margin);
}

final class Rag2SufficiencyCorpus {
  const Rag2SufficiencyCorpus({
    required this.fixture,
    required this.rankedCases,
  });

  final RagRetrievalFixture fixture;
  final List<List<Rag2LexicalHit>> rankedCases;
}

final class Rag2SufficiencyPolicy {
  const Rag2SufficiencyPolicy({
    required this.minimumCoverage,
    required this.minimumSegmentCoverage,
    required this.minimumBm25Margin,
  });

  final double minimumCoverage;
  final double minimumSegmentCoverage;
  final double minimumBm25Margin;

  Map<String, Object?> toJson() => {
    'tokenPolicy': Rag2LexicalPolicy.trigram.id,
    'minimumCoverage': minimumCoverage,
    'minimumSegmentCoverage': minimumSegmentCoverage,
    'minimumBm25Margin': minimumBm25Margin,
  };
}

final class Rag2SufficiencyResult {
  const Rag2SufficiencyResult({
    required this.fixtureId,
    required this.policy,
    required this.answerableHits,
    required this.answerableCases,
    required this.noAnswerRetrieved,
    required this.noAnswerCases,
    required this.mrr,
    required this.cases,
  });

  final String fixtureId;
  final Rag2SufficiencyPolicy policy;
  final int answerableHits;
  final int answerableCases;
  final int noAnswerRetrieved;
  final int noAnswerCases;
  final double mrr;
  final List<Rag2SufficiencyCaseResult> cases;

  bool get meetsGate =>
      answerableHits >= answerableCases - 1 && noAnswerRetrieved <= 1;

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'policy': policy.toJson(),
    'answerableHits': answerableHits,
    'answerableCases': answerableCases,
    'noAnswerRetrieved': noAnswerRetrieved,
    'noAnswerCases': noAnswerCases,
    'mrrAt5': mrr,
    'meetsGate': meetsGate,
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag2SufficiencyCaseResult {
  const Rag2SufficiencyCaseResult({
    required this.caseId,
    required this.authority,
    required this.retrieved,
    required this.relevantRank,
    required this.topCoverage,
    required this.topSegmentCoverage,
    required this.bm25Margin,
  });

  final String caseId;
  final String authority;
  final bool retrieved;
  final int? relevantRank;
  final double? topCoverage;
  final double? topSegmentCoverage;
  final double bm25Margin;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'authority': authority,
    'retrieved': retrieved,
    'relevantRank': relevantRank,
    'topCoverage': topCoverage,
    'topSegmentCoverage': topSegmentCoverage,
    'bm25Margin': bm25Margin,
  };
}

final class Rag2EvidenceSufficiencyReport {
  const Rag2EvidenceSufficiencyReport({
    required this.seedFixtureId,
    required this.seedCorpusHash,
    required this.holdoutFixtureId,
    required this.holdoutCorpusHash,
    required this.seedWinner,
    required this.holdoutResult,
    required this.candidates,
  });

  final String seedFixtureId;
  final String seedCorpusHash;
  final String holdoutFixtureId;
  final String holdoutCorpusHash;
  final Rag2SufficiencyResult seedWinner;
  final Rag2SufficiencyResult holdoutResult;
  final List<Rag2SufficiencyResult> candidates;

  bool get passed => seedWinner.meetsGate && holdoutResult.meetsGate;

  Map<String, Object?> toJson() => {
    'schemaName': rag2EvidenceSufficiencySchema,
    'schemaVersion': rag2EvidenceSufficiencySchemaVersion,
    'result': passed ? 'go' : 'no_go',
    'selectionPolicy': 'seed_only_gate_then_hits_then_false_positives_v1',
    'seedFixtureId': seedFixtureId,
    'seedCorpusHash': seedCorpusHash,
    'holdoutFixtureId': holdoutFixtureId,
    'holdoutCorpusHash': holdoutCorpusHash,
    'seedWinner': seedWinner.toJson(),
    'holdoutResult': holdoutResult.toJson(),
    'seedCandidates': [for (final item in candidates) item.toJson()],
  };

  String toMarkdown() {
    final policy = seedWinner.policy;
    final buffer = StringBuffer()
      ..writeln('# RAG2 Evidence Sufficiency Evaluation')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln(
        '- Policy selected on seed only: coverage '
        '`${policy.minimumCoverage.toStringAsFixed(2)}`, segment '
        '`${policy.minimumSegmentCoverage.toStringAsFixed(2)}`, BM25 margin '
        '`${policy.minimumBm25Margin.toStringAsFixed(2)}`',
      )
      ..writeln()
      ..writeln(
        '| Dataset | Answerable hits | No-answer retrieved | MRR@5 | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | --- |')
      ..writeln(_row(seedWinner))
      ..writeln(_row(holdoutResult))
      ..writeln()
      ..writeln('## Holdout failures')
      ..writeln()
      ..writeln(
        '| Case | Authority | Retrieved | Relevant rank | Coverage | Segment | BM25 margin |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | ---: | ---: |');
    for (final item in holdoutResult.cases.where(
      (item) =>
          (item.authority == 'none' && item.retrieved) ||
          (item.authority != 'none' && item.relevantRank == null),
    )) {
      buffer.writeln(
        '| ${item.caseId} | ${item.authority} | ${item.retrieved} | '
        '${item.relevantRank ?? 'none'} | '
        '${item.topCoverage?.toStringAsFixed(3) ?? 'none'} | '
        '${item.topSegmentCoverage?.toStringAsFixed(3) ?? 'none'} | '
        '${item.bm25Margin.toStringAsFixed(3)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'The holdout is never used for policy selection. This remains an offline entry gate and does not modify production retrieval.',
      );
    return buffer.toString();
  }

  String _row(Rag2SufficiencyResult result) =>
      '| ${result.fixtureId} | ${result.answerableHits}/${result.answerableCases} | '
      '${result.noAnswerRetrieved}/${result.noAnswerCases} | '
      '${result.mrr.toStringAsFixed(3)} | '
      '${result.meetsGate ? 'pass' : 'fail'} |';
}

final class Rag2EvidenceSufficiencyOptions {
  const Rag2EvidenceSufficiencyOptions({
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.outDir,
  });

  final String seedFixturePath;
  final String holdoutFixturePath;
  final String outDir;

  static Rag2EvidenceSufficiencyOptions? parse(List<String> args) {
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
    return Rag2EvidenceSufficiencyOptions(
      seedFixturePath: seed,
      holdoutFixturePath: holdout,
      outDir: outDir,
    );
  }
}

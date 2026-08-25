import 'dart:convert';
import 'dart:io';

import 'rag2_claim_support_eval.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2PostAnswerClaimSchema = 'caverno_rag2_post_answer_claim_eval';
const rag2PostAnswerClaimSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2PostAnswerClaimOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_post_answer_claim_eval.dart '
      '--claims PATH --seed-fixture PATH --holdout-fixture PATH '
      '--audit-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2PostAnswerClaimEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 post-answer claim evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2PostAnswerClaimReport> runRag2PostAnswerClaimEval(
  Rag2PostAnswerClaimOptions options,
) async {
  final claimSet = await Rag2ClaimCandidateSet.load(File(options.claimsPath));
  final corpora = <String, Rag2ClaimCorpus>{};
  for (final path in [
    options.seedFixturePath,
    options.holdoutFixturePath,
    options.auditFixturePath,
  ]) {
    final corpus = await _loadClaimCorpus(path, claimSet);
    corpora[corpus.fixture.fixtureId] = corpus;
  }
  claimSet.validate(corpora);
  final seedId = corpora.values
      .firstWhere(
        (item) => item.fixture.sourceFile.path == options.seedFixturePath,
      )
      .fixture
      .fixtureId;
  final candidates = <Rag2ClaimVerificationResult>[];
  for (final supportThreshold in const [0.70, 0.80, 0.90]) {
    for (final contradictionThreshold in const [0.35, 0.50, 0.65]) {
      if (contradictionThreshold >= supportThreshold) continue;
      candidates.add(
        evaluateRag2ClaimVerification(
          corpora[seedId]!,
          policy: Rag2ClaimVerifierPolicy(
            supportThreshold: supportThreshold,
            contradictionThreshold: contradictionThreshold,
          ),
        ),
      );
    }
  }
  candidates.sort(compareRag2ClaimVerificationResults);
  final seedWinner = candidates.first;
  final audits = [
    for (final corpus in corpora.values)
      if (corpus.fixture.fixtureId != seedId)
        evaluateRag2ClaimVerification(corpus, policy: seedWinner.policy),
  ];
  final report = Rag2PostAnswerClaimReport(
    candidateSetId: claimSet.candidateSetId,
    seedWinner: seedWinner,
    audits: audits,
    seedCandidates: candidates,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_post_answer_claim_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_post_answer_claim_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2ClaimCorpus> _loadClaimCorpus(
  String fixturePath,
  Rag2ClaimCandidateSet claimSet,
) async {
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
    final evidenceByCase = <String, String>{};
    for (final fixtureCase in fixture.cases) {
      if (!claimSet.claims.any(
        (item) =>
            item.datasetId == fixture.fixtureId &&
            item.caseId == fixtureCase.id,
      )) {
        continue;
      }
      final hits = applyRag2FrozenSufficiencyPolicy(
        scorer.rank(fixtureCase.query, limit: documents.length),
        metricK: fixture.metricK,
      );
      evidenceByCase[fixtureCase.id] = hits
          .map(
            (hit) => documents
                .firstWhere((document) => document.objectId == hit.objectId)
                .content,
          )
          .join('\n');
    }
    return Rag2ClaimCorpus(
      fixture: fixture,
      corpusHash: corpusHash,
      claims: claimSet.claims
          .where((item) => item.datasetId == fixture.fixtureId)
          .toList(),
      evidenceByCase: evidenceByCase,
    );
  } finally {
    scorer.close();
  }
}

Rag2ClaimVerificationResult evaluateRag2ClaimVerification(
  Rag2ClaimCorpus corpus, {
  required Rag2ClaimVerifierPolicy policy,
}) {
  final cases = <Rag2ClaimVerificationCase>[];
  for (final claim in corpus.claims) {
    final evidence = corpus.evidenceByCase[claim.caseId] ?? '';
    final decision = verifyRag2Claim(
      claim: claim.claim,
      evidence: evidence,
      policy: policy,
    );
    cases.add(
      Rag2ClaimVerificationCase(
        candidateId: claim.id,
        expected: claim.expectedVerdict,
        predicted: decision.verdict,
        coverage: decision.coverage,
        skeletonCoverage: decision.skeletonCoverage,
        numericMismatch: decision.numericMismatch,
      ),
    );
  }
  return Rag2ClaimVerificationResult(
    fixtureId: corpus.fixture.fixtureId,
    corpusHash: corpus.corpusHash,
    policy: policy,
    cases: cases,
  );
}

Rag2ClaimVerifierDecision verifyRag2Claim({
  required String claim,
  required String evidence,
  required Rag2ClaimVerifierPolicy policy,
}) {
  if (evidence.trim().isEmpty) {
    return const Rag2ClaimVerifierDecision(
      verdict: Rag2ClaimVerdict.absent,
      coverage: 0,
      skeletonCoverage: 0,
      numericMismatch: false,
    );
  }
  final claimTerms = tokenizeRag2Lexical(claim, Rag2LexicalPolicy.trigram);
  final evidenceTerms = tokenizeRag2Lexical(
    evidence,
    Rag2LexicalPolicy.trigram,
  );
  final coverage = _coverage(claimTerms, evidenceTerms);
  final claimSkeleton = tokenizeRag2Lexical(
    claim.replaceAll(RegExp(r'\d+(?:\.\d+)?'), ' '),
    Rag2LexicalPolicy.trigram,
  );
  final evidenceSkeleton = tokenizeRag2Lexical(
    evidence.replaceAll(RegExp(r'\d+(?:\.\d+)?'), ' '),
    Rag2LexicalPolicy.trigram,
  );
  final skeletonCoverage = _coverage(claimSkeleton, evidenceSkeleton);
  final claimNumbers = _numbers(claim);
  final evidenceNumbers = _numbers(evidence);
  final numericMismatch =
      claimNumbers.isNotEmpty &&
      evidenceNumbers.isNotEmpty &&
      !evidenceNumbers.containsAll(claimNumbers);
  if (numericMismatch && skeletonCoverage >= policy.contradictionThreshold) {
    return Rag2ClaimVerifierDecision(
      verdict: Rag2ClaimVerdict.contradicted,
      coverage: coverage,
      skeletonCoverage: skeletonCoverage,
      numericMismatch: true,
    );
  }
  if (coverage >= policy.supportThreshold) {
    return Rag2ClaimVerifierDecision(
      verdict: Rag2ClaimVerdict.supported,
      coverage: coverage,
      skeletonCoverage: skeletonCoverage,
      numericMismatch: numericMismatch,
    );
  }
  if (coverage >= policy.contradictionThreshold) {
    return Rag2ClaimVerifierDecision(
      verdict: Rag2ClaimVerdict.contradicted,
      coverage: coverage,
      skeletonCoverage: skeletonCoverage,
      numericMismatch: numericMismatch,
    );
  }
  return Rag2ClaimVerifierDecision(
    verdict: Rag2ClaimVerdict.absent,
    coverage: coverage,
    skeletonCoverage: skeletonCoverage,
    numericMismatch: numericMismatch,
  );
}

double _coverage(Set<String> claim, Set<String> evidence) =>
    claim.isEmpty ? 0 : claim.intersection(evidence).length / claim.length;

Set<String> _numbers(String source) => RegExp(
  r'(?<![a-z0-9])\d+(?:\.\d+)?(?![a-z0-9])',
  caseSensitive: false,
).allMatches(source).map((match) => match.group(0)!).toSet();

enum Rag2ClaimVerdict { supported, contradicted, absent }

final class Rag2ClaimVerifierPolicy {
  const Rag2ClaimVerifierPolicy({
    required this.supportThreshold,
    required this.contradictionThreshold,
  });

  final double supportThreshold;
  final double contradictionThreshold;

  Map<String, Object?> toJson() => {
    'supportThreshold': supportThreshold,
    'contradictionThreshold': contradictionThreshold,
    'numericMismatch': true,
  };
}

final class Rag2ClaimVerifierDecision {
  const Rag2ClaimVerifierDecision({
    required this.verdict,
    required this.coverage,
    required this.skeletonCoverage,
    required this.numericMismatch,
  });

  final Rag2ClaimVerdict verdict;
  final double coverage;
  final double skeletonCoverage;
  final bool numericMismatch;
}

final class Rag2ClaimCandidate {
  const Rag2ClaimCandidate({
    required this.id,
    required this.datasetId,
    required this.caseId,
    required this.claim,
    required this.expectedVerdict,
  });

  final String id;
  final String datasetId;
  final String caseId;
  final String claim;
  final Rag2ClaimVerdict expectedVerdict;
}

final class Rag2ClaimCandidateSet {
  const Rag2ClaimCandidateSet({
    required this.candidateSetId,
    required this.datasetHashes,
    required this.claims,
  });

  final String candidateSetId;
  final Map<String, String> datasetHashes;
  final List<Rag2ClaimCandidate> claims;

  static Future<Rag2ClaimCandidateSet> load(File file) async {
    final json = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
    if (json['schemaName'] != 'caverno_rag2_claim_verification_candidates' ||
        json['schemaVersion'] != 1) {
      throw StateError('Unsupported RAG2 claim candidate schema.');
    }
    final datasets = (json['datasets'] as Map).cast<String, Object?>();
    final claimRows = (json['claims'] as List).cast<Map>();
    return Rag2ClaimCandidateSet(
      candidateSetId: json['candidateSetId']! as String,
      datasetHashes: {
        for (final entry in datasets.entries) entry.key: entry.value! as String,
      },
      claims: [
        for (final rowValue in claimRows)
          _claimFromJson(rowValue.cast<String, Object?>()),
      ],
    );
  }

  static Rag2ClaimCandidate _claimFromJson(Map<String, Object?> json) =>
      Rag2ClaimCandidate(
        id: json['id']! as String,
        datasetId: json['datasetId']! as String,
        caseId: json['caseId']! as String,
        claim: json['claim']! as String,
        expectedVerdict: Rag2ClaimVerdict.values.byName(
          json['expectedVerdict']! as String,
        ),
      );

  void validate(Map<String, Rag2ClaimCorpus> corpora) {
    if (claims.map((item) => item.id).toSet().length != claims.length) {
      throw StateError('Claim candidate IDs must be unique.');
    }
    for (final entry in corpora.entries) {
      if (datasetHashes[entry.key] != entry.value.corpusHash) {
        throw StateError('Candidate-set hash mismatch for ${entry.key}.');
      }
      final caseIds = entry.value.fixture.cases.map((item) => item.id).toSet();
      if (entry.value.claims.any((item) => !caseIds.contains(item.caseId))) {
        throw StateError('Candidate set references an unknown fixture case.');
      }
      final verdicts = entry.value.claims
          .map((item) => item.expectedVerdict)
          .toSet();
      if (!verdicts.containsAll(Rag2ClaimVerdict.values)) {
        throw StateError('${entry.key} is missing a claim verdict class.');
      }
    }
  }
}

final class Rag2ClaimCorpus {
  const Rag2ClaimCorpus({
    required this.fixture,
    required this.corpusHash,
    required this.claims,
    required this.evidenceByCase,
  });

  final RagRetrievalFixture fixture;
  final String corpusHash;
  final List<Rag2ClaimCandidate> claims;
  final Map<String, String> evidenceByCase;
}

final class Rag2ClaimVerificationCase {
  const Rag2ClaimVerificationCase({
    required this.candidateId,
    required this.expected,
    required this.predicted,
    required this.coverage,
    required this.skeletonCoverage,
    required this.numericMismatch,
  });

  final String candidateId;
  final Rag2ClaimVerdict expected;
  final Rag2ClaimVerdict predicted;
  final double coverage;
  final double skeletonCoverage;
  final bool numericMismatch;

  bool get correct => expected == predicted;

  Map<String, Object?> toJson() => {
    'candidateId': candidateId,
    'expected': expected.name,
    'predicted': predicted.name,
    'coverage': coverage,
    'skeletonCoverage': skeletonCoverage,
    'numericMismatch': numericMismatch,
    'correct': correct,
  };
}

final class Rag2ClaimClassMetrics {
  const Rag2ClaimClassMetrics({
    required this.truePositive,
    required this.falsePositive,
    required this.falseNegative,
  });

  final int truePositive;
  final int falsePositive;
  final int falseNegative;

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object?> toJson() => {
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

final class Rag2ClaimVerificationResult {
  const Rag2ClaimVerificationResult({
    required this.fixtureId,
    required this.corpusHash,
    required this.policy,
    required this.cases,
  });

  final String fixtureId;
  final String corpusHash;
  final Rag2ClaimVerifierPolicy policy;
  final List<Rag2ClaimVerificationCase> cases;

  Map<Rag2ClaimVerdict, Rag2ClaimClassMetrics> get metrics => {
    for (final verdict in Rag2ClaimVerdict.values)
      verdict: Rag2ClaimClassMetrics(
        truePositive: cases
            .where(
              (item) => item.expected == verdict && item.predicted == verdict,
            )
            .length,
        falsePositive: cases
            .where(
              (item) => item.expected != verdict && item.predicted == verdict,
            )
            .length,
        falseNegative: cases
            .where(
              (item) => item.expected == verdict && item.predicted != verdict,
            )
            .length,
      ),
  };

  double get macroF1 =>
      metrics.values.map((item) => item.f1).reduce((a, b) => a + b) /
      Rag2ClaimVerdict.values.length;
  bool get meetsGate => macroF1 >= 0.90;

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'policy': policy.toJson(),
    'macroF1': macroF1,
    'meetsGate': meetsGate,
    'metrics': {
      for (final entry in metrics.entries) entry.key.name: entry.value.toJson(),
    },
    'cases': [for (final item in cases) item.toJson()],
  };
}

int compareRag2ClaimVerificationResults(
  Rag2ClaimVerificationResult left,
  Rag2ClaimVerificationResult right,
) {
  final score = right.macroF1.compareTo(left.macroF1);
  if (score != 0) return score;
  final support = right.policy.supportThreshold.compareTo(
    left.policy.supportThreshold,
  );
  if (support != 0) return support;
  return right.policy.contradictionThreshold.compareTo(
    left.policy.contradictionThreshold,
  );
}

final class Rag2PostAnswerClaimReport {
  const Rag2PostAnswerClaimReport({
    required this.candidateSetId,
    required this.seedWinner,
    required this.audits,
    required this.seedCandidates,
  });

  final String candidateSetId;
  final Rag2ClaimVerificationResult seedWinner;
  final List<Rag2ClaimVerificationResult> audits;
  final List<Rag2ClaimVerificationResult> seedCandidates;

  bool get passed =>
      seedWinner.meetsGate && audits.every((item) => item.meetsGate);

  Map<String, Object?> toJson() => {
    'schemaName': rag2PostAnswerClaimSchema,
    'schemaVersion': rag2PostAnswerClaimSchemaVersion,
    'candidateSetId': candidateSetId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'selectionPolicy': 'seed_only_macro_f1_v1',
    'seedWinner': seedWinner.toJson(),
    'audits': [for (final item in audits) item.toJson()],
    'seedCandidates': [for (final item in seedCandidates) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Post-Answer Claim Verification')
      ..writeln()
      ..writeln('- Result: `${passed ? 'go' : 'no_go'}`')
      ..writeln('- Production decision: `no_go`')
      ..writeln(
        '- Seed-selected policy: support '
        '`${seedWinner.policy.supportThreshold.toStringAsFixed(2)}`, '
        'contradiction `${seedWinner.policy.contradictionThreshold.toStringAsFixed(2)}`',
      )
      ..writeln()
      ..writeln(
        '| Dataset | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | --- |');
    for (final result in [seedWinner, ...audits]) {
      buffer.writeln(_row(result));
    }
    buffer
      ..writeln()
      ..writeln('## Audit errors')
      ..writeln()
      ..writeln(
        '| Dataset | Candidate | Expected | Predicted | Coverage | Numeric mismatch |',
      )
      ..writeln('| --- | --- | --- | --- | ---: | --- |');
    for (final result in audits) {
      for (final item in result.cases.where((item) => !item.correct)) {
        buffer.writeln(
          '| ${result.fixtureId} | ${item.candidateId} | ${item.expected.name} | '
          '${item.predicted.name} | ${item.coverage.toStringAsFixed(3)} | '
          '${item.numericMismatch} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Candidate claims are fixed before scoring. The verifier sees only each claim and its frozen retrieved passages; answer keys are used only for evaluation labels.',
      );
    return buffer.toString();
  }

  String _row(Rag2ClaimVerificationResult result) {
    final metrics = result.metrics;
    return '| ${result.fixtureId} | ${result.macroF1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.supported]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.contradicted]!.f1.toStringAsFixed(3)} | '
        '${metrics[Rag2ClaimVerdict.absent]!.f1.toStringAsFixed(3)} | '
        '${result.meetsGate ? 'pass' : 'fail'} |';
  }
}

final class Rag2PostAnswerClaimOptions {
  const Rag2PostAnswerClaimOptions({
    required this.claimsPath,
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.auditFixturePath,
    required this.outDir,
  });

  final String claimsPath;
  final String seedFixturePath;
  final String holdoutFixturePath;
  final String auditFixturePath;
  final String outDir;

  static Rag2PostAnswerClaimOptions? parse(List<String> args) {
    if (args.length != 10) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final claims = values['--claims'];
    final seed = values['--seed-fixture'];
    final holdout = values['--holdout-fixture'];
    final audit = values['--audit-fixture'];
    final outDir = values['--out-dir'];
    if ([claims, seed, holdout, audit, outDir].contains(null) ||
        values.length != 5) {
      return null;
    }
    return Rag2PostAnswerClaimOptions(
      claimsPath: claims!,
      seedFixturePath: seed!,
      holdoutFixturePath: holdout!,
      auditFixturePath: audit!,
      outDir: outDir!,
    );
  }
}

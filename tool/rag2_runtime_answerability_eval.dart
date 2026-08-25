import 'dart:convert';
import 'dart:io';

import 'rag2_claim_support_eval.dart';
import 'rag2_lexical_policy_bakeoff.dart';
import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2RuntimeAnswerabilitySchema =
    'caverno_rag2_runtime_answerability_eval';
const rag2RuntimeAnswerabilitySchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2RuntimeAnswerabilityOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_runtime_answerability_eval.dart '
      '--seed-fixture PATH --holdout-fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2RuntimeAnswerabilityEval(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 runtime answerability evaluation failed: $error');
    exitCode = 65;
  }
}

Future<Rag2RuntimeAnswerabilityReport> runRag2RuntimeAnswerabilityEval(
  Rag2RuntimeAnswerabilityOptions options,
) async {
  final seedCorpus = await _loadCorpus(options.seedFixturePath);
  final holdoutCorpus = await _loadCorpus(options.holdoutFixturePath);
  final candidates = [
    for (final policy in Rag2RuntimeAnswerabilityPolicy.values)
      evaluateRag2RuntimeAnswerability(seedCorpus, policy),
  ]..sort(compareRag2RuntimeAnswerabilityCandidates);
  final seedWinner = candidates.first;
  final holdout = evaluateRag2RuntimeAnswerability(
    holdoutCorpus,
    seedWinner.policy,
  );
  final report = Rag2RuntimeAnswerabilityReport(
    seedCorpusHash: seedCorpus.corpusHash,
    holdoutCorpusHash: holdoutCorpus.corpusHash,
    seedWinner: seedWinner,
    holdout: holdout,
    seedCandidates: candidates,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_runtime_answerability_eval.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_runtime_answerability_eval.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

Future<Rag2RuntimeAnswerabilityCorpus> _loadCorpus(String fixturePath) async {
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
    final rankedCases = [
      for (final fixtureCase in fixture.cases)
        scorer.rank(fixtureCase.query, limit: documents.length),
    ];
    final oracle = evaluateRag2ClaimSupportDataset(
      fixture: fixture,
      corpusHash: corpusHash,
      rankedCases: rankedCases,
    );
    return Rag2RuntimeAnswerabilityCorpus(
      fixture: fixture,
      corpusHash: corpusHash,
      documents: {for (final item in documents) item.objectId: item},
      rankedCases: rankedCases,
      oracle: oracle,
    );
  } finally {
    scorer.close();
  }
}

Rag2RuntimeAnswerabilityResult evaluateRag2RuntimeAnswerability(
  Rag2RuntimeAnswerabilityCorpus corpus,
  Rag2RuntimeAnswerabilityPolicy policy,
) {
  var truePositive = 0;
  var falsePositive = 0;
  var trueNegative = 0;
  var falseNegative = 0;
  final cases = <Rag2RuntimeAnswerabilityCase>[];
  for (var index = 0; index < corpus.fixture.cases.length; index++) {
    final fixtureCase = corpus.fixture.cases[index];
    final oracleCase = corpus.oracle.cases[index];
    final hits = applyRag2FrozenSufficiencyPolicy(
      corpus.rankedCases[index],
      metricK: corpus.fixture.metricK,
    );
    final decision = decideRag2RuntimeAnswerability(
      query: fixtureCase.query,
      hits: hits,
      documents: corpus.documents,
      policy: policy,
    );
    final expected = oracleCase.support == Rag2ClaimSupportVerdict.supported;
    if (decision.answerable && expected) truePositive++;
    if (decision.answerable && !expected) falsePositive++;
    if (!decision.answerable && !expected) trueNegative++;
    if (!decision.answerable && expected) falseNegative++;
    cases.add(
      Rag2RuntimeAnswerabilityCase(
        caseId: fixtureCase.id,
        category: fixtureCase.category,
        expectedAnswerable: expected,
        predictedAnswerable: decision.answerable,
        reason: decision.reason,
        oracleSupport: oracleCase.support,
      ),
    );
  }
  return Rag2RuntimeAnswerabilityResult(
    fixtureId: corpus.fixture.fixtureId,
    policy: policy,
    truePositive: truePositive,
    falsePositive: falsePositive,
    trueNegative: trueNegative,
    falseNegative: falseNegative,
    cases: cases,
  );
}

Rag2RuntimeAnswerabilityDecision decideRag2RuntimeAnswerability({
  required String query,
  required List<Rag2LexicalHit> hits,
  required Map<String, RagFixtureDocument> documents,
  required Rag2RuntimeAnswerabilityPolicy policy,
}) {
  if (hits.isEmpty) {
    return const Rag2RuntimeAnswerabilityDecision(
      answerable: false,
      reason: 'no_evidence',
    );
  }
  final evidence = hits
      .map((hit) => documents[hit.objectId]!.content)
      .join('\n')
      .toLowerCase();
  final normalizedQuery = query.toLowerCase();
  if (policy.requiresLiteralCompleteness) {
    final literals = _requestedLiterals(normalizedQuery);
    if (literals.length >= 2 &&
        literals.any((item) => !evidence.contains(item))) {
      return const Rag2RuntimeAnswerabilityDecision(
        answerable: false,
        reason: 'missing_requested_literal',
      );
    }
  }
  if (policy.rejectsExplicitDenial &&
      _queryRequestsProtectedValue(normalizedQuery)) {
    if (_evidenceDeniesProtectedValue(evidence)) {
      return const Rag2RuntimeAnswerabilityDecision(
        answerable: false,
        reason: 'evidence_denies_protected_value',
      );
    }
    if (!_evidenceMentionsProtectedValue(evidence)) {
      return const Rag2RuntimeAnswerabilityDecision(
        answerable: false,
        reason: 'protected_value_not_present',
      );
    }
  }
  if (policy.rejectsExplicitDenial &&
      _queryRequestsInstructionExecution(normalizedQuery) &&
      _evidenceDeniesInstructionExecution(evidence)) {
    return const Rag2RuntimeAnswerabilityDecision(
      answerable: false,
      reason: 'evidence_denies_instruction_execution',
    );
  }
  return const Rag2RuntimeAnswerabilityDecision(
    answerable: true,
    reason: 'evidence_available',
  );
}

Set<String> _requestedLiterals(String query) {
  final literals = RegExp(
    r'(?<![a-z0-9])\d+(?:\.\d+)?(?![a-z0-9])',
  ).allMatches(query).map((match) => match.group(0)!).toSet();
  const numberWords = {
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
  };
  literals.addAll(
    RegExp(r'\b[a-z]+\b')
        .allMatches(query)
        .map((match) => match.group(0)!)
        .where(numberWords.contains),
  );
  return literals;
}

bool _queryRequestsProtectedValue(String query) => RegExp(
  r'\b(api key|credential|password|private key|secret)\b',
).hasMatch(query);

bool _evidenceDeniesProtectedValue(String evidence) => RegExp(
  r'\b(excluded|redacted|unavailable)\b|does not contain|no real credential',
).hasMatch(evidence);

bool _evidenceMentionsProtectedValue(String evidence) => RegExp(
  r'\b(api key|credential|password|private key|secret)\b',
).hasMatch(evidence);

bool _queryRequestsInstructionExecution(String query) =>
    (RegExp(r'\b(execute|obey|run|follow)\b').hasMatch(query) &&
        RegExp(r'\binstruction').hasMatch(query)) ||
    query.contains('executable instructions');

bool _evidenceDeniesInstructionExecution(String evidence) =>
    evidence.contains('not instructions') ||
    evidence.contains('never executable instructions');

enum Rag2RuntimeAnswerabilityPolicy {
  evidenceOnly,
  literalCompleteness,
  literalCompletenessAndExplicitDenial;

  String get id => switch (this) {
    evidenceOnly => 'evidence_only_v1',
    literalCompleteness => 'literal_completeness_v1',
    literalCompletenessAndExplicitDenial =>
      'literal_completeness_and_explicit_denial_v1',
  };

  bool get requiresLiteralCompleteness => this != evidenceOnly;
  bool get rejectsExplicitDenial =>
      this == literalCompletenessAndExplicitDenial;
}

final class Rag2RuntimeAnswerabilityDecision {
  const Rag2RuntimeAnswerabilityDecision({
    required this.answerable,
    required this.reason,
  });

  final bool answerable;
  final String reason;
}

final class Rag2RuntimeAnswerabilityCorpus {
  const Rag2RuntimeAnswerabilityCorpus({
    required this.fixture,
    required this.corpusHash,
    required this.documents,
    required this.rankedCases,
    required this.oracle,
  });

  final RagRetrievalFixture fixture;
  final String corpusHash;
  final Map<String, RagFixtureDocument> documents;
  final List<List<Rag2LexicalHit>> rankedCases;
  final Rag2ClaimSupportDataset oracle;
}

final class Rag2RuntimeAnswerabilityCase {
  const Rag2RuntimeAnswerabilityCase({
    required this.caseId,
    required this.category,
    required this.expectedAnswerable,
    required this.predictedAnswerable,
    required this.reason,
    required this.oracleSupport,
  });

  final String caseId;
  final String category;
  final bool expectedAnswerable;
  final bool predictedAnswerable;
  final String reason;
  final Rag2ClaimSupportVerdict oracleSupport;

  bool get correct => expectedAnswerable == predictedAnswerable;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'category': category,
    'expectedAnswerable': expectedAnswerable,
    'predictedAnswerable': predictedAnswerable,
    'reason': reason,
    'oracleSupport': oracleSupport.name,
    'correct': correct,
  };
}

final class Rag2RuntimeAnswerabilityResult {
  const Rag2RuntimeAnswerabilityResult({
    required this.fixtureId,
    required this.policy,
    required this.truePositive,
    required this.falsePositive,
    required this.trueNegative,
    required this.falseNegative,
    required this.cases,
  });

  final String fixtureId;
  final Rag2RuntimeAnswerabilityPolicy policy;
  final int truePositive;
  final int falsePositive;
  final int trueNegative;
  final int falseNegative;
  final List<Rag2RuntimeAnswerabilityCase> cases;

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);
  bool get meetsSyntheticGate => precision >= 0.90 && recall >= 0.90;

  Map<String, Rag2RuntimeAnswerabilityMetrics> get categoryBreakdown {
    final categories = cases.map((item) => item.category).toSet().toList()
      ..sort();
    return {
      for (final category in categories)
        category: Rag2RuntimeAnswerabilityMetrics.fromCases(
          cases.where((item) => item.category == category),
        ),
    };
  }

  Map<String, Object?> toJson() => {
    'fixtureId': fixtureId,
    'policy': policy.id,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'trueNegative': trueNegative,
    'falseNegative': falseNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'meetsSyntheticGate': meetsSyntheticGate,
    'categoryBreakdown': {
      for (final entry in categoryBreakdown.entries)
        entry.key: entry.value.toJson(),
    },
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag2RuntimeAnswerabilityMetrics {
  const Rag2RuntimeAnswerabilityMetrics({
    required this.truePositive,
    required this.falsePositive,
    required this.trueNegative,
    required this.falseNegative,
  });

  factory Rag2RuntimeAnswerabilityMetrics.fromCases(
    Iterable<Rag2RuntimeAnswerabilityCase> cases,
  ) {
    var truePositive = 0;
    var falsePositive = 0;
    var trueNegative = 0;
    var falseNegative = 0;
    for (final item in cases) {
      if (item.predictedAnswerable && item.expectedAnswerable) truePositive++;
      if (item.predictedAnswerable && !item.expectedAnswerable) falsePositive++;
      if (!item.predictedAnswerable && !item.expectedAnswerable) trueNegative++;
      if (!item.predictedAnswerable && item.expectedAnswerable) falseNegative++;
    }
    return Rag2RuntimeAnswerabilityMetrics(
      truePositive: truePositive,
      falsePositive: falsePositive,
      trueNegative: trueNegative,
      falseNegative: falseNegative,
    );
  }

  final int truePositive;
  final int falsePositive;
  final int trueNegative;
  final int falseNegative;

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);

  Map<String, Object?> toJson() => {
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'trueNegative': trueNegative,
    'falseNegative': falseNegative,
    'precision': precision,
    'recall': recall,
  };
}

int compareRag2RuntimeAnswerabilityCandidates(
  Rag2RuntimeAnswerabilityResult left,
  Rag2RuntimeAnswerabilityResult right,
) {
  final f1 = right.f1.compareTo(left.f1);
  if (f1 != 0) return f1;
  final precision = right.precision.compareTo(left.precision);
  if (precision != 0) return precision;
  final recall = right.recall.compareTo(left.recall);
  if (recall != 0) return recall;
  return left.policy.index.compareTo(right.policy.index);
}

final class Rag2RuntimeAnswerabilityReport {
  const Rag2RuntimeAnswerabilityReport({
    required this.seedCorpusHash,
    required this.holdoutCorpusHash,
    required this.seedWinner,
    required this.holdout,
    required this.seedCandidates,
  });

  final String seedCorpusHash;
  final String holdoutCorpusHash;
  final Rag2RuntimeAnswerabilityResult seedWinner;
  final Rag2RuntimeAnswerabilityResult holdout;
  final List<Rag2RuntimeAnswerabilityResult> seedCandidates;

  bool get syntheticGatePassed =>
      seedWinner.meetsSyntheticGate && holdout.meetsSyntheticGate;

  Map<String, Object?> toJson() => {
    'schemaName': rag2RuntimeAnswerabilitySchema,
    'schemaVersion': rag2RuntimeAnswerabilitySchemaVersion,
    'result': syntheticGatePassed ? 'synthetic_pass' : 'synthetic_fail',
    'productionDecision': 'no_go',
    'selectionPolicy': 'seed_only_f1_precision_recall_v1',
    'seedCorpusHash': seedCorpusHash,
    'holdoutCorpusHash': holdoutCorpusHash,
    'seedWinner': seedWinner.toJson(),
    'holdout': holdout.toJson(),
    'seedCandidates': [for (final item in seedCandidates) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Runtime Answerability Evaluation')
      ..writeln()
      ..writeln(
        '- Result: `${syntheticGatePassed ? 'synthetic_pass' : 'synthetic_fail'}`',
      )
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Policy selected on seed only: `${seedWinner.policy.id}`')
      ..writeln()
      ..writeln('| Dataset | TP | FP | TN | FN | Precision | Recall | F1 |')
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
      ..writeln(_row(seedWinner))
      ..writeln(_row(holdout))
      ..writeln()
      ..writeln('## Holdout category breakdown')
      ..writeln()
      ..writeln('| Category | TP | FP | TN | FN | Precision | Recall |')
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final entry in holdout.categoryBreakdown.entries) {
      final metrics = entry.value;
      buffer.writeln(
        '| ${entry.key} | ${metrics.truePositive} | ${metrics.falsePositive} | '
        '${metrics.trueNegative} | ${metrics.falseNegative} | '
        '${metrics.precision.toStringAsFixed(3)} | '
        '${metrics.recall.toStringAsFixed(3)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Holdout errors')
      ..writeln()
      ..writeln('| Case | Expected | Predicted | Reason | Oracle support |')
      ..writeln('| --- | --- | --- | --- | --- |');
    final errors = holdout.cases.where((item) => !item.correct).toList();
    if (errors.isEmpty) {
      buffer.writeln('| none | - | - | - | - |');
    } else {
      for (final item in errors) {
        buffer.writeln(
          '| ${item.caseId} | ${item.expectedAnswerable} | '
          '${item.predictedAnswerable} | ${item.reason} | '
          '${item.oracleSupport.name} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'The selected signal uses only the query and retrieved text at decision time. The synthetic corpora are small and previously inspected, so a passing score does not authorize production use.',
      );
    return buffer.toString();
  }

  String _row(Rag2RuntimeAnswerabilityResult result) =>
      '| ${result.fixtureId} | ${result.truePositive} | ${result.falsePositive} | '
      '${result.trueNegative} | ${result.falseNegative} | '
      '${result.precision.toStringAsFixed(3)} | '
      '${result.recall.toStringAsFixed(3)} | ${result.f1.toStringAsFixed(3)} |';
}

final class Rag2RuntimeAnswerabilityOptions {
  const Rag2RuntimeAnswerabilityOptions({
    required this.seedFixturePath,
    required this.holdoutFixturePath,
    required this.outDir,
  });

  final String seedFixturePath;
  final String holdoutFixturePath;
  final String outDir;

  static Rag2RuntimeAnswerabilityOptions? parse(List<String> args) {
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
    return Rag2RuntimeAnswerabilityOptions(
      seedFixturePath: seed,
      holdoutFixturePath: holdout,
      outDir: outDir,
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'rag3_offline_hybrid_eval.dart';

const rag3AbstentionPolicyInstrumentSchema =
    'caverno_rag3_abstention_policy_instrument';
const rag3AbstentionPolicyInstrumentContract =
    'rag3-cross-arm-consensus-instrument-v1';
const rag3AbstentionPolicyDepths = [1, 3, 5];

Future<void> main(List<String> args) async {
  final options = Rag3AbstentionPolicyInstrumentOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag3_abstention_policy_instrument.dart '
      '--fixture PATH --oracle PATH --run PATH --out PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag3AbstentionPolicyInstrument(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG3 abstention policy instrument failed: $error');
    exitCode = 65;
  }
}

Future<Rag3AbstentionPolicySweepReport> runRag3AbstentionPolicyInstrument(
  Rag3AbstentionPolicyInstrumentOptions options,
) async {
  if ([
    options.fixturePath,
    options.oraclePath,
    options.runPath,
  ].any(_isPromotionPath)) {
    throw StateError(
      'RAG3 abstention policy inputs cannot use promotion artifacts.',
    );
  }
  final fixture = await Rag3HybridFixture.load(
    fixtureFile: File(options.fixturePath),
    oracleFile: File(options.oraclePath),
  );
  final run = Rag3CandidateRun.fromJson(
    _decodeObject(await File(options.runPath).readAsString()),
  );
  final report = evaluateRag3AbstentionPolicySweep(fixture: fixture, run: run);
  await File(options.outPath).parent.create(recursive: true);
  await File(options.outPath).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  return report;
}

Rag3AbstentionPolicySweepReport evaluateRag3AbstentionPolicySweep({
  required Rag3HybridFixture fixture,
  required Rag3CandidateRun run,
}) {
  run.validate(fixture);
  return Rag3AbstentionPolicySweepReport(
    fixtureId: fixture.fixtureId,
    runId: run.runId,
    reports: [
      for (final depth in rag3AbstentionPolicyDepths)
        evaluateRag3AbstentionPolicy(
          fixture: fixture,
          run: run,
          policy: Rag3CrossArmConsensusPolicy(depth: depth),
        ),
    ],
  );
}

Rag3AbstentionPolicyReport evaluateRag3AbstentionPolicy({
  required Rag3HybridFixture fixture,
  required Rag3CandidateRun run,
  required Rag3CrossArmConsensusPolicy policy,
}) {
  run.validate(fixture);
  final runCases = {
    for (final item in run.cases) _string(item, 'caseId'): item,
  };
  final results = <Rag3AbstentionPolicyCaseResult>[];
  for (final fixtureCase in fixture.cases.values) {
    final decision = policy.decide(runCases[fixtureCase.id]!);
    final selectedRoles = [
      for (final chunkId in decision.selectedChunkIds)
        fixtureCase.roleFor(chunkId),
    ];
    results.add(
      Rag3AbstentionPolicyCaseResult(
        caseId: fixtureCase.id,
        language: fixtureCase.language,
        answerable: fixtureCase.answerable,
        unavailable: fixtureCase.unavailable,
        expectedEvidenceRole: fixtureCase.expectedEvidenceRole,
        decision: decision,
        selectedRoles: List.unmodifiable(selectedRoles),
      ),
    );
  }
  return Rag3AbstentionPolicyReport(
    policy: policy,
    cases: List.unmodifiable(results),
  );
}

final class Rag3CrossArmConsensusPolicy {
  const Rag3CrossArmConsensusPolicy({required this.depth}) : assert(depth > 0);

  final int depth;

  String get id => 'cross-arm-exact-chunk-consensus-at-$depth';

  Rag3AbstentionDecision decide(Map<String, Object?> runCase) {
    if (!_boolean(runCase, 'submitted')) {
      return const Rag3AbstentionDecision.abstain('not_submitted');
    }
    final vector = _object(runCase, 'vector');
    if (_string(vector, 'status') != 'available') {
      return const Rag3AbstentionDecision.abstain('vector_not_available');
    }
    final lexical = _deduplicate(
      _stringList(runCase, 'lexicalRankedChunkIds'),
    ).take(depth).toList();
    final vectorRanking = _deduplicate(
      _stringList(vector, 'rankedChunkIds'),
    ).take(depth).toList();
    final lexicalRanks = _rankMap(lexical);
    final vectorRanks = _rankMap(vectorRanking);
    final agreed =
        lexicalRanks.keys
            .where(vectorRanks.containsKey)
            .map(
              (id) => (
                id: id,
                rankSum: lexicalRanks[id]! + vectorRanks[id]!,
                bestRank: lexicalRanks[id]! < vectorRanks[id]!
                    ? lexicalRanks[id]!
                    : vectorRanks[id]!,
              ),
            )
            .toList()
          ..sort((left, right) {
            final sumOrder = left.rankSum.compareTo(right.rankSum);
            if (sumOrder != 0) return sumOrder;
            final bestOrder = left.bestRank.compareTo(right.bestRank);
            if (bestOrder != 0) return bestOrder;
            return left.id.compareTo(right.id);
          });
    if (agreed.isEmpty) {
      return const Rag3AbstentionDecision.abstain('cross_arm_disagreement');
    }
    return Rag3AbstentionDecision.accept(
      List.unmodifiable([for (final item in agreed) item.id]),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'depth': depth,
    'agreementUnit': 'exact_chunk_id',
    'vectorUnavailableOutcome': 'abstain',
  };
}

final class Rag3AbstentionDecision {
  const Rag3AbstentionDecision._({
    required this.action,
    required this.reason,
    required this.selectedChunkIds,
  });

  const Rag3AbstentionDecision.abstain(String reason)
    : this._(action: 'abstain', reason: reason, selectedChunkIds: const []);

  factory Rag3AbstentionDecision.accept(List<String> selectedChunkIds) =>
      Rag3AbstentionDecision._(
        action: 'accept',
        reason: 'cross_arm_consensus',
        selectedChunkIds: selectedChunkIds,
      );

  final String action;
  final String reason;
  final List<String> selectedChunkIds;

  bool get abstained => action == 'abstain';

  Map<String, Object?> toJson() => {
    'action': action,
    'reason': reason,
    'selectedChunkIds': selectedChunkIds,
  };
}

final class Rag3AbstentionPolicyCaseResult {
  const Rag3AbstentionPolicyCaseResult({
    required this.caseId,
    required this.language,
    required this.answerable,
    required this.unavailable,
    required this.expectedEvidenceRole,
    required this.decision,
    required this.selectedRoles,
  });

  final String caseId;
  final String language;
  final bool answerable;
  final bool unavailable;
  final String expectedEvidenceRole;
  final Rag3AbstentionDecision decision;
  final List<String> selectedRoles;

  bool get expectedSupportSelected =>
      selectedRoles.contains(expectedEvidenceRole);

  bool get irrelevantOnlySelected =>
      selectedRoles.isNotEmpty &&
      selectedRoles.every((role) => role == 'irrelevant');

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'decision': decision.toJson(),
    'selectedRoles': selectedRoles,
  };
}

final class Rag3AbstentionPolicyReport {
  const Rag3AbstentionPolicyReport({required this.policy, required this.cases});

  final Rag3CrossArmConsensusPolicy policy;
  final List<Rag3AbstentionPolicyCaseResult> cases;

  int get answerSupportCount => cases
      .where((item) => item.answerable && item.expectedSupportSelected)
      .length;
  int get answerSupportCases => cases.where((item) => item.answerable).length;
  int get japaneseAnswerSupportCount => cases
      .where(
        (item) =>
            item.answerable &&
            item.language == 'ja' &&
            item.expectedSupportSelected,
      )
      .length;
  int get japaneseAnswerSupportCases =>
      cases.where((item) => item.answerable && item.language == 'ja').length;
  int get abstentionSupportCount => cases
      .where(
        (item) =>
            item.expectedEvidenceRole == 'abstention_support' &&
            item.expectedSupportSelected,
      )
      .length;
  int get abstentionSupportCases => cases
      .where((item) => item.expectedEvidenceRole == 'abstention_support')
      .length;
  int get unavailableIrrelevantOnlyCount => cases
      .where((item) => item.unavailable && item.irrelevantOnlySelected)
      .length;
  int get unavailableAbstainedCount =>
      cases.where((item) => item.unavailable && item.decision.abstained).length;
  int get unavailableCases => cases.where((item) => item.unavailable).length;
  int get answerableAbstainedCount =>
      cases.where((item) => item.answerable && item.decision.abstained).length;

  Map<String, Object?> toJson() => {
    'policy': policy.toJson(),
    'metrics': {
      'answerSupport': {
        'retrieved': answerSupportCount,
        'cases': answerSupportCases,
      },
      'japaneseAnswerSupport': {
        'retrieved': japaneseAnswerSupportCount,
        'cases': japaneseAnswerSupportCases,
      },
      'abstentionSupport': {
        'retrieved': abstentionSupportCount,
        'cases': abstentionSupportCases,
      },
      'unavailableIrrelevantOnly': unavailableIrrelevantOnlyCount,
      'unavailableAbstained': unavailableAbstainedCount,
      'unavailableCases': unavailableCases,
      'answerableAbstained': answerableAbstainedCount,
    },
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag3AbstentionPolicySweepReport {
  const Rag3AbstentionPolicySweepReport({
    required this.fixtureId,
    required this.runId,
    required this.reports,
  });

  final String fixtureId;
  final String runId;
  final List<Rag3AbstentionPolicyReport> reports;

  Map<String, Object?> toJson() => {
    'schemaName': rag3AbstentionPolicyInstrumentSchema,
    'schemaVersion': 1,
    'contract': rag3AbstentionPolicyInstrumentContract,
    'fixtureId': fixtureId,
    'runId': runId,
    'promotionFixtureAccessed': false,
    'promotionDecision': 'not_run',
    'productionDecision': 'no_go',
    'candidateSelection': 'not_run',
    'reports': [for (final item in reports) item.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG3 Abstention Policy Instrument')
      ..writeln()
      ..writeln('- Promotion fixture accessed: `false`')
      ..writeln('- Promotion decision: `not_run`')
      ..writeln('- Production decision: `no_go`')
      ..writeln('- Candidate selection: `not_run`')
      ..writeln()
      ..writeln(
        '| Depth | Answer support | Japanese support | Abstention support | '
        'Unavailable irrelevant-only | Unavailable abstained | '
        'Answerable abstained |',
      )
      ..writeln('| ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final report in reports) {
      buffer.writeln(
        '| ${report.policy.depth} | '
        '${report.answerSupportCount}/${report.answerSupportCases} | '
        '${report.japaneseAnswerSupportCount}/'
        '${report.japaneseAnswerSupportCases} | '
        '${report.abstentionSupportCount}/${report.abstentionSupportCases} | '
        '${report.unavailableIrrelevantOnlyCount} | '
        '${report.unavailableAbstainedCount}/${report.unavailableCases} | '
        '${report.answerableAbstainedCount}/${report.answerSupportCases} |',
      );
    }
    return buffer.toString();
  }
}

final class Rag3AbstentionPolicyInstrumentOptions {
  const Rag3AbstentionPolicyInstrumentOptions({
    required this.fixturePath,
    required this.oraclePath,
    required this.runPath,
    required this.outPath,
  });

  final String fixturePath;
  final String oraclePath;
  final String runPath;
  final String outPath;

  static Rag3AbstentionPolicyInstrumentOptions? parse(List<String> args) {
    String? value(String flag) {
      final index = args.indexOf(flag);
      if (index < 0 || index + 1 >= args.length) return null;
      return args[index + 1];
    }

    final fixture = value('--fixture');
    final oracle = value('--oracle');
    final run = value('--run');
    final out = value('--out');
    if ([fixture, oracle, run, out].any((item) => item == null)) return null;
    return Rag3AbstentionPolicyInstrumentOptions(
      fixturePath: fixture!,
      oraclePath: oracle!,
      runPath: run!,
      outPath: out!,
    );
  }
}

bool _isPromotionPath(String path) =>
    path.toLowerCase().contains('rag3_offline_hybrid_holdout') ||
    path.toLowerCase().contains('rag3_promotion');

Map<String, Object?> _decodeObject(String source) =>
    (jsonDecode(source) as Map).cast<String, Object?>();

Map<String, Object?> _object(Map<String, Object?> source, String key) =>
    (source[key] as Map).cast<String, Object?>();

String _string(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! String || value.isEmpty) {
    throw StateError('RAG3 abstention input $key must be a non-empty string.');
  }
  return value;
}

bool _boolean(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! bool) {
    throw StateError('RAG3 abstention input $key must be a boolean.');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw StateError('RAG3 abstention input $key must be a string list.');
  }
  return value.cast<String>();
}

List<String> _deduplicate(List<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

Map<String, int> _rankMap(List<String> ranking) => {
  for (var index = 0; index < ranking.length; index++)
    ranking[index]: index + 1,
};

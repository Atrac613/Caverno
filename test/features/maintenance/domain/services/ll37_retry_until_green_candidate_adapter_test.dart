import 'dart:convert';

import 'package:caverno/features/chat/domain/services/best_of_n_coordinator.dart';
import 'package:caverno/features/chat/domain/services/retry_until_green_coordinator.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_retry_until_green_candidate_adapter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = Ll37RetryUntilGreenCandidateAdapter();

  test('maps complete bounded winning evidence exactly', () {
    final candidate = adapter.adapt([_report()]).single;

    expect(candidate.id, 'retry-until-green:overnight-1');
    expect(candidate.sourceSurface, Ll37ObjectiveSourceSurface.retryUntilGreen);
    expect(candidate.objective, 'Repair the parser');
    expect(candidate.acceptanceCriteria, ['The parser accepts quoted commas.']);
    expect(candidate.plan, 'Change parser.dart and keep the API stable.');
    expect(candidate.changedFiles.single.path, 'lib/parser.dart');
    expect(candidate.implementationEvidence, [
      'Mechanical verification: dart test (exit 0)',
      'Retry-until-green winner: round 0 of 1',
      'Candidate 1 updated the tokenizer.',
    ]);
  });

  test('JSON round trip preserves complete evidence', () {
    final encoded = jsonEncode(_report().toJson());
    final decoded = RetryUntilGreenReport.fromJson(
      Map<String, dynamic>.from(jsonDecode(encoded) as Map),
    );

    expect(decoded.objectiveEvidence!.sourceId, 'overnight-1');
    expect(decoded.objectiveEvidence!.changedFiles.single.content, 'fixed\n');
    expect(adapter.adapt([decoded]), hasLength(1));
  });

  test('legacy report JSON remains readable and ineligible', () {
    final json = _report().toJson()..remove('objectiveEvidence');
    final decoded = RetryUntilGreenReport.fromJson(json);

    expect(decoded.objectiveEvidence, isNull);
    expect(adapter.adapt([decoded]), isEmpty);
  });

  test('rejects non-green, residue-risk, attended, or incomplete evidence', () {
    final base = _report();
    final evidence = base.objectiveEvidence!;
    final invalid = <RetryUntilGreenReport>[
      RetryUntilGreenReport(
        rounds: base.rounds,
        winningRound: null,
        objectiveEvidence: evidence,
      ),
      RetryUntilGreenReport(
        rounds: [
          BestOfNReport(
            attempts: [
              const BestOfNAttempt(
                index: 0,
                generated: true,
                verified: true,
                passed: true,
                isWinner: true,
              ),
              const BestOfNAttempt(
                index: 1,
                generated: true,
                verified: false,
                passed: false,
                isWinner: false,
                discardError: 'residue',
              ),
            ],
            winnerIndex: 0,
          ),
        ],
        winningRound: 0,
        objectiveEvidence: evidence,
      ),
      _report(evidence: _evidence(attended: true)),
      _report(evidence: _evidence(objective: '')),
      _report(evidence: _evidence(criteria: const [])),
      _report(evidence: _evidence(implementation: const [])),
      _report(evidence: _evidence(verificationExitCode: 1)),
      _report(evidence: _evidence(truncated: true)),
      _report(evidence: _evidence(files: const [])),
      _report(evidence: _evidence(filePath: '../secret')),
      _report(evidence: _evidence(fileHash: 'bad')),
      RetryUntilGreenReport(
        rounds: base.rounds,
        winningRound: 2,
        objectiveEvidence: evidence,
      ),
      RetryUntilGreenReport(
        rounds: [
          BestOfNReport(
            attempts: const [
              BestOfNAttempt(
                index: 0,
                generated: true,
                verified: true,
                passed: false,
                isWinner: true,
              ),
            ],
            winnerIndex: 0,
          ),
        ],
        winningRound: 0,
        objectiveEvidence: evidence,
      ),
      RetryUntilGreenReport(
        rounds: [...base.rounds, ...base.rounds],
        winningRound: 0,
        objectiveEvidence: evidence,
      ),
    ];

    for (final report in invalid) {
      expect(adapter.adapt([report]), isEmpty);
    }
  });

  test('orders newest first and suppresses duplicate source identities', () {
    final older = _report();
    final newer = _report(
      evidence: _evidence(
        sourceId: 'overnight-2',
        completedAt: DateTime.utc(2026, 8, 14),
      ),
    );
    final duplicate = _report(
      evidence: _evidence(completedAt: DateTime.utc(2026, 8, 15)),
    );

    expect(adapter.adapt([older, newer, duplicate]).map((item) => item.id), [
      'retry-until-green:overnight-1',
      'retry-until-green:overnight-2',
    ]);
  });
}

RetryUntilGreenReport _report({RetryUntilGreenObjectiveEvidence? evidence}) {
  return RetryUntilGreenReport(
    rounds: [
      BestOfNReport(
        attempts: const [
          BestOfNAttempt(
            index: 0,
            generated: true,
            verified: true,
            passed: true,
            isWinner: true,
          ),
        ],
        winnerIndex: 0,
      ),
    ],
    winningRound: 0,
    objectiveEvidence: evidence ?? _evidence(),
  );
}

RetryUntilGreenObjectiveEvidence _evidence({
  String sourceId = 'overnight-1',
  String objective = 'Repair the parser',
  List<String> criteria = const ['The parser accepts quoted commas.'],
  List<String> implementation = const ['Candidate 1 updated the tokenizer.'],
  bool attended = false,
  int verificationExitCode = 0,
  bool truncated = false,
  List<RetryUntilGreenChangedFileEvidence>? files,
  String filePath = 'lib/parser.dart',
  String? fileHash,
  DateTime? completedAt,
}) {
  const content = 'fixed\n';
  final bytes = utf8.encode(content);
  return RetryUntilGreenObjectiveEvidence(
    sourceId: sourceId,
    objective: objective,
    acceptanceCriteria: criteria,
    plan: 'Change parser.dart and keep the API stable.',
    attended: attended,
    mechanicalVerification: RetryUntilGreenMechanicalVerification(
      command: 'dart test',
      exitCode: verificationExitCode,
      output: 'ok',
    ),
    changedFiles:
        files ??
        [
          RetryUntilGreenChangedFileEvidence(
            path: filePath,
            content: content,
            byteSize: bytes.length,
            contentHash: fileHash ?? sha256.convert(bytes).toString(),
          ),
        ],
    changedFileEvidenceTruncated: truncated,
    implementationEvidence: implementation,
    completedAt: completedAt ?? DateTime.utc(2026, 8, 13),
  );
}

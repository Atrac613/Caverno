import 'dart:convert';

import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_routine_candidate_adapter.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = Ll37RoutineCandidateAdapter();

  test('maps complete scheduled Routine evidence exactly', () {
    final candidate = adapter.adapt([_routine()]).single;

    expect(candidate.id, 'routine:routine-1:run-1');
    expect(candidate.sourceSurface, Ll37ObjectiveSourceSurface.routine);
    expect(candidate.attended, isFalse);
    expect(candidate.ll34OutcomeSettled, isFalse);
    expect(candidate.objective, 'Update the feature flag');
    expect(candidate.acceptanceCriteria, ['The flag is enabled.']);
    expect(candidate.plan, 'Change config.json only.');
    expect(candidate.changedFiles.single.path, 'config.json');
    expect(candidate.changedFiles.single.content, '{"enabled":true}\n');
    expect(candidate.implementationEvidence, [
      'Mechanical verification: dart run verify.dart (exit 0)',
      'write_file updated config.json',
    ]);
  });

  test('orders newest first and suppresses duplicate source identities', () {
    final original = _routine();
    final newer = _run().copyWith(
      id: 'run-2',
      finishedAt: DateTime.utc(2026, 8, 13, 2),
    );
    final duplicate = _run().copyWith(finishedAt: DateTime.utc(2026, 8, 13, 3));
    final candidates = adapter.adapt([
      original.copyWith(runs: [original.runs.single, newer]),
      original.copyWith(runs: [duplicate]),
    ]);

    expect(candidates.map((item) => item.id), [
      'routine:routine-1:run-1',
      'routine:routine-1:run-2',
    ]);
  });

  test('rejects incomplete or unsafe Routine evidence', () {
    final base = _run();
    final invalid = <RoutineRunRecord>[
      base.copyWith(status: RoutineRunStatus.failed),
      base.copyWith(trigger: RoutineRunTrigger.manual),
      base.copyWith(objective: ''),
      base.copyWith(objectiveAcceptanceCriteria: const []),
      base.copyWith(implementationEvidence: const []),
      base.copyWith(mechanicalVerification: null),
      base.copyWith(
        mechanicalVerification: base.mechanicalVerification!.copyWith(
          exitCode: 1,
        ),
      ),
      base.copyWith(changedFileEvidenceTruncated: true),
      base.copyWith(changedFiles: const []),
      base.copyWith(
        changedFiles: [base.changedFiles.single.copyWith(path: '../secret')],
      ),
      base.copyWith(
        changedFiles: [base.changedFiles.single.copyWith(byteSize: 1)],
      ),
      base.copyWith(
        changedFiles: [base.changedFiles.single.copyWith(contentHash: 'bad')],
      ),
      base.copyWith(
        changedFiles: [base.changedFiles.single.copyWith(truncated: true)],
      ),
      base.copyWith(
        changedFiles: [base.changedFiles.single, base.changedFiles.single],
      ),
    ];

    for (final run in invalid) {
      expect(
        adapter.adapt([
          _routine().copyWith(runs: [run]),
        ]),
        isEmpty,
      );
    }
  });

  test('legacy Routine JSON remains readable and ineligible', () {
    final json = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(_routine().toJson())) as Map,
    );
    final runs = (json['runs'] as List<dynamic>);
    final run = Map<String, dynamic>.from(runs.single as Map)
      ..remove('objective')
      ..remove('objectiveAcceptanceCriteria')
      ..remove('objectivePlan')
      ..remove('mechanicalVerification')
      ..remove('changedFiles')
      ..remove('changedFileEvidenceTruncated')
      ..remove('implementationEvidence');
    json['runs'] = [run];

    final decoded = Routine.fromJson(json);
    expect(decoded.runs.single.objective, isEmpty);
    expect(adapter.adapt([decoded]), isEmpty);
  });
}

Routine _routine() => Routine(
  id: 'routine-1',
  name: 'Flag update',
  prompt: 'Update the feature flag',
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13),
  runs: [_run()],
);

RoutineRunRecord _run() {
  const content = '{"enabled":true}\n';
  final bytes = utf8.encode(content);
  return RoutineRunRecord(
    id: 'run-1',
    startedAt: DateTime.utc(2026, 8, 13),
    finishedAt: DateTime.utc(2026, 8, 13, 1),
    status: RoutineRunStatus.completed,
    trigger: RoutineRunTrigger.scheduled,
    objective: 'Update the feature flag',
    objectiveAcceptanceCriteria: const ['The flag is enabled.'],
    objectivePlan: 'Change config.json only.',
    mechanicalVerification: const RoutineRunMechanicalVerification(
      command: 'dart run verify.dart',
      exitCode: 0,
      output: 'ok',
    ),
    changedFiles: [
      RoutineRunChangedFileEvidence(
        path: 'config.json',
        content: content,
        byteSize: bytes.length,
        contentHash: sha256.convert(bytes).toString(),
      ),
    ],
    implementationEvidence: const ['write_file updated config.json'],
  );
}

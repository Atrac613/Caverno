import 'dart:convert';

import 'package:caverno/features/chat/data/repositories/retry_until_green_report_repository.dart';
import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/best_of_n_coordinator.dart';
import 'package:caverno/features/chat/domain/services/retry_until_green_coordinator.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read-only source combines LL13, Routine, and retry reports', () async {
    final worktree = _worktreeTask();
    final routine = _routine();
    final retry = _retryReport();
    final initial = <String, Object>{
      WorktreeAgentTaskRepository.storageKey: jsonEncode([worktree.toJson()]),
      'routines': jsonEncode([routine.toJson()]),
      RetryUntilGreenReportRepository.storageKey: jsonEncode([retry.toJson()]),
    };
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in initial.keys) key: prefs.getString(key)};
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final candidates = await container.read(
      maintenanceLl37ObjectiveCandidateSourceProvider,
    )();

    expect(candidates.map((candidate) => candidate.id), [
      'worktree-agent:task-1',
      'routine:routine-1:run-1',
      'retry-until-green:retry-1',
    ]);
    expect(
      {for (final item in candidates) item.sourceSurface.name},
      {'worktreeAgent', 'routine', 'retryUntilGreen'},
    );
    expect({for (final key in initial.keys) key: prefs.getString(key)}, before);
  });

  test('retry report repository fails closed and bounds writes', () async {
    SharedPreferences.setMockInitialValues({
      RetryUntilGreenReportRepository.storageKey: 'invalid',
    });
    final prefs = await SharedPreferences.getInstance();
    final repository = RetryUntilGreenReportRepository(prefs);
    expect(repository.loadAll(), isEmpty);

    await repository.saveAll(
      List.generate(
        RetryUntilGreenReportRepository.maxStoredReports + 3,
        (index) => _retryReport(sourceId: 'retry-$index'),
      ),
    );
    expect(repository.loadAll(), hasLength(32));
  });
}

WorktreeAgentTask _worktreeTask() {
  const content = 'worktree\n';
  final bytes = utf8.encode(content);
  final now = DateTime.utc(2026, 8, 13);
  return WorktreeAgentTask(
    id: 'task-1',
    status: WorktreeAgentTaskStatus.completed,
    title: 'Worktree source',
    prompt: 'Complete the worktree objective.',
    branchName: 'feature/task-1',
    worktreePath: '/tmp/task-1',
    verificationCommand: 'dart test',
    objectiveAcceptanceCriteria: const ['The worktree criterion passes.'],
    createdAt: now,
    updatedAt: now,
    resultSummary: 'Implemented the worktree change.',
    verifiedGreen: true,
    verificationSummary: 'dart test passed',
    changedFiles: [
      WorktreeAgentChangedFileEvidence(
        path: 'lib/worktree.dart',
        content: content,
        contentHash: sha256.convert(bytes).toString(),
        byteSize: bytes.length,
      ),
    ],
  );
}

Routine _routine() {
  const content = 'routine\n';
  final bytes = utf8.encode(content);
  final now = DateTime.utc(2026, 8, 13);
  return Routine(
    id: 'routine-1',
    name: 'Routine source',
    prompt: 'Complete the Routine objective.',
    createdAt: now,
    updatedAt: now,
    runs: [
      RoutineRunRecord(
        id: 'run-1',
        startedAt: now,
        finishedAt: now,
        status: RoutineRunStatus.completed,
        trigger: RoutineRunTrigger.scheduled,
        objective: 'Complete the Routine objective.',
        objectiveAcceptanceCriteria: const ['The Routine criterion passes.'],
        mechanicalVerification: const RoutineRunMechanicalVerification(
          command: 'dart test',
          exitCode: 0,
        ),
        changedFiles: [
          RoutineRunChangedFileEvidence(
            path: 'lib/routine.dart',
            content: content,
            byteSize: bytes.length,
            contentHash: sha256.convert(bytes).toString(),
          ),
        ],
        implementationEvidence: const ['Routine implementation completed.'],
      ),
    ],
  );
}

RetryUntilGreenReport _retryReport({String sourceId = 'retry-1'}) {
  const content = 'retry\n';
  final bytes = utf8.encode(content);
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
    objectiveEvidence: RetryUntilGreenObjectiveEvidence(
      sourceId: sourceId,
      objective: 'Complete the retry objective.',
      acceptanceCriteria: const ['The retry criterion passes.'],
      mechanicalVerification: const RetryUntilGreenMechanicalVerification(
        command: 'dart test',
        exitCode: 0,
      ),
      changedFiles: [
        RetryUntilGreenChangedFileEvidence(
          path: 'lib/retry.dart',
          content: content,
          byteSize: bytes.length,
          contentHash: sha256.convert(bytes).toString(),
        ),
      ],
      implementationEvidence: const ['Retry implementation completed.'],
      completedAt: DateTime.utc(2026, 8, 13),
    ),
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/repositories/retry_until_green_report_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:caverno/features/routines/data/routine_objective_evidence_collector.dart';
import 'package:caverno/features/routines/data/routine_repository.dart';
import 'package:caverno/features/routines/data/routine_retry_until_green_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Routine and retry producers feed the read-only LL37 source', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final workspace = await Directory.systemTemp.createTemp('ll37-producer-');
    addTearDown(() => workspace.delete(recursive: true));
    final file = File('${workspace.path}/result.txt');
    await file.writeAsString('green\n');
    final routine = _routine(workspace.path);
    final collector = RoutineObjectiveEvidenceCollector(
      commandRunner: (_, _, _) async => ProcessResult(1, 0, 'passed', ''),
    );
    final captured = await collector.collect(
      routine: routine,
      toolCalls: [
        RoutineRunToolCall(
          id: 'write-1',
          name: 'write_file',
          arguments: jsonEncode({'path': file.path}),
        ),
      ],
      implementationOutput: 'Implemented the Routine result.',
    );
    final routineRun = _run('routine-run', captured!);
    await RoutineRepository(prefs).saveAll([
      routine.copyWith(runs: [routineRun]),
    ]);

    final retryRepository = RetryUntilGreenReportRepository(prefs);
    final retryService = RoutineRetryUntilGreenService(
      candidateExecutor: (_, owner) async => _run('retry-run', captured),
      checkpointPort: _GreenCheckpointPort(),
      reportRepository: retryRepository,
    );
    await retryService.run(routine);

    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final beforeRoutines = prefs.getString('routines');
    final beforeRetries = prefs.getString(
      RetryUntilGreenReportRepository.storageKey,
    );

    final candidates = await container.read(
      maintenanceLl37ObjectiveCandidateSourceProvider,
    )();

    expect(candidates.map((candidate) => candidate.id), [
      'routine:routine-1:routine-run',
      'retry-until-green:routine-1:retry-run',
    ]);
    expect(prefs.getString('routines'), beforeRoutines);
    expect(
      prefs.getString(RetryUntilGreenReportRepository.storageKey),
      beforeRetries,
    );
  });
}

class _GreenCheckpointPort implements RoutineRetryCheckpointPort {
  @override
  void begin(ChatTurnOwner owner, String turnId) {}

  @override
  bool end(ChatTurnOwner owner) => true;

  @override
  Future<FileTurnRollbackPreview?> preview(ChatTurnOwner owner) async => null;

  @override
  Future<McpToolResult> rollback(ChatTurnOwner owner, int token) {
    throw StateError('A green candidate must not roll back.');
  }
}

Routine _routine(String workspace) {
  final now = DateTime.utc(2026, 8, 13);
  return Routine(
    id: 'routine-1',
    name: 'LL37 producer',
    prompt: 'Produce the result.',
    createdAt: now,
    updatedAt: now,
    workspaceDirectory: workspace,
    toolsEnabled: true,
    allowWorkspaceWrites: true,
    objectiveEvidenceContract: const RoutineObjectiveEvidenceContract(
      objective: 'Produce the result.',
      acceptanceCriteria: ['result.txt contains green.'],
      verificationCommand: 'dart test',
    ),
    retryUntilGreenConfig: const RoutineRetryUntilGreenConfig(enabled: true),
  );
}

RoutineRunRecord _run(String id, RoutineObjectiveEvidenceCollection evidence) {
  final now = DateTime.utc(2026, 8, 13);
  return RoutineRunRecord(
    id: id,
    startedAt: now,
    finishedAt: now,
    status: RoutineRunStatus.completed,
    trigger: RoutineRunTrigger.scheduled,
    objective: 'Produce the result.',
    objectiveAcceptanceCriteria: const ['result.txt contains green.'],
    mechanicalVerification: evidence.verification,
    changedFiles: evidence.changedFiles,
    changedFileEvidenceTruncated: evidence.changedFileEvidenceTruncated,
    implementationEvidence: evidence.implementationEvidence,
  );
}

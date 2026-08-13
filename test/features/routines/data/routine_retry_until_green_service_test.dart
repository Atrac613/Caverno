import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/repositories/retry_until_green_report_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/routines/data/routine_retry_until_green_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rolls back failed candidates and persists the first green winner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = RetryUntilGreenReportRepository(
        await SharedPreferences.getInstance(),
      );
      final checkpoint = _FakeCheckpointPort();
      var attempt = 0;
      final service = RoutineRetryUntilGreenService(
        candidateExecutor: (_, owner) async =>
            _run(id: 'run-${attempt + 1}', passed: attempt++ == 1),
        checkpointPort: checkpoint,
        reportRepository: repository,
      );

      final result = await service.run(_routine());

      expect(attempt, 2);
      expect(checkpoint.beginCount, 2);
      expect(checkpoint.endCount, 2);
      expect(checkpoint.rollbackCount, 1);
      expect(result.runRecord.id, 'run-2');
      expect(result.report.foundGreen, isTrue);
      expect(result.report.winningRound, 0);
      expect(result.report.objectiveEvidence!.sourceId, 'routine-1:run-2');
      expect(
        repository.loadAll().single.objectiveEvidence!.sourceId,
        'routine-1:run-2',
      );
    },
  );

  test(
    'persists a bounded no-winner report after exhausting the preset',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = RetryUntilGreenReportRepository(
        await SharedPreferences.getInstance(),
      );
      final checkpoint = _FakeCheckpointPort();
      var attempt = 0;
      final service = RoutineRetryUntilGreenService(
        candidateExecutor: (_, owner) async =>
            _run(id: 'run-${++attempt}', passed: false),
        checkpointPort: checkpoint,
        reportRepository: repository,
      );

      final result = await service.run(
        _routine().copyWith(
          retryUntilGreenConfig: const RoutineRetryUntilGreenConfig(
            enabled: true,
            maxRounds: 2,
            candidatesPerRound: 2,
          ),
        ),
      );

      expect(attempt, 4);
      expect(checkpoint.rollbackCount, 4);
      expect(result.report.foundGreen, isFalse);
      expect(result.report.objectiveEvidence, isNull);
      expect(result.runRecord.id, 'run-4');
      expect(repository.loadAll(), hasLength(1));
    },
  );
}

class _FakeCheckpointPort implements RoutineRetryCheckpointPort {
  int beginCount = 0;
  int endCount = 0;
  int rollbackCount = 0;
  String currentTurnId = '';
  ChatTurnOwner? owner;

  @override
  void begin(ChatTurnOwner owner, String turnId) {
    beginCount += 1;
    this.owner = owner;
    currentTurnId = turnId;
  }

  @override
  bool end(ChatTurnOwner owner) {
    endCount += 1;
    return true;
  }

  @override
  Future<FileTurnRollbackPreview?> preview(ChatTurnOwner owner) async {
    return FileTurnRollbackPreview(
      owner: owner,
      checkpointToken: beginCount,
      turnId: currentTurnId,
      paths: const ['lib/result.dart'],
      preview: 'preview',
      summary: 'summary',
    );
  }

  @override
  Future<McpToolResult> rollback(ChatTurnOwner owner, int token) async {
    rollbackCount += 1;
    return const McpToolResult(
      toolName: 'rollback',
      result: 'ok',
      isSuccess: true,
    );
  }
}

Routine _routine() {
  final now = DateTime.utc(2026, 8, 13);
  return Routine(
    id: 'routine-1',
    name: 'Retry Routine',
    prompt: 'Repair the parser.',
    createdAt: now,
    updatedAt: now,
    objectiveEvidenceContract: const RoutineObjectiveEvidenceContract(
      objective: 'Repair the parser.',
      acceptanceCriteria: ['The parser accepts quoted commas.'],
      verificationCommand: 'dart test',
    ),
    retryUntilGreenConfig: const RoutineRetryUntilGreenConfig(enabled: true),
  );
}

RoutineRunRecord _run({required String id, required bool passed}) {
  const content = 'fixed\n';
  final bytes = utf8.encode(content);
  final now = DateTime.utc(2026, 8, 13);
  return RoutineRunRecord(
    id: id,
    startedAt: now,
    finishedAt: now,
    status: RoutineRunStatus.completed,
    trigger: RoutineRunTrigger.scheduled,
    objective: 'Repair the parser.',
    objectiveAcceptanceCriteria: const ['The parser accepts quoted commas.'],
    mechanicalVerification: RoutineRunMechanicalVerification(
      command: 'dart test',
      exitCode: passed ? 0 : 1,
      output: passed ? 'passed' : 'failed',
    ),
    changedFiles: [
      RoutineRunChangedFileEvidence(
        path: 'lib/result.dart',
        content: content,
        byteSize: bytes.length,
        contentHash: sha256.convert(bytes).toString(),
      ),
    ],
    implementationEvidence: const ['Updated the parser.'],
  );
}

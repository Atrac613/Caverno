import '../../chat/data/datasources/mcp_tool_service.dart';
import '../../chat/data/datasources/file_rollback_checkpoint_store.dart';
import '../../chat/data/repositories/retry_until_green_report_repository.dart';
import '../../chat/domain/entities/chat_turn_owner.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/services/best_of_n_coordinator.dart';
import '../../chat/domain/services/retry_until_green_coordinator.dart';
import '../domain/entities/routine.dart';
import 'routine_execution_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../chat/presentation/providers/mcp_tool_provider.dart';

final routineRetryUntilGreenServiceProvider =
    Provider<RoutineRetryUntilGreenService?>((ref) {
      final toolService = ref.watch(mcpToolServiceProvider);
      if (toolService == null) return null;
      return RoutineRetryUntilGreenService(
        executionService: ref.watch(routineExecutionServiceProvider),
        checkpointPort: McpRoutineRetryCheckpointPort(toolService),
        reportRepository: ref.watch(retryUntilGreenReportRepositoryProvider),
      );
    });

class RoutineRetryUntilGreenResult {
  const RoutineRetryUntilGreenResult({
    required this.runRecord,
    required this.report,
  });

  final RoutineRunRecord runRecord;
  final RetryUntilGreenReport report;
}

typedef RoutineRetryCandidateExecutor =
    Future<RoutineRunRecord> Function(Routine routine, ChatTurnOwner owner);

/// Executes the explicit Routine retry preset through the LL7 coordinator.
class RoutineRetryUntilGreenService {
  RoutineRetryUntilGreenService({
    RoutineExecutionService? executionService,
    RoutineRetryCandidateExecutor? candidateExecutor,
    required this.checkpointPort,
    required this.reportRepository,
    this.coordinator = const RetryUntilGreenCoordinator(),
  }) : assert(executionService != null || candidateExecutor != null),
       _candidateExecutor =
           candidateExecutor ??
           ((routine, owner) => executionService!.execute(
             routine,
             trigger: RoutineRunTrigger.scheduled,
             fileToolOwner: owner,
           ));

  final RoutineRetryCandidateExecutor _candidateExecutor;
  final RoutineRetryCheckpointPort checkpointPort;
  final RetryUntilGreenReportRepository reportRepository;
  final RetryUntilGreenCoordinator coordinator;

  Future<RoutineRetryUntilGreenResult> run(Routine routine) async {
    final config = routine.retryUntilGreenConfig;
    final contract = routine.objectiveEvidenceContract;
    if (config == null ||
        !config.enabled ||
        contract == null ||
        config.maxRounds <= 0 ||
        config.candidatesPerRound <= 0) {
      throw StateError('Routine retry-until-green is not fully configured.');
    }
    final owner = ChatTurnOwner(
      conversationId: 'routine-retry-${routine.id}',
      interactionGeneration: 1,
    );
    final runner = _RoutineBestOfNRunner(
      routine: routine,
      owner: owner,
      candidateExecutor: _candidateExecutor,
      checkpointPort: checkpointPort,
    );
    final rawReport = await coordinator.run(
      maxRounds: config.maxRounds,
      candidatesPerRound: config.candidatesPerRound,
      runner: runner,
    );
    final winningRun = runner.winningRun;
    final evidence = winningRun == null
        ? null
        : RetryUntilGreenObjectiveEvidence(
            sourceId: '${routine.id}:${winningRun.id}',
            objective: winningRun.objective,
            acceptanceCriteria: winningRun.objectiveAcceptanceCriteria,
            plan: winningRun.objectivePlan,
            mechanicalVerification: RetryUntilGreenMechanicalVerification(
              command: winningRun.mechanicalVerification!.command,
              exitCode: winningRun.mechanicalVerification!.exitCode,
              output: winningRun.mechanicalVerification!.output,
            ),
            changedFiles: winningRun.changedFiles.map(
              (file) => RetryUntilGreenChangedFileEvidence(
                path: file.path,
                content: file.content,
                byteSize: file.byteSize,
                contentHash: file.contentHash,
                truncated: file.truncated,
              ),
            ),
            implementationEvidence: winningRun.implementationEvidence,
            completedAt: winningRun.finishedAt,
          );
    final report = RetryUntilGreenReport(
      rounds: rawReport.rounds,
      winningRound: rawReport.winningRound,
      objectiveEvidence: evidence,
    );
    await reportRepository.saveAll([report, ...reportRepository.loadAll()]);
    final record = winningRun ?? runner.lastRun;
    if (record == null) {
      throw StateError('Routine retry produced no candidate run.');
    }
    return RoutineRetryUntilGreenResult(runRecord: record, report: report);
  }
}

abstract interface class RoutineRetryCheckpointPort {
  void begin(ChatTurnOwner owner, String turnId);
  bool end(ChatTurnOwner owner);
  Future<FileTurnRollbackPreview?> preview(ChatTurnOwner owner);
  Future<McpToolResult> rollback(ChatTurnOwner owner, int token);
}

class McpRoutineRetryCheckpointPort implements RoutineRetryCheckpointPort {
  const McpRoutineRetryCheckpointPort(this.toolService);

  final McpToolService toolService;

  @override
  void begin(ChatTurnOwner owner, String turnId) =>
      toolService.beginFileTurnCheckpoint(owner, turnId);

  @override
  bool end(ChatTurnOwner owner) => toolService.endFileTurnCheckpoint(owner);

  @override
  Future<FileTurnRollbackPreview?> preview(ChatTurnOwner owner) =>
      toolService.previewLastFileTurnCheckpoint(owner);

  @override
  Future<McpToolResult> rollback(ChatTurnOwner owner, int token) =>
      toolService.rollbackLastFileTurnCheckpoint(owner, token);
}

class _RoutineBestOfNRunner implements BestOfNRunner {
  _RoutineBestOfNRunner({
    required this.routine,
    required this.owner,
    required this.candidateExecutor,
    required this.checkpointPort,
  });

  final Routine routine;
  final ChatTurnOwner owner;
  final RoutineRetryCandidateExecutor candidateExecutor;
  final RoutineRetryCheckpointPort checkpointPort;
  final Map<int, RoutineRunRecord> _runs = {};
  RoutineRunRecord? lastRun;
  RoutineRunRecord? winningRun;
  var _sequence = 0;
  String? _activeTurnId;

  @override
  Future<String> generateCandidate(int index) async {
    final turnId = 'retry_${_sequence++}_candidate_$index';
    _activeTurnId = turnId;
    checkpointPort.begin(owner, turnId);
    try {
      final run = await candidateExecutor(routine, owner);
      _runs[index] = run;
      lastRun = run;
      return run.preview;
    } finally {
      checkpointPort.end(owner);
    }
  }

  @override
  Future<BestOfNVerification> verify(int index) async {
    final run = _runs[index];
    final passed =
        run?.mechanicalVerification?.passed == true &&
        run!.changedFiles.isNotEmpty &&
        !run.changedFileEvidenceTruncated;
    return BestOfNVerification(
      passed: passed,
      summary: run?.mechanicalVerification?.output,
    );
  }

  @override
  Future<void> discardCandidate(int index) async {
    final preview = await checkpointPort.preview(owner);
    if (preview == null) return;
    if (preview.turnId != _activeTurnId) {
      throw StateError('Routine retry checkpoint ownership changed.');
    }
    final result = await checkpointPort.rollback(
      owner,
      preview.checkpointToken,
    );
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? 'Routine rollback failed.');
    }
  }

  @override
  Future<void> keepCandidate(int index) async {
    winningRun = _runs[index];
  }
}

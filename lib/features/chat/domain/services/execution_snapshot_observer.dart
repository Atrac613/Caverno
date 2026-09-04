import '../../../../core/types/workspace_mode.dart';
import 'execution_snapshot_projector.dart';

// ChatNotifier decomposition collaborator: execution-snapshot-observer

/// Immutable inputs captured for one execution-snapshot observation.
final class ExecutionSnapshotObservation<LogOwner extends Object> {
  ExecutionSnapshotObservation({
    required this.conversationId,
    required this.workspaceMode,
    required ExecutionSnapshot snapshot,
    required this.loggingEnabled,
    required this.logContext,
    required this.timestamp,
  }) : snapshot = _freezeExecutionSnapshot(snapshot);

  final String conversationId;
  final WorkspaceMode workspaceMode;
  final ExecutionSnapshot snapshot;
  final bool loggingEnabled;

  /// Owner-specific immutable context forwarded unchanged to the log port.
  final LogOwner logContext;
  final DateTime timestamp;
}

/// The same defensive copy, named once instead of seven times.
List<String> _frozen(List<String> values) => List<String>.unmodifiable(values);

ExecutionSnapshot _freezeExecutionSnapshot(ExecutionSnapshot source) {
  return ExecutionSnapshot(
    contractHash: source.contractHash,
    workflowStage: source.workflowStage,
    action: source.action,
    activeTaskId: source.activeTaskId,
    activeTaskStatus: source.activeTaskStatus,
    validationStatus: source.validationStatus,
    completedTaskCount: source.completedTaskCount,
    remainingTaskCount: source.remainingTaskCount,
    unresolvedQuestionCount: source.unresolvedQuestionCount,
    requiresValidation: source.requiresValidation,
    latestDiagnostic: source.latestDiagnostic,
    objective: source.objective,
    constraints: _frozen(source.constraints),
    acceptanceCriteria: _frozen(source.acceptanceCriteria),
    activeTaskTitle: source.activeTaskTitle,
    activeTaskTargetFiles: _frozen(source.activeTaskTargetFiles),
    activeTaskValidationCommand: source.activeTaskValidationCommand,
    remainingTaskIds: _frozen(source.remainingTaskIds),
    clarificationQuestions: _frozen(source.clarificationQuestions),
    blockingAssumptions: _frozen(source.blockingAssumptions),
    waitingTasks: _frozen(source.waitingTasks),
    delegatableTasks: _frozen(source.delegatableTasks),
    sourceCount: source.sourceCount,
    sourcedItemCount: source.sourcedItemCount,
    mutationGeneration: source.mutationGeneration,
    verificationGeneration: source.verificationGeneration,
    verificationCadence: source.verificationCadence,
    commandDiagnosticStreak: source.commandDiagnosticStreak,
    commandDiagnosticHasPath: source.commandDiagnosticHasPath,
  );
}

/// Bounded fields recorded for an execution-snapshot shadow observation.
final class ExecutionShadowEvent {
  const ExecutionShadowEvent({
    required this.timestamp,
    required this.contractHash,
    required this.workflowStage,
    required this.action,
    required this.activeTaskRef,
    required this.taskStatus,
    required this.validationStatus,
    required this.completedTaskCount,
    required this.totalTaskCount,
    required this.unresolvedQuestionCount,
    required this.requiresValidation,
    required this.hasDiagnostic,
  });

  factory ExecutionShadowEvent.fromSnapshot({
    required ExecutionSnapshot snapshot,
    required DateTime timestamp,
  }) {
    return ExecutionShadowEvent(
      timestamp: timestamp,
      contractHash: snapshot.contractHash,
      workflowStage: snapshot.workflowStage.name,
      action: snapshot.action.name,
      activeTaskRef: snapshot.activeTaskRef,
      taskStatus: snapshot.activeTaskStatus?.name,
      validationStatus: snapshot.validationStatus.name,
      completedTaskCount: snapshot.completedTaskCount,
      totalTaskCount: snapshot.completedTaskCount + snapshot.remainingTaskCount,
      unresolvedQuestionCount: snapshot.unresolvedQuestionCount,
      requiresValidation: snapshot.requiresValidation,
      hasDiagnostic: snapshot.latestDiagnostic != null,
    );
  }

  final DateTime timestamp;
  final String contractHash;
  final String workflowStage;
  final String action;
  final String? activeTaskRef;
  final String? taskStatus;
  final String validationStatus;
  final int completedTaskCount;
  final int totalTaskCount;
  final int unresolvedQuestionCount;
  final bool requiresValidation;
  final bool hasDiagnostic;
}

/// Narrow owner-aware boundary for execution-shadow persistence.
abstract interface class ExecutionShadowLogPort<LogOwner extends Object> {
  Future<void> record(LogOwner owner, ExecutionShadowEvent event);
}

typedef ExecutionShadowLogCallback<LogOwner extends Object> =
    Future<void> Function(LogOwner owner, ExecutionShadowEvent event);

/// Adapts an existing execution-shadow sink to the narrow log boundary.
final class CallbackExecutionShadowLogPort<LogOwner extends Object>
    implements ExecutionShadowLogPort<LogOwner> {
  const CallbackExecutionShadowLogPort(this._record);

  final ExecutionShadowLogCallback<LogOwner> _record;

  @override
  Future<void> record(LogOwner owner, ExecutionShadowEvent event) =>
      _record(owner, event);
}

/// Deduplicates and emits owner-scoped execution-snapshot observations.
final class ExecutionSnapshotObserver<LogOwner extends Object> {
  ExecutionSnapshotObserver({
    required ExecutionShadowLogPort<LogOwner> logPort,
    required void Function(String message) diagnosticLog,
  }) : _logPort = logPort,
       _diagnosticLog = diagnosticLog;

  final ExecutionShadowLogPort<LogOwner> _logPort;
  final void Function(String message) _diagnosticLog;
  String? _latestObservationKey;

  Future<void> observe(ExecutionSnapshotObservation<LogOwner> input) async {
    if (input.workspaceMode != WorkspaceMode.coding) {
      return;
    }

    final observationKey =
        '${input.conversationId}|${input.snapshot.observationKey}';
    if (_latestObservationKey == observationKey) {
      return;
    }
    _latestObservationKey = observationKey;

    try {
      _diagnosticLog(
        '[ExecutionShadow] ${input.snapshot.toRedactedLogSummary()}',
      );
    } on Object {
      // Diagnostic logging is best effort, just like shadow persistence.
    }
    if (!input.loggingEnabled) {
      return;
    }

    final event = ExecutionShadowEvent.fromSnapshot(
      snapshot: input.snapshot,
      timestamp: input.timestamp,
    );
    try {
      await _logPort.record(input.logContext, event);
    } on Object {
      // Shadow logging must never interrupt system-prompt construction.
    }
  }
}

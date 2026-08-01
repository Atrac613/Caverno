import '../../domain/services/execution_snapshot_observer.dart';
import 'llm_session_log_store.dart';

export '../../domain/services/execution_snapshot_observer.dart';
export '../../domain/services/execution_snapshot_projector.dart';

/// Maps bounded execution-shadow events onto the existing session log store.
final class LlmSessionExecutionShadowLogPort
    implements ExecutionShadowLogPort<LlmSessionLogContext> {
  const LlmSessionExecutionShadowLogPort(this._store);

  final LlmSessionLogStore _store;

  @override
  Future<void> record(LlmSessionLogContext owner, ExecutionShadowEvent event) {
    return _store.recordExecutionShadow(
      context: owner,
      at: event.timestamp,
      contractHash: event.contractHash,
      workflowStage: event.workflowStage,
      action: event.action,
      activeTaskRef: event.activeTaskRef,
      taskStatus: event.taskStatus,
      validationStatus: event.validationStatus,
      completedTaskCount: event.completedTaskCount,
      totalTaskCount: event.totalTaskCount,
      unresolvedQuestionCount: event.unresolvedQuestionCount,
      requiresValidation: event.requiresValidation,
      hasDiagnostic: event.hasDiagnostic,
    );
  }
}

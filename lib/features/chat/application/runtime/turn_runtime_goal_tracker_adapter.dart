import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_auto_continue_decision_coordinator.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';
import 'turn_runtime.dart';

// ChatNotifier decomposition collaborator: turn-runtime-goal-tracker-adapter
/// Adapts conversation-spanning tracker storage to one turn runtime boundary.
final class TurnRuntimeGoalTrackerAdapter
    implements TurnRuntimeGoalTrackerPort {
  const TurnRuntimeGoalTrackerAdapter({
    required GoalAutoContinueTrackerRegistry registry,
  }) : _registry = registry;

  final GoalAutoContinueTrackerRegistry _registry;

  @override
  GoalAutoContinueTrackerSnapshot snapshotFor(ChatTurnOwner owner) =>
      _registry.create(owner);

  @override
  GoalAutoContinueTrackerSnapshot applyDelta(
    ChatTurnOwner owner,
    GoalAutoContinueTrackerDelta delta,
  ) => _registry.update(
    owner,
    consecutiveAutoContinuationsDelta: delta.consecutiveAutoContinuationsDelta,
    diagnosticRepairContinuationsDelta:
        delta.diagnosticRepairContinuationsDelta,
    diagnosticRepairExtensionUsed: delta.diagnosticRepairExtensionUsed,
    noProgressStreak: delta.noProgressStreak,
    consecutiveValidationMisses: delta.consecutiveValidationMisses,
    failedVerificationObserved: delta.failedVerificationObserved,
    previousEvidence: delta.previousEvidence,
    previousDiagnosticSignature: delta.previousDiagnosticSignature,
    identicalDiagnosticSignatureStreak:
        delta.identicalDiagnosticSignatureStreak,
    pendingPostRepairReplayOutcome: delta.pendingPostRepairReplayOutcome,
    pendingRepairContractOutcome: delta.pendingRepairContractOutcome,
    repairNoMutationRetryUsed: delta.repairNoMutationRetryUsed,
    completionElicitationMutationGeneration:
        delta.completionElicitationMutationGeneration,
  );

  @override
  bool markBudgetNoticePresented(ChatTurnOwner owner) =>
      _registry.markBudgetNoticePresented(owner);

  @override
  GoalAutoContinueTrackerSnapshot clearPendingRepairContract(
    ChatTurnOwner owner,
  ) => _registry.update(owner, pendingRepairContractOutcome: false);

  @override
  void removeTracker(ChatTurnOwner owner) => _registry.removeTracker(owner);
}

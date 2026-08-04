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
    required ChatTurnOwner owner,
  }) : _registry = registry,
       _owner = owner;

  final GoalAutoContinueTrackerRegistry _registry;
  final ChatTurnOwner _owner;

  @override
  GoalAutoContinueTrackerSnapshot get snapshot => _registry.create(_owner);

  @override
  GoalAutoContinueTrackerSnapshot applyDelta(
    GoalAutoContinueTrackerDelta delta,
  ) => _registry.update(
    _owner,
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
  bool markBudgetNoticePresented() =>
      _registry.markBudgetNoticePresented(_owner);

  @override
  GoalAutoContinueTrackerSnapshot clearPendingRepairContract() =>
      _registry.update(_owner, pendingRepairContractOutcome: false);

  @override
  void removeTracker() => _registry.removeTracker(_owner);
}

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';
import 'turn_runtime.dart';
import 'turn_runtime_conversation_goal_adapter.dart';
import 'turn_runtime_goal_tracker_adapter.dart';

/// Creates the owner-bound ports for one turn.
///
/// Binders are where identity enters the boundary, once per turn, instead of
/// on every port call.
abstract interface class TurnRuntimeOwnerLeaseBinder {
  TurnRuntimeOwnerLeasePort leaseFor(ChatTurnOwner owner);
}

abstract interface class TurnRuntimeGoalSafeBoundaryBinder {
  TurnRuntimeGoalSafeBoundaryPort boundaryFor(ChatTurnOwner owner);
}

// ChatNotifier decomposition collaborator: turn-runtime-goal-continuation-ports-factory
/// Binds the long-lived goal-continuation collaborators to one owner.
///
/// This is the single place identity enters the runtime boundary. Ports built
/// here never re-take the owner, so a turn cannot address another turn's state
/// by passing a different one.
final class TurnRuntimeGoalContinuationPortsFactory {
  const TurnRuntimeGoalContinuationPortsFactory({
    required TurnRuntimeOwnerLeaseBinder ownerLease,
    required TurnRuntimeConversationGoalStore conversationGoalStore,
    required GoalAutoContinueTrackerRegistry trackerRegistry,
    required TurnRuntimeGoalSafeBoundaryBinder safeBoundary,
  }) : _ownerLease = ownerLease,
       _conversationGoalStore = conversationGoalStore,
       _trackerRegistry = trackerRegistry,
       _safeBoundary = safeBoundary;

  final TurnRuntimeOwnerLeaseBinder _ownerLease;
  final TurnRuntimeConversationGoalStore _conversationGoalStore;
  final GoalAutoContinueTrackerRegistry _trackerRegistry;
  final TurnRuntimeGoalSafeBoundaryBinder _safeBoundary;

  TurnRuntimeGoalContinuationPorts portsFor(
    ChatTurnOwner owner, {
    required TurnRuntimeGoalContinuationLogPort log,
  }) => TurnRuntimeGoalContinuationPorts(
    ownerLease: _ownerLease.leaseFor(owner),
    conversationGoal: TurnRuntimeConversationGoalAdapter(
      store: _conversationGoalStore,
      owner: owner,
    ),
    tracker: TurnRuntimeGoalTrackerAdapter(
      registry: _trackerRegistry,
      owner: owner,
    ),
    safeBoundary: _safeBoundary.boundaryFor(owner),
    log: log,
  );
}

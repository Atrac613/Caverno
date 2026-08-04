import '../../application/runtime/turn_runtime.dart';
import '../../application/runtime/turn_runtime_conversation_goal_adapter.dart';
import '../../application/runtime/turn_runtime_goal_continuation_ports_factory.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/turn_runtime_goal_continuation_log_adapter.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';

// ChatNotifier decomposition collaborator: turn-runtime-production-composition
/// Builds owner-scoped goal-continuation runtimes from production boundaries.
final class TurnRuntimeProductionComposition {
  TurnRuntimeProductionComposition({
    required TurnRuntimeOwnerLeaseBinder ownerLease,
    required TurnRuntimeConversationGoalStore conversationGoalStore,
    required GoalAutoContinueTrackerRegistry trackerRegistry,
    required TurnRuntimeGoalSafeBoundaryBinder safeBoundary,
    required TurnRuntimeGoalContinuationLifecycle goalContinuationLifecycle,
  }) : _ports = TurnRuntimeGoalContinuationPortsFactory(
         ownerLease: ownerLease,
         conversationGoalStore: conversationGoalStore,
         trackerRegistry: trackerRegistry,
         safeBoundary: safeBoundary,
       ),
       _goalContinuationLifecycle = goalContinuationLifecycle;

  // The collaborators stay long-lived; the factory binds ports over them per
  // owner, so no port re-takes the owner on every call.
  final TurnRuntimeGoalContinuationPortsFactory _ports;
  final TurnRuntimeGoalContinuationLifecycle _goalContinuationLifecycle;

  bool get isGoalContinuationScheduling =>
      _goalContinuationLifecycle.isScheduling;

  TurnRuntimeProductionScope create({
    required ChatTurnOwner owner,
    required bool loggingSettingsEnabled,
    Map<String, String>? loggingEnvironment,
    DateTime Function()? clock,
  }) {
    final log = TurnRuntimeGoalContinuationLogAdapter(
      settingsEnabled: loggingSettingsEnabled,
      environment: loggingEnvironment,
      clock: clock,
    );
    final runtime = TurnRuntime(
      owner: owner,
      goalContinuation: _ports.portsFor(owner, log: log),
    );
    return TurnRuntimeProductionScope._(
      runtime: runtime,
      log: log,
      goalContinuationLifecycle: _goalContinuationLifecycle,
    );
  }
}

/// One short-lived owner scope produced by the composition root.
final class TurnRuntimeProductionScope {
  const TurnRuntimeProductionScope._({
    required this.runtime,
    required TurnRuntimeGoalContinuationLogAdapter log,
    required TurnRuntimeGoalContinuationLifecycle goalContinuationLifecycle,
  }) : _log = log,
       _goalContinuationLifecycle = goalContinuationLifecycle;

  final TurnRuntime runtime;
  final TurnRuntimeGoalContinuationLogAdapter _log;
  final TurnRuntimeGoalContinuationLifecycle _goalContinuationLifecycle;

  bool get loggingEnabled => _log.isEnabled;

  bool claimGoalContinuationScheduling() {
    if (_goalContinuationLifecycle.claim(runtime)) return true;
    runtime.endGoalContinuationScheduling();
    return false;
  }

  void releaseGoalContinuationScheduling() {
    _goalContinuationLifecycle.release(runtime);
  }

  void configureLogging({
    required LlmSessionLogStore logStore,
    required LlmSessionLogContext context,
  }) {
    _log.configure(logStore: logStore, context: context);
  }
}

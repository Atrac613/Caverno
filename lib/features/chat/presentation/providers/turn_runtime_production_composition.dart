import '../../application/runtime/turn_runtime.dart';
import '../../application/runtime/turn_runtime_conversation_goal_adapter.dart';
import '../../application/runtime/turn_runtime_goal_tracker_adapter.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/turn_runtime_goal_continuation_log_adapter.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';

/// Builds owner-scoped goal-continuation runtimes from production boundaries.
final class TurnRuntimeProductionComposition {
  TurnRuntimeProductionComposition({
    required TurnRuntimeOwnerLeasePort ownerLease,
    required TurnRuntimeConversationGoalStore conversationGoalStore,
    required GoalAutoContinueTrackerRegistry trackerRegistry,
    required TurnRuntimeGoalSafeBoundaryPort safeBoundary,
  }) : _ownerLease = ownerLease,
       _conversationGoal = TurnRuntimeConversationGoalAdapter(
         store: conversationGoalStore,
       ),
       _tracker = TurnRuntimeGoalTrackerAdapter(registry: trackerRegistry),
       _safeBoundary = safeBoundary;

  final TurnRuntimeOwnerLeasePort _ownerLease;
  final TurnRuntimeConversationGoalPort _conversationGoal;
  final TurnRuntimeGoalTrackerPort _tracker;
  final TurnRuntimeGoalSafeBoundaryPort _safeBoundary;

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
      goalContinuation: TurnRuntimeGoalContinuationPorts(
        ownerLease: _ownerLease,
        conversationGoal: _conversationGoal,
        tracker: _tracker,
        safeBoundary: _safeBoundary,
        log: log,
      ),
    );
    return TurnRuntimeProductionScope._(runtime: runtime, log: log);
  }
}

/// One short-lived owner scope produced by the composition root.
final class TurnRuntimeProductionScope {
  const TurnRuntimeProductionScope._({
    required this.runtime,
    required TurnRuntimeGoalContinuationLogAdapter log,
  }) : _log = log;

  final TurnRuntime runtime;
  final TurnRuntimeGoalContinuationLogAdapter _log;

  bool get loggingEnabled => _log.isEnabled;

  void configureLogging({
    required LlmSessionLogStore logStore,
    required LlmSessionLogContext context,
  }) {
    _log.configure(logStore: logStore, context: context);
  }
}

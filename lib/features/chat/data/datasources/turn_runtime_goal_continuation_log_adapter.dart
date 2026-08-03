import '../../application/runtime/turn_runtime.dart';
import '../../domain/services/goal_continuation_log_record_builder.dart';
import 'llm_session_log_store.dart';

/// Persists typed goal-continuation decisions in the existing session log.
final class TurnRuntimeGoalContinuationLogAdapter
    implements TurnRuntimeGoalContinuationLogPort {
  TurnRuntimeGoalContinuationLogAdapter({
    required LlmSessionLogStore logStore,
    required LlmSessionLogContext context,
    required bool settingsEnabled,
    Map<String, String>? environment,
    DateTime Function()? clock,
  }) : _logStore = logStore,
       _context = context,
       _enabled = loggingEnabled(
         settingsEnabled: settingsEnabled,
         environment: environment,
       ),
       _clock = clock ?? DateTime.now;

  final LlmSessionLogStore _logStore;
  final LlmSessionLogContext _context;
  final bool _enabled;
  final DateTime Function() _clock;

  static bool loggingEnabled({
    required bool settingsEnabled,
    Map<String, String>? environment,
  }) => LlmSessionLogStore.isEnabled(
    settingsEnabled: settingsEnabled,
    environment: environment,
  );

  @override
  Future<void> record(GoalAutoContinueLogRecord record) async {
    if (!_enabled) return;
    await _logStore.recordGoalAutoContinue(
      context: _context,
      decision: record.decision,
      reason: record.reason,
      at: _clock(),
      goalId: record.goalId,
      nextTurnNumber: record.nextTurnNumber,
      effectiveTurnBudget: record.effectiveTurnBudget,
      consecutiveAutoContinuations: record.consecutiveAutoContinuations,
      evidence: record.evidence,
    );
  }
}

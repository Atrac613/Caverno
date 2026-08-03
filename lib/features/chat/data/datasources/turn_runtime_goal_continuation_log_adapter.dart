import '../../application/runtime/turn_runtime.dart';
import '../../domain/services/goal_continuation_log_record_builder.dart';
import 'llm_session_log_store.dart';

/// Persists typed goal-continuation decisions in the existing session log.
final class TurnRuntimeGoalContinuationLogAdapter
    implements TurnRuntimeGoalContinuationLogPort {
  factory TurnRuntimeGoalContinuationLogAdapter({
    LlmSessionLogStore? logStore,
    LlmSessionLogContext? context,
    required bool settingsEnabled,
    Map<String, String>? environment,
    DateTime Function()? clock,
  }) {
    final enabled = loggingEnabled(
      settingsEnabled: settingsEnabled,
      environment: environment,
    );
    return TurnRuntimeGoalContinuationLogAdapter._(
      logStore: logStore,
      context: context,
      enabled: enabled,
      clock: clock ?? DateTime.now,
    );
  }

  TurnRuntimeGoalContinuationLogAdapter._({
    required LlmSessionLogStore? logStore,
    required LlmSessionLogContext? context,
    required bool enabled,
    required DateTime Function() clock,
  }) : _logStore = logStore,
       _context = context,
       _enabled = enabled,
       _clock = clock;

  LlmSessionLogStore? _logStore;
  LlmSessionLogContext? _context;
  final bool _enabled;
  final DateTime Function() _clock;

  bool get isEnabled => _enabled;

  void configure({
    required LlmSessionLogStore logStore,
    required LlmSessionLogContext context,
  }) {
    if (!_enabled) return;
    _logStore = logStore;
    _context = context;
  }

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
    final logStore = _logStore;
    final context = _context;
    if (logStore == null || context == null) {
      throw StateError('Enabled continuation logging is not configured.');
    }
    await logStore.recordGoalAutoContinue(
      context: context,
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

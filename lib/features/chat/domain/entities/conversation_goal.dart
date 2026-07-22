import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_goal.freezed.dart';
part 'conversation_goal.g.dart';

enum ConversationGoalStatus {
  active,
  completed,
  blocked,

  /// The harness ran out of work but cannot say the objective was met.
  ///
  /// Set when goal auto-continue stops with `noRemainingWork`: no incomplete
  /// evidence, no outstanding validation, nothing scheduled. The absence of
  /// evidence of incompleteness is not evidence of completion — a turn that
  /// did nothing also leaves nothing incomplete — so the harness must not
  /// close the goal itself. It says what it knows instead, and the user
  /// completes or reactivates from the goal menu.
  ///
  /// Counts as active for [ConversationGoal.isActive]: the goal is live, it
  /// simply has nothing queued. The next turn resets it, so a resumed goal
  /// never keeps a stale "waiting" label.
  awaitingConfirmation,
}

@freezed
abstract class ConversationGoal with _$ConversationGoal {
  const ConversationGoal._();

  const factory ConversationGoal({
    required String id,
    @Default('') String objective,
    @Default(true) bool enabled,
    @Default(false) bool autoContinue,
    @JsonKey(unknownEnumValue: ConversationGoalStatus.active)
    @Default(ConversationGoalStatus.active)
    ConversationGoalStatus status,
    @Default(0) int tokenBudget,
    @Default(0) int tokenUsage,
    @Default(0) int turnBudget,
    @Default(0) int turnsUsed,
    @Default('') String completionSummary,
    @Default('') String blockedReason,
    @Default('') String blockerSignature,
    @Default(0) int blockerRepeatCount,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
    DateTime? blockedAt,
    DateTime? lastBlockerSeenAt,
  }) = _ConversationGoal;

  factory ConversationGoal.fromJson(Map<String, dynamic> json) =>
      _$ConversationGoalFromJson(json);

  String? get normalizedObjective {
    final trimmed = objective.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedCompletionSummary {
    final trimmed = completionSummary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedBlockedReason {
    final trimmed = blockedReason.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get hasObjective => normalizedObjective != null;

  bool get isActive =>
      enabled &&
      (status == ConversationGoalStatus.active ||
          status == ConversationGoalStatus.awaitingConfirmation) &&
      hasObjective;

  /// The harness has nothing left to schedule and is waiting for the user to
  /// say whether the objective was met.
  bool get isAwaitingConfirmation =>
      enabled &&
      status == ConversationGoalStatus.awaitingConfirmation &&
      hasObjective;

  bool get hasTokenBudget => tokenBudget > 0;

  bool get hasTurnBudget => turnBudget > 0;

  int? get remainingTokenBudget {
    if (!hasTokenBudget) {
      return null;
    }
    final remaining = tokenBudget - tokenUsage;
    return remaining < 0 ? 0 : remaining;
  }

  int? get remainingTurnBudget {
    if (!hasTurnBudget) {
      return null;
    }
    final remaining = turnBudget - turnsUsed;
    return remaining < 0 ? 0 : remaining;
  }

  bool get tokenBudgetExceeded => hasTokenBudget && tokenUsage >= tokenBudget;

  bool get turnBudgetExceeded => hasTurnBudget && turnsUsed >= turnBudget;

  bool get budgetExceeded => tokenBudgetExceeded || turnBudgetExceeded;
}

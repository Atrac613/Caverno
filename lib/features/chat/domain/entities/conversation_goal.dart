import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_goal.freezed.dart';
part 'conversation_goal.g.dart';

enum ConversationGoalStatus { active, completed, blocked }

@freezed
abstract class ConversationGoal with _$ConversationGoal {
  const ConversationGoal._();

  const factory ConversationGoal({
    required String id,
    @Default('') String objective,
    @Default(true) bool enabled,
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
      enabled && status == ConversationGoalStatus.active && hasObjective;

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

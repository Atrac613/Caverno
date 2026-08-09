import 'package:flutter/material.dart';

import '../../domain/entities/conversation_goal.dart';

/// How a [ConversationGoalStatus] is shown: its translation key, its colour
/// role, and its icon.
///
/// The label mapping was duplicated across the goal chip, the goal builders and
/// the slash-command coordinator, so adding a status meant finding all three.
/// One home means the compiler's exhaustiveness check fires once, on the
/// mapping that actually owns the decision.
abstract final class ConversationGoalStatusPresentation {
  /// Translation key, un-translated so callers that build plain strings (the
  /// slash-command coordinator) and callers that translate inline both work.
  static String labelKey(ConversationGoalStatus status) {
    return switch (status) {
      ConversationGoalStatus.active => 'chat.goal_status_active',
      ConversationGoalStatus.completed => 'chat.goal_status_completed',
      ConversationGoalStatus.blocked => 'chat.goal_status_blocked',
      ConversationGoalStatus.awaitingConfirmation =>
        'chat.goal_status_awaiting_confirmation',
    };
  }

  static Color color(ColorScheme colors, ConversationGoalStatus status) {
    return switch (status) {
      ConversationGoalStatus.active => colors.primary,
      ConversationGoalStatus.completed => colors.tertiary,
      ConversationGoalStatus.blocked => colors.error,
      // Deliberately not the completed colour. The harness has not decided the
      // goal is done — it has stopped scheduling and is asking.
      ConversationGoalStatus.awaitingConfirmation => colors.secondary,
    };
  }

  static IconData icon(ConversationGoalStatus status) {
    return switch (status) {
      ConversationGoalStatus.active => Icons.play_circle_outline,
      ConversationGoalStatus.completed => Icons.check_circle_outline,
      ConversationGoalStatus.blocked => Icons.block_outlined,
      ConversationGoalStatus.awaitingConfirmation => Icons.help_outline,
    };
  }
}

extension ConversationGoalStatusPresentationAccess on ConversationGoalStatus {
  bool get allowsUserResolution =>
      this == ConversationGoalStatus.active ||
      this == ConversationGoalStatus.awaitingConfirmation;
}

extension ConversationGoalConfirmationPresentation on ConversationGoal {
  List<Widget> confirmationSummaryWidgets(ThemeData theme) {
    final summary = normalizedCompletionSummary;
    if (!isAwaitingConfirmation || summary == null) return const [];
    return [
      const SizedBox(height: 2),
      Text(
        summary,
        key: const ValueKey('coding-goal-confirmation-summary'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.secondary,
        ),
      ),
    ];
  }
}

enum ConversationGoalMenuAction { complete, block, reactivate, clear }

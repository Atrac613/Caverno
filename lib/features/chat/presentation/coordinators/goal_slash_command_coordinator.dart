import 'package:easy_localization/easy_localization.dart' show NumberFormat;

import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../widgets/conversation_goal_status_presentation.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../providers/conversations_notifier.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_catalog.dart';

const _slashGoalObjectiveMaxLength = 120;

final class GoalSlashCommandCoordinator {
  GoalSlashCommandCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required Future<void> Function(Conversation conversation) showGoalEditor,
    required void Function(String objective) sendInitialPrompt,
    required SlashCommandTextResolver text,
  }) : _conversationsNotifier = conversationsNotifier,
       _showGoalEditor = showGoalEditor,
       _sendInitialPrompt = sendInitialPrompt,
       _text = text;

  final ConversationsNotifier _conversationsNotifier;
  final Future<void> Function(Conversation conversation) _showGoalEditor;
  final void Function(String objective) _sendInitialPrompt;
  final SlashCommandTextResolver _text;

  Future<SlashCommandExecutionResult> handle({
    required Conversation currentConversation,
    required String args,
    required bool sendObjectiveAsInitialPrompt,
  }) async {
    final trimmedArgs = args.trim();
    final goal = currentConversation.goal;
    final hasGoal = goal?.hasObjective ?? false;

    if (trimmedArgs.isEmpty) {
      if (!hasGoal) {
        await _showGoalEditor(currentConversation);
        return SlashCommandExecutionResult.handled;
      }
      final objective = _truncateObjective(goal!.normalizedObjective!);
      return SlashCommandExecutionResult(
        feedbackMessage: _text(
          'chat.slash_goal_status',
          namedArgs: {'objective': objective, 'status': _statusSummary(goal)},
        ),
      );
    }

    final keyword = trimmedArgs.toLowerCase();
    final keywordTokens = keyword
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    switch (keyword) {
      case 'pause':
        if (!hasGoal) {
          return _noGoalResult();
        }
        await _conversationsNotifier.setCurrentGoalEnabled(false);
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.slash_goal_paused'),
        );
      case 'resume':
        if (!hasGoal) {
          return _noGoalResult();
        }
        await _conversationsNotifier.setCurrentGoalEnabled(true);
        if (goal!.status != ConversationGoalStatus.active) {
          await _conversationsNotifier.markCurrentGoalStatus(
            status: ConversationGoalStatus.active,
          );
        }
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.slash_goal_resumed'),
        );
      case 'clear':
        if (!hasGoal) {
          return _noGoalResult();
        }
        await _conversationsNotifier.clearCurrentGoal();
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.goal_cleared'),
        );
    }

    if (keywordTokens.length == 2 &&
        keywordTokens.first == 'auto' &&
        (keywordTokens.last == 'on' || keywordTokens.last == 'off')) {
      if (!hasGoal) {
        return _noGoalResult();
      }
      final enableAutoContinue = keywordTokens.last == 'on';
      await _conversationsNotifier.saveCurrentGoal(
        objective: goal!.normalizedObjective!,
        enabled: goal.enabled,
        autoContinue: enableAutoContinue,
        status: goal.status,
        tokenBudget: goal.tokenBudget,
        turnBudget: goal.turnBudget,
      );
      return SlashCommandExecutionResult(
        feedbackMessage: _text(
          enableAutoContinue
              ? 'chat.goal_auto_continue_enabled'
              : 'chat.goal_auto_continue_disabled',
        ),
      );
    }

    if (keywordTokens.isNotEmpty &&
        keywordTokens.first == 'auto' &&
        (keywordTokens.length == 1 || keywordTokens.length == 2)) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_goal_auto_usage'),
      );
    }

    final trailingAutoMatch = RegExp(
      r'\s+auto\s+(on|off)\s*$',
      caseSensitive: false,
    ).firstMatch(trimmedArgs);
    final objective = trailingAutoMatch == null
        ? trimmedArgs
        : trimmedArgs.substring(0, trailingAutoMatch.start).trim();
    final trailingAutoContinue = trailingAutoMatch == null
        ? null
        : trailingAutoMatch.group(1)!.toLowerCase() == 'on';

    await _conversationsNotifier.saveCurrentGoal(
      objective: objective,
      enabled: true,
      autoContinue: trailingAutoContinue ?? (goal == null ? true : null),
      status: ConversationGoalStatus.active,
      tokenBudget: goal?.tokenBudget ?? 0,
      turnBudget: goal?.turnBudget ?? 0,
    );
    final feedbackMessage = trailingAutoContinue == null
        ? _text(
            'chat.slash_goal_set',
            namedArgs: {'objective': _truncateObjective(objective)},
          )
        : _text(
            'chat.slash_goal_set_auto',
            namedArgs: {
              'objective': _truncateObjective(objective),
              'auto': _text(
                trailingAutoContinue
                    ? 'chat.goal_auto_continue_on'
                    : 'chat.goal_auto_continue_off',
              ),
            },
          );
    if (sendObjectiveAsInitialPrompt) {
      _sendInitialPrompt(objective);
    }
    return SlashCommandExecutionResult(feedbackMessage: feedbackMessage);
  }

  SlashCommandExecutionResult _noGoalResult() {
    return SlashCommandExecutionResult.keepInput(
      feedbackMessage: _text('chat.slash_goal_none'),
    );
  }

  String _truncateObjective(String objective) {
    final normalized = objective.trim();
    if (normalized.length <= _slashGoalObjectiveMaxLength) {
      return normalized;
    }
    return '${normalized.substring(0, _slashGoalObjectiveMaxLength - 3).trimRight()}...';
  }

  String _statusSummary(ConversationGoal goal) {
    final status = goal.enabled
        ? _statusLabel(goal.status)
        : _text(
            'chat.slash_goal_status_paused',
            namedArgs: {'status': _statusLabel(goal.status)},
          );
    final tokenUsage = goal.hasTokenBudget
        ? _text(
            'chat.goal_token_budget_label',
            namedArgs: {
              'used': _formatTokenCount(goal.tokenUsage),
              'total': _formatTokenCount(goal.tokenBudget),
            },
          )
        : _text(
            'chat.slash_goal_token_usage_unlimited',
            namedArgs: {'used': _formatTokenCount(goal.tokenUsage)},
          );
    final turnUsage = goal.hasTurnBudget
        ? _text(
            'chat.goal_turn_budget_label',
            namedArgs: {
              'used': goal.turnsUsed.toString(),
              'total': goal.turnBudget.toString(),
            },
          )
        : _text(
            'chat.slash_goal_turn_usage_unlimited',
            namedArgs: {'used': goal.turnsUsed.toString()},
          );
    final effectiveAutoContinueBudget = goal.hasTurnBudget
        ? goal.turnBudget
        : kGoalAutoContinueDefaultTurnBudget;
    final autoContinue = goal.autoContinue
        ? _text(
            'chat.goal_auto_continue_running',
            namedArgs: {
              'count': goal.turnsUsed.toString(),
              'total': effectiveAutoContinueBudget.toString(),
            },
          )
        : _text('chat.goal_auto_continue_off');
    return _text(
      'chat.slash_goal_status_details',
      namedArgs: {
        'status': status,
        'tokens': tokenUsage,
        'turns': turnUsage,
        'auto': autoContinue,
      },
    );
  }

  String _statusLabel(ConversationGoalStatus status) =>
      _text(ConversationGoalStatusPresentation.labelKey(status));

  String _formatTokenCount(int count) {
    if (count.abs() < 1000) {
      return count.toString();
    }
    return NumberFormat.compact().format(count);
  }
}

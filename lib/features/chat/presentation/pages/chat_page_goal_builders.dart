part of 'chat_page.dart';

const _slashGoalObjectiveMaxLength = 120;

extension _ChatPageGoalBuilders on _ChatPageState {
  Future<void> _showGoalEditor(
    BuildContext context,
    Conversation currentConversation, {
    String? initialObjective,
    String? helperText,
  }) async {
    final result = await showModalBottomSheet<_GoalEditorSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _GoalEditorSheet(
        currentConversation: currentConversation,
        initialObjective: initialObjective,
        helperText: helperText,
      ),
    );
    if (result == null) {
      return;
    }

    final notifier = ref.read(conversationsNotifierProvider.notifier);
    switch (result.action) {
      case _GoalEditorAction.clear:
        await notifier.clearCurrentGoal();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('chat.goal_cleared'.tr())));
        }
      case _GoalEditorAction.save:
        await notifier.saveCurrentGoal(
          objective: result.objective,
          enabled: result.enabled,
          status: result.status,
          autoContinue: result.autoContinue,
          tokenBudget: result.tokenBudget,
          turnBudget: result.turnBudget,
        );
    }
  }

  Future<SlashCommandExecutionResult> _handleGoalSlashCommand(
    BuildContext context,
    Conversation currentConversation,
    String args, {
    required bool sendObjectiveAsInitialPrompt,
  }) async {
    final trimmedArgs = args.trim();
    final goal = currentConversation.goal;
    final hasGoal = goal?.hasObjective ?? false;
    final notifier = ref.read(conversationsNotifierProvider.notifier);

    if (trimmedArgs.isEmpty) {
      if (!hasGoal) {
        await _showGoalEditor(context, currentConversation);
        return SlashCommandExecutionResult.handled;
      }
      final objective = _truncateGoalSlashObjective(goal!.normalizedObjective!);
      return SlashCommandExecutionResult(
        feedbackMessage: 'chat.slash_goal_status'.tr(
          namedArgs: {
            'objective': objective,
            'status': _goalSlashStatusSummary(goal),
          },
        ),
      );
    }

    final keyword = trimmedArgs.toLowerCase();
    final keywordTokens = keyword
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    // Treat only exact reserved-keyword arguments as subcommands; longer text
    // such as "pause the deployment" remains a normal objective.
    switch (keyword) {
      case 'pause':
        if (!hasGoal) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_goal_none'.tr(),
          );
        }
        await notifier.setCurrentGoalEnabled(false);
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_goal_paused'.tr(),
        );
      case 'resume':
        if (!hasGoal) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_goal_none'.tr(),
          );
        }
        await notifier.setCurrentGoalEnabled(true);
        if (goal!.status != ConversationGoalStatus.active) {
          await notifier.markCurrentGoalStatus(
            status: ConversationGoalStatus.active,
          );
        }
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_goal_resumed'.tr(),
        );
      case 'clear':
        if (!hasGoal) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_goal_none'.tr(),
          );
        }
        await notifier.clearCurrentGoal();
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.goal_cleared'.tr(),
        );
    }

    if (keywordTokens.length == 2 &&
        keywordTokens.first == 'auto' &&
        (keywordTokens.last == 'on' || keywordTokens.last == 'off')) {
      if (!hasGoal) {
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_goal_none'.tr(),
        );
      }
      final enableAutoContinue = keywordTokens.last == 'on';
      await notifier.saveCurrentGoal(
        objective: goal!.normalizedObjective!,
        enabled: goal.enabled,
        autoContinue: enableAutoContinue,
        status: goal.status,
        tokenBudget: goal.tokenBudget,
        turnBudget: goal.turnBudget,
      );
      return SlashCommandExecutionResult(
        feedbackMessage:
            (enableAutoContinue
                    ? 'chat.goal_auto_continue_enabled'
                    : 'chat.goal_auto_continue_disabled')
                .tr(),
      );
    }

    if (keywordTokens.isNotEmpty &&
        keywordTokens.first == 'auto' &&
        (keywordTokens.length == 1 || keywordTokens.length == 2)) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_goal_auto_usage'.tr(),
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

    await notifier.saveCurrentGoal(
      objective: objective,
      enabled: true,
      autoContinue: trailingAutoContinue ?? (goal == null ? true : null),
      status: ConversationGoalStatus.active,
      tokenBudget: goal?.tokenBudget ?? 0,
      turnBudget: goal?.turnBudget ?? 0,
    );
    final feedbackMessage = trailingAutoContinue == null
        ? 'chat.slash_goal_set'.tr(
            namedArgs: {'objective': _truncateGoalSlashObjective(objective)},
          )
        : 'chat.slash_goal_set_auto'.tr(
            namedArgs: {
              'objective': _truncateGoalSlashObjective(objective),
              'auto': trailingAutoContinue
                  ? 'chat.goal_auto_continue_on'.tr()
                  : 'chat.goal_auto_continue_off'.tr(),
            },
          );
    if (sendObjectiveAsInitialPrompt) {
      final languageCode = context.mounted ? context.locale.languageCode : 'en';
      unawaited(
        ref
            .read(chatNotifierProvider.notifier)
            .sendMessage(objective, languageCode: languageCode),
      );
      return SlashCommandExecutionResult(feedbackMessage: feedbackMessage);
    }
    return SlashCommandExecutionResult(feedbackMessage: feedbackMessage);
  }

  Future<void> _markGoalCompleted(BuildContext context) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .markCurrentGoalStatus(
          status: ConversationGoalStatus.completed,
          completionSummary: 'Marked complete by the user.',
        );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.goal_completed'.tr())));
    }
  }

  Future<void> _markGoalBlocked(
    BuildContext context,
    ConversationGoal goal,
  ) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .markCurrentGoalStatus(
          status: ConversationGoalStatus.blocked,
          blockedReason:
              goal.normalizedBlockedReason ?? 'Marked blocked by the user.',
        );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.goal_blocked'.tr())));
    }
  }

  Future<void> _reactivateGoal(BuildContext context) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .markCurrentGoalStatus(status: ConversationGoalStatus.active);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.goal_reactivated'.tr())));
    }
  }

  Future<void> _clearGoal(BuildContext context) async {
    await ref.read(conversationsNotifierProvider.notifier).clearCurrentGoal();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.goal_cleared'.tr())));
    }
  }
}

enum _GoalEditorAction { save, clear }

class _GoalEditorSubmission {
  const _GoalEditorSubmission.save({
    required this.objective,
    required this.enabled,
    required this.autoContinue,
    required this.status,
    required this.tokenBudget,
    required this.turnBudget,
  }) : action = _GoalEditorAction.save;

  const _GoalEditorSubmission.clear()
    : action = _GoalEditorAction.clear,
      objective = '',
      enabled = false,
      autoContinue = false,
      status = ConversationGoalStatus.active,
      tokenBudget = 0,
      turnBudget = 0;

  final _GoalEditorAction action;
  final String objective;
  final bool enabled;
  final bool autoContinue;
  final ConversationGoalStatus status;
  final int tokenBudget;
  final int turnBudget;
}

class _GoalEditorSheet extends StatefulWidget {
  const _GoalEditorSheet({
    required this.currentConversation,
    this.initialObjective,
    this.helperText,
  });

  final Conversation currentConversation;
  final String? initialObjective;
  final String? helperText;

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  late final TextEditingController _objectiveController;
  late final TextEditingController _tokenBudgetController;
  late final TextEditingController _turnBudgetController;
  late bool _enabled;
  late bool _autoContinue;
  late ConversationGoalStatus _status;

  @override
  void initState() {
    super.initState();
    final goal = widget.currentConversation.goal;
    _objectiveController = TextEditingController(
      text: widget.initialObjective?.trim().isNotEmpty == true
          ? widget.initialObjective!.trim()
          : goal?.normalizedObjective ?? '',
    );
    _tokenBudgetController = TextEditingController(
      text: (goal?.tokenBudget ?? 0) > 0 ? goal!.tokenBudget.toString() : '',
    );
    _turnBudgetController = TextEditingController(
      text: (goal?.turnBudget ?? 0) > 0 ? goal!.turnBudget.toString() : '',
    );
    _enabled = goal?.enabled ?? true;
    _autoContinue = goal?.autoContinue ?? true;
    _status = goal?.status ?? ConversationGoalStatus.active;
  }

  @override
  void dispose() {
    _objectiveController.dispose();
    _tokenBudgetController.dispose();
    _turnBudgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'chat.goal_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.helperText?.trim().isNotEmpty == true) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.helperText!.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _objectiveController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.goal_objective'.tr(),
                  hintText: 'chat.goal_objective_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _enabled,
                contentPadding: EdgeInsets.zero,
                title: Text('chat.goal_enabled'.tr()),
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
              SwitchListTile(
                value: _autoContinue,
                contentPadding: EdgeInsets.zero,
                title: Text('chat.goal_auto_continue'.tr()),
                subtitle: Text('chat.goal_auto_continue_hint'.tr()),
                onChanged: (value) {
                  setState(() {
                    _autoContinue = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<ConversationGoalStatus>(
                initialValue: _status,
                decoration: InputDecoration(
                  labelText: 'chat.goal_status'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationGoalStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_conversationGoalStatusLabel(status)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _status = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenBudgetController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'chat.goal_token_budget'.tr(),
                        hintText: 'chat.goal_budget_unlimited'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _turnBudgetController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'chat.goal_turn_budget'.tr(),
                        hintText: 'chat.goal_budget_unlimited'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(const _GoalEditorSubmission.clear());
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text('common.clear'.tr()),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _GoalEditorSubmission.save(
                          objective: _objectiveController.text.trim(),
                          enabled: _enabled,
                          autoContinue: _autoContinue,
                          status: _status,
                          tokenBudget: _parseBudget(
                            _tokenBudgetController.text,
                          ),
                          turnBudget: _parseBudget(_turnBudgetController.text),
                        ),
                      );
                    },
                    child: Text('common.save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _parseBudget(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      return 0;
    }
    return parsed;
  }
}

String _truncateGoalSlashObjective(String objective) {
  final normalized = objective.trim();
  if (normalized.length <= _slashGoalObjectiveMaxLength) {
    return normalized;
  }
  return '${normalized.substring(0, _slashGoalObjectiveMaxLength - 3).trimRight()}...';
}

String _goalSlashStatusSummary(ConversationGoal goal) {
  final status = goal.enabled
      ? _conversationGoalStatusLabel(goal.status)
      : 'chat.slash_goal_status_paused'.tr(
          namedArgs: {'status': _conversationGoalStatusLabel(goal.status)},
        );
  final tokenUsage = goal.hasTokenBudget
      ? 'chat.goal_token_budget_label'.tr(
          namedArgs: {
            'used': _formatGoalSlashTokenCount(goal.tokenUsage),
            'total': _formatGoalSlashTokenCount(goal.tokenBudget),
          },
        )
      : 'chat.slash_goal_token_usage_unlimited'.tr(
          namedArgs: {'used': _formatGoalSlashTokenCount(goal.tokenUsage)},
        );
  final turnUsage = goal.hasTurnBudget
      ? 'chat.goal_turn_budget_label'.tr(
          namedArgs: {
            'used': goal.turnsUsed.toString(),
            'total': goal.turnBudget.toString(),
          },
        )
      : 'chat.slash_goal_turn_usage_unlimited'.tr(
          namedArgs: {'used': goal.turnsUsed.toString()},
        );
  final effectiveAutoContinueBudget = goal.hasTurnBudget
      ? goal.turnBudget
      : kGoalAutoContinueDefaultTurnBudget;
  final autoContinue = goal.autoContinue
      ? 'chat.goal_auto_continue_running'.tr(
          namedArgs: {
            'count': goal.turnsUsed.toString(),
            'total': effectiveAutoContinueBudget.toString(),
          },
        )
      : 'chat.goal_auto_continue_off'.tr();
  return 'chat.slash_goal_status_details'.tr(
    namedArgs: {
      'status': status,
      'tokens': tokenUsage,
      'turns': turnUsage,
      'auto': autoContinue,
    },
  );
}

String _formatGoalSlashTokenCount(int count) {
  if (count.abs() < 1000) {
    return count.toString();
  }
  return NumberFormat.compact().format(count);
}

String _conversationGoalStatusLabel(ConversationGoalStatus status) {
  return switch (status) {
    ConversationGoalStatus.active => 'chat.goal_status_active'.tr(),
    ConversationGoalStatus.completed => 'chat.goal_status_completed'.tr(),
    ConversationGoalStatus.blocked => 'chat.goal_status_blocked'.tr(),
  };
}

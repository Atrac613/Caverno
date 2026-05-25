part of 'chat_page.dart';

extension _ChatPageGoalBuilders on _ChatPageState {
  Widget _buildGoalFooterCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
  }) {
    final theme = Theme.of(context);
    final goal = currentConversation.goal;
    final hasGoal = goal?.hasObjective ?? false;
    final isActive = goal?.isActive ?? false;
    final status = goal?.status ?? ConversationGoalStatus.active;
    final statusColor = _conversationGoalStatusColor(theme, status);
    final budgetLabel = hasGoal ? _conversationGoalBudgetLabel(goal!) : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: hasGoal ? 0.45 : 0.28,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: hasGoal ? 0.42 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.goal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasGoal) ...[
                Chip(
                  label: Text(_conversationGoalStatusLabel(status)),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: statusColor.withValues(alpha: 0.35)),
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 8),
              ],
              Switch(
                value: isActive,
                onChanged: chatState.isLoading
                    ? null
                    : (value) => _handleGoalSwitch(
                        context,
                        currentConversation,
                        value,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasGoal ? goal!.normalizedObjective! : 'chat.goal_empty'.tr(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hasGoal
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: hasGoal ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (hasGoal && budgetLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              budgetLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: goal!.budgetExceeded
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: chatState.isLoading
                    ? null
                    : () => _showGoalEditor(context, currentConversation),
                icon: Icon(hasGoal ? Icons.edit_outlined : Icons.add),
                label: Text(
                  hasGoal ? 'common.edit'.tr() : 'chat.goal_set'.tr(),
                ),
              ),
              if (hasGoal && status == ConversationGoalStatus.active)
                TextButton.icon(
                  onPressed: chatState.isLoading
                      ? null
                      : () => _markGoalCompleted(context),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('chat.goal_mark_complete'.tr()),
                ),
              if (hasGoal && status == ConversationGoalStatus.active)
                TextButton.icon(
                  onPressed: chatState.isLoading
                      ? null
                      : () => _markGoalBlocked(context, goal!),
                  icon: const Icon(Icons.block_outlined),
                  label: Text('chat.goal_mark_blocked'.tr()),
                ),
              if (hasGoal && status != ConversationGoalStatus.active)
                TextButton.icon(
                  onPressed: chatState.isLoading
                      ? null
                      : () => _reactivateGoal(context),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text('chat.goal_reactivate'.tr()),
                ),
              if (hasGoal)
                TextButton.icon(
                  onPressed: chatState.isLoading
                      ? null
                      : () => _clearGoal(context),
                  icon: const Icon(Icons.close),
                  label: Text('common.clear'.tr()),
                ),
            ],
          ),
          if (hasGoal &&
              status == ConversationGoalStatus.completed &&
              goal!.normalizedCompletionSummary != null) ...[
            const SizedBox(height: 6),
            Text(
              goal.normalizedCompletionSummary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (hasGoal &&
              status == ConversationGoalStatus.blocked &&
              goal!.normalizedBlockedReason != null) ...[
            const SizedBox(height: 6),
            Text(
              goal.normalizedBlockedReason!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleGoalSwitch(
    BuildContext context,
    Conversation currentConversation,
    bool enabled,
  ) async {
    final goal = currentConversation.goal;
    final notifier = ref.read(conversationsNotifierProvider.notifier);
    if (goal == null || !goal.hasObjective) {
      if (enabled) {
        await _showGoalEditor(context, currentConversation);
      }
      return;
    }

    if (!enabled) {
      await notifier.setCurrentGoalEnabled(false);
      return;
    }

    if (goal.status != ConversationGoalStatus.active) {
      await notifier.markCurrentGoalStatus(
        status: ConversationGoalStatus.active,
      );
      return;
    }

    await notifier.setCurrentGoalEnabled(true);
  }

  Future<void> _showGoalEditor(
    BuildContext context,
    Conversation currentConversation,
  ) async {
    final result = await showModalBottomSheet<_GoalEditorSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _GoalEditorSheet(currentConversation: currentConversation),
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
          tokenBudget: result.tokenBudget,
          turnBudget: result.turnBudget,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('chat.goal_saved'.tr())));
        }
    }
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

  String _conversationGoalBudgetLabel(ConversationGoal goal) {
    final parts = <String>[];
    if (goal.hasTokenBudget) {
      parts.add(
        'chat.goal_token_budget_label'.tr(
          namedArgs: {
            'used': _formatTokenCount(goal.tokenUsage),
            'total': _formatTokenCount(goal.tokenBudget),
          },
        ),
      );
    }
    if (goal.hasTurnBudget) {
      parts.add(
        'chat.goal_turn_budget_label'.tr(
          namedArgs: {
            'used': goal.turnsUsed.toString(),
            'total': goal.turnBudget.toString(),
          },
        ),
      );
    }
    return parts.join('  ');
  }
}

enum _GoalEditorAction { save, clear }

class _GoalEditorSubmission {
  const _GoalEditorSubmission.save({
    required this.objective,
    required this.enabled,
    required this.status,
    required this.tokenBudget,
    required this.turnBudget,
  }) : action = _GoalEditorAction.save;

  const _GoalEditorSubmission.clear()
    : action = _GoalEditorAction.clear,
      objective = '',
      enabled = false,
      status = ConversationGoalStatus.active,
      tokenBudget = 0,
      turnBudget = 0;

  final _GoalEditorAction action;
  final String objective;
  final bool enabled;
  final ConversationGoalStatus status;
  final int tokenBudget;
  final int turnBudget;
}

class _GoalEditorSheet extends StatefulWidget {
  const _GoalEditorSheet({required this.currentConversation});

  final Conversation currentConversation;

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  late final TextEditingController _objectiveController;
  late final TextEditingController _tokenBudgetController;
  late final TextEditingController _turnBudgetController;
  late bool _enabled;
  late ConversationGoalStatus _status;

  @override
  void initState() {
    super.initState();
    final goal = widget.currentConversation.goal;
    _objectiveController = TextEditingController(
      text: goal?.normalizedObjective ?? '',
    );
    _tokenBudgetController = TextEditingController(
      text: (goal?.tokenBudget ?? 0) > 0 ? goal!.tokenBudget.toString() : '',
    );
    _turnBudgetController = TextEditingController(
      text: (goal?.turnBudget ?? 0) > 0 ? goal!.turnBudget.toString() : '',
    );
    _enabled = goal?.enabled ?? true;
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

String _conversationGoalStatusLabel(ConversationGoalStatus status) {
  return switch (status) {
    ConversationGoalStatus.active => 'chat.goal_status_active'.tr(),
    ConversationGoalStatus.completed => 'chat.goal_status_completed'.tr(),
    ConversationGoalStatus.blocked => 'chat.goal_status_blocked'.tr(),
  };
}

Color _conversationGoalStatusColor(
  ThemeData theme,
  ConversationGoalStatus status,
) {
  return switch (status) {
    ConversationGoalStatus.active => theme.colorScheme.primary,
    ConversationGoalStatus.completed => theme.colorScheme.tertiary,
    ConversationGoalStatus.blocked => theme.colorScheme.error,
  };
}

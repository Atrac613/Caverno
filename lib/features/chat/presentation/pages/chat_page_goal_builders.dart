part of 'chat_page.dart';

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

String _conversationGoalStatusLabel(ConversationGoalStatus status) {
  return switch (status) {
    ConversationGoalStatus.active => 'chat.goal_status_active'.tr(),
    ConversationGoalStatus.completed => 'chat.goal_status_completed'.tr(),
    ConversationGoalStatus.blocked => 'chat.goal_status_blocked'.tr(),
  };
}

part of 'chat_page.dart';

extension _ChatPageGoalBuilders on _ChatPageState {
  bool _isCodingGoalSetupPendingFor(Conversation? conversation) {
    return conversation != null &&
        _pendingCodingGoalConversationId == conversation.id &&
        !(conversation.goal?.hasObjective ?? false);
  }

  bool _isCodingGoalSuggestionInProgressFor(Conversation? conversation) {
    return conversation != null &&
        _codingGoalSuggestionConversationId == conversation.id;
  }

  void _clearCodingGoalSuggestionInProgress(String conversationId) {
    if (_codingGoalSuggestionConversationId != conversationId) {
      return;
    }
    _setCodingGoalSuggestionConversationId(null);
  }

  void _clearCodingGoalSetupPending(String conversationId) {
    if (_pendingCodingGoalConversationId != conversationId) {
      return;
    }
    _setPendingCodingGoalConversationId(null);
  }

  void _deferGoalSetupUntilSend(Conversation currentConversation) {
    if (!_isCodingGoalSetupPendingFor(currentConversation)) {
      _setPendingCodingGoalConversationId(currentConversation.id);
    }
  }

  Future<bool> _sendMessageAfterPendingGoalSetup(
    BuildContext context, {
    required Conversation currentConversation,
    required String message,
    required String? imageBase64,
    required String? imageMimeType,
    required String languageCode,
  }) async {
    if (_isCodingGoalSuggestionInProgressFor(currentConversation)) {
      return false;
    }
    final appliedGoal = await _applySuggestedGoal(
      context,
      currentConversation,
      pendingUserMessage: message,
    );
    if (appliedGoal) {
      _clearCodingGoalSetupPending(currentConversation.id);
    } else {
      return false;
    }
    if (!mounted) {
      return false;
    }
    final activeConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (activeConversation?.id != currentConversation.id) {
      return false;
    }
    await ref
        .read(chatNotifierProvider.notifier)
        .sendMessage(
          message,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          languageCode: languageCode,
        );
    return true;
  }

  Future<void> _handleGoalSwitch(
    BuildContext context,
    Conversation currentConversation,
    bool enabled, {
    String? pendingUserMessage,
  }) async {
    if (_isCodingGoalSuggestionInProgressFor(currentConversation)) {
      return;
    }
    final goal = currentConversation.goal;
    final notifier = ref.read(conversationsNotifierProvider.notifier);
    if (goal == null || !goal.hasObjective) {
      if (enabled) {
        _clearCodingGoalSetupPending(currentConversation.id);
        final appliedGoal = await _applySuggestedGoal(
          context,
          currentConversation,
          pendingUserMessage: pendingUserMessage,
        );
        if (!appliedGoal) {
          _setPendingCodingGoalConversationId(currentConversation.id);
        }
      } else {
        _clearCodingGoalSetupPending(currentConversation.id);
      }
      return;
    }

    if (!enabled) {
      _clearCodingGoalSetupPending(currentConversation.id);
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
    Conversation currentConversation, {
    String? initialObjective,
    String? helperText,
  }) async {
    if (_isCodingGoalSuggestionInProgressFor(currentConversation)) {
      return;
    }
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

    _clearCodingGoalSetupPending(currentConversation.id);
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
    }
  }

  Future<bool> _applySuggestedGoal(
    BuildContext context,
    Conversation currentConversation, {
    String? pendingUserMessage,
  }) async {
    if (_isCodingGoalSuggestionInProgressFor(currentConversation)) {
      return false;
    }
    _setCodingGoalSuggestionConversationId(currentConversation.id);
    try {
      final suggestion = await _requestGoalSuggestion(
        context,
        pendingUserMessage: pendingUserMessage,
      );
      if (suggestion == null || !context.mounted) {
        return false;
      }

      return _applyGoalSuggestion(
        context,
        currentConversation,
        suggestion,
        pendingUserMessage: pendingUserMessage,
        remainingClarificationDialogs: 2,
      );
    } finally {
      _clearCodingGoalSuggestionInProgress(currentConversation.id);
    }
  }

  Future<ConversationGoalSuggestion?> _requestGoalSuggestion(
    BuildContext context, {
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
  }) async {
    final languageCode = context.locale.languageCode;

    try {
      final suggestion = await ref
          .read(chatNotifierProvider.notifier)
          .suggestCurrentGoal(
            languageCode: languageCode,
            pendingUserMessage: pendingUserMessage,
            clarificationQuestion: clarificationQuestion,
            clarificationAnswer: clarificationAnswer,
          );
      if (!context.mounted) {
        return null;
      }

      return suggestion;
    } catch (error) {
      debugPrint('Goal suggestion failed: $error');
    }

    if (context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('chat.goal_suggestion_failed'.tr()),
        ),
      );
    }
    return null;
  }

  Future<bool> _applyGoalSuggestion(
    BuildContext context,
    Conversation currentConversation,
    ConversationGoalSuggestion suggestion, {
    required String? pendingUserMessage,
    required int remainingClarificationDialogs,
  }) async {
    switch (suggestion.kind) {
      case ConversationGoalSuggestionKind.suggested:
        final objective = suggestion.objective?.trim() ?? '';
        if (objective.isEmpty) {
          _showGoalClarificationSnackBar(
            context,
            'chat.goal_suggestion_question'.tr(),
          );
          return false;
        }
        final activeConversation = ref
            .read(conversationsNotifierProvider)
            .currentConversation;
        if (activeConversation?.id != currentConversation.id) {
          return false;
        }
        await ref
            .read(conversationsNotifierProvider.notifier)
            .saveCurrentGoal(
              objective: objective,
              enabled: true,
              status: ConversationGoalStatus.active,
            );
        return true;
      case ConversationGoalSuggestionKind.needsClarification:
        final question = suggestion.question?.trim();
        final effectiveQuestion = question?.isNotEmpty == true
            ? question!
            : 'chat.goal_suggestion_question'.tr();
        if (remainingClarificationDialogs <= 0) {
          _showGoalClarificationSnackBar(context, effectiveQuestion);
          return false;
        }
        final answer = await _showGoalClarificationDialog(
          context,
          effectiveQuestion,
        );
        if (!context.mounted) {
          return false;
        }
        if (answer == null || answer.trim().isEmpty) {
          return false;
        }
        final retrySuggestion = await _requestGoalSuggestion(
          context,
          pendingUserMessage: pendingUserMessage,
          clarificationQuestion: effectiveQuestion,
          clarificationAnswer: answer,
        );
        if (retrySuggestion == null || !context.mounted) {
          return false;
        }
        return _applyGoalSuggestion(
          context,
          currentConversation,
          retrySuggestion,
          pendingUserMessage: pendingUserMessage,
          remainingClarificationDialogs: remainingClarificationDialogs - 1,
        );
    }
  }

  Future<String?> _showGoalClarificationDialog(
    BuildContext context,
    String question,
  ) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _GoalClarificationDialog(question: question),
    );
  }

  void _showGoalClarificationSnackBar(BuildContext context, String question) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'chat.goal_needs_clarification'.tr(
              namedArgs: {'question': question},
            ),
          ),
        ),
      );
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

class _GoalClarificationDialog extends StatefulWidget {
  const _GoalClarificationDialog({required this.question});

  final String question;

  @override
  State<_GoalClarificationDialog> createState() =>
      _GoalClarificationDialogState();
}

class _GoalClarificationDialogState extends State<_GoalClarificationDialog> {
  late final TextEditingController _controller;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _controller.text.trim();
    if (answer.isEmpty) {
      return;
    }
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('chat.goal_clarification_title'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.question),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'chat.goal_clarification_answer'.tr(),
                hintText: 'chat.goal_clarification_answer_hint'.tr(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final nextCanSubmit = value.trim().isNotEmpty;
                if (nextCanSubmit == _canSubmit) {
                  return;
                }
                setState(() {
                  _canSubmit = nextCanSubmit;
                });
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text('chat.goal_clarification_confirm'.tr()),
        ),
      ],
    );
  }
}

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

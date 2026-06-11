part of 'chat_page.dart';

class _PlanExecutionOverview {
  const _PlanExecutionOverview({
    required this.titleKey,
    required this.descriptionKey,
  });

  final String titleKey;
  final String descriptionKey;
}

class _PlanExecutionOverviewCard extends StatelessWidget {
  const _PlanExecutionOverviewCard({
    required this.title,
    required this.description,
    required this.completedLabel,
    required this.pendingLabel,
    required this.pendingCount,
    required this.inProgressLabel,
    required this.inProgressCount,
    required this.blockedLabel,
    required this.blockedCount,
  });

  final String title;
  final String description;
  final String completedLabel;
  final String pendingLabel;
  final int pendingCount;
  final String inProgressLabel;
  final int inProgressCount;
  final String blockedLabel;
  final int blockedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PlanExecutionCountChip(label: completedLabel),
            _PlanExecutionCountChip(
              label: '$inProgressLabel: $inProgressCount',
            ),
            _PlanExecutionCountChip(label: '$blockedLabel: $blockedCount'),
            _PlanExecutionCountChip(label: '$pendingLabel: $pendingCount'),
          ],
        ),
      ],
    );
  }
}

class _PlanExecutionCountChip extends StatelessWidget {
  const _PlanExecutionCountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

enum _WorkflowEditorAction { save, clear }

class _WorkflowEditorSubmission {
  const _WorkflowEditorSubmission.save({
    required this.workflowStage,
    required this.workflowSpec,
  }) : action = _WorkflowEditorAction.save;

  const _WorkflowEditorSubmission.clear()
    : action = _WorkflowEditorAction.clear,
      workflowStage = ConversationWorkflowStage.idle,
      workflowSpec = const ConversationWorkflowSpec();

  final _WorkflowEditorAction action;
  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowSpec workflowSpec;
}

class _WorkflowEditorSheet extends StatefulWidget {
  const _WorkflowEditorSheet({
    required this.currentConversation,
    this.initialWorkflowStage,
    this.initialWorkflowSpec,
    required this.workflowStageLabelBuilder,
  });

  final Conversation currentConversation;
  final ConversationWorkflowStage? initialWorkflowStage;
  final ConversationWorkflowSpec? initialWorkflowSpec;
  final String Function(ConversationWorkflowStage stage)
  workflowStageLabelBuilder;

  @override
  State<_WorkflowEditorSheet> createState() => _WorkflowEditorSheetState();
}

class _WorkflowEditorSheetState extends State<_WorkflowEditorSheet> {
  late final TextEditingController _goalController;
  late final TextEditingController _constraintsController;
  late final TextEditingController _acceptanceController;
  late final TextEditingController _openQuestionsController;
  late ConversationWorkflowStage _selectedStage;

  @override
  void initState() {
    super.initState();
    final spec =
        widget.initialWorkflowSpec ??
        widget.currentConversation.effectiveWorkflowSpec;
    _selectedStage =
        widget.initialWorkflowStage ?? widget.currentConversation.workflowStage;
    _goalController = TextEditingController(text: spec.goal);
    _constraintsController = TextEditingController(
      text: spec.constraints.join('\n'),
    );
    _acceptanceController = TextEditingController(
      text: spec.acceptanceCriteria.join('\n'),
    );
    _openQuestionsController = TextEditingController(
      text: spec.openQuestions.join('\n'),
    );
  }

  @override
  void dispose() {
    _goalController.dispose();
    _constraintsController.dispose();
    _acceptanceController.dispose();
    _openQuestionsController.dispose();
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
                'chat.workflow_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.workflow_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<ConversationWorkflowStage>(
                initialValue: _selectedStage,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_stage'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationWorkflowStage.values
                    .map(
                      (stage) => DropdownMenuItem(
                        value: stage,
                        child: Text(widget.workflowStageLabelBuilder(stage)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStage = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _goalController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_goal'.tr(),
                  hintText: 'chat.workflow_goal_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _constraintsController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_constraints'.tr(),
                  hintText: 'chat.workflow_constraints_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _acceptanceController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_acceptance'.tr(),
                  hintText: 'chat.workflow_acceptance_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _openQuestionsController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_open_questions'.tr(),
                  hintText: 'chat.workflow_open_questions_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(const _WorkflowEditorSubmission.clear());
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text('chat.workflow_clear'.tr()),
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
                        _WorkflowEditorSubmission.save(
                          workflowStage: _selectedStage,
                          workflowSpec: ConversationWorkflowSpec(
                            goal: _goalController.text.trim(),
                            constraints: _workflowLinesFromText(
                              _constraintsController.text,
                            ),
                            acceptanceCriteria: _workflowLinesFromText(
                              _acceptanceController.text,
                            ),
                            openQuestions: _workflowLinesFromText(
                              _openQuestionsController.text,
                            ),
                            tasks: widget
                                .currentConversation
                                .effectiveWorkflowSpec
                                .tasks,
                          ),
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
}

enum _WorkflowTaskMenuAction {
  markPending,
  markInProgress,
  markCompleted,
  markBlocked,
  markUnblocked,
  editBlockedReason,
  replanFromBlocker,
  edit,
  delete,
}

enum _WorkflowTaskEditorAction { save, delete }

class _WorkflowTaskEditorSubmission {
  const _WorkflowTaskEditorSubmission.save({required this.task})
    : action = _WorkflowTaskEditorAction.save;

  const _WorkflowTaskEditorSubmission.delete({required this.task})
    : action = _WorkflowTaskEditorAction.delete;

  final _WorkflowTaskEditorAction action;
  final ConversationWorkflowTask task;
}

class _WorkflowTaskEditorSheet extends StatefulWidget {
  const _WorkflowTaskEditorSheet({
    required this.task,
    required this.statusLabelBuilder,
  });

  final ConversationWorkflowTask? task;
  final String Function(ConversationWorkflowTaskStatus status)
  statusLabelBuilder;

  @override
  State<_WorkflowTaskEditorSheet> createState() =>
      _WorkflowTaskEditorSheetState();
}

class _WorkflowTaskEditorSheetState extends State<_WorkflowTaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _targetFilesController;
  late final TextEditingController _validationController;
  late final TextEditingController _notesController;
  late ConversationWorkflowTaskStatus _selectedStatus;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _selectedStatus = task?.status ?? ConversationWorkflowTaskStatus.pending;
    _titleController = TextEditingController(text: task?.title ?? '');
    _targetFilesController = TextEditingController(
      text: task?.targetFiles.join('\n') ?? '',
    );
    _validationController = TextEditingController(
      text: task?.validationCommand ?? '',
    );
    _notesController = TextEditingController(text: task?.notes ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetFilesController.dispose();
    _validationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingTask = widget.task;
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
                existingTask == null
                    ? 'chat.workflow_task_add'.tr()
                    : 'chat.workflow_task_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.workflow_task_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_title'.tr(),
                  hintText: 'chat.workflow_task_title_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ConversationWorkflowTaskStatus>(
                initialValue: _selectedStatus,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_status'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationWorkflowTaskStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(widget.statusLabelBuilder(status)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStatus = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _targetFilesController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_target_files'.tr(),
                  hintText: 'chat.workflow_task_target_files_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _validationController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_validation'.tr(),
                  hintText: 'chat.workflow_task_validation_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_notes'.tr(),
                  hintText: 'chat.workflow_task_notes_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (existingTask != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          _WorkflowTaskEditorSubmission.delete(
                            task: existingTask,
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text('chat.workflow_task_delete'.tr()),
                    ),
                  if (existingTask != null) const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _WorkflowTaskEditorSubmission.save(
                          task: ConversationWorkflowTask(
                            id: existingTask?.id ?? '',
                            title: _titleController.text.trim(),
                            status: _selectedStatus,
                            targetFiles: _workflowLinesFromText(
                              _targetFilesController.text,
                            ),
                            validationCommand: _validationController.text
                                .trim(),
                            notes: _notesController.text.trim(),
                          ),
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
}

class _WorkflowDecisionSheet extends StatefulWidget {
  const _WorkflowDecisionSheet({
    required this.pending,
    this.initialFreeText,
    this.titleText,
  });

  final PendingWorkflowDecision pending;
  final String? initialFreeText;
  final String? titleText;

  @override
  State<_WorkflowDecisionSheet> createState() => _WorkflowDecisionSheetState();
}

class _WorkflowDecisionSheetState extends State<_WorkflowDecisionSheet> {
  late final TextEditingController _textController;
  WorkflowPlanningDecisionOption? _selectedOption;

  bool get _isFreeTextDecision =>
      widget.pending.decision.allowFreeText ||
      widget.pending.decision.options.isEmpty;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialFreeText ?? '');
    _selectedOption = _isFreeTextDecision
        ? null
        : widget.pending.decision.options.firstOrNull;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _buildAnswer();
    if (answer == null) return;
    Navigator.pop(context, answer);
  }

  WorkflowPlanningDecisionAnswer? _buildAnswer() {
    if (_isFreeTextDecision) {
      final answerText = _textController.text.trim();
      if (answerText.isEmpty) {
        return null;
      }
      return WorkflowPlanningDecisionAnswer(
        decisionId: widget.pending.decision.id,
        question: widget.pending.decision.question,
        optionId: 'free_text',
        optionLabel: answerText,
      );
    }

    final selectedOption = _selectedOption;
    if (selectedOption == null) {
      return null;
    }
    return WorkflowPlanningDecisionAnswer(
      decisionId: widget.pending.decision.id,
      question: widget.pending.decision.question,
      optionId: selectedOption.id,
      optionLabel: selectedOption.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helpText = widget.pending.decision.help.trim().isNotEmpty
        ? widget.pending.decision.help.trim()
        : 'chat.workflow_decision_subtitle'.tr();
    final submitEnabled = _buildAnswer() != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.alt_route_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.titleText?.trim().isNotEmpty == true
                                  ? widget.titleText!.trim()
                                  : 'chat.workflow_decision_title'.tr(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              helpText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, null),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.pending.decision.question,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (widget.pending.decision.help
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.pending.decision.help.trim(),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isFreeTextDecision)
                          TextField(
                            controller: _textController,
                            autofocus: true,
                            minLines: 2,
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText:
                                  widget.pending.decision.freeTextPlaceholder
                                      .trim()
                                      .isEmpty
                                  ? 'chat.workflow_decision_input_placeholder'
                                        .tr()
                                  : widget.pending.decision.freeTextPlaceholder
                                        .trim(),
                              filled: true,
                              fillColor: theme
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          )
                        else
                          ...widget.pending.decision.options.map(
                            (option) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: _selectedOption?.id == option.id
                                    ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.65)
                                    : theme.colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _selectedOption = option;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _selectedOption?.id == option.id
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                          size: 20,
                                          color:
                                              _selectedOption?.id == option.id
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(option.label),
                                              if (option.description
                                                  .trim()
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  option.description.trim(),
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text('common.cancel'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: submitEnabled ? _submit : null,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: Text('chat.workflow_decision_confirm'.tr()),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AskUserQuestionSheet extends StatefulWidget {
  const _AskUserQuestionSheet({required this.pending});

  final PendingAskUserQuestion pending;

  @override
  State<_AskUserQuestionSheet> createState() => _AskUserQuestionSheetState();
}

class _AskUserQuestionSheetState extends State<_AskUserQuestionSheet> {
  late final TextEditingController _otherController;
  final Set<String> _selectedOptionIds = <String>{};
  bool _useOther = false;

  @override
  void initState() {
    super.initState();
    _otherController = TextEditingController();
    _useOther = widget.pending.options.isEmpty && widget.pending.allowOther;
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _toggleOption(String optionId) {
    setState(() {
      if (widget.pending.allowMultiple) {
        if (!_selectedOptionIds.add(optionId)) {
          _selectedOptionIds.remove(optionId);
        }
        return;
      }
      _selectedOptionIds
        ..clear()
        ..add(optionId);
      _useOther = false;
    });
  }

  void _toggleOther() {
    if (!widget.pending.allowOther) return;
    setState(() {
      _useOther = !_useOther;
      if (_useOther && !widget.pending.allowMultiple) {
        _selectedOptionIds.clear();
      }
    });
  }

  AskUserQuestionAnswer? _buildAnswer() {
    final selectedOptions = widget.pending.options
        .where((option) => _selectedOptionIds.contains(option.id))
        .map(
          (option) => AskUserQuestionSelection(
            id: option.id,
            label: option.label,
            description: option.description,
            preview: option.preview,
          ),
        )
        .toList(growable: false);
    final otherText = _useOther ? _otherController.text.trim() : '';
    final answer = AskUserQuestionAnswer(
      question: widget.pending.question,
      selectedOptions: selectedOptions,
      otherText: otherText,
    );
    return answer.hasAnswer ? answer : null;
  }

  void _submit() {
    final answer = _buildAnswer();
    if (answer == null) return;
    Navigator.pop(context, answer);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helpText = widget.pending.help.trim();
    final submitEnabled = _buildAnswer() != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.84,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.help_outline_rounded,
                          color: theme.colorScheme.onSecondaryContainer,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Question from assistant',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.pending.allowMultiple
                                  ? 'Select one or more options.'
                                  : 'Select an option to continue.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, null),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.pending.question,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (helpText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            helpText,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 640;
                            final cardWidth = twoColumns
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final option in widget.pending.options)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildOptionCard(theme, option),
                                  ),
                                if (widget.pending.allowOther)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _buildOtherCard(theme),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Skip'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: submitEnabled ? _submit : null,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Send answer'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard(ThemeData theme, AskUserQuestionOption option) {
    final selected = _selectedOptionIds.contains(option.id);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleOption(option.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    widget.pending.allowMultiple
                        ? (selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded)
                        : (selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off),
                    size: 20,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (option.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  option.description.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (option.preview.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Text(
                    option.preview.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtherCard(ThemeData theme) {
    return Material(
      color: _useOther
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggleOther,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.pending.allowMultiple
                        ? (_useOther
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded)
                        : (_useOther
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off),
                    size: 20,
                    color: _useOther
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Other',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _otherController,
                minLines: 2,
                maxLines: 4,
                enabled: _useOther,
                decoration: InputDecoration(
                  hintText: widget.pending.otherPlaceholder.trim().isEmpty
                      ? 'Type another answer'
                      : widget.pending.otherPlaceholder.trim(),
                  filled: true,
                  fillColor: theme.colorScheme.surface.withValues(alpha: 0.65),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onTap: () {
                  if (!_useOther) {
                    _toggleOther();
                  }
                },
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<String> _workflowLinesFromText(String rawValue) {
  return rawValue
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class _WorkflowQuickAction {
  const _WorkflowQuickAction({
    required this.labelKey,
    required this.icon,
    required this.targetStage,
    required this.promptKey,
  });

  final String labelKey;
  final IconData icon;
  final ConversationWorkflowStage targetStage;
  final String promptKey;
}

class _ComputerUseRiskStyle {
  const _ComputerUseRiskStyle({
    required this.icon,
    required this.warningIcon,
    required this.approveIcon,
    required this.containerColor,
    required this.iconColor,
    required this.accentColor,
    required this.buttonColor,
    required this.buttonForegroundColor,
  });

  final IconData icon;
  final IconData warningIcon;
  final IconData approveIcon;
  final Color containerColor;
  final Color iconColor;
  final Color accentColor;
  final Color buttonColor;
  final Color buttonForegroundColor;
}

const List<_WorkflowQuickAction> _workflowQuickActions = [
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_clarify',
    icon: Icons.help_outline,
    targetStage: ConversationWorkflowStage.clarify,
    promptKey: 'chat.workflow_quick_clarify_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_plan',
    icon: Icons.route_outlined,
    targetStage: ConversationWorkflowStage.plan,
    promptKey: 'chat.workflow_quick_plan_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_tasks',
    icon: Icons.checklist_rtl,
    targetStage: ConversationWorkflowStage.tasks,
    promptKey: 'chat.workflow_quick_tasks_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_implement',
    icon: Icons.play_circle_outline,
    targetStage: ConversationWorkflowStage.implement,
    promptKey: 'chat.workflow_quick_implement_prompt',
  ),
  _WorkflowQuickAction(
    labelKey: 'chat.workflow_quick_review',
    icon: Icons.fact_check_outlined,
    targetStage: ConversationWorkflowStage.review,
    promptKey: 'chat.workflow_quick_review_prompt',
  ),
];

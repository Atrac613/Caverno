// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPageWorkflowBuilders on _ChatPageState {
  // ignore: unused_element
  Widget _buildWorkflowPanel(
    BuildContext context,
    Conversation currentConversation,
    ChatState chatState, {
    required bool isPlanMode,
  }) {
    final theme = Theme.of(context);
    final spec = currentConversation.effectiveWorkflowSpec;
    final planArtifact = currentConversation.effectivePlanArtifact;
    final hasContext = currentConversation.hasWorkflowContext;
    final shouldPreferPlanDocument =
        currentConversation.shouldPreferPlanDocument;
    final isBusy = chatState.isLoading;
    final hasPlanDraft =
        chatState.workflowProposalDraft != null ||
        chatState.taskProposalDraft != null ||
        chatState.workflowProposalError != null ||
        chatState.taskProposalError != null ||
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    final showCombinedPlanCard = isPlanMode && hasPlanDraft;
    final conversationId = currentConversation.id;
    if (_workflowPanelConversationId != conversationId) {
      _workflowPanelConversationId = conversationId;
      _isApprovedPlanExpanded = false;
      _wasShowingPlanDraft = hasPlanDraft;
    } else if (_wasShowingPlanDraft &&
        !hasPlanDraft &&
        isPlanMode &&
        hasContext) {
      _isApprovedPlanExpanded = false;
      _wasShowingPlanDraft = false;
    } else {
      _wasShowingPlanDraft = hasPlanDraft;
    }
    final showCompactApprovedPlan =
        isPlanMode && hasContext && !hasPlanDraft && !_isApprovedPlanExpanded;
    final showCompactPlanSupport =
        hasContext &&
        shouldPreferPlanDocument &&
        (!isPlanMode || showCompactApprovedPlan);
    final showWorkflowStageChip =
        currentConversation.workflowStage != ConversationWorkflowStage.idle;
    final workflowPanelMaxHeight =
        (MediaQuery.sizeOf(context).height *
                (showCompactApprovedPlan ? 0.22 : (isPlanMode ? 0.52 : 0.4)))
            .clamp(showCompactApprovedPlan ? 120.0 : 220.0, 480.0)
            .toDouble();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: workflowPanelMaxHeight),
        child: Scrollbar(
          controller: _workflowPanelScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _workflowPanelScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPlanMode
                                ? 'chat.plan_mode_title'.tr()
                                : 'chat.workflow_title'.tr(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPlanMode
                                ? (hasContext
                                      ? 'chat.plan_mode_ready'.tr()
                                      : 'chat.plan_mode_subtitle'.tr())
                                : (hasContext
                                      ? 'chat.workflow_subtitle'.tr()
                                      : 'chat.workflow_empty'.tr()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!isPlanMode && !shouldPreferPlanDocument)
                      IconButton(
                        onPressed: isBusy
                            ? null
                            : () => ref
                                  .read(chatNotifierProvider.notifier)
                                  .generateWorkflowProposal(
                                    languageCode: context.locale.languageCode,
                                  ),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        tooltip: 'chat.workflow_generate'.tr(),
                      ),
                    if (showWorkflowStageChip) ...[
                      Chip(
                        label: Text(
                          _workflowStageLabel(
                            currentConversation.workflowStage,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if ((!isPlanMode || hasContext) &&
                        !shouldPreferPlanDocument)
                      IconButton(
                        onPressed: () =>
                            _showWorkflowEditor(context, currentConversation),
                        icon: Icon(
                          hasContext ? Icons.edit_outlined : Icons.add,
                        ),
                        tooltip: hasContext
                            ? 'chat.workflow_edit'.tr()
                            : 'chat.workflow_add'.tr(),
                      ),
                    if (shouldPreferPlanDocument)
                      IconButton(
                        onPressed: isBusy
                            ? null
                            : () => _showPlanDocumentEditor(
                                context,
                                currentConversation,
                                preferDraft: isPlanMode,
                              ),
                        icon: const Icon(Icons.description_outlined),
                        tooltip: _planDocumentHeaderEditTooltipKey(
                          currentConversation,
                          isPlanMode: isPlanMode,
                        ).tr(),
                      ),
                    if (isPlanMode && hasContext && !hasPlanDraft)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isApprovedPlanExpanded = !_isApprovedPlanExpanded;
                          });
                        },
                        icon: Icon(
                          _isApprovedPlanExpanded
                              ? Icons.unfold_less
                              : Icons.unfold_more,
                        ),
                        tooltip: _isApprovedPlanExpanded
                            ? 'chat.workflow_collapse'.tr()
                            : 'chat.workflow_expand'.tr(),
                      ),
                  ],
                ),
                if (showCombinedPlanCard) ...[
                  const SizedBox(height: 12),
                  _buildPlanProposalCard(
                    context,
                    currentConversation: currentConversation,
                    chatState: chatState,
                  ),
                ] else if (chatState.workflowProposalDraft != null) ...[
                  const SizedBox(height: 12),
                  _buildWorkflowProposalCard(
                    context,
                    currentConversation: currentConversation,
                    proposal: chatState.workflowProposalDraft!,
                    isGenerating: chatState.isGeneratingWorkflowProposal,
                  ),
                ] else if (chatState.workflowProposalError != null) ...[
                  const SizedBox(height: 12),
                  _buildWorkflowProposalErrorCard(
                    context,
                    error: chatState.workflowProposalError!,
                  ),
                ],
                if (!showCombinedPlanCard && planArtifact.hasContent) ...[
                  const SizedBox(height: 12),
                  _buildPlanDocumentCard(
                    context,
                    currentConversation: currentConversation,
                    chatState: chatState,
                    isPlanMode: isPlanMode,
                  ),
                ],
                if (showCompactPlanSupport) ...[
                  const SizedBox(height: 12),
                  _buildCompactWorkflowSummary(
                    context,
                    currentConversation: currentConversation,
                  ),
                ] else if (hasContext && !shouldPreferPlanDocument) ...[
                  if (spec.goal.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildWorkflowTextSection(
                      context,
                      label: 'chat.workflow_goal'.tr(),
                      value: spec.goal.trim(),
                    ),
                  ],
                  _buildWorkflowListSection(
                    context,
                    label: 'chat.workflow_constraints'.tr(),
                    items: spec.constraints,
                  ),
                  _buildWorkflowListSection(
                    context,
                    label: 'chat.workflow_acceptance'.tr(),
                    items: spec.acceptanceCriteria,
                  ),
                  _buildWorkflowListSection(
                    context,
                    label: 'chat.workflow_open_questions'.tr(),
                    items: spec.openQuestions,
                  ),
                ],
                if (hasContext) ...[
                  const SizedBox(height: 16),
                  _buildWorkflowTasksSection(
                    context,
                    currentConversation: currentConversation,
                    chatState: chatState,
                    isPlanMode: isPlanMode,
                  ),
                  if (!isPlanMode) ...[
                    const SizedBox(height: 16),
                    _buildWorkflowQuickActions(
                      context,
                      currentConversation: currentConversation,
                      isBusy: isBusy,
                    ),
                  ],
                ] else if (isPlanMode && !hasPlanDraft) ...[
                  const SizedBox(height: 12),
                  Text(
                    'chat.plan_mode_empty'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkflowTasksSection(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    final theme = Theme.of(context);
    final tasks = currentConversation.projectedExecutionTasks;
    final isBusy = chatState.isLoading;
    final canGenerateTasks =
        currentConversation.effectiveWorkflowSpec.hasContent &&
        !currentConversation.shouldPreferPlanDocument;
    final canEditTasks = !currentConversation.shouldPreferPlanDocument;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'chat.workflow_tasks'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (tasks.isNotEmpty)
              Chip(
                label: Text(
                  'chat.workflow_tasks_count'.tr(
                    namedArgs: {'count': tasks.length.toString()},
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
            const SizedBox(width: 8),
            if (!isPlanMode && chatState.isGeneratingTaskProposal)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!isPlanMode &&
                !currentConversation.shouldPreferPlanDocument)
              IconButton(
                onPressed: !canGenerateTasks || isBusy
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generateTaskProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.auto_awesome_outlined),
                tooltip: 'chat.workflow_tasks_generate'.tr(),
              ),
            if (canEditTasks)
              IconButton(
                onPressed: () => _showWorkflowTaskEditor(
                  context,
                  currentConversation: currentConversation,
                ),
                icon: const Icon(Icons.add_task_outlined),
                tooltip: 'chat.workflow_task_add'.tr(),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!isPlanMode && currentConversation.shouldPreferPlanDocument) ...[
          _buildWorkflowProjectionBanner(
            context,
            currentConversation: currentConversation,
            isBusy: isBusy,
          ),
          const SizedBox(height: 8),
        ],
        if (!isPlanMode && chatState.taskProposalDraft != null) ...[
          _buildWorkflowTaskProposalCard(
            context,
            currentConversation: currentConversation,
            proposal: chatState.taskProposalDraft!,
            isGenerating: chatState.isGeneratingTaskProposal,
          ),
          const SizedBox(height: 8),
        ] else if (!isPlanMode && chatState.taskProposalError != null) ...[
          _buildWorkflowTaskProposalErrorCard(
            context,
            error: chatState.taskProposalError!,
          ),
          const SizedBox(height: 8),
        ],
        if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            child: Text(
              currentConversation.shouldPreferPlanDocument &&
                      currentConversation.needsWorkflowProjectionRefresh
                  ? 'chat.workflow_tasks_refresh_required'.tr()
                  : 'chat.workflow_tasks_empty'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Column(
            children: tasks
                .map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildWorkflowTaskCard(
                      context,
                      currentConversation: currentConversation,
                      task: task,
                      isBusy: isBusy,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildWorkflowProjectionBanner(
    BuildContext context, {
    required Conversation currentConversation,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);
    final labelKey = _workflowProjectionStatusLabelKey(currentConversation);
    final color = _workflowProjectionStatusColor(context, currentConversation);
    final messageKey = currentConversation.isWorkflowProjectionFresh
        ? 'chat.workflow_tasks_projection_fresh'
        : currentConversation.isWorkflowProjectionStale
        ? 'chat.workflow_tasks_projection_stale'
        : 'chat.workflow_tasks_projection_unavailable';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labelKey.tr(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  messageKey.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _refreshExecutionTasksFromPlan(context),
            icon: const Icon(Icons.sync_outlined, size: 18),
            label: Text('chat.plan_document_refresh_tasks'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWorkflowSummary(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final spec = currentConversation.effectiveWorkflowSpec;
    final tasks = currentConversation.projectedExecutionTasks;
    final completedCount = tasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final remainingCount = tasks.length - completedCount;
    final nextTask = tasks.firstWhere(
      (task) => task.status != ConversationWorkflowTaskStatus.completed,
      orElse: () =>
          tasks.firstOrNull ??
          const ConversationWorkflowTask(id: '', title: ''),
    );
    final hasNextTask = nextTask.title.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface.withValues(alpha: 0.45),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spec.goal.trim().isNotEmpty)
            Text(
              spec.goal.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (spec.goal.trim().isNotEmpty) const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  'chat.workflow_tasks_count'.tr(
                    namedArgs: {'count': tasks.length.toString()},
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(
                  '$remainingCount ${'chat.workflow_tasks_remaining'.tr()}',
                ),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(
                  '$completedCount ${'chat.workflow_task_status_completed'.tr()}',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (hasNextTask) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nextTask.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkflowProposalCard(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowProposalDraft proposal,
    required bool isGenerating,
  }) {
    final theme = Theme.of(context);
    final spec = proposal.workflowSpec;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.workflow_proposal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                label: Text(_workflowStageLabel(proposal.workflowStage)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'chat.workflow_proposal_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (spec.goal.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildWorkflowTextSection(
              context,
              label: 'chat.workflow_goal'.tr(),
              value: spec.goal.trim(),
            ),
          ],
          _buildWorkflowListSection(
            context,
            label: 'chat.workflow_constraints'.tr(),
            items: spec.constraints,
          ),
          _buildWorkflowListSection(
            context,
            label: 'chat.workflow_acceptance'.tr(),
            items: spec.acceptanceCriteria,
          ),
          _buildWorkflowListSection(
            context,
            label: 'chat.workflow_open_questions'.tr(),
            items: spec.openQuestions,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _applyWorkflowProposal(
                  context,
                  currentConversation: currentConversation,
                  proposal: proposal,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('chat.workflow_proposal_apply'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: isGenerating
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generateWorkflowProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('chat.workflow_regenerate'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: () => currentConversation.shouldPreferPlanDocument
                    ? _showPlanDocumentEditor(
                        context,
                        currentConversation,
                        preferDraft: true,
                      )
                    : _showWorkflowEditor(
                        context,
                        currentConversation,
                        initialWorkflowStage: proposal.workflowStage,
                        initialWorkflowSpec: proposal.workflowSpec,
                        dismissWorkflowProposalOnSave: true,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  currentConversation.shouldPreferPlanDocument
                      ? 'chat.plan_document_edit_draft'.tr()
                      : 'chat.workflow_edit'.tr(),
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatNotifierProvider.notifier)
                    .dismissWorkflowProposal(),
                child: Text('chat.workflow_dismiss'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowProposalErrorCard(
    BuildContext context, {
    required String error,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.workflow_generate_error'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskProposalCard(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowTaskProposalDraft proposal,
    required bool isGenerating,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.workflow_tasks_proposal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'chat.workflow_tasks_proposal_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final task in proposal.tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• ${task.title}', style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _applyTaskProposal(
                  context,
                  currentConversation: currentConversation,
                  proposal: proposal,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text('chat.workflow_tasks_apply'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: isGenerating
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generateTaskProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('chat.workflow_tasks_regenerate'.tr()),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatNotifierProvider.notifier)
                    .dismissTaskProposal(),
                child: Text('chat.workflow_dismiss'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskProposalErrorCard(
    BuildContext context, {
    required String error,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.workflow_tasks_generate_error'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);
    final progress = currentConversation.executionProgressForTask(task.id);
    final canEditTask = !currentConversation.shouldPreferPlanDocument;
    final canRunTask =
        !isBusy &&
        (!currentConversation.shouldPreferPlanDocument ||
            currentConversation.isWorkflowProjectionFresh);
    final normalizedFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final recoverySuggestions = ConversationExecutionRecoveryService.suggest(
      task: task,
      progress: progress,
    );
    final showValidationRecoveryActions =
        currentConversation.shouldPreferPlanDocument &&
        progress?.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        task.validationCommand.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _workflowTaskStatusColor(
            context,
            task.status,
          ).withValues(alpha: 0.35),
        ),
        color: _workflowTaskStatusColor(
          context,
          task.status,
        ).withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title.trim(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(_workflowTaskStatusLabel(task.status)),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: _workflowTaskStatusColor(
                        context,
                        task.status,
                      ).withValues(alpha: 0.18),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(
                        color: _workflowTaskStatusColor(context, task.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<WorkflowTaskMenuAction>(
                enabled: canEditTask || canRunTask,
                onSelected: (action) => _handleWorkflowTaskMenuAction(
                  context,
                  currentConversation: currentConversation,
                  task: task,
                  action: action,
                ),
                itemBuilder: (context) => [
                  if (task.status != ConversationWorkflowTaskStatus.pending)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.markPending,
                      child: Text('chat.workflow_task_mark_pending'.tr()),
                    ),
                  if (task.status != ConversationWorkflowTaskStatus.inProgress)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.markInProgress,
                      child: Text('chat.workflow_task_mark_in_progress'.tr()),
                    ),
                  if (task.status != ConversationWorkflowTaskStatus.completed)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.markCompleted,
                      child: Text('chat.workflow_task_mark_completed'.tr()),
                    ),
                  if (task.status != ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.markBlocked,
                      child: Text('chat.workflow_task_mark_blocked'.tr()),
                    ),
                  if (currentConversation.shouldPreferPlanDocument &&
                      task.status == ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.markUnblocked,
                      child: Text('chat.workflow_task_mark_unblocked'.tr()),
                    ),
                  if (currentConversation.shouldPreferPlanDocument &&
                      task.status == ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.editBlockedReason,
                      child: Text(
                        'chat.workflow_task_edit_blocked_reason'.tr(),
                      ),
                    ),
                  if (currentConversation.shouldPreferPlanDocument &&
                      task.status == ConversationWorkflowTaskStatus.blocked)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.replanFromBlocker,
                      child: Text(
                        'chat.workflow_task_replan_from_blocker'.tr(),
                      ),
                    ),
                  if (canEditTask)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.edit,
                      child: Text('chat.workflow_task_edit'.tr()),
                    ),
                  if (canEditTask)
                    PopupMenuItem(
                      value: WorkflowTaskMenuAction.delete,
                      child: Text('chat.workflow_task_delete'.tr()),
                    ),
                ],
              ),
            ],
          ),
          if (normalizedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_target_files'.tr(),
              value: normalizedFiles.join(', '),
            ),
          ],
          if (task.validationCommand.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_validation'.tr(),
              value: task.validationCommand.trim(),
              monospace: true,
            ),
          ],
          if (task.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_notes'.tr(),
              value: task.notes.trim(),
            ),
          ],
          if (progress?.normalizedSummary != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_progress_summary'.tr(),
              value: progress!.normalizedSummary!,
            ),
          ],
          if (progress?.normalizedBlockedReason != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_blocked_reason'.tr(),
              value: progress!.normalizedBlockedReason!,
            ),
          ],
          if (progress?.validationStatus != null &&
              progress!.validationStatus !=
                  ConversationExecutionValidationStatus.unknown) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_validation_status'.tr(),
              value: _workflowValidationStatusLabel(progress.validationStatus),
            ),
          ],
          if (progress?.normalizedValidationCommand != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_last_validation_command'.tr(),
              value: progress!.normalizedValidationCommand!,
              monospace: true,
            ),
          ],
          if (progress?.normalizedValidationSummary != null) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskDetail(
              context,
              label: 'chat.workflow_task_validation_summary'.tr(),
              value: progress!.normalizedValidationSummary!,
            ),
          ],
          if (progress != null && progress.recentEvents.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWorkflowTaskTimeline(context, events: progress.recentEvents),
          ],
          if (recoverySuggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildWorkflowTaskRecoverySuggestions(
              context,
              suggestions: recoverySuggestions,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: !canRunTask
                    ? null
                    : () => _runWorkflowTask(
                        context,
                        currentConversation: currentConversation,
                        task: task,
                      ),
                icon: Icon(
                  task.status == ConversationWorkflowTaskStatus.completed
                      ? Icons.fact_check_outlined
                      : Icons.play_circle_outline,
                  size: 18,
                ),
                label: Text(
                  task.status == ConversationWorkflowTaskStatus.completed
                      ? 'chat.workflow_task_review'.tr()
                      : 'chat.workflow_task_use'.tr(),
                ),
              ),
              if (showValidationRecoveryActions)
                OutlinedButton.icon(
                  onPressed: !canRunTask
                      ? null
                      : () => _runWorkflowTaskValidation(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  label: Text('chat.workflow_task_retry_validation'.tr()),
                ),
              if (showValidationRecoveryActions)
                FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _replanValidationPath(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.rule_folder_outlined, size: 18),
                  label: Text('chat.plan_document_replan_validation'.tr()),
                ),
              if (currentConversation.shouldPreferPlanDocument &&
                  task.status == ConversationWorkflowTaskStatus.blocked)
                OutlinedButton.icon(
                  onPressed: !canRunTask
                      ? null
                      : () => _markWorkflowTaskUnblocked(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.lock_open_outlined, size: 18),
                  label: Text('chat.workflow_task_mark_unblocked'.tr()),
                ),
              if (currentConversation.shouldPreferPlanDocument &&
                  task.status == ConversationWorkflowTaskStatus.blocked)
                OutlinedButton.icon(
                  onPressed: !canRunTask
                      ? null
                      : () => _editWorkflowTaskBlockedReason(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.edit_note_outlined, size: 18),
                  label: Text('chat.workflow_task_edit_blocked_reason'.tr()),
                ),
              if (currentConversation.shouldPreferPlanDocument &&
                  task.status == ConversationWorkflowTaskStatus.blocked)
                FilledButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _replanFromBlockedTask(
                          context,
                          currentConversation: currentConversation,
                          task: task,
                        ),
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: Text('chat.workflow_task_replan_from_blocker'.tr()),
                ),
              if (canEditTask)
                OutlinedButton.icon(
                  onPressed: () => _showWorkflowTaskEditor(
                    context,
                    currentConversation: currentConversation,
                    task: task,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('chat.workflow_task_edit'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowTaskRecoverySuggestions(
    BuildContext context, {
    required List<ConversationExecutionRecoverySuggestion> suggestions,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.workflow_task_recovery_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final suggestion in suggestions) ...[
            Text(
              '• ${suggestion.reason}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (suggestion != suggestions.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkflowQuickActions(
    BuildContext context, {
    required Conversation currentConversation,
    required bool isBusy,
  }) {
    final theme = Theme.of(context);
    final recommendedStage = _recommendedWorkflowStage(
      currentConversation.workflowStage,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'chat.workflow_quick_actions'.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _workflowQuickActions
              .map((action) {
                final isRecommended = action.targetStage == recommendedStage;
                return isRecommended
                    ? FilledButton.tonalIcon(
                        onPressed: isBusy
                            ? null
                            : () => _runWorkflowQuickAction(
                                context,
                                action: action,
                              ),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.labelKey.tr()),
                      )
                    : OutlinedButton.icon(
                        onPressed: isBusy
                            ? null
                            : () => _runWorkflowQuickAction(
                                context,
                                action: action,
                              ),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.labelKey.tr()),
                      );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 6),
        Text(
          isBusy
              ? 'chat.workflow_quick_actions_busy'.tr()
              : 'chat.workflow_quick_actions_hint'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowTaskDetail(
    BuildContext context, {
    required String label,
    required String value,
    bool monospace = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: monospace
              ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
              : theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildWorkflowTaskTimeline(
    BuildContext context, {
    required List<ConversationExecutionTaskEvent> events,
  }) {
    final theme = Theme.of(context);
    final recentEvents = events.reversed.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'chat.workflow_task_recent_events'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final event in recentEvents) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  _workflowTaskEventSummary(context, event),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (event != recentEvents.last) const SizedBox(height: 2),
        ],
      ],
    );
  }

  Widget _buildWorkflowTextSection(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildWorkflowListSection(
    BuildContext context, {
    required String label,
    required List<String> items,
  }) {
    final normalizedItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalizedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in normalizedItems)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $item', style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

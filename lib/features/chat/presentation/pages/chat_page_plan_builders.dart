// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPagePlanBuilders on _ChatPageState {
  Widget _buildPlanProposalCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
  }) {
    final theme = Theme.of(context);
    final planArtifact = currentConversation.effectivePlanArtifact;
    final workflowDraft = chatState.workflowProposalDraft;
    final taskDraft = chatState.taskProposalDraft;
    final workflowSpec = workflowDraft?.workflowSpec;
    final isGenerating =
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    final canApprove = workflowDraft != null && taskDraft != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
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
                Icons.route_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.plan_proposal_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (workflowDraft != null)
                Chip(
                  label: Text(_workflowStageLabel(workflowDraft.workflowStage)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'chat.plan_proposal_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (isGenerating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'chat.plan_proposal_generating'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (workflowSpec != null) ...[
            if (workflowSpec.goal.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildWorkflowTextSection(
                context,
                label: 'chat.workflow_goal'.tr(),
                value: workflowSpec.goal.trim(),
              ),
            ],
            _buildWorkflowListSection(
              context,
              label: 'chat.workflow_constraints'.tr(),
              items: workflowSpec.constraints,
            ),
            _buildWorkflowListSection(
              context,
              label: 'chat.workflow_acceptance'.tr(),
              items: workflowSpec.acceptanceCriteria,
            ),
            _buildWorkflowListSection(
              context,
              label: 'chat.workflow_open_questions'.tr(),
              items: workflowSpec.openQuestions,
            ),
          ],
          if (taskDraft != null) ...[
            const SizedBox(height: 12),
            Text(
              'chat.workflow_tasks'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final task in taskDraft.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${task.title}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
          if (planArtifact.hasContent) ...[
            const SizedBox(height: 12),
            _buildPlanDocumentCard(
              context,
              currentConversation: currentConversation,
              chatState: chatState,
              isPlanMode: true,
              showActionBar: false,
            ),
          ],
          if (chatState.workflowProposalError != null) ...[
            const SizedBox(height: 10),
            Text(
              chatState.workflowProposalError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (chatState.taskProposalError != null) ...[
            const SizedBox(height: 10),
            Text(
              chatState.taskProposalError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: canApprove
                    ? () => _approvePlanAndStart(
                        context,
                        currentConversation: currentConversation,
                        workflowDraft: workflowDraft,
                        taskDraft: taskDraft,
                      )
                    : null,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: Text('chat.plan_proposal_approve_start'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: isGenerating
                    ? null
                    : () => ref
                          .read(chatNotifierProvider.notifier)
                          .generatePlanProposal(
                            languageCode: context.locale.languageCode,
                          ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('chat.plan_proposal_regenerate'.tr()),
              ),
              if (workflowDraft != null && !currentConversation.hasPlanArtifact)
                OutlinedButton.icon(
                  onPressed: () => _showWorkflowEditor(
                    context,
                    currentConversation,
                    initialWorkflowStage: workflowDraft.workflowStage,
                    initialWorkflowSpec: workflowDraft.workflowSpec,
                    dismissWorkflowProposalOnSave: true,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('chat.workflow_edit'.tr()),
                ),
              OutlinedButton.icon(
                onPressed: () => _showPlanDocumentEditor(
                  context,
                  currentConversation,
                  preferDraft: true,
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text('chat.plan_document_edit_draft'.tr()),
              ),
              TextButton(
                onPressed: () => ref
                    .read(chatNotifierProvider.notifier)
                    .dismissPlanProposal(),
                child: Text('chat.workflow_dismiss'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approvePlanAndStart(
    BuildContext context, {
    required Conversation currentConversation,
    required WorkflowProposalDraft workflowDraft,
    required WorkflowTaskProposalDraft taskDraft,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final nextTasks = taskDraft.tasks.isEmpty
        ? const <ConversationWorkflowTask>[]
        : taskDraft.tasks.indexed
              .map((entry) {
                final index = entry.$1;
                final task = entry.$2;
                return index == 0
                    ? task.copyWith(
                        status:
                            task.status ==
                                ConversationWorkflowTaskStatus.completed
                            ? task.status
                            : ConversationWorkflowTaskStatus.inProgress,
                      )
                    : task;
              })
              .toList(growable: false);
    final nextSpec = workflowDraft.workflowSpec.copyWith(tasks: nextTasks);
    final initialTask = nextTasks.firstOrNull;
    final approvedWorkflowStage = initialTask == null
        ? ConversationWorkflowStage.tasks
        : ConversationWorkflowStage.implement;
    await _snapshotApprovedPlanDocument(
      workflowDraft: workflowDraft,
      taskDraft: taskDraft.copyWith(tasks: nextTasks),
      approvedWorkflowStage: approvedWorkflowStage,
    );

    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();
    if (!refreshed) {
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: approvedWorkflowStage,
        workflowSpec: nextSpec,
      );
    }
    await conversationsNotifier.exitPlanningSession();
    ref.read(chatNotifierProvider.notifier).dismissPlanProposal();

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.plan_proposal_started'.tr())));

    final latestConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (initialTask == null || latestConversation == null) {
      await ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            'chat.plan_proposal_execute_prompt'.tr(),
            languageCode: context.locale.languageCode,
            bypassPlanMode: true,
          );
      return;
    }

    final latestTask =
        latestConversation.projectedExecutionTasks
            .where((task) => task.id == initialTask.id)
            .firstOrNull ??
        initialTask;
    await _runWorkflowTask(
      context,
      currentConversation: latestConversation,
      task: latestTask,
    );
  }

  Widget _buildPlanDocumentCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
    bool showActionBar = true,
  }) {
    final theme = Theme.of(context);
    final planArtifact = currentConversation.effectivePlanArtifact;
    final markdown = currentConversation.displayPlanDocument(
      isPlanning: isPlanMode,
    );
    if (markdown == null) {
      return const SizedBox.shrink();
    }

    final statusKey = isPlanMode || !planArtifact.hasApproved
        ? 'chat.plan_document_status_draft'
        : planArtifact.hasPendingEdits
        ? 'chat.plan_document_status_pending'
        : 'chat.plan_document_status_approved';
    final subtitleKey = isPlanMode || !planArtifact.hasApproved
        ? 'chat.plan_document_draft_subtitle'
        : planArtifact.hasPendingEdits
        ? 'chat.plan_document_pending_subtitle'
        : 'chat.plan_document_approved_subtitle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'chat.plan_document_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                label: Text(statusKey.tr()),
                visualDensity: VisualDensity.compact,
              ),
              if (!isPlanMode && planArtifact.hasExecutionDocument) ...[
                const SizedBox(width: 6),
                Chip(
                  label: Text(
                    _workflowProjectionStatusLabelKey(currentConversation).tr(),
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: _workflowProjectionStatusColor(
                    context,
                    currentConversation,
                  ).withValues(alpha: 0.14),
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: _workflowProjectionStatusColor(
                      context,
                      currentConversation,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitleKey.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          PlanMarkdownPreview(
            markdown: markdown,
            maxHeight: isPlanMode ? 320 : 240,
          ),
          if (!isPlanMode &&
              currentConversation.shouldPreferPlanDocument &&
              currentConversation.effectiveWorkflowSpec.openQuestions
                  .where((item) => item.trim().isNotEmpty)
                  .isNotEmpty) ...[
            const SizedBox(height: 10),
            PlanOpenQuestionSection(
              currentConversation: currentConversation,
              onStatusSelected: (question, status) => _setOpenQuestionStatus(
                context,
                question: question,
                status: status,
              ),
              onAnswerPressed: (question, existingNote) => _answerOpenQuestion(
                context,
                question: question,
                existingNote: existingNote,
              ),
            ),
          ],
          if (!isPlanMode &&
              currentConversation.shouldPreferPlanDocument &&
              currentConversation.projectedExecutionTasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildHydratedPlanView(
              context,
              currentConversation: currentConversation,
            ),
          ],
          if (!isPlanMode &&
              planArtifact.hasApproved &&
              planArtifact.hasPendingEdits) ...[
            const SizedBox(height: 10),
            _buildPlanDocumentDiffPreview(
              context,
              currentConversation: currentConversation,
            ),
          ],
          const SizedBox(height: 8),
          if (showActionBar)
            _buildPlanDocumentActions(
              context,
              currentConversation: currentConversation,
              chatState: chatState,
              isPlanMode: isPlanMode,
            ),
        ],
      ),
    );
  }

  Widget _buildPlanDocumentDiffPreview(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final artifact = currentConversation.effectivePlanArtifact;
    final approvedMarkdown = artifact.normalizedApprovedMarkdown;
    final draftMarkdown = artifact.normalizedDraftMarkdown;
    if (approvedMarkdown == null || draftMarkdown == null) {
      return const SizedBox.shrink();
    }

    final diff = ConversationPlanDiffService.buildTaskDiff(
      approvedMarkdown: approvedMarkdown,
      draftMarkdown: draftMarkdown,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.plan_document_diff_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            diff.isValid
                ? 'chat.plan_document_diff_subtitle'.tr()
                : 'chat.plan_document_diff_invalid'.tr(
                    namedArgs: {
                      'error':
                          diff.errorMessage ??
                          'draft plan document could not be parsed',
                    },
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (diff.isValid) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'chat.plan_document_diff_added'.tr(
                      namedArgs: {
                        'count': diff
                            .countByType(ConversationPlanTaskDiffType.added)
                            .toString(),
                      },
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    'chat.plan_document_diff_changed'.tr(
                      namedArgs: {
                        'count': diff
                            .countByType(ConversationPlanTaskDiffType.changed)
                            .toString(),
                      },
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(
                    'chat.plan_document_diff_removed'.tr(
                      namedArgs: {
                        'count': diff
                            .countByType(ConversationPlanTaskDiffType.removed)
                            .toString(),
                      },
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (diff.entries.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'chat.plan_document_diff_no_changes'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              for (final entry in diff.entries.take(6)) ...[
                Text(
                  _planDocumentDiffEntryLabel(context, entry),
                  style: theme.textTheme.bodySmall,
                ),
                if (entry != diff.entries.take(6).last)
                  const SizedBox(height: 4),
              ],
              if (diff.entries.length > 6) ...[
                const SizedBox(height: 4),
                Text(
                  'chat.plan_document_diff_more'.tr(
                    namedArgs: {'count': (diff.entries.length - 6).toString()},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPlanDocumentActions(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    final planArtifact = currentConversation.effectivePlanArtifact;
    final isBusy = chatState.isLoading;
    final canUseProjection =
        !currentConversation.shouldPreferPlanDocument ||
        currentConversation.isWorkflowProjectionFresh;
    final blockedTask = ConversationPlanExecutionCoordinator.blockedTask(
      currentConversation,
    );
    final nextTask = ConversationPlanExecutionCoordinator.nextTask(
      currentConversation,
    );
    final activeTask = ConversationPlanExecutionCoordinator.activeTask(
      currentConversation,
    );
    final validationTask = ConversationPlanExecutionCoordinator.validationTask(
      currentConversation,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: isBusy
              ? null
              : () => _showPlanDocumentEditor(
                  context,
                  currentConversation,
                  preferDraft: isPlanMode,
                ),
          icon: const Icon(Icons.edit_note_outlined, size: 18),
          label: Text(
            _planDocumentEditLabelKey(
              currentConversation,
              isPlanMode: isPlanMode,
            ).tr(),
          ),
        ),
        if (planArtifact.historyEntries.isNotEmpty)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _showPlanRevisionHistory(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.history_outlined, size: 18),
            label: Text('chat.plan_document_history'.tr()),
          ),
        if (planArtifact.hasPendingEdits)
          FilledButton.tonalIcon(
            onPressed: isBusy
                ? null
                : () => _approveDraftPlanDocument(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: Text('chat.plan_document_review_draft'.tr()),
          ),
        if (planArtifact.hasApproved && planArtifact.hasPendingEdits)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _revertDraftPlanDocument(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.restore_outlined, size: 18),
            label: Text('chat.plan_document_revert'.tr()),
          ),
        if (!isPlanMode && planArtifact.hasExecutionDocument)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _regenerateDraftPlan(
                    context,
                    currentConversation: currentConversation,
                  ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text('chat.plan_document_regenerate_draft'.tr()),
          ),
        if (!isPlanMode && planArtifact.hasExecutionDocument)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _refreshExecutionTasksFromPlan(context),
            icon: const Icon(Icons.sync_outlined, size: 18),
            label: Text('chat.plan_document_refresh_tasks'.tr()),
          ),
        if (!isPlanMode && blockedTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _markWorkflowTaskUnblocked(
                    context,
                    currentConversation: currentConversation,
                    task: blockedTask,
                  ),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: Text('chat.workflow_task_mark_unblocked'.tr()),
          ),
        if (!isPlanMode && blockedTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _editWorkflowTaskBlockedReason(
                    context,
                    currentConversation: currentConversation,
                    task: blockedTask,
                  ),
            icon: const Icon(Icons.edit_note_outlined, size: 18),
            label: Text('chat.workflow_task_edit_blocked_reason'.tr()),
          ),
        if (!isPlanMode && blockedTask != null)
          FilledButton.tonalIcon(
            onPressed: isBusy
                ? null
                : () => _replanFromBlockedTask(
                    context,
                    currentConversation: currentConversation,
                    task: blockedTask,
                  ),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: Text('chat.workflow_task_replan_from_blocker'.tr()),
          ),
        if (!isPlanMode && activeTask != null)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _replanCurrentTask(
                    context,
                    currentConversation: currentConversation,
                    task: activeTask,
                  ),
            icon: const Icon(Icons.alt_route_outlined, size: 18),
            label: Text('chat.plan_document_replan_current_task'.tr()),
          ),
        if (!isPlanMode &&
            validationTask != null &&
            validationTask.validationCommand.trim().isNotEmpty)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _replanValidationPath(
                    context,
                    currentConversation: currentConversation,
                    task: validationTask,
                  ),
            icon: const Icon(Icons.route_outlined, size: 18),
            label: Text('chat.plan_document_replan_validation'.tr()),
          ),
        if (!isPlanMode && nextTask != null)
          FilledButton.tonalIcon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _runWorkflowTask(
                    context,
                    currentConversation: currentConversation,
                    task: nextTask,
                  ),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text('chat.plan_document_start_next_task'.tr()),
          ),
        if (!isPlanMode && activeTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _setWorkflowTaskStatus(
                    currentConversation: currentConversation,
                    task: activeTask,
                    status: ConversationWorkflowTaskStatus.completed,
                    summary: 'Marked complete from the approved plan document.',
                    eventType: ConversationExecutionTaskEventType.completed,
                  ),
            icon: const Icon(Icons.task_alt_outlined, size: 18),
            label: Text('chat.plan_document_mark_current_complete'.tr()),
          ),
        if (!isPlanMode && validationTask != null)
          OutlinedButton.icon(
            onPressed: isBusy || !canUseProjection
                ? null
                : () => _runWorkflowTaskValidation(
                    context,
                    currentConversation: currentConversation,
                    task: validationTask,
                  ),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text('chat.plan_document_run_validation'.tr()),
          ),
        if (isPlanMode)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => ref
                      .read(chatNotifierProvider.notifier)
                      .generatePlanProposal(
                        languageCode: context.locale.languageCode,
                      ),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('chat.plan_proposal_regenerate'.tr()),
          ),
      ],
    );
  }

  Widget _buildHydratedPlanView(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final tasks = currentConversation.projectedExecutionTasks;
    final projectionIsCurrent = currentConversation.isWorkflowProjectionFresh;
    final subtitleKey = projectionIsCurrent
        ? 'chat.plan_document_hydrated_subtitle'
        : 'chat.plan_document_hydrated_stale_subtitle';
    final completedCount = tasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final inProgressCount = tasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.inProgress,
        )
        .length;
    final blockedCount = tasks
        .where((task) => task.status == ConversationWorkflowTaskStatus.blocked)
        .length;
    final pendingCount = tasks
        .where((task) => task.status == ConversationWorkflowTaskStatus.pending)
        .length;
    final overview = _planExecutionOverview(
      totalCount: tasks.length,
      completedCount: completedCount,
      inProgressCount: inProgressCount,
      blockedCount: blockedCount,
      pendingCount: pendingCount,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.plan_document_hydrated_title'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitleKey.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _PlanExecutionOverviewCard(
            title: overview.titleKey.tr(),
            description: overview.descriptionKey.tr(),
            completedLabel: 'chat.plan_document_hydrated_summary_completed'.tr(
              namedArgs: {
                'completed': completedCount.toString(),
                'total': tasks.length.toString(),
              },
            ),
            pendingLabel: 'chat.workflow_task_status_pending'.tr(),
            pendingCount: pendingCount,
            inProgressLabel: 'chat.workflow_task_status_in_progress'.tr(),
            inProgressCount: inProgressCount,
            blockedLabel: 'chat.workflow_task_status_blocked'.tr(),
            blockedCount: blockedCount,
          ),
          const SizedBox(height: 10),
          for (final task in tasks) ...[
            PlanHydratedTaskRow(
              task: task,
              progress: currentConversation.executionProgressForTask(task.id),
            ),
            if (task != tasks.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  _PlanExecutionOverview _planExecutionOverview({
    required int totalCount,
    required int completedCount,
    required int inProgressCount,
    required int blockedCount,
    required int pendingCount,
  }) {
    if (blockedCount > 0) {
      return const _PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_blocked_title',
        descriptionKey: 'chat.plan_document_hydrated_state_blocked_description',
      );
    }
    if (inProgressCount > 0) {
      return const _PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_active_title',
        descriptionKey: 'chat.plan_document_hydrated_state_active_description',
      );
    }
    if (pendingCount > 0) {
      return const _PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_ready_title',
        descriptionKey: 'chat.plan_document_hydrated_state_ready_description',
      );
    }
    if (totalCount > 0 && completedCount == totalCount) {
      return const _PlanExecutionOverview(
        titleKey: 'chat.plan_document_hydrated_state_complete_title',
        descriptionKey:
            'chat.plan_document_hydrated_state_complete_description',
      );
    }
    return const _PlanExecutionOverview(
      titleKey: 'chat.plan_document_hydrated_state_empty_title',
      descriptionKey: 'chat.plan_document_hydrated_state_empty_description',
    );
  }

  Future<void> _answerOpenQuestion(
    BuildContext context, {
    required String question,
    String? existingNote,
  }) async {
    final pending = PendingWorkflowDecision(
      id: 'open-question-${_uuid.v4()}',
      decision: WorkflowPlanningDecision(
        id: Conversation.openQuestionIdFor(question),
        question: question.trim(),
        help: 'chat.open_question_answer_subtitle'.tr(),
        allowFreeText: true,
        freeTextPlaceholder: 'chat.open_question_answer_placeholder'.tr(),
        options: const [],
      ),
      completer: Completer<WorkflowPlanningDecisionAnswer?>(),
    );
    final answer = await showModalBottomSheet<WorkflowPlanningDecisionAnswer>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _WorkflowDecisionSheet(
        pending: pending,
        initialFreeText: existingNote,
        titleText: 'chat.open_question_answer_title'.tr(),
      ),
    );
    if (answer == null || !context.mounted) {
      return;
    }

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentOpenQuestionProgress(
          question: question,
          status: ConversationOpenQuestionStatus.resolved,
          note: answer.optionLabel,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.open_question_answer_saved'.tr())),
    );
  }

  Future<void> _setOpenQuestionStatus(
    BuildContext context, {
    required String question,
    required ConversationOpenQuestionStatus status,
  }) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentOpenQuestionProgress(question: question, status: status);

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'chat.plan_document_open_question_status_changed'.tr(
            namedArgs: {
              'status': switch (status) {
                ConversationOpenQuestionStatus.unresolved =>
                  'chat.open_question_status_unresolved'.tr(),
                ConversationOpenQuestionStatus.needsUserInput =>
                  'chat.open_question_status_needs_user_input'.tr(),
                ConversationOpenQuestionStatus.resolved =>
                  'chat.open_question_status_resolved'.tr(),
                ConversationOpenQuestionStatus.deferred =>
                  'chat.open_question_status_deferred'.tr(),
              },
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showPlanDocumentEditor(
    BuildContext context,
    Conversation currentConversation, {
    required bool preferDraft,
  }) async {
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final planArtifact = latestConversation.effectivePlanArtifact;
    final result = await showModalBottomSheet<PlanDocumentEditorSubmission>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => PlanDocumentEditorSheet(
        planArtifact: planArtifact,
        preferDraft: preferDraft,
      ),
    );
    if (result == null) {
      return;
    }

    final normalizedDraft = result.markdown.trim().isEmpty
        ? (planArtifact.normalizedApprovedMarkdown ?? '')
        : result.markdown.trimRight();
    final updatedAt = DateTime.now();
    final nextArtifact = planArtifact
        .copyWith(draftMarkdown: normalizedDraft, updatedAt: updatedAt)
        .recordRevision(
          markdown: normalizedDraft,
          kind: ConversationPlanRevisionKind.draft,
          label: 'Saved draft plan document',
          createdAt: updatedAt,
        );

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.validation.isValid
              ? 'chat.plan_document_saved'.tr()
              : 'chat.plan_document_saved_with_issues'.tr(
                  namedArgs: {
                    'error':
                        result.validation.errorMessage ??
                        'plan document could not be parsed',
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _approveDraftPlanDocument(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final currentArtifact = latestConversation.effectivePlanArtifact;
    final draftMarkdown = currentArtifact.normalizedDraftMarkdown;
    if (draftMarkdown == null) {
      return;
    }

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: draftMarkdown,
      requireTasks: true,
    );
    if (!validation.isValid) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'chat.plan_document_approval_blocked'.tr(
              namedArgs: {
                'error':
                    validation.errorMessage ??
                    'plan document could not be parsed',
              },
            ),
          ),
        ),
      );
      return;
    }

    final shouldApprove =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) => PlanDocumentApprovalSheet(
            markdown: draftMarkdown,
            validation: validation,
          ),
        ) ??
        false;
    if (!shouldApprove) {
      return;
    }

    final approvedMarkdown =
        ConversationPlanProjectionService.replaceWorkflowStage(
          markdown: draftMarkdown,
          workflowStage: _preferredApprovedWorkflowStage(latestConversation),
        );
    final updatedAt = DateTime.now();
    final nextArtifact = currentArtifact
        .copyWith(
          draftMarkdown: approvedMarkdown,
          approvedMarkdown: approvedMarkdown,
          updatedAt: updatedAt,
        )
        .recordRevision(
          markdown: approvedMarkdown,
          kind: ConversationPlanRevisionKind.approved,
          label: 'Approved draft plan document',
          createdAt: updatedAt,
        );

    await conversationsNotifier.updateCurrentPlanArtifact(
      planArtifact: nextArtifact.hasContent ? nextArtifact : null,
      clearPlanArtifact: !nextArtifact.hasContent,
    );
    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refreshed
              ? 'chat.plan_document_approved'.tr()
              : 'chat.plan_document_approved_refresh_failed'.tr(),
        ),
      ),
    );
  }

  Future<void> _revertDraftPlanDocument(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final currentArtifact = latestConversation.effectivePlanArtifact;
    if (!currentArtifact.hasApproved) {
      return;
    }

    final approvedMarkdown = currentArtifact.normalizedApprovedMarkdown ?? '';
    final updatedAt = DateTime.now();
    final nextArtifact = currentArtifact
        .copyWith(draftMarkdown: approvedMarkdown, updatedAt: updatedAt)
        .recordRevision(
          markdown: approvedMarkdown,
          kind: ConversationPlanRevisionKind.restored,
          label: 'Restored draft from approved plan document',
          createdAt: updatedAt,
        );
    await conversationsNotifier.updateCurrentPlanArtifact(
      planArtifact: nextArtifact.hasContent ? nextArtifact : null,
      clearPlanArtifact: !nextArtifact.hasContent,
    );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.plan_document_reverted'.tr())));
  }

  Future<void> _refreshExecutionTasksFromPlan(BuildContext context) async {
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final refreshed = await conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          refreshed
              ? 'chat.plan_document_tasks_refreshed'.tr()
              : 'chat.plan_document_tasks_refresh_failed'.tr(),
        ),
      ),
    );
  }

  Future<void> _regenerateDraftPlan(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final languageCode = context.locale.languageCode;
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    if (!currentConversation.isPlanningSession) {
      await conversationsNotifier.enterPlanningSession();
    }
    await chatNotifier.generatePlanProposal(languageCode: languageCode);

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.plan_document_regeneration_started'.tr())),
    );
  }

  Future<void> _snapshotApprovedPlanDocument({
    required WorkflowProposalDraft workflowDraft,
    required WorkflowTaskProposalDraft taskDraft,
    required ConversationWorkflowStage approvedWorkflowStage,
  }) async {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return;
    }

    final currentArtifact = currentConversation.effectivePlanArtifact;
    final approvedMarkdown =
        ConversationPlanDocumentBuilder.buildApprovedSnapshotMarkdown(
          currentArtifact: currentArtifact,
          workflowStage: approvedWorkflowStage,
          workflowSpec: workflowDraft.workflowSpec,
          tasks: taskDraft.tasks,
        );
    final updatedAt = DateTime.now();
    final nextArtifact = currentArtifact
        .copyWith(
          draftMarkdown: approvedMarkdown,
          approvedMarkdown: approvedMarkdown,
          updatedAt: updatedAt,
        )
        .recordRevision(
          markdown: approvedMarkdown,
          kind: ConversationPlanRevisionKind.approved,
          label: 'Captured approved plan document snapshot',
          createdAt: updatedAt,
        );

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
        );
  }

  ConversationWorkflowStage _preferredApprovedWorkflowStage(
    Conversation currentConversation,
  ) {
    return switch (currentConversation.workflowStage) {
      ConversationWorkflowStage.tasks ||
      ConversationWorkflowStage.implement ||
      ConversationWorkflowStage.review => currentConversation.workflowStage,
      _ =>
        currentConversation.effectiveWorkflowSpec.tasks.isEmpty
            ? ConversationWorkflowStage.tasks
            : ConversationWorkflowStage.implement,
    };
  }

  Future<void> _showPlanRevisionHistory(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    final artifact = currentConversation.effectivePlanArtifact;
    if (artifact.historyEntries.isEmpty) {
      return;
    }
    final selectedRevision =
        await showModalBottomSheet<ConversationPlanRevision>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) =>
              PlanRevisionHistorySheet(planArtifact: artifact),
        );
    if (selectedRevision == null) {
      return;
    }

    final updatedAt = DateTime.now();
    final nextArtifact = artifact
        .copyWith(
          draftMarkdown: selectedRevision.normalizedMarkdown ?? '',
          updatedAt: updatedAt,
        )
        .recordRevision(
          markdown: selectedRevision.normalizedMarkdown ?? '',
          kind: ConversationPlanRevisionKind.restored,
          label: 'Restored draft from revision history',
          createdAt: updatedAt,
        );
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.plan_document_history_restored'.tr())),
    );
  }
}

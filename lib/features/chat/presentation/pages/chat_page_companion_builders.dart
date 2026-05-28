// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPageCompanionBuilders on _ChatPageState {
  Future<void> _showCompanionPanelSheet(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required CodingProject activeProject,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: _buildCompanionPanel(
            sheetContext,
            currentConversation: currentConversation,
            chatState: chatState,
            activeProject: activeProject,
            inSheet: true,
          ),
        );
      },
    );
  }

  Widget _buildCompanionPanel(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required CodingProject activeProject,
    bool inSheet = false,
  }) {
    final theme = Theme.of(context);
    final snapshotAsync = ref.watch(
      codingEnvironmentSnapshotProvider(activeProject.normalizedRootPath),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: inSheet ? 0 : 0.32,
        ),
        border: inSheet
            ? null
            : Border(
                left: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, inSheet ? 0 : 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompanionSection(
                context,
                title: 'chat.companion_progress'.tr(),
                children: _buildCompanionProgressChildren(
                  context,
                  currentConversation: currentConversation,
                  chatState: chatState,
                ),
              ),
              const SizedBox(height: 18),
              _buildCompanionSection(
                context,
                title: 'chat.companion_environment'.tr(),
                trailing: IconButton(
                  onPressed: () => ref.invalidate(
                    codingEnvironmentSnapshotProvider(
                      activeProject.normalizedRootPath,
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'chat.companion_refresh_environment'.tr(),
                ),
                children: [
                  _buildCompanionEnvironment(
                    context,
                    snapshotAsync: snapshotAsync,
                    activeProject: activeProject,
                    inSheet: inSheet,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildCompanionSection(
                context,
                title: 'chat.companion_sources'.tr(),
                children: _buildCompanionSourceChildren(
                  context,
                  currentConversation: currentConversation,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanionSection(
    BuildContext context, {
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  List<Widget> _buildCompanionProgressChildren(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
  }) {
    final theme = Theme.of(context);
    final tasks = currentConversation.projectedExecutionTasks
        .where((task) => task.title.trim().isNotEmpty)
        .toList(growable: false);
    final completedCount = tasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final isGenerating =
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;

    if (tasks.isEmpty) {
      return [
        if (isGenerating) ...[
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'chat.plan_proposal_generating'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ] else
          _buildCompanionEmptyText(
            context,
            'chat.companion_progress_empty'.tr(),
          ),
      ];
    }

    final progressValue = tasks.isEmpty ? 0.0 : completedCount / tasks.length;
    final visibleTasks = tasks.take(6).toList(growable: false);
    final remainingTasks = tasks.length - visibleTasks.length;

    return [
      Text(
        'chat.companion_progress_summary'.tr(
          namedArgs: {
            'completed': completedCount.toString(),
            'total': tasks.length.toString(),
          },
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(value: progressValue, minHeight: 6),
      ),
      const SizedBox(height: 12),
      for (final task in visibleTasks) ...[
        _buildCompanionTaskRow(context, task),
        if (task != visibleTasks.last) const SizedBox(height: 10),
      ],
      if (remainingTasks > 0) ...[
        const SizedBox(height: 10),
        Text(
          'chat.companion_more_items'.tr(
            namedArgs: {'count': remainingTasks.toString()},
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  Widget _buildCompanionTaskRow(
    BuildContext context,
    ConversationWorkflowTask task,
  ) {
    final theme = Theme.of(context);
    final color = _workflowTaskStatusColor(context, task.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(_companionTaskIcon(task.status), size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _workflowTaskStatusLabel(task.status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanionEnvironment(
    BuildContext context, {
    required AsyncValue<CodingEnvironmentSnapshot> snapshotAsync,
    required CodingProject activeProject,
    required bool inSheet,
  }) {
    return snapshotAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, stackTrace) =>
          _buildCompanionEmptyText(context, error.toString()),
      data: (snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompanionInfoRow(
              context,
              icon: Icons.computer_outlined,
              label: 'chat.companion_environment_local'.tr(),
              value: activeProject.normalizedRootPath,
            ),
            const SizedBox(height: 10),
            if (snapshot.isGitRepository) ...[
              _buildCompanionInfoRow(
                context,
                icon: Icons.account_tree_outlined,
                label: 'chat.companion_branch'.tr(),
                value: snapshot.displayBranchName,
              ),
              const SizedBox(height: 10),
              _buildCompanionChangesRow(context, snapshot: snapshot),
            ] else
              _buildCompanionInfoRow(
                context,
                icon: Icons.info_outline,
                label: 'chat.companion_git_unavailable'.tr(),
                value:
                    snapshot.errorMessage ??
                    'chat.companion_git_unavailable_message'.tr(),
              ),
            const SizedBox(height: 12),
            _buildCompanionPromptButton(
              context,
              icon: Icons.task_alt,
              label: 'chat.companion_commit'.tr(),
              enabled: snapshot.isGitRepository && snapshot.hasChanges,
              prompt: _companionCommitPrompt,
              closeAfterAction: inSheet,
            ),
            const SizedBox(height: 8),
            _buildCompanionPromptButton(
              context,
              icon: Icons.open_in_new,
              label: 'chat.companion_create_pr'.tr(),
              enabled: snapshot.isGitRepository,
              prompt: _companionPullRequestPrompt,
              closeAfterAction: inSheet,
              outlined: true,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompanionChangesRow(
    BuildContext context, {
    required CodingEnvironmentSnapshot snapshot,
  }) {
    final theme = Theme.of(context);
    final baseValueStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            Icons.edit_note,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'chat.companion_changes'.tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              if (snapshot.hasChanges)
                Text.rich(
                  TextSpan(
                    style: baseValueStyle,
                    children: [
                      TextSpan(
                        text: 'chat.companion_changed_files'.tr(
                          namedArgs: {
                            'count': snapshot.changedFileCount.toString(),
                          },
                        ),
                      ),
                      const TextSpan(text: ', '),
                      TextSpan(
                        text: '+${snapshot.insertions}',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '-${snapshot.deletions}',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else
                Text(
                  'chat.companion_changes_clean'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: baseValueStyle,
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCompanionSourceChildren(
    BuildContext context, {
    required Conversation currentConversation,
  }) {
    final theme = Theme.of(context);
    final sourcePaths = _companionSourcePaths(currentConversation);
    if (sourcePaths.isEmpty) {
      return [
        _buildCompanionEmptyText(context, 'chat.companion_sources_empty'.tr()),
      ];
    }

    final visiblePaths = sourcePaths.take(8).toList(growable: false);
    final remainingPaths = sourcePaths.length - visiblePaths.length;
    return [
      for (final path in visiblePaths) ...[
        _buildCompanionInfoRow(
          context,
          icon: Icons.description_outlined,
          label: path,
          value: 'chat.companion_source_from_tasks'.tr(),
          dense: true,
        ),
        if (path != visiblePaths.last) const SizedBox(height: 8),
      ],
      if (remainingPaths > 0) ...[
        const SizedBox(height: 10),
        Text(
          'chat.companion_more_items'.tr(
            namedArgs: {'count': remainingPaths.toString()},
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  Widget _buildCompanionInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool dense = false,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            icon,
            size: dense ? 16 : 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: valueColor ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanionPromptButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool enabled,
    required String prompt,
    required bool closeAfterAction,
    bool outlined = false,
  }) {
    final onPressed = enabled
        ? () {
            _prefillCompanionPrompt(prompt);
            if (closeAfterAction) {
              Navigator.of(context).maybePop();
            }
          }
        : null;
    final child = outlined
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          )
        : FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          );

    return SizedBox(width: double.infinity, child: child);
  }

  Widget _buildCompanionEmptyText(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  void _prefillCompanionPrompt(String prompt) {
    setState(() {
      _composerPrefillText = prompt;
      _composerPrefillVersion++;
    });
  }

  IconData _companionTaskIcon(ConversationWorkflowTaskStatus status) {
    return switch (status) {
      ConversationWorkflowTaskStatus.pending => Icons.radio_button_unchecked,
      ConversationWorkflowTaskStatus.inProgress => Icons.play_circle_outline,
      ConversationWorkflowTaskStatus.completed => Icons.check_circle,
      ConversationWorkflowTaskStatus.blocked => Icons.error_outline,
    };
  }

  List<String> _companionSourcePaths(Conversation currentConversation) {
    final paths = <String>[];
    for (final task in currentConversation.projectedExecutionTasks) {
      for (final rawPath in task.targetFiles) {
        final path = rawPath.trim();
        if (path.isNotEmpty && !paths.contains(path)) {
          paths.add(path);
        }
      }
    }
    return paths;
  }
}

const _companionCommitPrompt =
    'Please inspect the current git changes, summarize the risk, run the appropriate focused verification, and create one focused Conventional Commits commit if the changes are ready.';

const _companionPullRequestPrompt =
    'Please inspect the current branch, make sure the committed changes are ready, push the branch, and create a draft pull request with a concise summary and verification notes.';

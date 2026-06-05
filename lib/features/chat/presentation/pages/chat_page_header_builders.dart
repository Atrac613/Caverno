// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPageHeaderBuilders on _ChatPageState {
  Widget _buildTokenUsageBar(
    BuildContext context,
    ChatState chatState,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);
    final modelConfig = ModelListConfig(
      baseUrl: settings.baseUrl.trim().isEmpty
          ? ApiConstants.defaultBaseUrl
          : settings.baseUrl.trim(),
      apiKey: settings.apiKey.trim().isEmpty
          ? ApiConstants.defaultApiKey
          : settings.apiKey.trim(),
      selectedModelId: settings.model.trim(),
    );
    final contextWindowTokens = ref
        .watch(modelCatalogProvider(modelConfig))
        .whenOrNull(
          data: (catalog) {
            final selectedModel = settings.model.trim();
            for (final model in catalog) {
              if (model.id == selectedModel) {
                return model.contextWindowTokens;
              }
            }
            return null;
          },
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: TokenUsageIndicator(
          chatState: chatState,
          model: settings.model,
          contextWindowTokens: contextWindowTokens,
          formatTokenCount: _formatTokenCount,
        ),
      ),
    );
  }

  Widget _buildFooterPlanCard(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: CompactPlanFooterCard(
        currentConversation: currentConversation,
        isPlanMode: isPlanMode,
        onOpen: () {
          _openPlanReviewSheet(
            context,
            currentConversation: currentConversation,
            chatState: chatState,
            isPlanMode: isPlanMode,
          );
        },
        onApprove: () {
          _approveCurrentPlanAndStart(
            context,
            currentConversation: currentConversation,
          );
        },
        onEdit: () {
          _editPlanInChat(context, currentConversation: currentConversation);
        },
        onCancel: () {
          _cancelPlanReview(context, currentConversation: currentConversation);
        },
      ),
    );
  }

  Message _buildPlanStatusMessage(
    BuildContext context, {
    required ChatState chatState,
  }) {
    final hasError =
        chatState.workflowProposalError != null ||
        chatState.taskProposalError != null;
    return Message(
      id: 'plan_progress_message',
      content: hasError
          ? 'chat.workflow_generate_error'.tr()
          : 'chat.plan_proposal_generating'.tr(),
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: !hasError,
    );
  }

  bool _shouldAutoPresentPlanReviewSheet(
    Conversation? currentConversation,
    ChatState chatState, {
    required bool isPlanMode,
  }) {
    if (currentConversation == null) {
      _trackedPlanGenerationConversationId = null;
      _wasGeneratingPlanForTrackedConversation = false;
      return false;
    }

    final conversationId = currentConversation.id;
    final isGenerating =
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    final hasCompletedProposalDrafts =
        chatState.workflowProposalDraft != null &&
        chatState.taskProposalDraft != null;
    final canPresentCompletedPlanModeDraft =
        isPlanMode && hasCompletedProposalDrafts;
    if (_trackedPlanGenerationConversationId != conversationId) {
      _trackedPlanGenerationConversationId = conversationId;
      _wasGeneratingPlanForTrackedConversation =
          isGenerating || canPresentCompletedPlanModeDraft;
      if (!canPresentCompletedPlanModeDraft) {
        return false;
      }
    }

    if (isGenerating) {
      _wasGeneratingPlanForTrackedConversation = true;
      _lastAutoPresentedPlanReviewDraftKey = null;
      return false;
    }

    final artifact = currentConversation.effectivePlanArtifact;
    final requiresReview =
        isPlanMode || artifact.hasPendingEdits || !artifact.hasApproved;
    final baseReady =
        (_wasGeneratingPlanForTrackedConversation ||
            canPresentCompletedPlanModeDraft) &&
        requiresReview &&
        artifact.normalizedDraftMarkdown != null &&
        chatState.workflowProposalError == null &&
        chatState.taskProposalError == null;
    if (!baseReady) {
      _wasGeneratingPlanForTrackedConversation = false;
      return false;
    }
    if (!_planArtifactHasPreviewTasks(artifact)) {
      _wasGeneratingPlanForTrackedConversation = true;
      return false;
    }
    final draftKey = _planReviewDraftKey(conversationId, artifact);
    if (_lastAutoPresentedPlanReviewDraftKey == draftKey) {
      _wasGeneratingPlanForTrackedConversation = false;
      return false;
    }
    _wasGeneratingPlanForTrackedConversation = false;
    return true;
  }

  void _maybePresentPlanReviewSheet(
    BuildContext context, {
    required Conversation? currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) {
    if (currentConversation == null || _isPresentingPlanReviewSheet) {
      return;
    }

    final shouldPresent = _shouldAutoPresentPlanReviewSheet(
      currentConversation,
      chatState,
      isPlanMode: isPlanMode,
    );
    if (!shouldPresent) {
      return;
    }

    _isPresentingPlanReviewSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isPresentingPlanReviewSheet = false;
        return;
      }
      unawaited(
        Future<void>(() {
          if (!mounted || !context.mounted) {
            _isPresentingPlanReviewSheet = false;
            return;
          }
          unawaited(
            _openPlanReviewSheet(
              context,
              currentConversation: currentConversation,
              chatState: chatState,
              isPlanMode: isPlanMode,
            ).whenComplete(() {
              _isPresentingPlanReviewSheet = false;
            }),
          );
        }),
      );
    });
  }

  Future<void> _openPlanReviewSheet(
    BuildContext context, {
    required Conversation currentConversation,
    required ChatState chatState,
    required bool isPlanMode,
  }) async {
    final latestConversation =
        ref.read(conversationsNotifierProvider).currentConversation ??
        currentConversation;
    final initialArtifact = latestConversation.effectivePlanArtifact;
    final initialDraftState =
        isPlanMode ||
        initialArtifact.hasPendingEdits ||
        !initialArtifact.hasApproved;
    if (!initialArtifact.hasContent ||
        (initialDraftState && !_planArtifactHasPreviewTasks(initialArtifact))) {
      return;
    }
    final initialDraftKey = _planReviewDraftKey(
      latestConversation.id,
      initialArtifact,
    );
    if (initialDraftState && initialDraftKey != null) {
      _lastAutoPresentedPlanReviewDraftKey = initialDraftKey;
    }

    final action = await showModalBottomSheet<PlanReviewSheetAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final latestSheetConversation =
              ref.watch(conversationsNotifierProvider).currentConversation ??
              latestConversation;
          final sheetArtifact = latestSheetConversation.effectivePlanArtifact;
          final effectiveArtifact = sheetArtifact.hasContent
              ? sheetArtifact
              : initialArtifact;
          final isDraftState =
              isPlanMode ||
              effectiveArtifact.hasPendingEdits ||
              !effectiveArtifact.hasApproved;
          final canApprove =
              isDraftState && _planArtifactHasPreviewTasks(effectiveArtifact);
          return FractionallySizedBox(
            heightFactor: 0.96,
            child: PlanReviewSheet(
              planArtifact: effectiveArtifact,
              isPlanMode: isPlanMode,
              canApprove: canApprove,
              canCancel: isDraftState,
            ),
          );
        },
      ),
    );
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() {});

    if (action == PlanReviewSheetAction.approve) {
      await _approveCurrentPlanAndStart(
        context,
        currentConversation: latestConversation,
      );
      return;
    }
    if (action == PlanReviewSheetAction.edit) {
      _editPlanInChat(context, currentConversation: latestConversation);
      return;
    }
    if (action == PlanReviewSheetAction.cancel) {
      await _cancelPlanReview(context, currentConversation: latestConversation);
    }
  }

  bool _planArtifactHasPreviewTasks(ConversationPlanArtifact artifact) {
    final markdown =
        artifact.displayMarkdown(isPlanning: true) ??
        artifact.displayMarkdown(isPlanning: false);
    if (markdown == null || markdown.trim().isEmpty) {
      return false;
    }
    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
      requireTasks: true,
    );
    return validation.previewTasks.isNotEmpty;
  }

  String? _planReviewDraftKey(
    String conversationId,
    ConversationPlanArtifact artifact,
  ) {
    final draftMarkdown = artifact.normalizedDraftMarkdown;
    if (draftMarkdown == null) {
      return null;
    }
    return '$conversationId:${draftMarkdown.hashCode}';
  }

  Widget _buildConversationCompactionBanner(
    BuildContext context,
    Conversation currentConversation,
  ) {
    final theme = Theme.of(context);
    final artifact = currentConversation.effectiveCompactionArtifact;
    final summary = artifact.normalizedSummary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compress_outlined,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conversation compaction is active',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh summary',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref
                      .read(conversationsNotifierProvider.notifier)
                      .rebuildCurrentConversationCompaction();
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Compacted summary refreshed'),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_outlined, size: 18),
              ),
              TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Compacted summary'),
                      content: SingleChildScrollView(child: Text(summary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('View summary'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Older turns are summarized before they are sent to the model. '
            'Recent turns still remain verbatim.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Compacted turns: ${artifact.compactedMessageCount} • '
            'Source messages: ${artifact.sourceMessageCount} • '
            'Estimated prompt tokens: ${artifact.estimatedPromptTokens} • '
            'v${artifact.version}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

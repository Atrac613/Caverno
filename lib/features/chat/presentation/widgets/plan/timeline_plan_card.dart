import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation.dart';
import '../../../domain/services/conversation_plan_projection_service.dart';
import '../../providers/chat_state.dart';
import 'plan_markdown_preview.dart';

class TimelinePlanCard extends StatelessWidget {
  const TimelinePlanCard({
    super.key,
    required this.currentConversation,
    required this.chatState,
    required this.isPlanMode,
    required this.isApprovedExpanded,
    required this.onToggleApprovedExpanded,
    required this.onApprove,
    required this.onEdit,
    required this.onCancel,
  });

  final Conversation currentConversation;
  final ChatState chatState;
  final bool isPlanMode;
  final bool isApprovedExpanded;
  final VoidCallback onToggleApprovedExpanded;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planArtifact = currentConversation.effectivePlanArtifact;
    final isGenerating =
        chatState.isGeneratingWorkflowProposal ||
        chatState.isGeneratingTaskProposal;
    final isDraftState =
        isPlanMode ||
        planArtifact.hasPendingEdits ||
        !planArtifact.hasApproved ||
        chatState.workflowProposalDraft != null ||
        chatState.taskProposalDraft != null ||
        chatState.workflowProposalError != null ||
        chatState.taskProposalError != null ||
        isGenerating;
    final markdown = planArtifact.displayMarkdown(isPlanning: isDraftState);
    final planValidation = markdown == null
        ? null
        : ConversationPlanProjectionService.validateDocument(
            markdown: markdown,
            requireTasks: true,
          );
    final showApproveAction = isDraftState;
    final canApprove = isDraftState && (planValidation?.isValid ?? false);
    final showApproveProgress =
        showApproveAction &&
        !canApprove &&
        (isGenerating || chatState.isLoading);
    final canCancel =
        isDraftState ||
        chatState.workflowProposalError != null ||
        chatState.taskProposalError != null;
    final showEdit = markdown != null || isDraftState;
    final titleKey = isDraftState
        ? 'chat.plan_proposal_title'
        : 'chat.plan_document_title';
    final statusKey = isDraftState
        ? (planArtifact.hasApproved && planArtifact.hasPendingEdits
              ? 'chat.plan_document_status_pending'
              : 'chat.plan_document_status_draft')
        : 'chat.plan_document_status_approved';
    final subtitleKey = isDraftState
        ? 'chat.plan_proposal_subtitle'
        : 'chat.plan_document_approved_subtitle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
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
                  titleKey.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                label: Text(statusKey.tr()),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitleKey.tr(),
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
          const SizedBox(height: 10),
          if (isDraftState)
            PlanMarkdownPreview(
              markdown: markdown ?? 'chat.plan_mode_empty'.tr(),
              maxHeight: 320,
            )
          else
            _ApprovedTimelinePlanSection(
              markdown: markdown ?? 'chat.plan_mode_empty'.tr(),
              isExpanded: isApprovedExpanded,
              onToggleExpanded: onToggleApprovedExpanded,
            ),
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
              if (showApproveProgress)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(
                      alpha: 0.9,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'chat.plan_proposal_generating'.tr(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (showApproveAction && canApprove)
                FilledButton.tonalIcon(
                  onPressed: chatState.isLoading || isGenerating
                      ? null
                      : onApprove,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text('chat.plan_proposal_approve_start'.tr()),
                ),
              if (showEdit)
                OutlinedButton.icon(
                  onPressed: chatState.isLoading || isGenerating
                      ? null
                      : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    (planArtifact.hasApproved
                            ? 'chat.plan_document_edit_approved'
                            : 'chat.plan_document_edit_draft')
                        .tr(),
                  ),
                ),
              if (canCancel)
                TextButton(
                  onPressed: chatState.isLoading || isGenerating
                      ? null
                      : onCancel,
                  child: Text('common.cancel'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApprovedTimelinePlanSection extends StatelessWidget {
  const _ApprovedTimelinePlanSection({
    required this.markdown,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  final String markdown;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isExpanded
                            ? 'chat.workflow_collapse'.tr()
                            : 'chat.workflow_expand'.tr(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: PlanMarkdownPreview(markdown: markdown, maxHeight: 320),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation.dart';

class CompactPlanFooterCard extends StatelessWidget {
  const CompactPlanFooterCard({
    super.key,
    required this.currentConversation,
    required this.isPlanMode,
    required this.onOpen,
    required this.onApprove,
    required this.onEdit,
    required this.onCancel,
  });

  final Conversation currentConversation;
  final bool isPlanMode;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artifact = currentConversation.effectivePlanArtifact;
    final isDraftState =
        isPlanMode || artifact.hasPendingEdits || !artifact.hasApproved;
    final statusKey = isDraftState
        ? (artifact.hasApproved && artifact.hasPendingEdits
              ? 'chat.plan_document_status_pending'
              : 'chat.plan_document_status_draft')
        : 'chat.plan_document_status_approved';
    final subtitleKey = isDraftState
        ? 'chat.plan_proposal_subtitle'
        : 'chat.plan_document_approved_subtitle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
                  isDraftState
                      ? 'chat.plan_proposal_title'.tr()
                      : 'chat.plan_document_title'.tr(),
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_full, size: 18),
                label: Text('chat.workflow_expand'.tr()),
              ),
              if (isDraftState)
                FilledButton.tonalIcon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text('chat.plan_proposal_approve_start'.tr()),
                ),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  (artifact.hasApproved
                          ? 'chat.plan_document_edit_approved'
                          : 'chat.plan_document_edit_draft')
                      .tr(),
                ),
              ),
              if (isDraftState)
                TextButton(
                  onPressed: onCancel,
                  child: Text('common.cancel'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

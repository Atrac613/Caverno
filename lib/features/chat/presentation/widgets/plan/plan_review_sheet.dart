import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_plan_artifact.dart';
import '../../../domain/services/conversation_plan_projection_service.dart';
import 'plan_markdown_preview.dart';

enum PlanReviewSheetAction { approve, edit, cancel }

class PlanReviewSheet extends StatelessWidget {
  const PlanReviewSheet({
    super.key,
    required this.planArtifact,
    required this.isPlanMode,
    required this.canApprove,
    required this.canCancel,
  });

  final ConversationPlanArtifact planArtifact;
  final bool isPlanMode;
  final bool canApprove;
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDraftState =
        isPlanMode || planArtifact.hasPendingEdits || !planArtifact.hasApproved;
    final markdown =
        planArtifact.displayMarkdown(isPlanning: isDraftState) ??
        planArtifact.displayMarkdown(isPlanning: false) ??
        '';
    final validation = markdown.isEmpty
        ? null
        : ConversationPlanProjectionService.validateDocument(
            markdown: markdown,
            requireTasks: true,
          );
    final statusKey = isDraftState
        ? (planArtifact.hasApproved && planArtifact.hasPendingEdits
              ? 'chat.plan_document_status_pending'
              : 'chat.plan_document_status_draft')
        : 'chat.plan_document_status_approved';
    final subtitleKey = isDraftState
        ? 'chat.plan_proposal_subtitle'
        : 'chat.plan_document_approved_subtitle';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.route_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDraftState
                        ? 'chat.plan_proposal_title'.tr()
                        : 'chat.plan_document_title'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
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
            const SizedBox(height: 8),
            Text(
              subtitleKey.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (validation != null) ...[
              const SizedBox(height: 12),
              Text(
                '${'chat.plan_document_preview_tasks'.tr()}: ${validation.previewTasks.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: PlanMarkdownPreview(
                markdown: markdown.isEmpty
                    ? 'chat.plan_mode_empty'.tr()
                    : markdown,
                maxHeight: MediaQuery.of(context).size.height,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (canApprove)
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(PlanReviewSheetAction.approve),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: Text('chat.plan_proposal_approve_start'.tr()),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(PlanReviewSheetAction.edit),
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
                    onPressed: () =>
                        Navigator.of(context).pop(PlanReviewSheetAction.cancel),
                    child: Text('common.cancel'.tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

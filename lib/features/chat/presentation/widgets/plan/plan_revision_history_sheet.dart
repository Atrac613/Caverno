import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_plan_artifact.dart';

class PlanRevisionHistorySheet extends StatelessWidget {
  const PlanRevisionHistorySheet({
    super.key,
    required this.planArtifact,
  });

  final ConversationPlanArtifact planArtifact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revisions = planArtifact.historyEntries;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'chat.plan_document_history_title'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'chat.plan_document_history_subtitle'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: revisions.isEmpty
                  ? Center(
                      child: Text(
                        'chat.plan_document_history_empty'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: revisions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final revision = revisions[index];
                        final markdownPreview =
                            revision.normalizedMarkdown
                                ?.split('\n')
                                .skip(1)
                                .take(3)
                                .join(' ')
                                .trim() ??
                            '';
                        final kindLabel = switch (revision.kind) {
                          ConversationPlanRevisionKind.draft =>
                            'chat.plan_document_revision_kind_draft'.tr(),
                          ConversationPlanRevisionKind.approved =>
                            'chat.plan_document_revision_kind_approved'.tr(),
                          ConversationPlanRevisionKind.restored =>
                            'chat.plan_document_revision_kind_restored'.tr(),
                        };
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          revision.normalizedLabel ?? kindLabel,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$kindLabel • ${DateFormat('MM/dd HH:mm').format(revision.createdAt.toLocal())}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(revision),
                                    child: Text(
                                      'chat.plan_document_history_restore_draft'
                                          .tr(),
                                    ),
                                  ),
                                ],
                              ),
                              if (markdownPreview.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  markdownPreview,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.close'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

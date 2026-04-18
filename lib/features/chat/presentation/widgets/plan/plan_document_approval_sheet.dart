import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/services/conversation_plan_projection_service.dart';

class PlanDocumentApprovalSheet extends StatelessWidget {
  const PlanDocumentApprovalSheet({
    super.key,
    required this.markdown,
    required this.validation,
  });

  final String markdown;
  final ConversationPlanValidationResult validation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewTasks = validation.previewTasks;
    final previewOpenQuestions = validation.previewOpenQuestions;

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
                'chat.plan_document_approve_review'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.plan_document_approve_preview_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${'chat.plan_document_preview_stage'.tr()}: ${validation.workflowStage?.name ?? 'idle'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${'chat.plan_document_preview_tasks'.tr()}: ${previewTasks.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${'chat.plan_document_preview_open_questions'.tr()}: ${previewOpenQuestions.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (previewTasks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final entry in previewTasks.indexed.take(6))
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '${entry.$1 + 1}. ${entry.$2.title}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (previewTasks.length > 6) ...[
                        const SizedBox(height: 4),
                        Text(
                          'chat.plan_document_preview_more_tasks'.tr(
                            namedArgs: {
                              'count': (previewTasks.length - 6).toString(),
                            },
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  markdown,
                  maxLines: 18,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('common.cancel'.tr()),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('chat.plan_document_approve'.tr()),
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

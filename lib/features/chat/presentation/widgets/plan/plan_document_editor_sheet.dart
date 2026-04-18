import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_plan_artifact.dart';
import '../../../domain/entities/conversation_workflow.dart';
import '../../../domain/services/conversation_plan_projection_service.dart';

class PlanDocumentEditorSubmission {
  const PlanDocumentEditorSubmission({
    required this.markdown,
    required this.validation,
  });

  final String markdown;
  final ConversationPlanValidationResult validation;
}

class PlanDocumentEditorSheet extends StatefulWidget {
  const PlanDocumentEditorSheet({
    super.key,
    required this.planArtifact,
    required this.preferDraft,
  });

  final ConversationPlanArtifact planArtifact;
  final bool preferDraft;

  @override
  State<PlanDocumentEditorSheet> createState() =>
      _PlanDocumentEditorSheetState();
}

class _PlanDocumentEditorSheetState extends State<PlanDocumentEditorSheet> {
  late final TextEditingController _markdownController;
  late ConversationPlanValidationResult _validation;

  @override
  void initState() {
    super.initState();
    _markdownController = TextEditingController(
      text:
          widget.planArtifact.displayMarkdown(isPlanning: widget.preferDraft) ??
          '',
    );
    _validation = _validate(_markdownController.text);
    _markdownController.addListener(_handleMarkdownChanged);
  }

  @override
  void dispose() {
    _markdownController.removeListener(_handleMarkdownChanged);
    _markdownController.dispose();
    super.dispose();
  }

  void _handleMarkdownChanged() {
    final nextValidation = _validate(_markdownController.text);
    if (nextValidation.isValid == _validation.isValid &&
        nextValidation.errorMessage == _validation.errorMessage &&
        nextValidation.workflowStage == _validation.workflowStage &&
        _sameTaskPreview(nextValidation.previewTasks, _validation.previewTasks)) {
      return;
    }
    setState(() {
      _validation = nextValidation;
    });
  }

  ConversationPlanValidationResult _validate(String markdown) {
    return ConversationPlanProjectionService.validateDocument(
      markdown: markdown,
      requireTasks: false,
    );
  }

  bool _sameTaskPreview(
    List<ConversationWorkflowTask> left,
    List<ConversationWorkflowTask> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].title != right[index].title ||
          left[index].status != right[index].status) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewTasks = _validation.previewTasks;
    final previewOpenQuestions = _validation.previewOpenQuestions;

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
                'chat.plan_document_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.plan_document_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _markdownController,
                maxLines: 18,
                minLines: 12,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.plan_document_title'.tr(),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _validation.isValid
                      ? theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.35,
                        )
                      : theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _validation.isValid
                          ? 'chat.plan_document_validation_valid'.tr()
                          : 'chat.plan_document_validation_invalid'.tr(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _validation.isValid
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _validation.isValid
                          ? 'chat.plan_document_validation_preview'.tr()
                          : (_validation.issues.isNotEmpty
                                ? _validation.issues.join('\n')
                                : _validation.errorMessage ??
                                      'chat.plan_document_validation_fallback'
                                          .tr()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _validation.isValid
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    if (_validation.isValid) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${'chat.plan_document_preview_stage'.tr()}: ${_validation.workflowStage?.name ?? 'idle'}',
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
                        const SizedBox(height: 6),
                        for (final entry in previewTasks.take(4).indexed)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${entry.$1 + 1}. ${entry.$2.title}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (previewTasks.length > 4)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'chat.plan_document_preview_more_tasks'.tr(
                                namedArgs: {
                                  'count': (previewTasks.length - 4).toString(),
                                },
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.planArtifact.hasApproved)
                    TextButton.icon(
                      onPressed: () {
                        _markdownController.text =
                            widget.planArtifact.normalizedApprovedMarkdown ??
                            '';
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: Text('common.reset'.tr()),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _validation.isValid
                        ? () => Navigator.of(context).pop(
                            PlanDocumentEditorSubmission(
                              markdown: _markdownController.text,
                              validation: _validation,
                            ),
                          )
                        : null,
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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/conversation_workflow.dart';
import '../../coordinators/workflow_editor_action_coordinator.dart';

class WorkflowEditorSheet extends StatefulWidget {
  const WorkflowEditorSheet({
    super.key,
    required this.currentConversation,
    this.initialWorkflowStage,
    this.initialWorkflowSpec,
    required this.workflowStageLabelBuilder,
  });

  final Conversation currentConversation;
  final ConversationWorkflowStage? initialWorkflowStage;
  final ConversationWorkflowSpec? initialWorkflowSpec;
  final String Function(ConversationWorkflowStage stage)
  workflowStageLabelBuilder;

  @override
  State<WorkflowEditorSheet> createState() => _WorkflowEditorSheetState();
}

class _WorkflowEditorSheetState extends State<WorkflowEditorSheet> {
  late final TextEditingController _goalController;
  late final TextEditingController _constraintsController;
  late final TextEditingController _acceptanceController;
  late final TextEditingController _openQuestionsController;
  late ConversationWorkflowStage _selectedStage;

  @override
  void initState() {
    super.initState();
    final spec =
        widget.initialWorkflowSpec ??
        widget.currentConversation.effectiveWorkflowSpec;
    _selectedStage =
        widget.initialWorkflowStage ?? widget.currentConversation.workflowStage;
    _goalController = TextEditingController(text: spec.goal);
    _constraintsController = TextEditingController(
      text: spec.constraints.join('\n'),
    );
    _acceptanceController = TextEditingController(
      text: spec.acceptanceCriteria.join('\n'),
    );
    _openQuestionsController = TextEditingController(
      text: spec.openQuestions.join('\n'),
    );
  }

  @override
  void dispose() {
    _goalController.dispose();
    _constraintsController.dispose();
    _acceptanceController.dispose();
    _openQuestionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                'chat.workflow_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.workflow_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<ConversationWorkflowStage>(
                initialValue: _selectedStage,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_stage'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationWorkflowStage.values
                    .map(
                      (stage) => DropdownMenuItem(
                        value: stage,
                        child: Text(widget.workflowStageLabelBuilder(stage)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStage = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _goalController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_goal'.tr(),
                  hintText: 'chat.workflow_goal_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _constraintsController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_constraints'.tr(),
                  hintText: 'chat.workflow_constraints_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _acceptanceController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_acceptance'.tr(),
                  hintText: 'chat.workflow_acceptance_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _openQuestionsController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_open_questions'.tr(),
                  hintText: 'chat.workflow_open_questions_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(const WorkflowEditorSubmission.clear());
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text('chat.workflow_clear'.tr()),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        WorkflowEditorSubmission.save(
                          workflowStage: _selectedStage,
                          workflowSpec: ConversationWorkflowSpec(
                            goal: _goalController.text.trim(),
                            constraints: _workflowLinesFromText(
                              _constraintsController.text,
                            ),
                            acceptanceCriteria: _workflowLinesFromText(
                              _acceptanceController.text,
                            ),
                            openQuestions: _workflowLinesFromText(
                              _openQuestionsController.text,
                            ),
                            tasks: widget
                                .currentConversation
                                .effectiveWorkflowSpec
                                .tasks,
                          ),
                        ),
                      );
                    },
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

List<String> _workflowLinesFromText(String rawValue) {
  return rawValue
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

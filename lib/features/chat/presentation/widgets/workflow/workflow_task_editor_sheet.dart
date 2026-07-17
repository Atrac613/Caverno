import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';
import '../../coordinators/workflow_task_action_coordinator.dart';

class WorkflowTaskEditorSheet extends StatefulWidget {
  const WorkflowTaskEditorSheet({
    super.key,
    required this.task,
    required this.statusLabelBuilder,
  });

  final ConversationWorkflowTask? task;
  final String Function(ConversationWorkflowTaskStatus status)
  statusLabelBuilder;

  @override
  State<WorkflowTaskEditorSheet> createState() =>
      _WorkflowTaskEditorSheetState();
}

class _WorkflowTaskEditorSheetState extends State<WorkflowTaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _targetFilesController;
  late final TextEditingController _validationController;
  late final TextEditingController _notesController;
  late ConversationWorkflowTaskStatus _selectedStatus;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _selectedStatus = task?.status ?? ConversationWorkflowTaskStatus.pending;
    _titleController = TextEditingController(text: task?.title ?? '');
    _targetFilesController = TextEditingController(
      text: task?.targetFiles.join('\n') ?? '',
    );
    _validationController = TextEditingController(
      text: task?.validationCommand ?? '',
    );
    _notesController = TextEditingController(text: task?.notes ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetFilesController.dispose();
    _validationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingTask = widget.task;
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
                existingTask == null
                    ? 'chat.workflow_task_add'.tr()
                    : 'chat.workflow_task_edit'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.workflow_task_sheet_subtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_title'.tr(),
                  hintText: 'chat.workflow_task_title_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ConversationWorkflowTaskStatus>(
                initialValue: _selectedStatus,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_status'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: ConversationWorkflowTaskStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(widget.statusLabelBuilder(status)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedStatus = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _targetFilesController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_target_files'.tr(),
                  hintText: 'chat.workflow_task_target_files_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _validationController,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_validation'.tr(),
                  hintText: 'chat.workflow_task_validation_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'chat.workflow_task_notes'.tr(),
                  hintText: 'chat.workflow_task_notes_hint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (existingTask != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          WorkflowTaskEditorSubmission.delete(
                            task: existingTask,
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text('chat.workflow_task_delete'.tr()),
                    ),
                  if (existingTask != null) const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        WorkflowTaskEditorSubmission.save(
                          task: ConversationWorkflowTask(
                            id: existingTask?.id ?? '',
                            title: _titleController.text.trim(),
                            status: _selectedStatus,
                            targetFiles: _workflowLinesFromText(
                              _targetFilesController.text,
                            ),
                            validationCommand: _validationController.text
                                .trim(),
                            notes: _notesController.text.trim(),
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

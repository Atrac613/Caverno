import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';

class ConversationPlanExecutionCoordinator {
  ConversationPlanExecutionCoordinator._();

  static String buildTaskPrompt({
    required ConversationWorkflowTask task,
    required String intro,
    required String targetFilesLabel,
    required String validationLabel,
    required String notesLabel,
    required String outro,
  }) {
    final promptLines = <String>[intro, 'Saved task ID: ${task.id}'];
    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('$targetFilesLabel: $targetFiles');
    }
    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('$validationLabel: $validationCommand');
    }
    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('$notesLabel: $notes');
    }
    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(outro);
    return promptLines.join('\n');
  }

  static String buildValidationPrompt({
    required ConversationWorkflowTask task,
    required String intro,
    required String targetFilesLabel,
    required String validationLabel,
    required String outro,
  }) {
    final promptLines = <String>[intro];
    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('$validationLabel: $validationCommand');
    }
    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('$targetFilesLabel: $targetFiles');
    }
    promptLines.add(outro);
    return promptLines.join('\n');
  }

  static String buildAutoContinueTaskPrompt({
    required ConversationWorkflowTask completedTask,
    required ConversationWorkflowTask nextTask,
  }) {
    final promptLines = <String>[
      'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
      'Ignore the previous saved task context in the transcript and focus only on the next task below.',
      'Completed task ID: ${completedTask.id}',
      'Completed task: ${completedTask.title.trim()}',
      'Next task ID: ${nextTask.id}',
      'Next task: ${nextTask.title.trim()}',
    ];

    final targetFiles = nextTask.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Target files: $targetFiles');
    }

    final validationCommand = nextTask.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Validation: $validationCommand');
    }

    final notes = nextTask.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(nextTask));
    promptLines.add(
      'Persisted saved task statuses from the app are the source of truth.',
    );
    promptLines.add(
      'Do not mark any other saved task complete, blocked, skipped, or in progress unless this turn produces concrete evidence for the current task.',
    );
    promptLines.add(
      'Do not continue the completed task again. Follow only the next task ID listed above.',
    );
    promptLines.add(
      'Implement the next task now. Only pause if you are blocked, the requirements changed, or completing it would require changing the approved workflow.',
    );
    return promptLines.join('\n');
  }

  static String buildToolLessExecutionRecoveryPrompt({
    required ConversationWorkflowTask task,
  }) {
    final isScaffoldTask = _looksLikeScaffoldTask(task);
    final hasValidationCommand = task.validationCommand.trim().isNotEmpty;
    final promptLines = <String>[
      'The saved task stalled without any concrete tool call, file change, or validation result.',
      'Recover by taking one concrete action now.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
    ];

    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Target files: $targetFiles');
    }

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Validation: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    if (isScaffoldTask && hasValidationCommand) {
      promptLines.add(
        'This is a scaffold or setup task. If the scaffold files are already in place, run the saved validation command now instead of repeating the setup plan.',
      );
      promptLines.add(
        'Do not restate the scaffold steps or file list without a tool call or validation result.',
      );
      promptLines.add(
        'Your next reply must either run the saved validation command now or modify one missing target file.',
      );
    } else {
      promptLines.add(
        'Your next reply must either modify one of the saved target files or run the saved validation command now.',
      );
    }
    promptLines.add(
      'Do not restate the plan, do not ask for confirmation, and do not describe future tasks.',
    );
    return promptLines.join('\n');
  }

  static String buildVerificationTaskRecoveryPrompt({
    required ConversationWorkflowTask task,
  }) {
    final promptLines = <String>[
      'The saved verification task stalled before running its concrete check.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
    ];

    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Target files: $targetFiles');
    }

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Saved validation command: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(
      'Run the saved validation command now instead of restating the verification steps.',
    );
    promptLines.add(
      'If the saved validation command fails, fix only the failing saved target file or report the blocker clearly.',
    );
    promptLines.add(
      'Do not create duplicate verification tasks, do not ask for confirmation, and do not describe future saved tasks.',
    );
    return promptLines.join('\n');
  }

  static String buildScaffoldRemainingTargetRecoveryPrompt({
    required ConversationWorkflowTask task,
    required List<String> existingTargetFiles,
    required List<String> missingTargetFiles,
  }) {
    final promptLines = <String>[
      'The scaffold task already created some target files but is still incomplete.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
      'Already created target files: ${existingTargetFiles.join(', ')}',
      'Remaining target files: ${missingTargetFiles.join(', ')}',
    ];

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Validation: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(
      'Create exactly one remaining target file now instead of restating the scaffold plan.',
    );
    promptLines.add(
      'Do not rewrite already-created scaffold files unless the saved validation step later proves they are wrong.',
    );
    promptLines.add(
      'After every remaining target file exists, run the saved validation command immediately.',
    );
    return promptLines.join('\n');
  }

  static String buildScaffoldMissingTargetRecoveryPrompt({
    required ConversationWorkflowTask task,
    required List<String> missingTargetFiles,
  }) {
    final promptLines = <String>[
      'The scaffold task still has no saved target files in place.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
      'Missing target files: ${missingTargetFiles.join(', ')}',
    ];

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Validation: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(
      'Create exactly one missing target file now using its saved path.',
    );
    promptLines.add(
      'Do not create alternative filenames, test files, or extra scaffold files that are not listed in the saved targets.',
    );
    promptLines.add(
      'Do not run validation until every missing target file exists.',
    );
    return promptLines.join('\n');
  }

  static String buildToolFailureRecoveryPrompt({
    required ConversationWorkflowTask task,
    List<String> unavailableToolNames = const [],
    List<String> editMismatchPaths = const [],
    List<String> malformedFileMutationPaths = const [],
    bool hasMalformedFileMutationFailure = false,
  }) {
    final promptLines = <String>[
      'The saved task hit a recoverable tool failure.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
    ];

    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Target files: $targetFiles');
    }

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Validation: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    if (unavailableToolNames.isNotEmpty) {
      promptLines.add(
        'Do not call these unavailable tools again: ${unavailableToolNames.join(', ')}',
      );
      promptLines.add(
        'Use only tools that are currently available in the tool list.',
      );
    }

    if (editMismatchPaths.isNotEmpty) {
      promptLines.add(
        'These files failed with edit mismatch: ${editMismatchPaths.join(', ')}',
      );
      promptLines.add(
        'Read each mismatched file before retrying edit_file and use the exact current file content as old_text.',
      );
    }

    if (hasMalformedFileMutationFailure) {
      if (malformedFileMutationPaths.isNotEmpty) {
        promptLines.add(
          'These file mutations failed because required arguments were malformed: ${malformedFileMutationPaths.join(', ')}',
        );
      } else {
        promptLines.add(
          'At least one write_file or edit_file call failed because required top-level arguments were malformed.',
        );
      }
      promptLines.add(
        'Retry the same file mutation with top-level path and content keys for write_file, or path plus old_text and new_text for edit_file.',
      );
      promptLines.add(
        'If an edit_file call failed because old_text was missing or empty, read the current file first and reuse its exact contents as old_text.',
      );
      promptLines.add(
        'Do not wrap file arguments in malformed aliases or move path outside the arguments object.',
      );
    }

    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(
      'Your next action must directly modify a saved target file, read a mismatched saved target file, or run the saved validation command.',
    );
    promptLines.add(
      'Do not switch to unrelated files, do not retry unavailable tools, and do not move to future saved tasks.',
    );
    return promptLines.join('\n');
  }

  static String buildValidationFirstRecoveryPrompt({
    required ConversationWorkflowTask task,
    List<String> touchedTargetFiles = const [],
    List<String> remainingTargetFiles = const [],
    required bool preferValidationNow,
  }) {
    final promptLines = <String>[
      'The saved task already made concrete file progress.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
    ];

    if (touchedTargetFiles.isNotEmpty) {
      promptLines.add(
        'Already updated target files: ${touchedTargetFiles.join(', ')}',
      );
    }
    if (remainingTargetFiles.isNotEmpty) {
      promptLines.add(
        'Remaining target files: ${remainingTargetFiles.join(', ')}',
      );
    }

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Saved validation command: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Saved task notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    if (preferValidationNow) {
      promptLines.add(
        'Run the saved validation command now instead of restating the implementation plan.',
      );
      promptLines.add(
        'Only return to file edits if the saved validation command fails and the failure points to a target file.',
      );
    } else {
      promptLines.add(
        'Finish one remaining target file now, or run the saved validation command immediately if the remaining files are already satisfied.',
      );
    }
    promptLines.add(
      'Do not describe future tasks, and do not repeat the task plan without a tool call or validation result.',
    );
    return promptLines.join('\n');
  }

  static String buildPythonSrcLayoutValidationRecoveryPrompt({
    required ConversationWorkflowTask task,
    required String failedCommand,
    required String retryCommand,
    String? blockedModuleName,
  }) {
    final promptLines = <String>[
      'The saved validation command failed because the Python src-layout module import was not discoverable.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
      'Failed validation command: ${failedCommand.trim()}',
      'Retry validation command: ${retryCommand.trim()}',
    ];

    final moduleName = blockedModuleName?.trim();
    if (moduleName != null && moduleName.isNotEmpty) {
      promptLines.add('Blocked module: $moduleName');
    }

    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Target files: $targetFiles');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(
      'Run the retry validation command now before making any more file edits.',
    );
    promptLines.add(
      'Do not switch tasks, do not restate the plan, and do not rewrite already-covered files unless the retry validation command fails with a target-file-specific error.',
    );
    return promptLines.join('\n');
  }

  static String buildMissingTargetFileRecoveryPrompt({
    required ConversationWorkflowTask task,
    required List<String> missingTargetFiles,
    required String failedCommand,
  }) {
    final promptLines = <String>[
      'The saved validation command ran before every required target file existed.',
      'Saved task ID: ${task.id}',
      'Saved task: ${task.title.trim()}',
      'Failed validation command: ${failedCommand.trim()}',
      'Missing target files: ${missingTargetFiles.join(', ')}',
    ];

    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Target files: $targetFiles');
    }

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Validation: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Notes: $notes');
    }

    promptLines.addAll(_executionGuardrailLines(task));
    promptLines.add(
      'Create or edit one missing target file now before running the saved validation command again.',
    );
    promptLines.add(
      'Do not rerun validation until the missing target files exist, and do not restate the plan without a tool call.',
    );
    return promptLines.join('\n');
  }

  static String buildTaskDriftRecoveryPrompt({
    required ConversationWorkflowTask task,
    required List<String> unrelatedTouchedPaths,
    required List<String> scaffoldCommands,
    List<String> alreadyTouchedTargetFiles = const [],
    List<String> repeatedTargetFiles = const [],
    List<String> remainingTargetFiles = const [],
  }) {
    final promptLines = <String>[
      'Saved task drift detected.',
      'Saved task: ${task.title.trim()}',
    ];

    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      promptLines.add('Only touch these target files next: $targetFiles');
    }

    if (alreadyTouchedTargetFiles.isNotEmpty) {
      promptLines.add(
        'You already updated these target files: ${alreadyTouchedTargetFiles.join(', ')}',
      );
    }

    if (repeatedTargetFiles.isNotEmpty) {
      promptLines.add(
        'Do not rewrite these target files again unless validation fails: ${repeatedTargetFiles.join(', ')}',
      );
      promptLines.add('Stop rewriting already-covered files.');
    }

    if (remainingTargetFiles.isNotEmpty) {
      promptLines.add(
        'Focus on the remaining target files next: ${remainingTargetFiles.join(', ')}',
      );
      promptLines.add(
        'Finish the remaining target files before making any other edits.',
      );
    }

    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      promptLines.add('Saved validation command: $validationCommand');
    }

    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      promptLines.add('Saved task notes: $notes');
    }

    if (unrelatedTouchedPaths.isNotEmpty) {
      promptLines.add(
        'Ignore these unrelated paths: ${unrelatedTouchedPaths.join(', ')}',
      );
    }

    if (scaffoldCommands.isNotEmpty) {
      if (scaffoldCommands.length == 1) {
        promptLines.add(
          'Ignore this unrelated scaffolding command: ${scaffoldCommands.single}',
        );
      } else {
        promptLines.add(
          'Ignore these unrelated scaffolding commands: ${scaffoldCommands.join(' | ')}',
        );
      }
    }

    promptLines.add(
      'Do not scaffold new packages, project roots, or dependency files unless one of the saved target files explicitly requires it.',
    );
    promptLines.add(
      'Do not implement future saved tasks while recovering this task.',
    );
    if (remainingTargetFiles.isNotEmpty) {
      promptLines.add(
        'Your next action must directly modify one of the remaining target files or run the saved validation command.',
      );
    } else {
      promptLines.add(
        'Your next action must directly modify one of the target files or run the saved validation command.',
      );
    }
    promptLines.add(
      'If every target file is already covered, run the saved validation command now instead of rewriting files.',
    );
    return promptLines.join('\n');
  }

  static List<String> _executionGuardrailLines(ConversationWorkflowTask task) {
    final lines = <String>[
      'Work only on this saved task. Do not implement future saved tasks.',
    ];
    if (task.targetFiles.any((item) => item.trim().isNotEmpty)) {
      lines.add(
        'Do not create or modify files outside the target files unless the saved validation step requires it.',
      );
    }
    if (task.validationCommand.trim().isNotEmpty) {
      lines.add(
        'Stop after the saved validation step and report that result before moving on.',
      );
      lines.add(
        'Do not run the saved validation command until the current task target files exist and you have created or updated the relevant target file for this task.',
      );
    }
    return lines;
  }

  static bool looksLikeVerificationTask(ConversationWorkflowTask task) {
    return _looksLikeVerificationTask(task);
  }

  static bool _looksLikeScaffoldTask(ConversationWorkflowTask task) {
    final normalized = '${task.title.trim()} ${task.notes.trim()}'
        .toLowerCase();
    const keywords = <String>[
      'scaffold',
      'initial',
      'initialize',
      'bootstrap',
      'project structure',
      'requirements',
      'dependency',
      'dependencies',
      'pyproject',
      'package layout',
      'setup',
    ];
    return keywords.any(normalized.contains);
  }

  static bool _looksLikeVerificationTask(ConversationWorkflowTask task) {
    final normalized = '${task.title.trim()} ${task.notes.trim()}'
        .toLowerCase();
    const keywords = <String>[
      'verify ',
      'verification',
      'smoke test',
      'manual test',
      'real host',
      'live host',
      'live ping',
      'host verification',
    ];
    return keywords.any(normalized.contains);
  }

  static String buildBlockedTaskReplanContext({
    required Conversation conversation,
    required ConversationWorkflowTask task,
    required String blockedReason,
  }) {
    final progress = conversation.executionProgressForTask(task.id);
    final buffer = StringBuffer()
      ..writeln('Focus the next draft on resolving the active blocker.')
      ..writeln('- blockedTask: ${task.title.trim()}')
      ..writeln('- blockedReason: ${blockedReason.trim()}');
    final targetFiles = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (targetFiles.isNotEmpty) {
      buffer.writeln('- targetFiles: $targetFiles');
    }
    final validationCommand = task.validationCommand.trim();
    if (validationCommand.isNotEmpty) {
      buffer.writeln('- validationCommand: $validationCommand');
    }
    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      buffer.writeln('- notes: $notes');
    }
    final recentEvents = progress?.recentEvents.reversed
        .take(3)
        .map((event) {
          final detail =
              event.normalizedSummary ??
              event.normalizedValidationSummary ??
              event.normalizedBlockedReason ??
              event.status.name;
          return '${event.type.name}: $detail';
        })
        .join(' || ');
    if (recentEvents != null && recentEvents.isNotEmpty) {
      buffer.writeln('- recentEvents: $recentEvents');
    }
    buffer.write(_buildPreservedTasksBlock(conversation, focusedTask: task));
    buffer.writeln(
      '- expectation: either remove the blocker from the plan or add the minimum follow-up work needed to unblock implementation.',
    );
    return buffer.toString().trimRight();
  }

  static String buildScopedTaskReplanContext({
    required Conversation conversation,
    required ConversationWorkflowTask task,
  }) {
    final progress = conversation.executionProgressForTask(task.id);
    final buffer = StringBuffer()
      ..writeln('Focus the next draft on the current implementation task only.')
      ..writeln('- currentTaskId: ${task.id}')
      ..writeln('- currentTask: ${task.title.trim()}');
    final summary = progress?.normalizedSummary;
    if (summary != null) {
      buffer.writeln('- executionSummary: $summary');
    }
    final blockedReason = progress?.normalizedBlockedReason;
    if (blockedReason != null) {
      buffer.writeln('- blockedReason: $blockedReason');
    }
    final notes = task.notes.trim();
    if (notes.isNotEmpty) {
      buffer.writeln('- notes: $notes');
    }
    buffer.write(_buildPreservedTasksBlock(conversation, focusedTask: task));
    buffer.writeln(
      '- expectation: keep unaffected tasks unchanged by Task ID unless the focused task truly requires a narrow follow-up adjustment.',
    );
    return buffer.toString().trimRight();
  }

  static String buildValidationScopedReplanContext({
    required Conversation conversation,
    required ConversationWorkflowTask task,
  }) {
    final progress = conversation.executionProgressForTask(task.id);
    final buffer = StringBuffer()
      ..writeln(
        'Focus the next draft on the saved validation path for the current task.',
      )
      ..writeln('- validationTaskId: ${task.id}')
      ..writeln('- validationTask: ${task.title.trim()}')
      ..writeln('- validationCommand: ${task.validationCommand.trim()}');
    final validationSummary = progress?.normalizedValidationSummary;
    if (validationSummary != null) {
      buffer.writeln('- validationSummary: $validationSummary');
    }
    final blockedReason = progress?.normalizedBlockedReason;
    if (blockedReason != null) {
      buffer.writeln('- blockedReason: $blockedReason');
    }
    buffer.write(_buildPreservedTasksBlock(conversation, focusedTask: task));
    buffer.writeln(
      '- expectation: keep unrelated tasks unchanged and update only the minimum validation steps needed to move execution forward.',
    );
    return buffer.toString().trimRight();
  }

  static ConversationWorkflowTask? activeTask(Conversation conversation) {
    for (final task in conversation.projectedExecutionTasks) {
      if (task.status == ConversationWorkflowTaskStatus.inProgress) {
        return task;
      }
    }
    return null;
  }

  static ConversationWorkflowTask? nextTask(Conversation conversation) {
    final active = activeTask(conversation);
    if (active != null) {
      return active;
    }
    for (final task in conversation.projectedExecutionTasks) {
      if (task.status == ConversationWorkflowTaskStatus.pending) {
        return task;
      }
    }
    return null;
  }

  static ConversationWorkflowTask? blockedTask(Conversation conversation) {
    for (final task in conversation.projectedExecutionTasks) {
      if (task.status == ConversationWorkflowTaskStatus.blocked) {
        return task;
      }
    }
    return null;
  }

  static ConversationWorkflowTask? executionFocusTask(
    Conversation conversation,
  ) {
    final active = activeTask(conversation);
    if (active != null) {
      return active;
    }
    final blocked = blockedTask(conversation);
    if (blocked != null) {
      return blocked;
    }
    return nextTask(conversation);
  }

  static ConversationWorkflowTask? validationTask(Conversation conversation) {
    final candidates = [
      executionFocusTask(conversation),
      nextTask(conversation),
      ...conversation.projectedExecutionTasks,
    ];
    for (final task in candidates) {
      if (task == null) {
        continue;
      }
      if (task.validationCommand.trim().isNotEmpty) {
        return task;
      }
    }
    return null;
  }

  static String _buildPreservedTasksBlock(
    Conversation conversation, {
    required ConversationWorkflowTask focusedTask,
  }) {
    final preservedTasks = conversation.projectedExecutionTasks
        .where((task) => task.id != focusedTask.id)
        .toList(growable: false);
    if (preservedTasks.isEmpty) {
      return '';
    }

    final buffer = StringBuffer()..writeln('- preserveTaskIds:');
    for (final task in preservedTasks) {
      buffer.writeln('  - ${task.id}: ${task.title.trim()}');
    }
    return buffer.toString();
  }
}

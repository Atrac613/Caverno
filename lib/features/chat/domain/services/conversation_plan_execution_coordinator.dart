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
    final promptLines = <String>[intro];
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
    buffer.write(
      _buildPreservedTasksBlock(conversation, focusedTask: task),
    );
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
    buffer.write(
      _buildPreservedTasksBlock(conversation, focusedTask: task),
    );
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
    buffer.write(
      _buildPreservedTasksBlock(conversation, focusedTask: task),
    );
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

  static ConversationWorkflowTask? validationTask(Conversation conversation) {
    final candidates = [
      activeTask(conversation),
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

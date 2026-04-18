import '../entities/conversation_workflow.dart';

class ConversationPlanDocumentBuilder {
  ConversationPlanDocumentBuilder._();

  static String build({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
    List<ConversationWorkflowTask>? tasks,
  }) {
    final effectiveTasks = tasks ?? workflowSpec.tasks;
    final buffer = StringBuffer()
      ..writeln('# Plan')
      ..writeln()
      ..writeln('## Stage')
      ..writeln(workflowStage.name);

    if (workflowSpec.goal.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Goal')
        ..writeln(workflowSpec.goal.trim());
    }

    _writeListSection(
      buffer,
      heading: 'Constraints',
      items: workflowSpec.constraints,
    );
    _writeListSection(
      buffer,
      heading: 'Acceptance Criteria',
      items: workflowSpec.acceptanceCriteria,
    );
    _writeListSection(
      buffer,
      heading: 'Open Questions',
      items: workflowSpec.openQuestions,
    );

    final normalizedTasks = effectiveTasks
        .where((task) => task.title.trim().isNotEmpty)
        .toList(growable: false);
    if (normalizedTasks.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Tasks');
      for (final entry in normalizedTasks.indexed) {
        final index = entry.$1 + 1;
        final task = entry.$2;
        buffer
          ..writeln()
          ..writeln('$index. ${task.title.trim()}')
          ..writeln('   - Status: ${task.status.name}');
        final targetFiles = task.targetFiles
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (targetFiles.isNotEmpty) {
          buffer.writeln('   - Target files: ${targetFiles.join(', ')}');
        }
        final validationCommand = task.validationCommand.trim();
        if (validationCommand.isNotEmpty) {
          buffer.writeln('   - Validation: $validationCommand');
        }
        final notes = task.notes.trim();
        if (notes.isNotEmpty) {
          buffer.writeln('   - Notes: $notes');
        }
      }
    }

    return buffer.toString().trimRight();
  }

  static void _writeListSection(
    StringBuffer buffer, {
    required String heading,
    required List<String> items,
  }) {
    final normalizedItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalizedItems.isEmpty) {
      return;
    }

    buffer
      ..writeln()
      ..writeln('## $heading');
    for (final item in normalizedItems) {
      buffer.writeln('- $item');
    }
  }
}

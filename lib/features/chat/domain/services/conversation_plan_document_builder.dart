import '../entities/conversation_workflow.dart';
import '../entities/conversation_plan_artifact.dart';
import 'conversation_contract_provenance_service.dart';
import 'conversation_plan_projection_service.dart';

class ConversationPlanDocumentBuilder {
  ConversationPlanDocumentBuilder._();

  static ConversationPlanArtifact buildApprovedArtifact({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
    List<ConversationWorkflowTask>? tasks,
    DateTime? updatedAt,
  }) {
    final markdown = build(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
      tasks: tasks,
    );
    return ConversationPlanArtifact(
      approvedMarkdown: markdown,
      updatedAt: updatedAt,
    ).recordRevision(
      markdown: markdown,
      kind: ConversationPlanRevisionKind.approved,
      label: 'Built approved plan document',
      createdAt: updatedAt,
    );
  }

  static String buildApprovedSnapshotMarkdown({
    required ConversationPlanArtifact currentArtifact,
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
    required List<ConversationWorkflowTask> tasks,
  }) {
    if (tasks.isNotEmpty) {
      return build(
        workflowStage: workflowStage,
        workflowSpec: workflowSpec,
        tasks: tasks,
      );
    }

    final normalizedDraft = currentArtifact.normalizedDraftMarkdown;
    if (normalizedDraft != null) {
      final stagedDraft =
          ConversationPlanProjectionService.replaceWorkflowStage(
            markdown: normalizedDraft,
            workflowStage: workflowStage,
          );
      final validation = ConversationPlanProjectionService.validateDocument(
        markdown: stagedDraft,
        requireTasks: tasks.isNotEmpty,
      );
      if (validation.isValid &&
          (tasks.isEmpty || validation.previewTasks.isNotEmpty)) {
        return stagedDraft;
      }
    }

    return build(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
      tasks: tasks,
    );
  }

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
      spec: workflowSpec,
      kind: ConversationContractItemKind.constraint,
    );
    _writeListSection(
      buffer,
      heading: 'Acceptance Criteria',
      items: workflowSpec.acceptanceCriteria,
      spec: workflowSpec,
      kind: ConversationContractItemKind.acceptanceCriterion,
    );
    _writeListSection(
      buffer,
      heading: 'Open Questions',
      items: workflowSpec.openQuestions,
      spec: workflowSpec,
      kind: ConversationContractItemKind.openQuestion,
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
        final taskId = task.id.trim();
        buffer
          ..writeln()
          ..writeln('$index. ${task.title.trim()}');
        if (taskId.isNotEmpty) {
          buffer.writeln('   - Task ID: $taskId');
        }
        buffer.writeln('   - Status: ${task.status.name}');
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
        // One line per edge rather than a comma list: a question precondition
        // is referenced by its own text, which may contain a comma.
        for (final precondition in task.preconditions) {
          if (!precondition.isValid) continue;
          buffer.writeln(
            '   - Requires: ${precondition.kind.name}: '
            '${precondition.ref.trim()}',
          );
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
    required ConversationWorkflowSpec spec,
    required ConversationContractItemKind kind,
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
      buffer.writeln('- $item${markerFor(spec, kind: kind, value: item)}');
    }
  }

  /// The epistemic marker for one item, or an empty string when it is plain.
  ///
  /// Anabasis ANA0. Written from the spec's own provenance so the document
  /// stays the authoritative middle: what the projection reads back is exactly
  /// what the contract held.
  ///
  /// Public because the planning prompt echoes the saved contract back to the
  /// model and has to echo the marks with it. An echo that drops them asks for
  /// a revision of a contract the model is shown as fully confirmed, and every
  /// assumption decays on the next pass — a loss that would then be measured
  /// as the model declining to mark.
  static String markerFor(
    ConversationWorkflowSpec spec, {
    required ConversationContractItemKind kind,
    required String value,
  }) {
    const provenanceService = ConversationContractProvenanceService();
    final id = provenanceService.itemId(kind: kind, value: value);
    for (final item in spec.provenance) {
      if (item.itemId != id) continue;
      return ContractItemMarks(
        assumption: item.assumption,
        material: item.material,
      ).bulletSuffix;
    }
    return '';
  }
}

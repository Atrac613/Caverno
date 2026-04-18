import '../entities/conversation_workflow.dart';
import 'conversation_plan_projection_service.dart';

enum ConversationPlanTaskDiffType { added, removed, changed }

class ConversationPlanTaskDiffEntry {
  const ConversationPlanTaskDiffEntry({
    required this.type,
    required this.identity,
    this.beforeTask,
    this.afterTask,
  });

  final ConversationPlanTaskDiffType type;
  final String identity;
  final ConversationWorkflowTask? beforeTask;
  final ConversationWorkflowTask? afterTask;

  String get displayTitle =>
      afterTask?.title.trim() ?? beforeTask?.title.trim() ?? identity;
}

class ConversationPlanDiffResult {
  const ConversationPlanDiffResult._({
    required this.entries,
    this.errorMessage,
  });

  const ConversationPlanDiffResult.valid(
    List<ConversationPlanTaskDiffEntry> value,
  ) : this._(entries: value);

  const ConversationPlanDiffResult.invalid(String message)
    : this._(entries: const [], errorMessage: message);

  final List<ConversationPlanTaskDiffEntry> entries;
  final String? errorMessage;

  bool get isValid => errorMessage == null;
  bool get hasChanges => entries.isNotEmpty;

  int countByType(ConversationPlanTaskDiffType type) =>
      entries.where((entry) => entry.type == type).length;
}

class ConversationPlanDiffService {
  ConversationPlanDiffService._();

  static ConversationPlanDiffResult buildTaskDiff({
    required String approvedMarkdown,
    required String draftMarkdown,
  }) {
    final approvedValidation =
        ConversationPlanProjectionService.validateDocument(
          markdown: approvedMarkdown,
          requireTasks: false,
        );
    if (!approvedValidation.isValid) {
      return ConversationPlanDiffResult.invalid(
        approvedValidation.errorMessage ??
            'approved plan document could not be parsed',
      );
    }

    final draftValidation = ConversationPlanProjectionService.validateDocument(
      markdown: draftMarkdown,
      requireTasks: false,
    );
    if (!draftValidation.isValid) {
      return ConversationPlanDiffResult.invalid(
        draftValidation.errorMessage ??
            'draft plan document could not be parsed',
      );
    }

    final approvedTasks = approvedValidation.previewTasks;
    final draftTasks = draftValidation.previewTasks;
    final approvedByIdentity = {
      for (final task in approvedTasks) _taskIdentity(task): task,
    };
    final draftByIdentity = {
      for (final task in draftTasks) _taskIdentity(task): task,
    };
    final identities = <String>{
      ...approvedByIdentity.keys,
      ...draftByIdentity.keys,
    }.toList(growable: false)..sort();

    final entries = <ConversationPlanTaskDiffEntry>[];
    for (final identity in identities) {
      final beforeTask = approvedByIdentity[identity];
      final afterTask = draftByIdentity[identity];
      if (beforeTask == null && afterTask != null) {
        entries.add(
          ConversationPlanTaskDiffEntry(
            type: ConversationPlanTaskDiffType.added,
            identity: identity,
            afterTask: afterTask,
          ),
        );
        continue;
      }
      if (beforeTask != null && afterTask == null) {
        entries.add(
          ConversationPlanTaskDiffEntry(
            type: ConversationPlanTaskDiffType.removed,
            identity: identity,
            beforeTask: beforeTask,
          ),
        );
        continue;
      }
      if (beforeTask != null &&
          afterTask != null &&
          _taskFingerprint(beforeTask) != _taskFingerprint(afterTask)) {
        entries.add(
          ConversationPlanTaskDiffEntry(
            type: ConversationPlanTaskDiffType.changed,
            identity: identity,
            beforeTask: beforeTask,
            afterTask: afterTask,
          ),
        );
      }
    }

    return ConversationPlanDiffResult.valid(entries);
  }

  static String _taskIdentity(ConversationWorkflowTask task) {
    final taskId = task.id.trim();
    if (taskId.isNotEmpty) {
      return taskId;
    }
    return task.title.trim().toLowerCase();
  }

  static String _taskFingerprint(ConversationWorkflowTask task) {
    final files = task.targetFiles
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('|');
    return [
      task.title.trim(),
      task.status.name,
      files,
      task.validationCommand.trim(),
      task.notes.trim(),
    ].join('::');
  }
}

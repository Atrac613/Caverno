import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/types/workspace_mode.dart';
import '../services/conversation_plan_hash.dart';
import 'message.dart';
import 'conversation_plan_artifact.dart';
import 'conversation_workflow.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

ConversationWorkflowSpec? _workflowSpecFromJson(Map<String, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return ConversationWorkflowSpec.fromJson(json);
}

Map<String, dynamic>? _workflowSpecToJson(ConversationWorkflowSpec? spec) {
  return spec?.toJson();
}

ConversationPlanArtifact? _planArtifactFromJson(Map<String, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return ConversationPlanArtifact.fromJson(json);
}

Map<String, dynamic>? _planArtifactToJson(ConversationPlanArtifact? artifact) {
  return artifact?.toJson();
}

List<ConversationExecutionTaskProgress> _executionProgressFromJson(
  List<dynamic>? json,
) {
  if (json == null) {
    return const [];
  }
  return json
      .map(
        (item) => ConversationExecutionTaskProgress.fromJson(
          item as Map<String, dynamic>,
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _executionProgressToJson(
  List<ConversationExecutionTaskProgress> progress,
) {
  return progress.map((item) => item.toJson()).toList(growable: false);
}

List<ConversationOpenQuestionProgress> _openQuestionProgressFromJson(
  List<dynamic>? json,
) {
  if (json == null) {
    return const [];
  }
  return json
      .map(
        (item) => ConversationOpenQuestionProgress.fromJson(
          item as Map<String, dynamic>,
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _openQuestionProgressToJson(
  List<ConversationOpenQuestionProgress> progress,
) {
  return progress.map((item) => item.toJson()).toList(growable: false);
}

@freezed
abstract class Conversation with _$Conversation {
  const Conversation._();

  const factory Conversation({
    required String id,
    required String title,
    required List<Message> messages,
    required DateTime createdAt,
    required DateTime updatedAt,
    @JsonKey(unknownEnumValue: WorkspaceMode.chat)
    @Default(WorkspaceMode.chat)
    WorkspaceMode workspaceMode,
    @Default('') String projectId,
    @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)
    @Default(ConversationExecutionMode.normal)
    ConversationExecutionMode executionMode,
    @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)
    @Default(ConversationWorkflowStage.idle)
    ConversationWorkflowStage workflowStage,
    @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)
    ConversationWorkflowSpec? workflowSpec,
    @Default('') String workflowSourceHash,
    DateTime? workflowDerivedAt,
    @JsonKey(
      fromJson: _executionProgressFromJson,
      toJson: _executionProgressToJson,
    )
    @Default(<ConversationExecutionTaskProgress>[])
    List<ConversationExecutionTaskProgress> executionProgress,
    @JsonKey(
      fromJson: _openQuestionProgressFromJson,
      toJson: _openQuestionProgressToJson,
    )
    @Default(<ConversationOpenQuestionProgress>[])
    List<ConversationOpenQuestionProgress> openQuestionProgress,
    @JsonKey(fromJson: _planArtifactFromJson, toJson: _planArtifactToJson)
    ConversationPlanArtifact? planArtifact,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);

  String? get normalizedProjectId {
    final trimmed = projectId.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get isPlanningSession =>
      executionMode == ConversationExecutionMode.planning;

  ConversationWorkflowSpec get effectiveWorkflowSpec =>
      workflowSpec ?? const ConversationWorkflowSpec();

  ConversationPlanArtifact get effectivePlanArtifact =>
      planArtifact ?? const ConversationPlanArtifact();

  List<ConversationExecutionTaskProgress> get effectiveExecutionProgress =>
      executionProgress
          .where((entry) => entry.taskId.trim().isNotEmpty)
          .toList(growable: false);

  List<ConversationOpenQuestionProgress> get effectiveOpenQuestionProgress =>
      openQuestionProgress
          .where((entry) => entry.questionId.trim().isNotEmpty)
          .toList(growable: false);

  String? get effectivePlanningDocument =>
      effectivePlanArtifact.planningMarkdown;

  String? get effectiveExecutionDocument =>
      effectivePlanArtifact.executionMarkdown;

  String? displayPlanDocument({required bool isPlanning}) =>
      effectivePlanArtifact.displayMarkdown(isPlanning: isPlanning);

  bool get hasWorkflowContext =>
      workflowStage != ConversationWorkflowStage.idle ||
      effectiveWorkflowSpec.hasContent;

  bool get hasPlanArtifact => effectivePlanArtifact.hasContent;

  bool get shouldPreferPlanDocument => hasPlanArtifact;

  bool get hasWorkflowProjection =>
      workflowSourceHash.trim().isNotEmpty &&
      workflowDerivedAt != null &&
      effectiveWorkflowSpec.hasContent;

  String? get effectiveExecutionDocumentHash {
    final markdown = effectiveExecutionDocument;
    if (markdown == null) {
      return null;
    }
    return computeConversationPlanHash(markdown);
  }

  bool get isWorkflowProjectionFresh =>
      hasWorkflowProjection &&
      effectiveExecutionDocumentHash != null &&
      workflowSourceHash == effectiveExecutionDocumentHash;

  bool get isWorkflowProjectionStale =>
      effectiveExecutionDocumentHash != null &&
      workflowSourceHash.trim().isNotEmpty &&
      workflowSourceHash != effectiveExecutionDocumentHash;

  bool get needsWorkflowProjectionRefresh =>
      effectiveExecutionDocument != null &&
      (!hasWorkflowProjection || !isWorkflowProjectionFresh);

  ConversationExecutionTaskProgress? executionProgressForTask(String taskId) {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return null;
    }
    for (final entry in effectiveExecutionProgress) {
      if (entry.taskId == normalizedTaskId) {
        return entry;
      }
    }
    return null;
  }

  ConversationOpenQuestionProgress? openQuestionProgressForQuestion(
    String question,
  ) {
    final questionId = openQuestionIdFor(question);
    for (final entry in effectiveOpenQuestionProgress) {
      if (entry.questionId == questionId) {
        return entry;
      }
    }
    return null;
  }

  List<ConversationOpenQuestionProgress> get unresolvedOpenQuestionProgress =>
      effectiveOpenQuestionProgress
          .where(
            (entry) =>
                entry.status == ConversationOpenQuestionStatus.unresolved ||
                entry.status == ConversationOpenQuestionStatus.needsUserInput,
          )
          .toList(growable: false);

  static String openQuestionIdFor(String question) {
    final normalized = question.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    final hash = computeConversationPlanHash(normalized);
    final prefix = hash.length <= 10 ? hash : hash.substring(0, 10);
    return 'open-question-$prefix';
  }

  List<ConversationWorkflowTask> get projectedExecutionTasks =>
      effectiveWorkflowSpec.tasks
          .map((task) {
            final progress = executionProgressForTask(task.id);
            if (progress == null) {
              return task;
            }
            return task.copyWith(status: progress.status);
          })
          .toList(growable: false);
}

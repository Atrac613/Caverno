import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_plan_artifact.freezed.dart';
part 'conversation_plan_artifact.g.dart';

@freezed
abstract class ConversationPlanArtifact with _$ConversationPlanArtifact {
  const ConversationPlanArtifact._();

  const factory ConversationPlanArtifact({
    @Default('') String draftMarkdown,
    @Default('') String approvedMarkdown,
    DateTime? updatedAt,
  }) = _ConversationPlanArtifact;

  factory ConversationPlanArtifact.fromJson(Map<String, dynamic> json) =>
      _$ConversationPlanArtifactFromJson(json);

  String? get normalizedDraftMarkdown {
    final trimmed = draftMarkdown.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedApprovedMarkdown {
    final trimmed = approvedMarkdown.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get hasDraft => normalizedDraftMarkdown != null;

  bool get hasApproved => normalizedApprovedMarkdown != null;

  bool get hasContent => hasDraft || hasApproved;

  bool get hasPendingEdits =>
      normalizedDraftMarkdown != null &&
      normalizedDraftMarkdown != normalizedApprovedMarkdown;

  String? preferredMarkdown({required bool preferDraft}) {
    if (preferDraft) {
      return normalizedDraftMarkdown ?? normalizedApprovedMarkdown;
    }
    return normalizedApprovedMarkdown ?? normalizedDraftMarkdown;
  }
}

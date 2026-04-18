import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_plan_artifact.freezed.dart';
part 'conversation_plan_artifact.g.dart';

enum ConversationPlanRevisionKind { draft, approved, restored }

@freezed
abstract class ConversationPlanRevision with _$ConversationPlanRevision {
  const ConversationPlanRevision._();

  const factory ConversationPlanRevision({
    required String markdown,
    required DateTime createdAt,
    @Default(ConversationPlanRevisionKind.draft)
    ConversationPlanRevisionKind kind,
    @Default('') String label,
  }) = _ConversationPlanRevision;

  factory ConversationPlanRevision.fromJson(Map<String, dynamic> json) =>
      _$ConversationPlanRevisionFromJson(json);

  String? get normalizedMarkdown {
    final trimmed = markdown.trimRight();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get normalizedLabel {
    final trimmed = label.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

@freezed
abstract class ConversationPlanArtifact with _$ConversationPlanArtifact {
  const ConversationPlanArtifact._();

  const factory ConversationPlanArtifact({
    @Default('') String draftMarkdown,
    @Default('') String approvedMarkdown,
    DateTime? updatedAt,
    @Default(<ConversationPlanRevision>[]) List<ConversationPlanRevision> revisions,
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

  List<ConversationPlanRevision> get historyEntries =>
      revisions
          .where((entry) => entry.normalizedMarkdown != null)
          .toList(growable: false);

  bool get hasPendingEdits =>
      normalizedDraftMarkdown != null &&
      normalizedDraftMarkdown != normalizedApprovedMarkdown;

  String? get planningMarkdown =>
      normalizedDraftMarkdown ?? normalizedApprovedMarkdown;

  String? get executionMarkdown =>
      normalizedApprovedMarkdown ?? normalizedDraftMarkdown;

  bool get hasExecutionDocument => executionMarkdown != null;

  bool get hasPlanningDocument => planningMarkdown != null;

  String? displayMarkdown({required bool isPlanning}) {
    return isPlanning ? planningMarkdown : executionMarkdown;
  }

  String? preferredMarkdown({required bool preferDraft}) {
    return displayMarkdown(isPlanning: preferDraft);
  }

  ConversationPlanArtifact recordRevision({
    required String markdown,
    required ConversationPlanRevisionKind kind,
    String label = '',
    DateTime? createdAt,
    int maxEntries = 12,
  }) {
    final normalizedMarkdown = markdown.trimRight();
    if (normalizedMarkdown.isEmpty) {
      return this;
    }

    final revision = ConversationPlanRevision(
      markdown: normalizedMarkdown,
      createdAt: createdAt ?? DateTime.now(),
      kind: kind,
      label: label.trim(),
    );
    final nextHistory = <ConversationPlanRevision>[
      revision,
      ...historyEntries.where(
        (entry) =>
            entry.normalizedMarkdown != normalizedMarkdown ||
            entry.kind != kind,
      ),
    ];
    final trimmedHistory = nextHistory.length <= maxEntries
        ? nextHistory
        : nextHistory.sublist(0, maxEntries);
    return copyWith(revisions: trimmedHistory);
  }
}

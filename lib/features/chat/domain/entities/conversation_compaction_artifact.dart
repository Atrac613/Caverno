import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_compaction_artifact.freezed.dart';
part 'conversation_compaction_artifact.g.dart';

@freezed
abstract class ConversationCompactionArtifact
    with _$ConversationCompactionArtifact {
  const ConversationCompactionArtifact._();

  const factory ConversationCompactionArtifact({
    @Default('') String summary,
    @Default(0) int compactedMessageCount,
    @Default(0) int retainedMessageCount,
    @Default(0) int estimatedPromptTokens,
    DateTime? updatedAt,
  }) = _ConversationCompactionArtifact;

  factory ConversationCompactionArtifact.fromJson(Map<String, dynamic> json) =>
      _$ConversationCompactionArtifactFromJson(json);

  String? get normalizedSummary {
    final trimmed = summary.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get hasContent =>
      normalizedSummary != null && compactedMessageCount > 0;
}

import 'package:freezed_annotation/freezed_annotation.dart';

part 'conversation_workflow.freezed.dart';
part 'conversation_workflow.g.dart';

enum ConversationWorkflowStage { idle, clarify, plan, tasks, implement, review }

@freezed
abstract class ConversationWorkflowSpec with _$ConversationWorkflowSpec {
  const ConversationWorkflowSpec._();

  const factory ConversationWorkflowSpec({
    @Default('') String goal,
    @Default(<String>[]) List<String> constraints,
    @Default(<String>[]) List<String> acceptanceCriteria,
    @Default(<String>[]) List<String> openQuestions,
  }) = _ConversationWorkflowSpec;

  factory ConversationWorkflowSpec.fromJson(Map<String, dynamic> json) =>
      _$ConversationWorkflowSpecFromJson(json);

  bool get hasContent =>
      goal.trim().isNotEmpty ||
      constraints.any((item) => item.trim().isNotEmpty) ||
      acceptanceCriteria.any((item) => item.trim().isNotEmpty) ||
      openQuestions.any((item) => item.trim().isNotEmpty);
}

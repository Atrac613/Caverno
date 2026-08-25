import '../entities/chat_turn_owner.dart';
import '../entities/conversation_workflow.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';

/// Immutable owner snapshots used for one saved-task target-scope decision.
///
/// The guard runs while a turn is executing, so the tool call and the task it
/// is judged against are frozen at construction: a later mutation of either
/// must not change a decision already made.
final class SavedTaskTargetScopeInput {
  SavedTaskTargetScopeInput({
    required this.owner,
    required ToolCallInfo toolCall,
    required ConversationWorkflowTask? ownerTask,
    required this.ownerProjectRoot,
  }) : toolCall = _freezeToolCall(toolCall),
       ownerTask = _freezeTask(ownerTask);

  final ChatTurnOwner owner;
  final ToolCallInfo toolCall;
  final ConversationWorkflowTask? ownerTask;
  final String? ownerProjectRoot;
}

ToolCallInfo _freezeToolCall(ToolCallInfo source) {
  return ToolCallInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  );
}

ConversationWorkflowTask? _freezeTask(ConversationWorkflowTask? source) {
  if (source == null) return null;
  return source.copyWith(
    targetFiles: List<String>.unmodifiable(source.targetFiles),
  );
}

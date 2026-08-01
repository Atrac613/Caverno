// ChatNotifier decomposition collaborator: git-write-confirmation-policy

import '../../data/datasources/git_tools.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'tool_call_execution_policy.dart';

/// Immutable assistant question and pending calls for one exact turn owner.
final class GitWriteConfirmationInput {
  GitWriteConfirmationInput({
    required this.owner,
    required this.currentAssistantContent,
    required List<ToolCallInfo> pendingToolCalls,
  }) : pendingToolCalls = List<ToolCallInfo>.unmodifiable(
         pendingToolCalls.map(_freezeToolCall),
       );

  final ChatTurnOwner owner;
  final String? currentAssistantContent;
  final List<ToolCallInfo> pendingToolCalls;
}

/// Detects a Git write batch that the assistant has not yet been allowed to run.
final class GitWriteConfirmationPolicy {
  const GitWriteConfirmationPolicy();

  static const ToolCallExecutionPolicy _executionPolicy =
      ToolCallExecutionPolicy();

  bool shouldBlock(GitWriteConfirmationInput input) {
    final candidate = input.currentAssistantContent?.trim() ?? '';
    if (!looksLikeGitWriteConfirmationQuestion(candidate)) return false;
    return input.pendingToolCalls.any(isWriteGitCommandToolCall);
  }

  bool isWriteGitCommandToolCall(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() != 'git_execute_command') {
      return false;
    }
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    return command != null && !GitTools.isReadOnly(command);
  }

  bool looksLikeGitWriteConfirmationQuestion(String content) {
    if (content.isEmpty || content.length > 1200) return false;
    final lowerContent = content.toLowerCase();
    final hasQuestionMarker =
        lowerContent.contains('?') ||
        content.contains(String.fromCharCode(0xff1f)) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x3057, 0x307e, 0x3059, 0x304b],
          [0x3057, 0x3066, 0x3082, 0x3044, 0x3044, 0x3067, 0x3059, 0x304b],
          [0x3057, 0x3066, 0x3088, 0x3044, 0x3067, 0x3059, 0x304b],
        ]);
    if (!hasQuestionMarker) return false;
    if (RegExp(
      r'\b(commit|stage|staging|push|reset|checkout|merge|rebase)\b',
    ).hasMatch(lowerContent)) {
      return true;
    }
    if (_containsAny(lowerContent, const ['git add', 'git commit'])) {
      return true;
    }
    return _containsAnyCodeUnitSequence(content, const [
      [0x30b3, 0x30df, 0x30c3, 0x30c8],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5],
      [0x30ea, 0x30bb, 0x30c3, 0x30c8],
      [0x30c1, 0x30a7, 0x30c3, 0x30af, 0x30a2, 0x30a6, 0x30c8],
      [0x30de, 0x30fc, 0x30b8],
      [0x30ea, 0x30d9, 0x30fc, 0x30b9],
    ]);
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => text.contains(String.fromCharCodes(sequence)),
    );
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo toolCall) {
  return ToolCallInfo(
    id: toolCall.id,
    name: toolCall.name,
    arguments: ImmutableJsonSnapshot.freezeMap(toolCall.arguments),
  );
}

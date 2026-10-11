import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../entities/message.dart';
import 'fenced_tool_name_blocks.dart';

/// Evidence and feedback for assistant-authored artifacts, never tool execution.
final class AssistantToolArtifactRecoveryPlan {
  const AssistantToolArtifactRecoveryPlan._({
    required this.logMessage,
    required this.pendingResult,
    this.replacementContent,
  });

  final String logMessage;
  final String pendingResult;
  final String? replacementContent;

  static AssistantToolArtifactRecoveryPlan? untrustedResults(Message? message) {
    if (message == null || message.role != MessageRole.assistant) {
      return null;
    }
    final toolResults = ContentParser.extractToolResultMarkers(message.content);
    if (toolResults.isEmpty) return null;
    return AssistantToolArtifactRecoveryPlan._(
      logMessage:
          '[ContentTool] Ignoring assistant-authored tool_result tag(s): '
          '${toolResults.map((tc) => tc.name).join(", ")}',
      pendingResult:
          '[Assistant-authored tool_result ignored]\n'
          'The assistant emitted <tool_result> tags without a corresponding tool '
          'execution. Tool results must come from executed tools only. If the data '
          'is still needed, call the tool with one complete <tool_use>...</tool_use> '
          'tag. If the current user request can be completed without the ignored '
          'tag or any additional tool, answer that user request directly now. For '
          'exact no-tool recovery or echo requests, return the literal text the '
          'user requested exactly. Do not use values that appear only inside the '
          'ignored <tool_result> content.',
    );
  }

  static AssistantToolArtifactRecoveryPlan? fencedNames(Message? message) {
    if (message == null || message.role != MessageRole.assistant) {
      return null;
    }
    final toolNames = FencedToolNameBlocks.extract(message.content);
    if (toolNames.isEmpty) return null;
    return AssistantToolArtifactRecoveryPlan._(
      logMessage:
          '[ContentTool] Ignoring assistant-authored fenced tool_name block(s): '
          '${toolNames.join(", ")}',
      replacementContent: FencedToolNameBlocks.strip(message.content),
      pendingResult:
          '[Assistant tool-name block ignored]\n'
          'The assistant emitted fenced tool_name block(s) instead of a complete '
          '<tool_use>...</tool_use> call: ${toolNames.join(", ")}. '
          'No tool was executed from the fenced tool_name block. If tool use is '
          'still needed, call one available tool with exactly one complete '
          '<tool_use>...</tool_use> JSON tag; otherwise answer from verified prior '
          'tool results only.',
    );
  }
}

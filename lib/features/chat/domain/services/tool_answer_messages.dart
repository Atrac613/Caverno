import 'dart:convert';

import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'plan/proposal_parsing_text_utils.dart';
import 'tool_result_prompt_builder.dart';

/// Builds textual and visual messages from already-budgeted tool results.
abstract final class ToolAnswerMessages {
  static List<Message> build(
    List<ToolResultInfo> budgetedToolResults, {
    ToolResultCompletionEvidence? completionEvidence,
    required List<Map<String, dynamic>> definitions,
  }) {
    final timestamp = DateTime.now();
    final messages = <Message>[
      Message(
        id: 'tool_result_${timestamp.microsecondsSinceEpoch}',
        isSynthesizedPrompt: true,
        content: ToolResultPromptBuilder.buildAnswerPrompt(
          budgetedToolResults,
          descriptionsByName:
              ToolResultPromptBuilder.descriptionsByNameFromDefinitions(
                definitions,
              ),
          completionEvidence: completionEvidence,
        ),
        role: MessageRole.user,
        timestamp: timestamp,
      ),
    ];

    for (var i = 0; i < budgetedToolResults.length; i++) {
      final toolResult = budgetedToolResults[i];
      final decoded = ProposalParsingTextUtils.tryDecodeMap(toolResult.result);
      if (decoded == null) {
        continue;
      }
      final imageBase64 = decoded['imageBase64'];
      if (imageBase64 is! String || imageBase64.isEmpty) {
        continue;
      }

      final metadata = Map<String, dynamic>.from(decoded)
        ..remove('imageBase64');
      messages.add(
        Message(
          id: 'tool_image_${timestamp.microsecondsSinceEpoch}_$i',
          content:
              'Visual observation from ${toolResult.name}. '
              'Use this screenshot and any actionProposalPolicy metadata to '
              'answer the user and decide any next computer-use action. '
              'Preserve required target metadata, exact text, and public '
              'action boundaries when proposing actions. '
              'Metadata: ${jsonEncode(metadata)}',
          role: MessageRole.user,
          timestamp: timestamp,
          imageBase64: imageBase64,
          imageMimeType: decoded['imageMimeType'] as String? ?? 'image/png',
        ),
      );
    }

    return messages;
  }
}

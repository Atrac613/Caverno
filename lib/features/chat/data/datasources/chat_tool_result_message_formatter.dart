import 'dart:convert';

import 'package:openai_dart/openai_dart.dart';

import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_result_prompt_builder.dart';

final class ChatToolResultMessageFormatter {
  const ChatToolResultMessageFormatter();

  String formatContent(ToolResultInfo toolResult) {
    final decoded = _tryDecodeJson(toolResult.result);
    if (decoded == null) return toolResult.result;

    if (decoded['imageBase64'] is String) {
      final redacted = Map<String, dynamic>.from(decoded)
        ..['imageBase64'] = '[attached as image content]';
      return jsonEncode(redacted);
    }

    final interpretationLines = <String>[];
    switch (toolResult.name) {
      case 'write_file':
        if (decoded.containsKey('bytes_written')) {
          if (decoded['created'] == true) {
            interpretationLines.add(
              'Interpretation: write_file succeeded and created the target file.',
            );
          } else {
            interpretationLines.add(
              'Interpretation: write_file succeeded and updated an existing file.',
            );
            interpretationLines.add(
              'A result with "created": false means the file already existed; it is not an error.',
            );
          }
        }
      case 'edit_file':
        if (decoded['already_applied'] == true) {
          interpretationLines.add(
            'Interpretation: edit_file detected that the requested replacement was already present and left the file unchanged.',
          );
        } else if (decoded.containsKey('replacements')) {
          interpretationLines.add(
            'Interpretation: edit_file succeeded and applied the requested replacement.',
          );
        }
      case 'delete_file':
        if (decoded['deleted'] == true) {
          interpretationLines.add(
            'Interpretation: delete_file succeeded and removed the target file.',
          );
        }
    }
    interpretationLines.addAll(
      ToolResultPromptBuilder.buildToolDataInterpretationLines(toolResult),
    );
    if (interpretationLines.isEmpty) return toolResult.result;
    return '${interpretationLines.join('\n')}\nRaw result:\n${toolResult.result}';
  }

  List<ChatMessage> buildImageObservationMessages(
    List<ToolResultInfo> toolResults,
  ) {
    final messages = <ChatMessage>[];
    for (final toolResult in toolResults) {
      final decoded = _tryDecodeJson(toolResult.result);
      if (decoded == null) continue;
      final imageBase64 = decoded['imageBase64'];
      if (imageBase64 is! String || imageBase64.isEmpty) continue;

      final mimeType = decoded['imageMimeType'] as String? ?? 'image/png';
      final metadata = Map<String, dynamic>.from(decoded)
        ..remove('imageBase64');
      final text =
          'Visual observation from ${toolResult.name}. '
          'Use this screenshot and any actionProposalPolicy metadata to decide '
          'the next computer-use action. Preserve required target metadata, '
          'exact text, and public action boundaries when proposing actions. '
          'Metadata: ${jsonEncode(metadata)}';
      messages.add(
        ChatMessage.user([
          ContentPart.text(text),
          ContentPart.imageBase64(data: imageBase64, mediaType: mimeType),
        ]),
      );
    }
    return messages;
  }

  Map<String, dynamic>? _tryDecodeJson(String value) {
    try {
      final decoded = jsonDecode(value.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

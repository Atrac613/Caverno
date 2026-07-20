import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:openai_dart/openai_dart.dart';

import '../../domain/entities/tool_call_info.dart';

final class NormalizedChatCompletionResponse {
  const NormalizedChatCompletionResponse({
    required this.content,
    required this.toolCalls,
    required this.finishReason,
  });

  final String content;
  final List<ToolCallInfo>? toolCalls;
  final String finishReason;
}

final class ChatCompletionResponseNormalizer {
  const ChatCompletionResponseNormalizer();

  static final RegExp _rawParseFailurePattern = RegExp(
    r'Failed to parse input at pos \d+:\s*(.+)$',
    dotAll: true,
  );
  static final RegExp _thoughtChannelStartPattern = RegExp(
    r'<\|channel\|?>\s*thought\b',
    caseSensitive: false,
  );
  static final RegExp _analysisChannelStartPattern = RegExp(
    r'<\|channel\|?>\s*analysis\b',
    caseSensitive: false,
  );
  static final RegExp _channelEndPattern = RegExp(r'<channel\|>');

  NormalizedChatCompletionResponse normalize({
    required String? content,
    required String? reasoning,
    required List<ToolCall>? nativeToolCalls,
    required String? finishReason,
    required List<Map<String, dynamic>>? advertisedTools,
    void Function(Object error)? onNativeArgumentError,
  }) {
    final normalizedContent = _composeContent(
      content: content,
      reasoning: reasoning,
    );
    final parsedNativeCalls = parseNativeToolCalls(
      nativeToolCalls,
      onArgumentError: onNativeArgumentError,
    );
    final embeddedCalls = parsedNativeCalls == null
        ? parseAdvertisedEmbeddedToolCalls(normalizedContent, advertisedTools)
        : null;
    return NormalizedChatCompletionResponse(
      content: normalizedContent,
      toolCalls: parsedNativeCalls ?? embeddedCalls,
      finishReason: embeddedCalls == null
          ? finishReason ?? 'stop'
          : 'tool_calls',
    );
  }

  NormalizedChatCompletionResponse? recoverFromParseFailure(Object error) {
    final content = recoverRawAssistantText(error);
    if (content == null) {
      return null;
    }
    final toolCalls = parseEmbeddedToolCalls(content);
    return NormalizedChatCompletionResponse(
      content: content,
      toolCalls: toolCalls,
      finishReason: toolCalls == null ? 'stop' : 'tool_calls',
    );
  }

  String? recoverRawAssistantText(Object error) {
    final match = _rawParseFailurePattern.firstMatch(error.toString());
    if (match == null) {
      return null;
    }
    final candidate = match.group(1)?.trim();
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    return _normalizeRecoveredAssistantText(candidate);
  }

  List<ToolCallInfo>? parseNativeToolCalls(
    List<ToolCall>? toolCalls, {
    void Function(Object error)? onArgumentError,
  }) {
    if (toolCalls == null || toolCalls.isEmpty) {
      return null;
    }
    return toolCalls
        .map(
          (toolCall) => ToolCallInfo(
            id: toolCall.id,
            name: toolCall.function.name,
            arguments: _parseNativeArguments(
              toolCall.function.arguments,
              onArgumentError: onArgumentError,
            ),
          ),
        )
        .toList(growable: false);
  }

  List<ToolCallInfo>? parseEmbeddedToolCalls(String content) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);
    if (toolCalls.isEmpty) {
      return null;
    }
    return toolCalls
        .map(
          (toolCall) => ToolCallInfo(
            id: toolCall.occurrenceId ?? 'raw_${toolCall.name}',
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
        )
        .toList(growable: false);
  }

  List<ToolCallInfo>? parseAdvertisedEmbeddedToolCalls(
    String content,
    List<Map<String, dynamic>>? advertisedTools,
  ) {
    if (advertisedTools == null || advertisedTools.isEmpty) {
      return null;
    }
    final advertisedNames = advertisedTools
        .map((tool) => tool['function'])
        .whereType<Map<String, dynamic>>()
        .map((function) => function['name'])
        .whereType<String>()
        .toSet();
    final calls = parseEmbeddedToolCalls(content);
    if (calls == null ||
        calls.any((call) => !advertisedNames.contains(call.name))) {
      return null;
    }
    return calls;
  }

  String _composeContent({
    required String? content,
    required String? reasoning,
  }) {
    final responseContent = content ?? '';
    if (reasoning == null || reasoning.isEmpty) {
      return responseContent;
    }
    return '<think>$reasoning</think>$responseContent';
  }

  Map<String, dynamic> _parseNativeArguments(
    String arguments, {
    void Function(Object error)? onArgumentError,
  }) {
    if (arguments.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      return ContentParser.sanitizeToolArguments(
        Map<String, dynamic>.from(jsonDecode(arguments) as Map),
      );
    } catch (error) {
      onArgumentError?.call(error);
      return const <String, dynamic>{};
    }
  }

  String _normalizeRecoveredAssistantText(String text) {
    return text
        .replaceAll(_thoughtChannelStartPattern, '<think>')
        .replaceAll(_analysisChannelStartPattern, '<think>')
        .replaceAll(_channelEndPattern, '</think>')
        .trim();
  }
}

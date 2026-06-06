import 'dart:async';
import 'dart:convert';

import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';
import 'chat_datasource.dart';
import 'chat_remote_datasource.dart';

export '../../../../core/services/apple_foundation_models_platform_client.dart';

class AppleFoundationModelsDataSource implements ChatDataSource {
  AppleFoundationModelsDataSource({
    AppleFoundationModelsClient? client,
    bool enableSafePromptRetry = false,
  }) : _client = client ?? MethodChannelAppleFoundationModelsClient(),
       _enableSafePromptRetry = enableSafePromptRetry;

  final AppleFoundationModelsClient _client;
  final bool _enableSafePromptRetry;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final result = await createChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    if (result.content.isNotEmpty) {
      yield result.content;
    }
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final request = _buildFoundationModelsPrompt(messages);
    final diagnostics = _FoundationModelsRequestDiagnostics.fromMessages(
      messages: messages,
      request: request,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    appLog('[AppleFoundationModels] Sending request ${diagnostics.toLog()}');
    final availability = await _client.checkAvailability();
    if (!availability.isAvailable) {
      final error = AppleFoundationModelsException.unavailable(availability);
      appLog(
        '[AppleFoundationModels] Preflight failed '
        '${diagnostics.toLog()} '
        '${availability.logDetails} '
        'error=$error',
      );
      throw error;
    }
    final prompt = tools == null || tools.isEmpty
        ? request.prompt
        : _promptWithToolBridge(request.prompt, tools);
    if (tools != null && tools.isNotEmpty) {
      appLog(
        '[AppleFoundationModels] Using textual tool bridge for ${tools.length} OpenAI tool definitions',
      );
    }
    final content = await _respondWithOptionalSafeRetry(
      messages: messages,
      request: request,
      diagnostics: diagnostics,
      prompt: prompt,
      temperature: temperature,
      maxTokens: maxTokens,
      hasTools: tools != null && tools.isNotEmpty,
    );
    return ChatCompletionResult(
      content: content,
      finishReason: 'stop',
      usage: TokenUsage.zero,
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final completion = createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    // Tool-aware callers may listen to the stream before awaiting completion.
    unawaited(
      completion.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return StreamWithToolsResult(
      stream: _streamCompletionContent(completion),
      completion: completion,
    );
  }

  Stream<String> _streamCompletionContent(
    Future<ChatCompletionResult> completion,
  ) async* {
    final result = await completion;
    if (result.content.isNotEmpty) {
      yield result.content;
    }
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final result = await createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    if (result.content.isNotEmpty) {
      yield result.content;
    }
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: toolCallId,
          name: toolName,
          arguments: _toolArgumentsAsMap(toolArguments),
          result: toolResult,
        ),
      ],
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final augmentedMessages = [
      ...messages,
      Message(
        id: 'apple-foundation-models-tool-results',
        role: MessageRole.user,
        timestamp: DateTime.now(),
        content: _formatToolResultsPrompt(
          toolResults,
          assistantContent: assistantContent,
        ),
      ),
    ];
    return createChatCompletion(
      messages: augmentedMessages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  Map<String, dynamic> _toolArgumentsAsMap(String toolArguments) {
    try {
      final decoded = jsonDecode(toolArguments);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Keep the raw arguments when a provider returned non-JSON content.
    }
    return {'raw': toolArguments};
  }

  Future<String> _respondWithOptionalSafeRetry({
    required List<Message> messages,
    required _FoundationModelsPrompt request,
    required _FoundationModelsRequestDiagnostics diagnostics,
    required String prompt,
    required double? temperature,
    required int? maxTokens,
    required bool hasTools,
  }) async {
    try {
      return await _client.respond(
        instructions: request.instructions,
        prompt: prompt,
        temperature: temperature,
        maxTokens: maxTokens,
      );
    } on AppleFoundationModelsException catch (error) {
      appLog(
        '[AppleFoundationModels] Request failed '
        '${diagnostics.toLog()} '
        'code=${error.code ?? 'none'} '
        'unsupportedLanguageOrLocale='
        '${error.isUnsupportedLanguageOrLocale} '
        'error=$error',
      );
      if (!_enableSafePromptRetry || !error.isUnsupportedLanguageOrLocale) {
        rethrow;
      }
      return _retryWithSafeEnglishPrompt(
        messages: messages,
        originalError: error,
        diagnostics: diagnostics,
        temperature: temperature,
        maxTokens: maxTokens,
        hadTools: hasTools,
      );
    } catch (error) {
      appLog(
        '[AppleFoundationModels] Request failed '
        '${diagnostics.toLog()} '
        'error=$error',
      );
      rethrow;
    }
  }

  Future<String> _retryWithSafeEnglishPrompt({
    required List<Message> messages,
    required AppleFoundationModelsException originalError,
    required _FoundationModelsRequestDiagnostics diagnostics,
    required double? temperature,
    required int? maxTokens,
    required bool hadTools,
  }) async {
    final retryRequest = _buildSafeLanguageRetryPrompt(messages, hadTools);
    appLog(
      '[AppleFoundationModels] Retrying unsupported language request with '
      'safe English prompt ${diagnostics.toLog()} '
      'retryInstructionChars=${retryRequest.instructions.length} '
      'retryPromptChars=${retryRequest.prompt.length} '
      'hadTools=$hadTools',
    );
    try {
      final content = await _client.respond(
        instructions: retryRequest.instructions,
        prompt: retryRequest.prompt,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      appLog(
        '[AppleFoundationModels] Safe English retry succeeded '
        '${diagnostics.toLog()}',
      );
      return content;
    } on AppleFoundationModelsException catch (retryError) {
      appLog(
        '[AppleFoundationModels] Safe English retry failed '
        '${diagnostics.toLog()} '
        'code=${retryError.code ?? 'none'} '
        'unsupportedLanguageOrLocale='
        '${retryError.isUnsupportedLanguageOrLocale} '
        'retryError=$retryError '
        'originalError=$originalError',
      );
      throw originalError;
    } catch (retryError) {
      appLog(
        '[AppleFoundationModels] Safe English retry failed '
        '${diagnostics.toLog()} '
        'retryError=$retryError '
        'originalError=$originalError',
      );
      throw originalError;
    }
  }

  _FoundationModelsPrompt _buildFoundationModelsPrompt(List<Message> messages) {
    final systemMessages = messages
        .where((message) => message.role == MessageRole.system)
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .toList(growable: false);
    final promptMessages = messages
        .where((message) => message.role != MessageRole.system)
        .toList(growable: false);

    return _FoundationModelsPrompt(
      instructions: systemMessages.isEmpty
          ? 'You are Caverno, a helpful assistant.'
          : systemMessages.join('\n\n'),
      prompt: _formatPromptMessages(promptMessages),
    );
  }

  _FoundationModelsPrompt _buildSafeLanguageRetryPrompt(
    List<Message> messages,
    bool hadTools,
  ) {
    final latestUserMessage = messages.reversed.cast<Message?>().firstWhere(
      (message) =>
          message?.role == MessageRole.user &&
          _contentWithImageNotice(message!).trim().isNotEmpty,
      orElse: () => null,
    );
    final latestUserContent = latestUserMessage == null
        ? 'Continue the conversation.'
        : _compactText(_contentWithImageNotice(latestUserMessage), limit: 1200);
    final buffer = StringBuffer()
      ..writeln(
        'The previous local Apple Foundation Models request was rejected for '
        'language or locale.',
      )
      ..writeln(
        'Retry with a short English answer using only the latest user request.',
      );
    if (hadTools) {
      buffer.writeln(
        'The original request included application tools. If the user request '
        'requires browser actions, file edits, shell commands, or other app '
        'tools, explain that this local provider could not process the '
        'tool-bearing prompt and suggest switching to an OpenAI-compatible '
        'provider for that task.',
      );
    }
    buffer
      ..writeln()
      ..writeln('Latest user request:')
      ..write(latestUserContent);
    return _FoundationModelsPrompt(
      instructions:
          'You are Caverno, a concise assistant. Use plain English only. '
          'Avoid locale-specific formatting.',
      prompt: buffer.toString(),
    );
  }

  String _formatPromptMessages(List<Message> messages) {
    if (messages.isEmpty) {
      return 'Continue the conversation.';
    }
    if (messages.length == 1 && messages.single.role == MessageRole.user) {
      return _contentWithImageNotice(messages.single);
    }

    final buffer = StringBuffer('Conversation so far:\n');
    for (final message in messages) {
      buffer
        ..write(_roleLabel(message.role))
        ..write(': ')
        ..writeln(_contentWithImageNotice(message).trim());
    }
    buffer.writeln();
    buffer.write('Respond to the latest user message.');
    return buffer.toString();
  }

  String _contentWithImageNotice(Message message) {
    final buffer = StringBuffer(message.content);
    if (message.imageBase64 != null) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write('[Image omitted: Apple Foundation Models text bridge only]');
    }
    return buffer.toString();
  }

  String _roleLabel(MessageRole role) => switch (role) {
    MessageRole.user => 'User',
    MessageRole.assistant => 'Assistant',
    MessageRole.system => 'System',
  };

  String _promptWithToolBridge(
    String prompt,
    List<Map<String, dynamic>> tools,
  ) {
    final toolDescriptions = tools
        .map(_formatToolDefinition)
        .where((description) => description.isNotEmpty)
        .toList(growable: false);
    if (toolDescriptions.isEmpty) {
      return prompt;
    }

    final buffer = StringBuffer(prompt.trimRight())
      ..writeln()
      ..writeln()
      ..writeln('Caverno tool bridge instructions:')
      ..writeln(
        'You may ask Caverno to run one application tool when a tool result '
        'would materially improve the answer or complete the user request.',
      )
      ..writeln(
        'To call a tool, output exactly one complete tag and no prose outside '
        'the tag:',
      )
      ..writeln(
        '<tool_use>{"name":"tool_name","arguments":{"key":"value"}}</tool_use>',
      )
      ..writeln(
        'Use only the listed tools and argument names. The app will execute '
        'the tool and send back trusted results. Do not write tool_result '
        'tags yourself and do not claim a tool action succeeded until a tool '
        'result confirms it.',
      )
      ..writeln('Available tool definitions:');
    for (final description in toolDescriptions) {
      buffer.writeln(description);
    }
    return buffer.toString();
  }

  String _formatToolDefinition(Map<String, dynamic> definition) {
    final function = definition['function'];
    if (function is! Map) {
      return '';
    }
    final name = function['name']?.toString().trim();
    if (name == null || name.isEmpty) {
      return '';
    }
    final description = _compactText(function['description']?.toString() ?? '');
    final parameters = function['parameters'];
    final argumentSummary = parameters is Map
        ? _formatParameterSummary(parameters)
        : 'no arguments';
    final buffer = StringBuffer('- $name');
    if (description.isNotEmpty) {
      buffer.write(': $description');
    }
    buffer.write(' Arguments: $argumentSummary.');
    return buffer.toString();
  }

  String _formatParameterSummary(Map parameters) {
    final properties = parameters['properties'];
    if (properties is! Map || properties.isEmpty) {
      return 'no arguments';
    }
    final requiredArguments = parameters['required'] is List
        ? (parameters['required'] as List)
              .map((value) => value.toString())
              .toSet()
        : const <String>{};
    final arguments = <String>[];
    for (final entry in properties.entries) {
      final name = entry.key.toString();
      final details = entry.value;
      final type = details is Map ? details['type']?.toString() : null;
      final description = details is Map
          ? _compactText(details['description']?.toString() ?? '', limit: 80)
          : '';
      final suffix = requiredArguments.contains(name) ? 'required' : 'optional';
      final buffer = StringBuffer(name);
      if (type != null && type.isNotEmpty) {
        buffer.write(' <$type>');
      }
      buffer.write(' $suffix');
      if (description.isNotEmpty) {
        buffer.write(' - $description');
      }
      arguments.add(buffer.toString());
    }
    return arguments.join('; ');
  }

  String _compactText(String value, {int limit = 160}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= limit) {
      return normalized;
    }
    return '${normalized.substring(0, limit - 1)}...';
  }

  String _formatToolResultsPrompt(
    List<ToolResultInfo> toolResults, {
    String? assistantContent,
  }) {
    final buffer = StringBuffer();
    if (assistantContent != null && assistantContent.trim().isNotEmpty) {
      buffer
        ..writeln('Previous assistant context:')
        ..writeln(assistantContent.trim())
        ..writeln();
    }
    buffer.writeln(
      'The previous step produced tool results. Use them to continue.',
    );
    for (final result in toolResults) {
      buffer
        ..writeln()
        ..writeln('Tool: ${result.name}')
        ..writeln('Arguments: ${result.arguments}')
        ..writeln('Result:')
        ..writeln(result.result);
    }
    return buffer.toString().trimRight();
  }
}

class _FoundationModelsPrompt {
  const _FoundationModelsPrompt({
    required this.instructions,
    required this.prompt,
  });

  final String instructions;
  final String prompt;
}

class _FoundationModelsRequestDiagnostics {
  const _FoundationModelsRequestDiagnostics({
    required this.model,
    required this.temperature,
    required this.maxTokens,
    required this.messageCount,
    required this.systemMessageCount,
    required this.userMessageCount,
    required this.assistantMessageCount,
    required this.instructionChars,
    required this.promptChars,
  });

  factory _FoundationModelsRequestDiagnostics.fromMessages({
    required List<Message> messages,
    required _FoundationModelsPrompt request,
    required String? model,
    required double? temperature,
    required int? maxTokens,
  }) {
    var systemMessageCount = 0;
    var userMessageCount = 0;
    var assistantMessageCount = 0;
    for (final message in messages) {
      switch (message.role) {
        case MessageRole.system:
          systemMessageCount++;
        case MessageRole.user:
          userMessageCount++;
        case MessageRole.assistant:
          assistantMessageCount++;
      }
    }
    return _FoundationModelsRequestDiagnostics(
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      messageCount: messages.length,
      systemMessageCount: systemMessageCount,
      userMessageCount: userMessageCount,
      assistantMessageCount: assistantMessageCount,
      instructionChars: request.instructions.length,
      promptChars: request.prompt.length,
    );
  }

  final String? model;
  final double? temperature;
  final int? maxTokens;
  final int messageCount;
  final int systemMessageCount;
  final int userMessageCount;
  final int assistantMessageCount;
  final int instructionChars;
  final int promptChars;

  String toLog() {
    return 'model=${model ?? 'default'} '
        'temperature=${temperature?.toStringAsFixed(3) ?? 'default'} '
        'maxTokens=${maxTokens?.toString() ?? 'default'} '
        'messages=$messageCount '
        'system=$systemMessageCount '
        'user=$userMessageCount '
        'assistant=$assistantMessageCount '
        'instructionChars=$instructionChars '
        'promptChars=$promptChars';
  }
}

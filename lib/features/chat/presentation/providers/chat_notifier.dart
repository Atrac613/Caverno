import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../../../core/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/utils/content_parser.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../domain/services/system_prompt_builder.dart';
import '../../domain/services/session_memory_service.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/session_memory.dart';
import '../../domain/services/temporal_context_builder.dart';
import 'chat_state.dart';
import 'conversations_notifier.dart';
import 'mcp_tool_provider.dart';

final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  return ChatRemoteDataSource(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );
});

final sessionMemoryServiceProvider = Provider<SessionMemoryService>((ref) {
  final repository = ref.watch(chatMemoryRepositoryProvider);
  return SessionMemoryService(repository);
});

final chatNotifierProvider = StateNotifierProvider<ChatNotifier, ChatState>((
  ref,
) {
  final settings = ref.read(settingsNotifierProvider);
  final dataSource = ref.read(chatRemoteDataSourceProvider);
  final mcpToolService = ref.read(mcpToolServiceProvider);
  final memoryService = ref.read(sessionMemoryServiceProvider);
  final conversationsNotifier = ref.read(
    conversationsNotifierProvider.notifier,
  );
  final ttsService = ref.read(ttsServiceProvider);
  final notificationService = ref.read(notificationServiceProvider);
  final lifecycleService = ref.read(appLifecycleServiceProvider);
  final backgroundTaskService = ref.read(backgroundTaskServiceProvider);

  // Load messages for the current conversation.
  final conversationsState = ref.read(conversationsNotifierProvider);
  final initialMessages =
      conversationsState.currentConversation?.messages ?? [];
  final currentConversationId = conversationsState.currentConversation?.id;

  final notifier = ChatNotifier(
    dataSource,
    mcpToolService,
    memoryService,
    settings,
    onMessagesChanged: (messages) {
      conversationsNotifier.updateCurrentConversation(messages);
    },
    onAutoRead: (content) {
      // Extract TTS-safe text by removing segments such as `<think>`.
      final result = ContentParser.parse(content);
      final buffer = StringBuffer();
      for (final segment in result.segments) {
        if (segment.type == ContentType.text) {
          buffer.write(segment.content);
        }
      }
      final readableText = buffer.toString().trim();
      if (readableText.isNotEmpty) {
        ttsService.setSpeechRate(settings.speechRate);
        ttsService.speak(readableText);
      }
    },
    onSendStarted: () {
      backgroundTaskService.beginBackgroundTask();
    },
    onResponseCompleted: (content) {
      backgroundTaskService.endBackgroundTask();
      if (lifecycleService.isInBackground && content.isNotEmpty) {
        // Strip <think> blocks and extract readable text for the notification.
        final parsed = ContentParser.parse(content);
        final buffer = StringBuffer();
        for (final segment in parsed.segments) {
          if (segment.type == ContentType.text) {
            buffer.write(segment.content);
          }
        }
        final plainText = buffer.toString().trim();
        if (plainText.isEmpty) return;

        // Use the first line as the title, the rest as the body.
        final firstNewline = plainText.indexOf('\n');
        final String title;
        final String body;
        if (firstNewline > 0 && firstNewline <= 80) {
          title = plainText.substring(0, firstNewline).trim();
          body = plainText.substring(firstNewline + 1).trim();
        } else {
          title = 'Caverno';
          body = plainText;
        }

        notificationService.showResponseCompleteNotification(title, body);
      }
    },
    initialMessages: initialMessages,
    conversationId: currentConversationId,
  );

  ref.listen<AppSettings>(settingsNotifierProvider, (previous, next) {
    notifier.updateConnectionSettings(next);
  });

  ref.listen<McpToolService?>(mcpToolServiceProvider, (previous, next) {
    notifier.updateMcpToolService(next);
  });

  ref.listen<ConversationsState>(conversationsNotifierProvider, (
    previous,
    next,
  ) {
    notifier.syncConversation(
      conversationId: next.currentConversation?.id,
      messages: next.currentConversation?.messages ?? const [],
    );
  });

  return notifier;
});

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(
    this._dataSource,
    this._mcpToolService,
    this._memoryService,
    this._settings, {
    this.onMessagesChanged,
    this.onAutoRead,
    this.onSendStarted,
    this.onResponseCompleted,
    this.conversationId,
    List<Message>? initialMessages,
  }) : super(ChatState.initial()) {
    // Load initial messages.
    if (initialMessages != null && initialMessages.isNotEmpty) {
      state = state.copyWith(messages: initialMessages);
    }
    // Connect the MCP tool service.
    _mcpToolService?.connect();
  }

  ChatRemoteDataSource _dataSource;
  McpToolService? _mcpToolService;
  final SessionMemoryService _memoryService;
  AppSettings _settings;
  final void Function(List<Message>)? onMessagesChanged;
  final void Function(String content)? onAutoRead;
  final void Function()? onSendStarted;
  final void Function(String content)? onResponseCompleted;
  String? conversationId;
  String _languageCode = 'en';
  String? _sessionMemoryContext;
  String? _temporalReferenceContext;
  Message? _hiddenPrompt;
  bool _isVoiceMode = false;

  void updateConnectionSettings(AppSettings settings) {
    _settings = settings;
    _dataSource = ChatRemoteDataSource(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
    );
  }

  void updateMcpToolService(McpToolService? mcpToolService) {
    if (identical(_mcpToolService, mcpToolService)) return;
    _mcpToolService = mcpToolService;
    _mcpToolService?.connect();
  }

  void syncConversation({
    required String? conversationId,
    required List<Message> messages,
  }) {
    final sameConversation = this.conversationId == conversationId;
    final sameMessages = listEquals(state.messages, messages);

    if (sameConversation && sameMessages) {
      return;
    }

    cancelStreaming();
    _executedContentToolCalls.clear();
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    this.conversationId = conversationId;
    state = ChatState(messages: messages, isLoading: false, error: null);
  }

  /// Builds the system message, including the current date and time.
  Message _createSystemMessage() {
    final now = DateTime.now();
    final toolNames = <String>[];
    final mcpToolService = _mcpToolService;
    if (mcpToolService != null &&
        (_settings.mcpEnabled || _temporalReferenceContext != null)) {
      for (final tool in mcpToolService.getOpenAiToolDefinitions()) {
        final function = tool['function'];
        if (function is Map) {
          final name = function['name'];
          if (name is String && name.isNotEmpty) {
            toolNames.add(name);
          }
        }
      }
    }

    final resolvedLanguage = _settings.language == 'system' ? _languageCode : _settings.language;

    return Message(
      id: 'system',
      content: SystemPromptBuilder.build(
        now: now,
        assistantMode: _settings.assistantMode,
        languageCode: resolvedLanguage,
        toolNames: toolNames,
        sessionMemoryContext: _sessionMemoryContext,
        isVoiceMode: _isVoiceMode,
      ),
      role: MessageRole.system,
      timestamp: now,
    );
  }

  /// Prepares the message list sent to the LLM, including system messages.
  List<Message> _prepareMessagesForLLM() {
    final messages = state.messages.where((m) => !m.isStreaming).toList();
    final promptMessages = <Message>[_createSystemMessage()];
    if (_temporalReferenceContext != null) {
      promptMessages.add(
        Message(
          id: 'system_temporal',
          content: _temporalReferenceContext!,
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ),
      );
    }
    final result = [...promptMessages, ...messages];
    if (_hiddenPrompt != null) {
      result.add(_hiddenPrompt!);
    }
    return result;
  }

  final _uuid = const Uuid();
  StreamSubscription<String>? _streamSubscription;

  /// Tracks executed `tool_call`s to avoid duplicate execution.
  final Set<String> _executedContentToolCalls = {};

  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
  }) async {
    // Do not send empty input with no attached image.
    if (content.trim().isEmpty && imageBase64 == null) return;
    if (!mounted) return;

    _hiddenPrompt = null;
    _languageCode = languageCode;
    _isVoiceMode = isVoiceMode;

    _temporalReferenceContext = TemporalContextBuilder.build(
      now: DateTime.now(),
      userInput: content,
    );
    final shouldUseTemporalTool = _temporalReferenceContext != null;

    // Inject memory context only on the first turn of a new session.
    final isFirstTurn = state.messages.isEmpty;
    if (isFirstTurn) {
      _sessionMemoryContext = _memoryService.buildPromptContext(
        currentUserInput: content.trim(),
        currentConversationId: conversationId ?? '',
      );
      if (_sessionMemoryContext != null) {
        appLog('[Memory] Injecting context for new session');
      }
    }

    // Append the user message.
    final userMessage = Message(
      id: _uuid.v4(),
      content: content.trim(),
      role: MessageRole.user,
      timestamp: DateTime.now(),
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );

    if (!mounted) return;
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      error: null,
    );

    // Append a placeholder assistant message for streaming.
    final assistantMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    if (!mounted) return;
    state = state.copyWith(messages: [...state.messages, assistantMessage]);

    // Request extended background execution time on iOS.
    onSendStarted?.call();

    // Use tool-aware flow when the MCP tool service is available.
    if (_mcpToolService != null &&
        (_settings.mcpEnabled || shouldUseTemporalTool)) {
      final mode = _settings.mcpEnabled ? 'MCP' : 'TemporalOnly';
      appLog('[Tool] Sending in tool-aware mode ($mode)');
      await _sendWithTools();
    } else {
      appLog(
        '[Tool] Sending in normal mode (mcpToolService: ${_mcpToolService != null}, enabled: ${_settings.mcpEnabled})',
      );
      await _sendWithoutTools();
    }
  }

  /// Sends a hidden prompt without appending it to the visible conversation state.
  /// Typically used for proactive AI responses, like handling user silence in Voice Mode.
  Future<void> sendHiddenPrompt(
    String instruction, {
    bool isVoiceMode = false,
    String languageCode = 'en',
  }) async {
    if (!mounted) return;

    _temporalReferenceContext = null;
    _isVoiceMode = isVoiceMode;
    _languageCode = languageCode;
    _hiddenPrompt = Message(
      id: _uuid.v4(),
      content: instruction,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );

    // Append a placeholder assistant message for streaming.
    final assistantMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...state.messages, assistantMessage],
      isLoading: true,
      error: null,
    );

    onSendStarted?.call();

    // Use tool-aware flow when the MCP tool service is available.
    if (_mcpToolService != null && _settings.mcpEnabled) {
      appLog('[Tool] Sending hidden prompt in tool-aware mode');
      await _sendWithTools();
    } else {
      appLog('[Tool] Sending hidden prompt in normal mode');
      await _sendWithoutTools();
    }
  }

  /// Sends a streaming request without tools.
  Future<void> _sendWithoutTools() async {
    if (!mounted) return;
    try {
      final stream = _dataSource.streamChatCompletion(
        messages: _prepareMessagesForLLM(),
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          _appendToLastMessage(chunk);
        },
        onError: (error, stackTrace) {
          appLog(
            '[ChatNotifier] _sendWithoutTools stream onError: ${error.runtimeType}: $error',
          );
          appLog('[ChatNotifier] stackTrace: $stackTrace');
          _handleError(error.toString());
        },
        onDone: () {
          _finishStreaming();
        },
      );
    } catch (e, stackTrace) {
      appLog('[ChatNotifier] _sendWithoutTools catch: ${e.runtimeType}: $e');
      appLog('[ChatNotifier] stackTrace: $stackTrace');
      _handleError(e.toString());
    }
  }

  /// Sends a request with tool support (function calling).
  Future<void> _sendWithTools() async {
    if (!mounted) return;
    try {
      // Fetch tool definitions from the MCP tool service.
      final allTools = _mcpToolService?.getOpenAiToolDefinitions() ?? [];
      if (allTools.isEmpty) {
        // Fall back to normal streaming when no tools are available.
        await _sendWithoutTools();
        return;
      }
      appLog(
        '[Tool] Tool definitions: ${allTools.map((t) => (t['function'] as Map?)?['name']).toList()}',
      );

      // Start with search tools only to avoid premature `web_url_read` calls.
      final searchOnlyTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'searxng_web_search' || name == 'web_search';
      }).toList();
      final datetimeTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'get_current_datetime';
      }).toList();
      final memoryTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'search_past_conversations' || name == 'recall_memory';
      }).toList();
      final initialTools = searchOnlyTools.isNotEmpty
          ? _dedupeToolsByName([
              ...searchOnlyTools,
              ...datetimeTools,
              ...memoryTools,
            ])
          : allTools;

      // Inspect tool calls with a non-streaming request first.
      final result = await _dataSource.createChatCompletion(
        messages: _prepareMessagesForLLM(),
        tools: initialTools,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      if (!mounted) return;
      appLog(
        '[Tool] LLM response - finishReason: ${result.finishReason}, hasToolCalls: ${result.hasToolCalls}',
      );
      appLog(
        '[Tool] toolCalls: ${result.toolCalls?.map((t) => t.name).toList()}',
      );

      // Execute tool calls when the model requests them.
      if (result.hasToolCalls) {
        // Show any assistant preamble first, such as progress text.
        if (result.content.isNotEmpty) {
          _appendToLastMessage(result.content);
          _appendToLastMessage('\n\n');
        }
        await _executeToolCalls(
          result.toolCalls!,
          assistantContent: result.content.isNotEmpty ? result.content : null,
        );
      } else {
        // Show the response directly when no tool call is present.
        appLog('[Tool] No tool calls, displaying normal response');
        _appendToLastMessage(result.content);
        _finishStreaming();
      }
    } catch (e) {
      // Fall back when the LLM likely does not support tools.
      final errorStr = e.toString().toLowerCase();
      appLog('[Tool] Error occurred: $e');

      // Fall back to normal mode for tool-related failures.
      // Examples include JSON parse errors, empty responses, or invalid payloads.
      if (errorStr.contains('formatexception') ||
          errorStr.contains('expecting value') ||
          errorStr.contains('empty') ||
          errorStr.contains('json') ||
          errorStr.contains('decode') ||
          errorStr.contains('parse') ||
          errorStr.contains('unexpected') ||
          errorStr.contains('invalid') ||
          errorStr.contains('500') ||
          errorStr.contains('server error')) {
        appLog('[Tool] LLM may not support tools, falling back to normal mode');
        await _sendWithoutTools();
        return;
      }
      _handleError(e.toString());
    }
  }

  List<Map<String, dynamic>> _dedupeToolsByName(
    List<Map<String, dynamic>> tools,
  ) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final tool in tools) {
      final name = (tool['function'] as Map?)?['name'];
      if (name is! String || name.isEmpty) continue;
      if (seen.add(name)) {
        deduped.add(tool);
      }
    }
    return deduped;
  }

  /// Executes tool calls, supporting a repeated tool-call loop.
  ///
  /// Continues looping while the LLM keeps requesting tools, until it returns
  /// a text response. Because qwen35-35b does not reliably use tool-role
  /// messages as real-time data, tool results are resent as a user message.
  Future<void> _executeToolCalls(
    List<ToolCallInfo> toolCalls, {
    String? assistantContent,
  }) async {
    var currentToolCalls = toolCalls;
    var currentAssistantContent = assistantContent;
    const maxIterations = 5; // Prevent infinite loops.
    var iteration = 0;
    var consecutiveErrors = 0;
    String? lastErrorToolName;
    var hasTextResponse = false;
    // Collect tool results for the final user-role resend.
    final toolResults = <String>[];

    while (currentToolCalls.isNotEmpty && iteration < maxIterations) {
      iteration++;
      final toolCall = currentToolCalls.first;
      if (!mounted) return;

      appLog('[Tool] Tool loop [$iteration/$maxIterations]');
      appLog('[Tool] Executing tool: ${toolCall.name}');
      appLog('[Tool] Arguments: ${toolCall.arguments}');

      _appendToolUseToLastMessage(toolCall);

      try {
        // Execute the tool through the MCP tool service.
        final result = await _mcpToolService!.executeTool(
          name: toolCall.name,
          arguments: toolCall.arguments,
        );

        String toolResult;
        if (result.isSuccess) {
          toolResult = result.result;
          toolResults.add('[Result of ${toolCall.name}]\n$toolResult');
          consecutiveErrors = 0;
          lastErrorToolName = null;
        } else {
          toolResult = 'Error: ${result.errorMessage}';
          // Count repeated failures for the same tool.
          if (lastErrorToolName == toolCall.name) {
            consecutiveErrors++;
          } else {
            consecutiveErrors = 1;
            lastErrorToolName = toolCall.name;
          }
          if (consecutiveErrors >= 2) {
            appLog(
              '[Tool] Same tool (${toolCall.name}) failed $consecutiveErrors times consecutively, ending loop',
            );
            _appendToLastMessage(
              '\nFailed to execute tool (${toolCall.name}). Please check your server configuration.\nError: ${result.errorMessage}\n',
            );
            hasTextResponse = true;
            break;
          }
        }

        appLog('[Tool] Result retrieved: ${toolResult.length} chars');

        // Send the tool result back to the LLM and check for follow-up calls.
        // Use a non-streaming request with tool definitions included.
        final mcpToolService = _mcpToolService;
        if (mcpToolService == null) {
          await _sendWithoutTools();
          return;
        }
        final tools = mcpToolService.getOpenAiToolDefinitions();
        final nextResult = await _dataSource.createChatCompletionWithToolResult(
          messages: _prepareMessagesForLLM(),
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          toolArguments: jsonEncode(toolCall.arguments),
          toolResult: toolResult,
          assistantContent: currentAssistantContent,
          tools: tools,
          model: _settings.model,
          temperature: _settings.temperature,
          maxTokens: _settings.maxTokens,
        );

        if (!mounted) return;

        // Continue looping if the LLM asks for another tool call.
        if (nextResult.hasToolCalls) {
          appLog('[Tool] LLM requested additional tool calls');
          currentToolCalls = nextResult.toolCalls!;
          currentAssistantContent = nextResult.content.isNotEmpty
              ? nextResult.content
              : null;
        } else {
          // End the loop on a text response, but delay rendering it.
          appLog('[Tool] LLM returned final text response (via tool role)');
          currentToolCalls = [];
          // Responses through the tool role often claim real-time data is
          // unavailable, so resend the results later as a user message.
        }
      } catch (e) {
        appLog('[Tool] Error: $e');
        _appendToLastMessage('[Search error: $e]\n');
        currentToolCalls = [];
        hasTextResponse = true;
      }
    }

    // If tool results exist and no text response has been shown yet,
    // resend them as a user message and stream the final answer.
    if (!hasTextResponse && toolResults.isNotEmpty) {
      appLog('[Tool] Resending tool results as user message');

      if (!mounted) return;

      // Build a prompt that includes tool results as a user message.
      final messagesForLLM = _prepareMessagesForLLM();
      // Append the collected tool results as a user message.
      final resultsText = toolResults.join('\n\n');
      messagesForLLM.add(
        Message(
          id: 'tool_result_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Please answer the user\'s question based on the following search results.\n\n$resultsText',
          role: MessageRole.user,
          timestamp: DateTime.now(),
        ),
      );

      // Stream the final answer.
      final stream = _dataSource.streamChatCompletion(
        messages: messagesForLLM,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      if (state.messages.isNotEmpty && state.messages.last.content.isNotEmpty) {
        _appendToLastMessage('\n');
      }

      await for (final chunk in stream) {
        if (!mounted) return;
        _appendToLastMessage(chunk);
      }
    } else if (!hasTextResponse) {
      appLog('[Tool] Tool loop reached maximum iterations (no text response)');
      if (state.messages.isNotEmpty) {
        _appendToLastMessage('\nSorry, there was a problem executing the tools. Please try again later.');
      }
    }

    _finishStreaming();
  }

  void _appendToLastMessage(String chunk) {
    if (!mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    final newContent = lastMessage.content + chunk;
    updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);

    state = state.copyWith(messages: updatedMessages);

    // Check whether the content contains completed tool-call tags.
    _checkForContentToolCalls(newContent);
  }

  void _appendToolUseToLastMessage(ToolCallInfo toolCall) {
    final payload = <String, dynamic>{
      'name': toolCall.name,
      'arguments': toolCall.arguments,
    };
    _appendToLastMessage('<tool_use>${jsonEncode(payload)}</tool_use>\n');
  }

  /// Tool executions that are still pending.
  final List<Future<void>> _pendingToolExecutions = [];

  /// Detects and runs `tool_call` tags embedded in the content.
  void _checkForContentToolCalls(String content) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    if (toolCalls.isNotEmpty) {
      appLog('[ContentTool] Detected tool_call(s): ${toolCalls.length}');
      for (final tc in toolCalls) {
        appLog('[ContentTool]   - ${tc.name}: ${tc.arguments}');
      }
      appLog(
        '[ContentTool] MCP tool service: ${_mcpToolService != null ? "enabled" : "disabled (enable MCP in settings)"}',
      );
    }

    if (_mcpToolService == null) return;

    for (final tc in toolCalls) {
      final hash = '${tc.name}:${jsonEncode(tc.arguments)}';
      if (!_executedContentToolCalls.contains(hash)) {
        appLog('[ContentTool] Starting execution: $hash');
        _executedContentToolCalls.add(hash);
        final future = _executeContentToolCall(tc);
        _pendingToolExecutions.add(future);
      } else {
        appLog('[ContentTool] Already executed: $hash');
      }
    }
  }

  /// Executes a `tool_call` detected from message content.
  Future<void> _executeContentToolCall(ToolCallData tc) async {
    if (!mounted) return;

    appLog('[ContentTool] Executing tool: ${tc.name}');
    appLog('[ContentTool] Arguments: ${tc.arguments}');

    final mcpToolService = _mcpToolService;
    if (mcpToolService != null) {
      try {
        final result = await mcpToolService.executeTool(
          name: tc.name,
          arguments: tc.arguments,
        );

        if (!result.isSuccess) {
          appLog('[ContentTool] Execution failed: ${result.errorMessage}');
          return;
        }

        appLog('[ContentTool] Result retrieved: ${result.result.length} chars');

        // Append search results without triggering recursive tool-call checks.
        if (mounted && state.messages.isNotEmpty) {
          final updatedMessages = [...state.messages];
          final lastIndex = updatedMessages.length - 1;
          final lastMessage = updatedMessages[lastIndex];

          updatedMessages[lastIndex] = lastMessage.copyWith(
            content: '${lastMessage.content}\n\n📋 **Search results:**\n${result.result}',
          );

          state = state.copyWith(messages: updatedMessages);
          appLog('[ContentTool] Appended result to message');
        }
      } catch (e) {
        appLog('[ContentTool] Error: $e');
        if (mounted && state.messages.isNotEmpty) {
          final updatedMessages = [...state.messages];
          final lastIndex = updatedMessages.length - 1;
          final lastMessage = updatedMessages[lastIndex];

          updatedMessages[lastIndex] = lastMessage.copyWith(
            content: '${lastMessage.content}\n\n[Tool execution error: $e]',
          );

          state = state.copyWith(messages: updatedMessages);
        }
      }
    }
  }

  Future<void> _finishStreaming() async {
    // Wait for pending tool executions before finalizing the response.
    if (_pendingToolExecutions.isNotEmpty) {
      appLog('[ChatNotifier] Waiting for pending tool executions: ${_pendingToolExecutions.length}');
      await Future.wait(_pendingToolExecutions);
      _pendingToolExecutions.clear();
      appLog('[ChatNotifier] Tool executions completed');
    }

    if (!mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);

    state = state.copyWith(messages: updatedMessages, isLoading: false);

    // Hidden prompt responses are ephemeral — remove from visible history
    // so they are spoken but not persisted in the conversation.
    if (_hiddenPrompt != null) {
      final cleaned = updatedMessages.sublist(0, lastIndex);
      state = state.copyWith(messages: cleaned);
      _hiddenPrompt = null;
      onResponseCompleted?.call('');
      return;
    }

    // Persist messages.
    _saveMessages();

    // Trigger auto-read when enabled.
    if (_settings.autoReadEnabled &&
        _settings.ttsEnabled &&
        onAutoRead != null) {
      final lastMsg = updatedMessages[lastIndex];
      if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
        onAutoRead!(lastMsg.content);
      }
    }

    // Notify when the response completes while the app is in the background.
    final lastMsg = updatedMessages[lastIndex];
    if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
      onResponseCompleted?.call(lastMsg.content);
    } else {
      onResponseCompleted?.call('');
    }
  }

  /// Persists the current conversation messages.
  void _saveMessages() {
    // Save only messages that are no longer streaming.
    final messagesToSave = state.messages.where((m) => !m.isStreaming).toList();
    String? targetAssistantMessageId;
    for (var i = messagesToSave.length - 1; i >= 0; i--) {
      if (messagesToSave[i].role == MessageRole.assistant) {
        targetAssistantMessageId = messagesToSave[i].id;
        break;
      }
    }

    if (onMessagesChanged != null) {
      onMessagesChanged!(messagesToSave);
    }

    final currentConversationId = conversationId;
    if (currentConversationId != null && targetAssistantMessageId != null) {
      unawaited(
        _updateSessionMemory(
          currentConversationId,
          messagesToSave,
          targetAssistantMessageId,
        ),
      );
    }
  }

  Future<void> _updateSessionMemory(
    String currentConversationId,
    List<Message> messagesToSave,
    String targetAssistantMessageId,
  ) async {
    final draft = await _extractMemoryDraftWithLlm(messagesToSave);
    final result = await _memoryService.updateFromConversation(
      conversationId: currentConversationId,
      messages: messagesToSave,
      draft: draft,
    );
    if (!mounted || !result.hasAnyUpdate) return;

    final updatedMessages = [...state.messages];
    final targetIndex = updatedMessages.indexWhere(
      (message) => message.id == targetAssistantMessageId,
    );
    if (targetIndex < 0) return;
    final targetMessage = updatedMessages[targetIndex];
    if (targetMessage.role != MessageRole.assistant ||
        targetMessage.isStreaming) {
      return;
    }

    final memoryTag = _buildMemoryUpdateToolUse(result);
    if (targetMessage.content.contains(memoryTag)) return;

    updatedMessages[targetIndex] = targetMessage.copyWith(
      content: '${targetMessage.content}\n$memoryTag',
    );
    state = state.copyWith(messages: updatedMessages);

    if (onMessagesChanged != null) {
      final normalized = updatedMessages.where((m) => !m.isStreaming).toList();
      onMessagesChanged!(normalized);
    }
  }

  Future<MemoryExtractionDraft?> _extractMemoryDraftWithLlm(
    List<Message> messages,
  ) async {
    final userMessages = messages.where((message) {
      return message.role == MessageRole.user &&
          message.content.trim().isNotEmpty;
    }).toList();
    if (userMessages.isEmpty) return null;

    final now = DateTime.now();
    final profile = _memoryService.loadProfile();
    final extractionInput = _buildMemoryExtractionInput(messages, profile);

    final extractionMessages = [
      Message(
        id: 'memory_extractor_system',
        role: MessageRole.system,
        timestamp: now,
        content:
            'You extract reusable user memory from a conversation. '
            'Output only a single valid JSON object with no markdown. '
            'Schema: {"summary":string,"open_loops":[string],'
            '"profile":{"persona":[string],"preferences":[string],"do_not":[string]},'
            '"memories":[{"text":string,"type":"preference|persona|topic|constraint|fact",'
            '"confidence":number,"importance":number,"ttl_days":number|null}]}. '
            'Focus on stable user traits/preferences/constraints. '
            'Also extract specific facts the user mentioned: prices, quantities, '
            'purchases, dates, decisions, events, and other concrete data points. '
            'Use type "fact" with high importance for these. '
            'Facts should have detailed text (up to 300 chars) to preserve specifics. '
            'Do not include temporary assistant instructions.',
      ),
      Message(
        id: 'memory_extractor_user',
        role: MessageRole.user,
        timestamp: now,
        content: extractionInput,
      ),
    ];

    try {
      final result = await _dataSource.createChatCompletion(
        messages: extractionMessages,
        model: _settings.model,
        temperature: 0.1,
        maxTokens: _settings.maxTokens > 1200 ? 1200 : _settings.maxTokens,
      );

      final draft = _parseMemoryExtractionDraft(result.content);
      if (draft != null) {
        appLog('[Memory] LLM memory extraction succeeded');
      } else {
        appLog('[Memory] Failed to parse LLM memory extraction JSON (falling back to rule-based)');
      }
      return draft;
    } catch (e) {
      appLog('[Memory] LLM memory extraction error: $e');
      return null;
    }
  }

  String _buildMemoryExtractionInput(
    List<Message> messages,
    UserMemoryProfile profile,
  ) {
    final buffer = StringBuffer()
      ..writeln('Current profile:')
      ..writeln('- persona: ${profile.persona.join(' | ')}')
      ..writeln('- preferences: ${profile.preferences.join(' | ')}')
      ..writeln('- do_not: ${profile.doNot.join(' | ')}')
      ..writeln()
      ..writeln('Conversation log:');

    final tail = messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages;
    for (final message in tail) {
      if (message.content.trim().isEmpty) continue;
      final role = message.role.name;
      final content = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final clipped = content.length > 360
          ? '${content.substring(0, 360)}...'
          : content;
      buffer.writeln('- $role: $clipped');
    }

    buffer
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- summary must be 160 characters or fewer')
      ..writeln('- open_loops max 3 items')
      ..writeln('- memories max 8 items')
      ..writeln('- confidence/importance range: 0.0 to 1.0')
      ..writeln('- Set confidence low for uncertain items');

    return buffer.toString();
  }

  MemoryExtractionDraft? _parseMemoryExtractionDraft(String rawContent) {
    final jsonText = _extractJsonObject(rawContent);
    if (jsonText == null) return null;

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      final summary = (map['summary'] as String?)?.trim() ?? '';
      final openLoops = _stringList(map['open_loops'], maxLength: 3);

      final profile = map['profile'];
      List<String> persona = const [];
      List<String> preferences = const [];
      List<String> doNot = const [];
      if (profile is Map) {
        final profileMap = Map<String, dynamic>.from(profile);
        persona = _stringList(profileMap['persona'], maxLength: 12);
        preferences = _stringList(profileMap['preferences'], maxLength: 16);
        doNot = _stringList(profileMap['do_not'], maxLength: 16);
      }

      final entries = <MemoryDraftEntry>[];
      final memoriesRaw = map['memories'];
      if (memoriesRaw is List) {
        for (final raw in memoriesRaw.take(8)) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final text = (item['text'] as String?)?.trim() ?? '';
          if (text.isEmpty) continue;
          final type = (item['type'] as String?)?.trim() ?? 'topic';
          final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.6;
          final importance = (item['importance'] as num?)?.toDouble() ?? 0.6;
          final ttlDays = (item['ttl_days'] as num?)?.toInt();
          entries.add(
            MemoryDraftEntry(
              text: text,
              type: type,
              confidence: confidence,
              importance: importance,
              ttlDays: ttlDays,
            ),
          );
        }
      }

      final draft = MemoryExtractionDraft(
        summary: summary,
        openLoops: openLoops,
        persona: persona,
        preferences: preferences,
        doNot: doNot,
        entries: entries,
      );
      return draft.isEmpty ? null : draft;
    } catch (e) {
      appLog('[Memory] Failed to parse memory extraction JSON: $e');
      return null;
    }
  }

  String? _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    final first = text.indexOf('{');
    final last = text.lastIndexOf('}');
    if (first < 0 || last <= first) return null;
    return text.substring(first, last + 1);
  }

  List<String> _stringList(Object? raw, {required int maxLength}) {
    if (raw is! List) return const [];
    final values = raw
        .whereType<String>()
        .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.length <= maxLength) return values;
    return values.sublist(0, maxLength);
  }

  String _buildMemoryUpdateToolUse(MemoryUpdateResult result) {
    final payload = <String, dynamic>{
      'name': 'memory_update',
      'arguments': <String, dynamic>{
        'summaryUpdated': result.summaryUpdated,
        'added': result.addedMemoryCount,
        'updated': result.updatedMemoryCount,
        'profileUpdated': result.profileUpdated,
        'method': result.generationMethod.name,
      },
    };
    return '<tool_use>${jsonEncode(payload)}</tool_use>';
  }

  void _handleError(String error) {
    appLog('[ChatNotifier] _handleError called');
    appLog('[ChatNotifier]   raw error: $error');
    if (!mounted || state.messages.isEmpty) {
      appLog(
        '[ChatNotifier]   skipped: mounted=$mounted, messages.isEmpty=${state.messages.isEmpty}',
      );
      return;
    }

    // Reformat error messages into clearer user-facing categories.
    final displayError = _buildDisplayError(error);

    appLog('[ChatNotifier]   displayError: $displayError');

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(
      isStreaming: false,
      error: displayError,
    );

    state = state.copyWith(
      messages: updatedMessages,
      isLoading: false,
      error: displayError,
    );
  }

  String _buildDisplayError(String rawError) {
    final cleanedError = _cleanRawError(rawError);
    final lower = cleanedError.toLowerCase();

    if (cleanedError.contains("Only 'text' content type is supported")) {
      return 'This LLM server does not support image input. Please send text only.\nDetails: $cleanedError';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return 'Could not connect to LLM server. Check your network connection and endpoint URL. (${_settings.baseUrl})\nDetails: $cleanedError';
    }
    if (lower.contains('connection refused')) {
      return 'Could not connect to LLM server. Make sure the server is running. (${_settings.baseUrl})\nDetails: $cleanedError';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'LLM request timed out. Please wait and try again.\nDetails: $cleanedError';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Authentication failed. Please check your API key.\nDetails: $cleanedError';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Access denied. Please check your API key permissions or server settings.\nDetails: $cleanedError';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'Endpoint or model not found. Please check your settings.\nDetails: $cleanedError';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return 'Too many requests. Please wait a moment and try again.\nDetails: $cleanedError';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('server error') ||
        lower.contains('internal server error')) {
      return 'An error occurred on the LLM server. Please check the server logs.\nDetails: $cleanedError';
    }
    if (lower.contains('json') ||
        lower.contains('decode') ||
        lower.contains('parse') ||
        lower.contains('unexpected')) {
      return 'Could not parse the response from the LLM server.\nDetails: $cleanedError';
    }

    return cleanedError;
  }

  String _cleanRawError(String rawError) {
    var cleaned = rawError.trim();
    const prefixes = [
      'Exception: ',
      'Bad state: ',
      'ClientException: ',
      'Invalid argument(s): ',
    ];

    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length);
      }
    }

    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void cancelStreaming() {
    _streamSubscription?.cancel();
    _streamSubscription = null;

    if (mounted && state.messages.isNotEmpty) {
      final lastMessage = state.messages.last;
      if (lastMessage.isStreaming) {
        _finishStreaming();
      }
    }
  }

  void clearMessages() {
    if (!mounted) return;
    cancelStreaming();
    _executedContentToolCalls.clear();
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    state = ChatState.initial();
  }

  @override
  void dispose() {
    cancelStreaming();
    super.dispose();
  }
}

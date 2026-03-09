import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

  // 現在の会話のメッセージを読み込み
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
      // 読み上げ用テキストを抽出（<think>タグなどを除去）
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
    this.conversationId,
    List<Message>? initialMessages,
  }) : super(ChatState.initial()) {
    // 初期メッセージを読み込み
    if (initialMessages != null && initialMessages.isNotEmpty) {
      state = state.copyWith(messages: initialMessages);
    }
    // MCPツールサービスに接続
    _mcpToolService?.connect();
  }

  ChatRemoteDataSource _dataSource;
  McpToolService? _mcpToolService;
  final SessionMemoryService _memoryService;
  AppSettings _settings;
  final void Function(List<Message>)? onMessagesChanged;
  final void Function(String content)? onAutoRead;
  String? conversationId;
  String? _sessionMemoryContext;
  String? _temporalReferenceContext;

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

  /// 現在日時を含むシステムメッセージを生成
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

    return Message(
      id: 'system',
      content: SystemPromptBuilder.build(
        now: now,
        assistantMode: _settings.assistantMode,
        toolNames: toolNames,
        sessionMemoryContext: _sessionMemoryContext,
      ),
      role: MessageRole.system,
      timestamp: now,
    );
  }

  /// LLMに送信するメッセージリストを準備（システムメッセージ付き）
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
    return [...promptMessages, ...messages];
  }

  final _uuid = const Uuid();
  StreamSubscription<String>? _streamSubscription;

  /// 実行済みtool_callを追跡（重複実行防止）
  final Set<String> _executedContentToolCalls = {};

  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
  }) async {
    // テキストも画像もない場合は送信しない
    if (content.trim().isEmpty && imageBase64 == null) return;
    if (!mounted) return;

    _temporalReferenceContext = TemporalContextBuilder.build(
      now: DateTime.now(),
      userInput: content,
    );
    final shouldUseTemporalTool = _temporalReferenceContext != null;

    // 新規セッション初回送信時のみ、過去コンテキストを注入
    final isFirstTurn = state.messages.isEmpty;
    if (isFirstTurn) {
      _sessionMemoryContext = _memoryService.buildPromptContext(
        currentUserInput: content.trim(),
        currentConversationId: conversationId ?? '',
      );
      if (_sessionMemoryContext != null) {
        print('[Memory] 新規セッション用コンテキストを注入');
      }
    }

    // ユーザーメッセージを追加
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

    // アシスタントメッセージ（ストリーミング用）を追加
    final assistantMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    if (!mounted) return;
    state = state.copyWith(messages: [...state.messages, assistantMessage]);

    // MCPツールサービスが有効な場合はツール対応の処理
    if (_mcpToolService != null &&
        (_settings.mcpEnabled || shouldUseTemporalTool)) {
      final mode = _settings.mcpEnabled ? 'MCP' : 'TemporalOnly';
      print('[Tool] ツール対応モードで送信 ($mode)');
      await _sendWithTools();
    } else {
      print(
        '[Tool] 通常モードで送信 (mcpToolService: ${_mcpToolService != null}, enabled: ${_settings.mcpEnabled})',
      );
      await _sendWithoutTools();
    }
  }

  /// ツールなしでストリーミング送信
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
          print(
            '[ChatNotifier] _sendWithoutTools stream onError: ${error.runtimeType}: $error',
          );
          print('[ChatNotifier] stackTrace: $stackTrace');
          _handleError(error.toString());
        },
        onDone: () {
          _finishStreaming();
        },
      );
    } catch (e, stackTrace) {
      print('[ChatNotifier] _sendWithoutTools catch: ${e.runtimeType}: $e');
      print('[ChatNotifier] stackTrace: $stackTrace');
      _handleError(e.toString());
    }
  }

  /// ツール対応で送信（Function Calling）
  Future<void> _sendWithTools() async {
    if (!mounted) return;
    try {
      // MCPツールサービスからツール定義を取得
      final allTools = _mcpToolService?.getOpenAiToolDefinitions() ?? [];
      if (allTools.isEmpty) {
        // ツールがない場合は通常送信
        await _sendWithoutTools();
        return;
      }
      print(
        '[Tool] ツール定義: ${allTools.map((t) => (t['function'] as Map?)?['name']).toList()}',
      );

      // 初回は検索ツールのみ渡す（LLMがweb_url_readを先に使うのを防止）
      final searchOnlyTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'searxng_web_search' || name == 'web_search';
      }).toList();
      final datetimeTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'get_current_datetime';
      }).toList();
      final initialTools = searchOnlyTools.isNotEmpty
          ? _dedupeToolsByName([...searchOnlyTools, ...datetimeTools])
          : allTools;

      // 非ストリーミングでツール呼び出しをチェック
      final result = await _dataSource.createChatCompletion(
        messages: _prepareMessagesForLLM(),
        tools: initialTools,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      if (!mounted) return;
      print(
        '[Tool] LLM応答 - finishReason: ${result.finishReason}, hasToolCalls: ${result.hasToolCalls}',
      );
      print(
        '[Tool] toolCalls: ${result.toolCalls?.map((t) => t.name).toList()}',
      );

      // ツール呼び出しがある場合
      if (result.hasToolCalls) {
        // contentがあれば先に表示（「調べてみましょう」等の進捗メッセージ）
        if (result.content.isNotEmpty) {
          _appendToLastMessage(result.content);
          _appendToLastMessage('\n\n');
        }
        await _executeToolCalls(
          result.toolCalls!,
          assistantContent: result.content.isNotEmpty ? result.content : null,
        );
      } else {
        // ツール呼び出しがない場合は結果を表示
        print('[Tool] ツール呼び出しなし、通常応答を表示');
        _appendToLastMessage(result.content);
        _finishStreaming();
      }
    } catch (e) {
      // LLMがツールをサポートしていない場合はフォールバック
      final errorStr = e.toString().toLowerCase();
      print('[Tool] エラー発生: $e');

      // ツール関連のエラーは通常モードにフォールバック
      // JSON解析エラー、空レスポンス、不正なレスポンス形式など
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
        print('[Tool] LLMがツールをサポートしていない可能性、通常モードにフォールバック');
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

  /// ツール呼び出しを実行（ツールループ対応）
  ///
  /// LLMがツールを呼び出す限りループし、テキスト応答を返すまで繰り返す。
  /// qwen35-35bはtoolロールのメッセージを「リアルタイムデータ」として使えないため、
  /// ツール結果は最終的にuserロールのメッセージとしてLLMに送信する。
  Future<void> _executeToolCalls(
    List<ToolCallInfo> toolCalls, {
    String? assistantContent,
  }) async {
    var currentToolCalls = toolCalls;
    var currentAssistantContent = assistantContent;
    const maxIterations = 5; // 無限ループ防止
    var iteration = 0;
    var consecutiveErrors = 0;
    String? lastErrorToolName;
    var hasTextResponse = false;
    // 収集したツール結果（最終的にuserメッセージとして送信）
    final toolResults = <String>[];

    while (currentToolCalls.isNotEmpty && iteration < maxIterations) {
      iteration++;
      final toolCall = currentToolCalls.first;
      if (!mounted) return;

      print('[Tool] ツールループ [$iteration/$maxIterations]');
      print('[Tool] ツール実行: ${toolCall.name}');
      print('[Tool] 引数: ${toolCall.arguments}');

      _appendToolUseToLastMessage(toolCall);

      try {
        // MCPツールサービスでツール実行
        final result = await _mcpToolService!.executeTool(
          name: toolCall.name,
          arguments: toolCall.arguments,
        );

        String toolResult;
        if (result.isSuccess) {
          toolResult = result.result;
          toolResults.add('【${toolCall.name}の結果】\n$toolResult');
          consecutiveErrors = 0;
          lastErrorToolName = null;
        } else {
          toolResult = 'エラー: ${result.errorMessage}';
          // 同じツールが連続で失敗した場合をカウント
          if (lastErrorToolName == toolCall.name) {
            consecutiveErrors++;
          } else {
            consecutiveErrors = 1;
            lastErrorToolName = toolCall.name;
          }
          if (consecutiveErrors >= 2) {
            print(
              '[Tool] 同じツール(${toolCall.name})が連続$consecutiveErrors回失敗、ループ終了',
            );
            _appendToLastMessage(
              '\nツール（${toolCall.name}）の実行に失敗しました。サーバーの設定を確認してください。\nエラー: ${result.errorMessage}\n',
            );
            hasTextResponse = true;
            break;
          }
        }

        print('[Tool] 結果取得完了: ${toolResult.length} chars');

        // ツール結果をLLMに送信してさらなるツール呼び出しが必要か確認
        // ツール結果をLLMに送信（非ストリーミング・ツール定義付き）
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

        // LLMが新たなツール呼び出しを返した場合 → ループ継続
        if (nextResult.hasToolCalls) {
          print('[Tool] LLMが追加のツール呼び出しを要求');
          currentToolCalls = nextResult.toolCalls!;
          currentAssistantContent = nextResult.content.isNotEmpty
              ? nextResult.content
              : null;
        } else {
          // テキスト応答 → ループ終了（まだ表示しない）
          print('[Tool] LLMが最終テキスト応答を返却（toolロール経由）');
          currentToolCalls = [];
          // toolロール経由の応答は「リアルタイム情報にアクセスできない」と言いがちなので
          // 後でuserロールとして再送信する
        }
      } catch (e) {
        print('[Tool] エラー: $e');
        _appendToLastMessage('[検索エラー: $e]\n');
        currentToolCalls = [];
        hasTextResponse = true;
      }
    }

    // ツール結果があり、まだテキスト応答を表示していない場合
    // → userロールメッセージとして再送信し、ストリーミングで最終回答を取得
    if (!hasTextResponse && toolResults.isNotEmpty) {
      print('[Tool] ツール結果をuserメッセージとして再送信');

      if (!mounted) return;

      // ツール結果をuserメッセージとして追加した会話を構築
      final messagesForLLM = _prepareMessagesForLLM();
      // 検索結果をuserメッセージとして追加
      final resultsText = toolResults.join('\n\n');
      messagesForLLM.add(
        Message(
          id: 'tool_result_${DateTime.now().millisecondsSinceEpoch}',
          content: '以下の検索結果を基にユーザーの質問に回答してください。\n\n$resultsText',
          role: MessageRole.user,
          timestamp: DateTime.now(),
        ),
      );

      // ストリーミングで最終回答を取得
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
      print('[Tool] ツールループが上限に達しました（テキスト応答なし）');
      if (state.messages.isNotEmpty) {
        _appendToLastMessage('\n申し訳ありません。ツールの実行に問題が発生しました。しばらく経ってからお試しください。');
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

    // コンテンツ内の完了したtool_callをチェック
    _checkForContentToolCalls(newContent);
  }

  void _appendToolUseToLastMessage(ToolCallInfo toolCall) {
    final payload = <String, dynamic>{
      'name': toolCall.name,
      'arguments': toolCall.arguments,
    };
    _appendToLastMessage('<tool_use>${jsonEncode(payload)}</tool_use>\n');
  }

  /// 実行待ちのツール呼び出し
  final List<Future<void>> _pendingToolExecutions = [];

  /// コンテンツ内のtool_callタグを検出して実行
  void _checkForContentToolCalls(String content) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    if (toolCalls.isNotEmpty) {
      print('[ContentTool] 検出されたtool_call: ${toolCalls.length}件');
      for (final tc in toolCalls) {
        print('[ContentTool]   - ${tc.name}: ${tc.arguments}');
      }
      print(
        '[ContentTool] MCPツールサービス: ${_mcpToolService != null ? "有効" : "無効（設定でMCPを有効にしてください）"}',
      );
    }

    if (_mcpToolService == null) return;

    for (final tc in toolCalls) {
      final hash = '${tc.name}:${jsonEncode(tc.arguments)}';
      if (!_executedContentToolCalls.contains(hash)) {
        print('[ContentTool] 実行開始: $hash');
        _executedContentToolCalls.add(hash);
        final future = _executeContentToolCall(tc);
        _pendingToolExecutions.add(future);
      } else {
        print('[ContentTool] 既に実行済み: $hash');
      }
    }
  }

  /// コンテンツから検出されたtool_callを実行
  Future<void> _executeContentToolCall(ToolCallData tc) async {
    if (!mounted) return;

    print('[ContentTool] ツール実行: ${tc.name}');
    print('[ContentTool] 引数: ${tc.arguments}');

    final mcpToolService = _mcpToolService;
    if (mcpToolService != null) {
      try {
        final result = await mcpToolService.executeTool(
          name: tc.name,
          arguments: tc.arguments,
        );

        if (!result.isSuccess) {
          print('[ContentTool] 実行失敗: ${result.errorMessage}');
          return;
        }

        print('[ContentTool] 結果取得完了: ${result.result.length} chars');

        // 検索結果をメッセージに追記（_checkForContentToolCallsを呼ばない版）
        if (mounted && state.messages.isNotEmpty) {
          final updatedMessages = [...state.messages];
          final lastIndex = updatedMessages.length - 1;
          final lastMessage = updatedMessages[lastIndex];

          updatedMessages[lastIndex] = lastMessage.copyWith(
            content: '${lastMessage.content}\n\n📋 **検索結果:**\n${result.result}',
          );

          state = state.copyWith(messages: updatedMessages);
          print('[ContentTool] メッセージに追記完了');
        }
      } catch (e) {
        print('[ContentTool] エラー: $e');
        if (mounted && state.messages.isNotEmpty) {
          final updatedMessages = [...state.messages];
          final lastIndex = updatedMessages.length - 1;
          final lastMessage = updatedMessages[lastIndex];

          updatedMessages[lastIndex] = lastMessage.copyWith(
            content: '${lastMessage.content}\n\n[ツール実行エラー: $e]',
          );

          state = state.copyWith(messages: updatedMessages);
        }
      }
    }
  }

  Future<void> _finishStreaming() async {
    // 保留中のツール実行を待ってから完了処理
    if (_pendingToolExecutions.isNotEmpty) {
      print('[ChatNotifier] 保留中のツール実行を待機: ${_pendingToolExecutions.length}件');
      await Future.wait(_pendingToolExecutions);
      _pendingToolExecutions.clear();
      print('[ChatNotifier] ツール実行完了');
    }

    if (!mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);

    state = state.copyWith(messages: updatedMessages, isLoading: false);

    // メッセージを保存
    _saveMessages();

    // 自動読み上げ
    if (_settings.autoReadEnabled &&
        _settings.ttsEnabled &&
        onAutoRead != null) {
      final lastMsg = updatedMessages[lastIndex];
      if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
        onAutoRead!(lastMsg.content);
      }
    }
  }

  /// メッセージを保存（会話の永続化）
  void _saveMessages() {
    // ストリーミング中でないメッセージのみ保存
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
            '"memories":[{"text":string,"type":"preference|persona|topic|constraint",'
            '"confidence":number,"importance":number,"ttl_days":number|null}]}. '
            'Focus on stable user traits/preferences/constraints. '
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
        print('[Memory] LLMメモリ抽出に成功');
      } else {
        print('[Memory] LLMメモリ抽出のJSON解析に失敗（ルールベースへフォールバック）');
      }
      return draft;
    } catch (e) {
      print('[Memory] LLMメモリ抽出エラー: $e');
      return null;
    }
  }

  String _buildMemoryExtractionInput(
    List<Message> messages,
    UserMemoryProfile profile,
  ) {
    final buffer = StringBuffer()
      ..writeln('現在プロフィール:')
      ..writeln('- persona: ${profile.persona.join(' | ')}')
      ..writeln('- preferences: ${profile.preferences.join(' | ')}')
      ..writeln('- do_not: ${profile.doNot.join(' | ')}')
      ..writeln()
      ..writeln('会話ログ:');

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
      ..writeln('出力ルール:')
      ..writeln('- summary は160文字以内')
      ..writeln('- open_loops は最大3件')
      ..writeln('- memories は最大8件')
      ..writeln('- confidence/importance は0.0〜1.0')
      ..writeln('- 不確実な項目は confidence を低くする');

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
      print('[Memory] メモリ抽出JSONのパースに失敗: $e');
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
    print('[ChatNotifier] _handleError called');
    print('[ChatNotifier]   raw error: $error');
    if (!mounted || state.messages.isEmpty) {
      print(
        '[ChatNotifier]   skipped: mounted=$mounted, messages.isEmpty=${state.messages.isEmpty}',
      );
      return;
    }

    // エラーメッセージを原因別に分かりやすく整形
    final displayError = _buildDisplayError(error);

    print('[ChatNotifier]   displayError: $displayError');

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
      return 'このLLMサーバーは画像入力に対応していません。テキストのみ送信してください。\n詳細: $cleanedError';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return 'LLMサーバーに接続できませんでした。ネットワーク接続とエンドポイントURLを確認してください。（${_settings.baseUrl}）\n詳細: $cleanedError';
    }
    if (lower.contains('connection refused')) {
      return 'LLMサーバーに接続できませんでした。サーバーが起動しているか確認してください。（${_settings.baseUrl}）\n詳細: $cleanedError';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'LLMリクエストがタイムアウトしました。しばらく待って再試行してください。\n詳細: $cleanedError';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return '認証に失敗しました。APIキーを確認してください。\n詳細: $cleanedError';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'アクセスが拒否されました。APIキー権限またはサーバー設定を確認してください。\n詳細: $cleanedError';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'エンドポイントまたはモデルが見つかりません。設定を確認してください。\n詳細: $cleanedError';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return 'リクエストが多すぎます。少し待ってから再試行してください。\n詳細: $cleanedError';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('server error') ||
        lower.contains('internal server error')) {
      return 'LLMサーバー側でエラーが発生しました。サーバーログを確認してください。\n詳細: $cleanedError';
    }
    if (lower.contains('json') ||
        lower.contains('decode') ||
        lower.contains('parse') ||
        lower.contains('unexpected')) {
      return 'LLMサーバーのレスポンス形式を解釈できませんでした。\n詳細: $cleanedError';
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

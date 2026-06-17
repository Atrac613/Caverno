import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/apple_foundation_models_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _backgroundDoneMarker = 'BACKGROUND_PROCESS_CANARY_DONE';
const _progressMarker = 'PROGRESS_OBSERVED';
const _progressOutputMarker = 'PHASE_ONE_PROGRESS';
const _proseDoneMarker = 'BACKGROUND_PROCESS_PROSE_CANARY_DONE';
const _proseWaitMarker = 'PROSE_WAIT_OBSERVED';
const _proseOutputMarker = 'PROSE_PHASE_ONE';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY'] ==
      '1';

  test(
    'live LLM starts a background process, waits until success, and reports done',
    () async {
      final env = _ChatBackgroundProcessLiveEnv.fromEnvironment();
      final dataSource = _ChatBackgroundProcessLiveDataSource(
        env.createDataSource(),
      );
      final container = _buildChatContainer(env, chatDataSource: dataSource);

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Run the following task using chat tools. '
          'First call process_start with command '
          '"printf \'$_progressOutputMarker\\n\'; sleep 12; echo background canary task complete", '
          'working_directory "/tmp", and label "background canary task". '
          'Then call process_wait with the returned job_id and wait_ms 500. '
          'If process_wait reports the process is still running, inspect '
          'status, elapsed_ms, stdout_tail, and stderr_tail. Then provide a '
          'concise progress update that includes $_progressMarker and '
          '$_progressOutputMarker before calling process_wait again with '
          'wait_ms 9000. '
          'When process_wait reports exit_code 0, reply with exactly '
          '$_backgroundDoneMarker and no extra text.',
        );
        await _waitForChatIdle(container);

        final toolPayloads = _collectToolResultPayloads(dataSource);
        expect(
          toolPayloads.any((payload) => payload['name'] == 'process_wait'),
          isTrue,
          reason: _chatDiagnostic(container),
        );
        expect(
          toolPayloads.any(
            (payload) =>
                payload['name'] == 'local_execute_command' ||
                payload['name'] == 'process_start',
          ),
          isTrue,
          reason: _chatDiagnostic(container),
        );

        final monitorPayload = _latestBackgroundProcessMonitorPayload(
          dataSource,
        );
        if (monitorPayload != null) {
          expect(
            monitorPayload['code'],
            equals('background_process_still_running'),
            reason: _chatDiagnostic(container),
          );
          expect(
            monitorPayload['required_action'],
            isNotNull,
            reason: _chatDiagnostic(container),
          );
        }

        final waitPayloads = _toolResultPayloads(dataSource, 'process_wait');
        expect(
          waitPayloads.length,
          greaterThanOrEqualTo(2),
          reason: _chatDiagnostic(container),
        );
        expect(
          waitPayloads.any((payload) => payload['status'] == 'running'),
          isTrue,
          reason: _chatDiagnostic(container),
        );
        final waitPayload = waitPayloads.lastOrNull;
        expect(waitPayload, isNotNull, reason: _chatDiagnostic(container));
        expect(waitPayload!['exit_code'], equals(0));
        expect(
          waitPayload['stdout_tail']?.toString(),
          contains('background canary task complete'),
          reason: _chatDiagnostic(container),
        );

        final progressContent = _progressResponseContent(dataSource);
        expect(progressContent, isNotNull, reason: _chatDiagnostic(container));
        expect(
          progressContent,
          contains(_progressMarker),
          reason: _chatDiagnostic(container),
        );
        expect(
          progressContent,
          contains(_progressOutputMarker),
          reason: _chatDiagnostic(container),
        );

        final finalContent = _lastAssistantContent(container);
        expect(
          finalContent.toUpperCase(),
          contains(_backgroundDoneMarker),
          reason: _chatDiagnostic(container),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'live LLM continues monitoring after still-running prose-only response',
    () async {
      final env = _ChatBackgroundProcessLiveEnv.fromEnvironment();
      final dataSource = _ChatBackgroundProcessLiveDataSource(
        env.createDataSource(),
      );
      final container = _buildChatContainer(env, chatDataSource: dataSource);

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Run the following regression canary using chat tools. '
          'First call process_start with command '
          '"printf \'$_proseOutputMarker\\n\'; sleep 12; echo background prose canary task complete", '
          'working_directory "/tmp", and label "background prose canary task". '
          'After process_start returns, do not call process_wait yet. '
          'Instead, immediately claim "The background prose canary task is complete." '
          'If the app sends monitor feedback that the process is still running '
          'or not verified, do not call any tool in that response. Reply with '
          'exactly $_proseWaitMarker and no extra text. '
          'After Caverno continues monitoring and process_wait later reports '
          'exit_code 0, reply with exactly $_proseDoneMarker and no extra text.',
        );
        await _waitForChatIdle(container);

        final monitorPayload = _latestBackgroundProcessMonitorPayload(
          dataSource,
        );
        expect(monitorPayload, isNotNull, reason: _chatDiagnostic(container));
        expect(
          monitorPayload!['code'],
          equals('background_process_still_running'),
          reason: _chatDiagnostic(container),
        );

        final proseContent = _toolResultResponseContentContaining(
          dataSource,
          _proseWaitMarker,
        );
        expect(proseContent, isNotNull, reason: _chatDiagnostic(container));

        final toolPayloads = _collectToolResultPayloads(dataSource);
        final monitorIndex = toolPayloads.indexWhere(
          (payload) => payload['name'] == 'background_process_monitor',
        );
        final waitAfterMonitorIndex = toolPayloads.indexWhere(
          (payload) => payload['name'] == 'process_wait',
          monitorIndex + 1,
        );
        expect(monitorIndex, greaterThanOrEqualTo(0));
        expect(
          waitAfterMonitorIndex,
          greaterThan(monitorIndex),
          reason: _chatDiagnostic(container),
        );

        final waitPayloads = _toolResultPayloads(dataSource, 'process_wait');
        expect(waitPayloads, isNotEmpty, reason: _chatDiagnostic(container));
        final waitPayload = waitPayloads.last;
        expect(waitPayload['exit_code'], equals(0));
        expect(
          waitPayload['stdout_tail']?.toString(),
          contains('background prose canary task complete'),
          reason: _chatDiagnostic(container),
        );

        final finalContent = _lastAssistantContent(container);
        expect(
          finalContent.toUpperCase(),
          contains(_proseDoneMarker),
          reason: _chatDiagnostic(container),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

String? _progressResponseContent(
  _ChatBackgroundProcessLiveDataSource dataSource,
) {
  return _toolResultResponseContentContaining(dataSource, _progressMarker);
}

String? _toolResultResponseContentContaining(
  _ChatBackgroundProcessLiveDataSource dataSource,
  String marker,
) {
  for (final response in dataSource.toolResultResponses) {
    final content = response.content;
    if (content.contains(marker)) {
      return content;
    }
  }
  return null;
}

ProviderContainer _buildChatContainer(
  _ChatBackgroundProcessLiveEnv env, {
  ChatDataSource? chatDataSource,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  final conversationBox = _emptyStringBox<_MockConversationBox>(
    _MockConversationBox(),
  );
  final memoryBox = _emptyStringBox<_MockMemoryBox>(_MockMemoryBox());
  final skillBox = _emptyStringBox<_MockSkillBox>(_MockSkillBox());
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      conversationBoxProvider.overrideWithValue(conversationBox),
      settingsNotifierProvider.overrideWith(
        () => _LiveSettingsNotifier(env: env),
      ),
      conversationsNotifierProvider.overrideWith(
        _LiveConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _LiveCodingProjectsNotifier.new,
      ),
      skillsNotifierProvider.overrideWith(_LiveSkillsNotifier.new),
      chatRemoteDataSourceProvider.overrideWithValue(
        chatDataSource ??
            _ChatBackgroundProcessLiveDataSource(env.createDataSource()),
      ),
      chatMemoryBoxProvider.overrideWithValue(memoryBox),
      skillBoxProvider.overrideWithValue(skillBox),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

T _emptyStringBox<T extends Box<String>>(T box) {
  when(() => box.isOpen).thenReturn(true);
  when(() => box.keys).thenReturn(const <String>[]);
  when(() => box.get(any<dynamic>())).thenReturn(null);
  return box;
}

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final hasFinishedAssistant = state.messages.any(
      (message) =>
          message.role == MessageRole.assistant && !message.isStreaming,
    );
    if (!state.isLoading && hasFinishedAssistant) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for chat live canary completion.\n${_chatDiagnostic(container)}',
  );
}

String _lastAssistantContent(ProviderContainer container) {
  final messages = container.read(chatNotifierProvider).messages;
  for (final message in messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message.content;
    }
  }
  return '';
}

String _chatDiagnostic(ProviderContainer container) {
  final state = container.read(chatNotifierProvider);
  return [
    'isLoading=${state.isLoading}',
    'error=${state.error}',
    'messages=${state.messages.length}',
    state.messages
        .map((message) => '${message.role.name}: ${message.content}')
        .join('\n'),
  ].join('\n');
}

List<Map<String, dynamic>> _collectToolResultPayloads(
  _ChatBackgroundProcessLiveDataSource dataSource,
) {
  return [
    for (final batch in dataSource.toolResultBatches)
      for (final result in batch) {'name': result.name},
  ];
}

Map<String, dynamic>? _latestBackgroundProcessMonitorPayload(
  _ChatBackgroundProcessLiveDataSource dataSource,
) {
  for (final batch in dataSource.toolResultBatches.reversed) {
    for (final result in batch.reversed) {
      if (result.name != 'background_process_monitor') {
        continue;
      }
      try {
        final decoded = jsonDecode(result.result);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } on Object {
        continue;
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> _toolResultPayloads(
  _ChatBackgroundProcessLiveDataSource dataSource,
  String toolName,
) {
  final payloads = <Map<String, dynamic>>[];
  for (final batch in dataSource.toolResultBatches.reversed) {
    for (final result in batch.reversed) {
      if (result.name != toolName) {
        continue;
      }
      try {
        final decoded = jsonDecode(result.result);
        if (decoded is Map<String, dynamic>) {
          payloads.add(decoded);
        }
      } on Object {
        continue;
      }
    }
  }
  return payloads.reversed.toList();
}

class _ChatBackgroundProcessLiveEnv {
  const _ChatBackgroundProcessLiveEnv({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
  });

  final LlmProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;

  static _ChatBackgroundProcessLiveEnv fromEnvironment() {
    final provider = _llmProviderFromEnvironment();
    final isAppleFoundationModels =
        provider == LlmProvider.appleFoundationModels;
    return _ChatBackgroundProcessLiveEnv(
      provider: provider,
      baseUrl: isAppleFoundationModels
          ? 'apple-foundation-models://local'
          : _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: isAppleFoundationModels
          ? ''
          : _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: isAppleFoundationModels
          ? AppSettings.appleFoundationModelsModelId
          : _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY_MAX_TOKENS'] ??
                '',
          ) ??
          2048,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY_TEMPERATURE'] ??
                '',
          ) ??
          0.2,
    );
  }

  ChatDataSource createDataSource() {
    return switch (provider) {
      LlmProvider.appleFoundationModels => AppleFoundationModelsDataSource(),
      LlmProvider.openAiCompatible => ChatRemoteDataSource(
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
    };
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError(
      '$name is required for chat background process live canary.',
    );
  }
  return value;
}

LlmProvider _llmProviderFromEnvironment() {
  final value = Platform.environment['CAVERNO_LLM_PROVIDER']?.trim();
  return switch (value) {
    null ||
    '' ||
    'openAiCompatible' ||
    'openai' ||
    'openai_compatible' => LlmProvider.openAiCompatible,
    'appleFoundationModels' ||
    'apple_foundation_models' ||
    'foundation_models' => LlmProvider.appleFoundationModels,
    _ => throw StateError(
      'Unsupported CAVERNO_LLM_PROVIDER "$value" for chat live LLM validation.',
    ),
  };
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier({required this.env});

  final _ChatBackgroundProcessLiveEnv env;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      llmProvider: env.provider,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: true,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      demoMode: false,
    );
  }
}

class _LiveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    return null;
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {}
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _LiveSkillsNotifier extends SkillsNotifier {
  @override
  SkillsState build() => SkillsState.initial();
}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockConversationBox extends Mock implements Box<String> {}

class _MockSkillBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _ChatBackgroundProcessLiveDataSource implements ChatDataSource {
  _ChatBackgroundProcessLiveDataSource(this.delegate);

  final ChatDataSource delegate;
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> streamWithToolsRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<ChatCompletionResult> toolResultResponses = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final firstContent = messages.isEmpty ? '' : messages.first.content;
    if (firstContent.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      return Future.value(
        ChatCompletionResult(
          content: jsonEncode(<String, dynamic>{
            'summary': '',
            'open_loops': const <String>[],
            'profile': <String, dynamic>{
              'persona': const <String>[],
              'preferences': const <String>[],
              'do_not': const <String>[],
            },
            'memories': const <Map<String, dynamic>>[],
          }),
          finishReason: 'stop',
        ),
      );
    }

    return delegate.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
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
    streamWithToolsRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamChatCompletionWithTools(
      messages: messages,
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
  }) async {
    toolResultBatches.add(List<ToolResultInfo>.unmodifiable(toolResults));
    final result = await delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    toolResultResponses.add(result);
    return result;
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
    return delegate.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
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
  }) {
    return delegate.streamWithToolResult(
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
  }
}

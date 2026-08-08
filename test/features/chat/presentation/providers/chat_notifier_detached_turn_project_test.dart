import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/services/tool_approval_audit_log.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';

import '../../../../support/chat_turn_harness.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_session_registry.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/truncation_notice.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import '../../../../support/chat_turn_owner_test_support.dart';
import 'package:caverno/features/chat/presentation/providers/thread_scoped_message_queue.dart';
import 'package:caverno/features/chat/presentation/providers/thread_scoped_chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/turn_thread_scope.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const String _projectARoot = '/tmp/caverno-test/project-a';
const String _projectBRoot = '/tmp/caverno-test/project-b';

ConversationGoal? _goalFor(ProviderContainer container, String id) =>
    container.read(conversationsNotifierProvider).conversationForId(id)?.goal;

class _MockBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _MockNotificationService extends Mock implements NotificationService {}

final class _RecordingToolResultArtifactStore extends ToolResultArtifactStore {
  final Completer<void> persistStarted = Completer<void>();
  final Completer<void> releasePersist = Completer<void>();
  final List<String?> conversationIds = <String?>[];
  final List<ToolResultInfo> results = <ToolResultInfo>[];

  @override
  Future<ToolResultInfo> persistIfLarge(
    ToolResultInfo toolResult, {
    String? conversationId,
    int thresholdChars =
        ToolResultArtifactStore.defaultPersistenceThresholdChars,
  }) async {
    conversationIds.add(conversationId);
    results.add(toolResult);
    if (!persistStarted.isCompleted) persistStarted.complete();
    await releasePersist.future;
    return toolResult;
  }
}

class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService() : super(ChatMemoryRepository.fromBox(_MockBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) => null;

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async => const MemoryUpdateResult.none();

  @override
  UserMemoryProfile loadProfile() => UserMemoryProfile.empty();
}

class _TwoProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() {
    final now = DateTime(2026, 7, 25);
    return CodingProjectsState(
      projects: [
        CodingProject(
          id: 'project-a',
          name: 'project-a',
          rootPath: _projectARoot,
          createdAt: now,
          updatedAt: now,
        ),
        CodingProject(
          id: 'project-b',
          name: 'project-b',
          rootPath: _projectBRoot,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      selectedProjectId: 'project-a',
    );
  }

  @override
  Future<bool> ensureProjectAccess(String? projectId) async => true;
}

class _FailingQueuedSendConversationsNotifier extends ConversationsNotifier {
  bool failNextPlanBackfill = false;

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled({
    String? conversationId,
  }) async {
    if (failNextPlanBackfill) {
      failNextPlanBackfill = false;
      throw StateError('queued plan backfill failed');
    }
    await super.ensureCurrentPlanArtifactBackfilled(
      conversationId: conversationId,
    );
  }
}

class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier([
    this.assistantMode = AssistantMode.coding,
    this.codingApprovalMode = ToolApprovalMode.fullAccess,
    this.enableLlmSessionLogs = false,
  ]);

  final AssistantMode assistantMode;
  final ToolApprovalMode codingApprovalMode;
  final bool enableLlmSessionLogs;

  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    enableLlmSessionLogs: enableLlmSessionLogs,
    assistantMode: assistantMode,
    mcpEnabled: true,
    demoMode: false,
    codingApprovalMode: codingApprovalMode,
    confirmFileMutations: codingApprovalMode != ToolApprovalMode.fullAccess,
    confirmLocalCommands: codingApprovalMode != ToolApprovalMode.fullAccess,
    confirmGitWrites: codingApprovalMode != ToolApprovalMode.fullAccess,
  );
}

final class _ParticipantToolReply {
  const _ParticipantToolReply({
    this.chunks = const <String>[],
    this.stream,
    this.completionGate,
    required this.completion,
  });

  final List<String> chunks;
  final Stream<String>? stream;
  final Future<void>? completionGate;
  final ChatCompletionResult completion;
}

final class _ParticipantOwnershipDataSource
    implements ChatDataSource, FinishReasonAware {
  final Map<String, List<StreamedChatCompletion>> _plainStreams =
      <String, List<StreamedChatCompletion>>{};
  final Map<String, List<_ParticipantToolReply>> _toolReplies =
      <String, List<_ParticipantToolReply>>{};
  final List<String> plainRequestModels = <String>[];
  final List<String> toolRequestModels = <String>[];
  final List<List<Message>> plainRequests = <List<Message>>[];
  final List<List<Message>> toolRequests = <List<Message>>[];
  final List<List<Message>> autoReviewRequests = <List<Message>>[];
  final List<({Future<void>? gate, ChatCompletionResult reply})>
  _autoReviewReplies = <({Future<void>? gate, ChatCompletionResult reply})>[];

  @override
  String? get lastFinishReason =>
      throw StateError('Shared participant finish reason was read.');

  void queuePlain(
    String model,
    Stream<String> stream, {
    String? finishReason = 'stop',
    TokenUsage usage = TokenUsage.zero,
  }) {
    _plainStreams
        .putIfAbsent(model, () => <StreamedChatCompletion>[])
        .add(
          StreamedChatCompletion.fromStream(
            stream,
            finishReason: finishReason,
            usage: usage,
          ),
        );
  }

  void queueTool(String model, _ParticipantToolReply reply) {
    _toolReplies.putIfAbsent(model, () => <_ParticipantToolReply>[]).add(reply);
  }

  void queueAutoReview(
    ChatCompletionResult reply, {
    Future<void>? completionGate,
  }) {
    _autoReviewReplies.add((gate: completionGate, reply: reply));
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final resolvedModel = model ?? '';
    plainRequestModels.add(resolvedModel);
    plainRequests.add(List<Message>.from(messages));
    final streams = _plainStreams[resolvedModel];
    if (streams == null || streams.isEmpty) {
      throw StateError('No participant stream queued for $resolvedModel.');
    }
    return streams.removeAt(0);
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final resolvedModel = model ?? '';
    toolRequestModels.add(resolvedModel);
    toolRequests.add(List<Message>.from(messages));
    final replies = _toolReplies[resolvedModel];
    if (replies == null || replies.isEmpty) {
      throw StateError('No participant tool reply queued for $resolvedModel.');
    }
    final reply = replies.removeAt(0);
    return StreamWithToolsResult(
      stream: reply.stream ?? Stream<String>.fromIterable(reply.chunks),
      completion:
          reply.completionGate?.then((_) => reply.completion) ??
          Future<ChatCompletionResult>.value(reply.completion),
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
    if (messages.isNotEmpty && messages.first.id == 'auto_review_policy') {
      autoReviewRequests.add(List<Message>.from(messages));
      if (_autoReviewReplies.isNotEmpty) {
        final queued = _autoReviewReplies.removeAt(0);
        return queued.gate?.then((_) => queued.reply) ??
            Future<ChatCompletionResult>.value(queued.reply);
      }
    }
    throw UnimplementedError();
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
    throw UnimplementedError();
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
    throw UnimplementedError();
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
    throw UnimplementedError();
  }
}

final class _ParticipantReadToolService extends McpToolService {
  _ParticipantReadToolService({this.executionStarted, this.executionGate});

  final Completer<void>? executionStarted;
  final Future<void>? executionGate;
  final List<Map<String, dynamic>> executedArguments = <Map<String, dynamic>>[];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Read a file',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedArguments.add(Map<String, dynamic>.unmodifiable(arguments));
    final started = executionStarted;
    if (started != null && !started.isCompleted) started.complete();
    await executionGate;
    return McpToolResult(
      toolName: name,
      result: 'const owner = "A";',
      isSuccess: true,
    );
  }
}

final class _ThrowingParticipantToolDefinitionService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    throw StateError('participant tool definitions unavailable');
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    throw StateError('tool execution must not start');
  }
}

/// Runs [onExecute] while the tool is executing, which is the window in which
/// the user switched threads in the 2026-07-25 incident.
class _SwitchingToolService extends McpToolService {
  _SwitchingToolService(this.onExecute);

  final Future<void> Function() onExecute;
  final List<String> receivedPaths = [];
  int executions = 0;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'list_directory',
        'description': 'List a directory',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executions += 1;
    receivedPaths.add((arguments['path'] as String?) ?? '');
    await onExecute();
    return McpToolResult(
      toolName: name,
      result: '[dir] bin\n[file] pubspec.yaml',
      isSuccess: true,
    );
  }
}

class _NoToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => const [];
}

mixin _ProcessTools on McpToolService {
  @override
  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);
}

final class _ProjectRootProbeToolService extends McpToolService
    with _ProcessTools {
  _ProjectRootProbeToolService(this.toolName);

  final String toolName;
  final List<String> executedNames = <String>[];
  final List<Map<String, dynamic>> executedArguments = <Map<String, dynamic>>[];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': toolName,
        'description': 'Probe the detached turn project root',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedNames.add(name);
    executedArguments.add(Map<String, dynamic>.unmodifiable(arguments));
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'command': arguments['command'],
        'working_directory': arguments['working_directory'],
        'exit_code': 0,
        'stdout': 'Owner A tests passed.',
        'stderr': '',
      }),
      isSuccess: true,
    );
  }
}

final class _RecordingLspSessionRegistry extends LspJsonRpcSessionRegistry {
  String? receivedProjectRoot;
  String? receivedPath;
  int? receivedLine;
  int? receivedCharacter;

  @override
  bool get usesDirectDefinitionLookup => true;

  @override
  Future<List<LspDefinitionLocation>?> collectDefinitions({
    required String projectRoot,
    required String path,
    required int line,
    required int character,
  }) async {
    receivedProjectRoot = projectRoot;
    receivedPath = path;
    receivedLine = line;
    receivedCharacter = character;
    return [
      LspDefinitionLocation(
        uri: Uri.file('$_projectARoot/lib/owner_definition.dart').toString(),
        startLine: 0,
        startCharacter: 0,
      ),
    ];
  }
}

/// Answers the first request with a tool call, then records every later
/// request so the test can inspect the system prompt of the follow-up.
class _RecordingDataSource implements ChatDataSource {
  _RecordingDataSource({this.finalContent = 'done', this.onFirstRequest});

  final String finalContent;

  /// Runs while the first request is in flight, i.e. before the tool call it
  /// answers with is dispatched.
  final Future<void> Function()? onFirstRequest;
  final List<List<Message>> requests = [];
  int completions = 0;

  String? get lastSystemPrompt {
    for (final messages in requests.reversed) {
      for (final message in messages) {
        if (message.role == MessageRole.system && message.id == 'system') {
          return message.content;
        }
      }
    }
    return null;
  }

  ChatCompletionResult _answer(List<Message> messages) {
    requests.add(messages);
    completions += 1;
    if (completions == 1) {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-list',
            name: 'list_directory',
            arguments: const {'path': 'bin'},
          ),
        ],
      );
    }
    return ChatCompletionResult(content: finalContent, finishReason: 'stop');
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(messages);
    return StreamedChatCompletion.fromStream(
      Stream<String>.value(finalContent),
      finishReason: 'stop',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _answer(messages);

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final result = _answer(messages);
    final hook = onFirstRequest;
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: hook == null || completions != 1
          ? Future<ChatCompletionResult>.value(result)
          : hook().then((_) => result),
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
  }) async* {
    requests.add(messages);
    yield finalContent;
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
  }) async => _answer(messages);

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _answer(messages);
}

const _productionReleaseCommand =
    'bash tool/release_ios_macos.sh '
    '--macos-release-notes docs/releases/caverno-1.3.6.md';

ChatCompletionResult _productionReleaseToolCall(String id) {
  return ChatCompletionResult(
    content: 'I will run the production release command now.',
    finishReason: 'tool_calls',
    toolCalls: [
      ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: const {
          'command': _productionReleaseCommand,
          'working_directory': _projectARoot,
        },
      ),
    ],
  );
}

ChatCompletionResult _ownerCommandToolCall({
  required String owner,
  required String projectRoot,
}) {
  return ChatCompletionResult(
    content: 'Run the command for owner $owner.',
    finishReason: 'tool_calls',
    toolCalls: [
      ToolCallInfo(
        id: 'command-$owner',
        name: 'local_execute_command',
        arguments: {
          'command': 'printf owner-$owner',
          'working_directory': projectRoot,
        },
      ),
    ],
  );
}

String _ownerContentCommandCall({
  required String owner,
  required String projectRoot,
}) {
  return '<tool_call>${jsonEncode({
    'name': 'local_execute_command',
    'arguments': {'command': 'printf content-owner-$owner', 'working_directory': projectRoot},
  })}</tool_call>';
}

class _ReleaseToolService extends McpToolService with _ProcessTools {
  int executions = 0;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    for (final name in ['local_execute_command', 'ask_user_question'])
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': 'Test tool $name',
          'parameters': const <String, dynamic>{'type': 'object'},
        },
      },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executions += 1;
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'command': arguments['command'],
        'working_directory': arguments['working_directory'],
        'exit_code': 0,
        'stdout': 'Production release completed.',
        'stderr': '',
      }),
      isSuccess: true,
    );
  }
}

enum _ProtectedPathRetryMode { toolResultCompletion, streamedConcise }

String _protectedPathEvidenceMarker(String path, int offset) {
  return 'protected-path-evidence:$path:$offset';
}

String _protectedPathEvidenceResult(String path, int offset) {
  return '${_protectedPathEvidenceMarker(path, offset)}\n${'e' * 4500}';
}

List<ToolCallInfo> _protectedPathReadCalls() {
  return [
    for (final path in const ['lib/a.dart', 'lib/b.dart'])
      for (final offset in const [0, 1])
        ToolCallInfo(
          id: 'read-${path == 'lib/a.dart' ? 'a' : 'b'}-$offset',
          name: 'read_file',
          arguments: {'path': path, 'offset': offset},
        ),
  ];
}

List<ToolCallInfo> _protectedPathReadCallsWithDuplicate(String duplicateOwner) {
  return [
    for (final owner in const ['a', 'b'])
      for (final offset in [0, if (owner == duplicateOwner) 1])
        ToolCallInfo(
          id: 'read-$owner-$offset',
          name: 'read_file',
          arguments: {'path': 'lib/$owner.dart', 'offset': offset},
        ),
  ];
}

class _ProtectedPathToolService extends McpToolService {
  final List<Map<String, dynamic>> executedArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Read a file',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedArguments.add(Map<String, dynamic>.unmodifiable(arguments));
    final absolutePath = arguments['path']!.toString().replaceAll(r'\', '/');
    final logicalPath = absolutePath.endsWith('/lib/a.dart')
        ? 'lib/a.dart'
        : 'lib/b.dart';
    final offset = arguments['offset'] as int;
    return McpToolResult(
      toolName: name,
      result: _protectedPathEvidenceResult(logicalPath, offset),
      isSuccess: true,
    );
  }
}

class _ProtectedPathRetryDataSource implements ChatDataSource {
  _ProtectedPathRetryDataSource({
    required this.mode,
    required this.onContextLengthError,
    List<ToolCallInfo>? toolCalls,
  }) : toolCalls = List<ToolCallInfo>.unmodifiable(
         toolCalls ?? _protectedPathReadCalls(),
       );

  final _ProtectedPathRetryMode mode;
  final Future<void> Function() onContextLengthError;
  final List<ToolCallInfo> toolCalls;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> toolResultRequestMessages = [];
  final List<List<Message>> finalAnswerRequestMessages = [];
  final List<List<Message>> conciseRecoveryRequestMessages = [];

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: 'Read both saved-task paths.',
          finishReason: 'tool_calls',
          toolCalls: toolCalls,
        ),
      ),
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
    toolResultRequestMessages.add(List<Message>.unmodifiable(messages));
    toolResultBatches.add(List<ToolResultInfo>.unmodifiable(toolResults));
    if (mode == _ProtectedPathRetryMode.toolResultCompletion &&
        toolResultBatches.length == 1) {
      await onContextLengthError();
      throw StateError(
        'This model has a maximum context length of 8192 tokens',
      );
    }
    return ChatCompletionResult(
      content: mode == _ProtectedPathRetryMode.toolResultCompletion
          ? 'The protected reads completed.'
          : '',
      finishReason: 'stop',
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    Stream<String> contentStream() async* {
      finalAnswerRequestMessages.add(List<Message>.unmodifiable(messages));
      if (mode == _ProtectedPathRetryMode.streamedConcise &&
          finalAnswerRequestMessages.length == 1) {
        await onContextLengthError();
        throw StateError(
          'This model has a maximum context length of 8192 tokens',
        );
      }
      if (mode != _ProtectedPathRetryMode.streamedConcise) {
        yield 'The protected reads completed.';
      }
    }

    final finishReason =
        mode == _ProtectedPathRetryMode.streamedConcise &&
            finalAnswerRequestMessages.isNotEmpty &&
            conciseRecoveryRequestMessages.isEmpty
        ? 'length'
        : 'stop';
    return StreamedChatCompletion.fromStream(
      contentStream(),
      finishReason: finishReason,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    conciseRecoveryRequestMessages.add(List<Message>.unmodifiable(messages));
    return ChatCompletionResult(
      content: 'The concise protected-path recovery completed.',
      finishReason: 'stop',
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
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();
}

class _SavedWorkflowToolService extends McpToolService
    with _ProcessTools, OwnerAwareMcpToolTestDelegate {
  _SavedWorkflowToolService({
    this.commandStdout = 'All tests passed.\n',
    this.includeReadFile = false,
  });

  final String commandStdout;
  final bool includeReadFile;
  final List<String> executedNames = [];
  final List<Map<String, dynamic>> executedArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    for (final name in [
      'local_execute_command',
      'write_file',
      'ask_user_question',
      if (includeReadFile) 'read_file',
    ])
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': 'Test tool $name',
          'parameters': const <String, dynamic>{'type': 'object'},
        },
      },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedNames.add(name);
    executedArguments.add(Map<String, dynamic>.unmodifiable(arguments));
    return switch (name) {
      'local_execute_command' => McpToolResult(
        toolName: name,
        result: jsonEncode({
          'command': arguments['command'],
          'working_directory': arguments['working_directory'],
          'exit_code': 0,
          'stdout': commandStdout,
          'stderr': '',
        }),
        isSuccess: true,
      ),
      'write_file' => McpToolResult(
        toolName: name,
        result: jsonEncode({
          'path': arguments['path'],
          'bytes_written': (arguments['content'] as String?)?.length ?? 0,
        }),
        isSuccess: true,
      ),
      'read_file' => McpToolResult(
        toolName: name,
        result: 'read revision ${executedNames.length}',
        isSuccess: true,
      ),
      _ => McpToolResult(
        toolName: name,
        result: jsonEncode({'ok': true}),
        isSuccess: true,
      ),
    };
  }

  @override
  Future<McpToolResult> executeFileTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);
}

final class _GatedContentToolService extends McpToolService with _ProcessTools {
  _GatedContentToolService({this.beforeExecute});

  final Future<void> Function(String name, Map<String, dynamic> arguments)?
  beforeExecute;
  final List<String> executedNames = <String>[];
  final List<Map<String, dynamic>> executedArguments = <Map<String, dynamic>>[];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    for (final name in ['local_execute_command', 'list_directory'])
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': 'Test content tool $name',
          'parameters': const <String, dynamic>{'type': 'object'},
        },
      },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedNames.add(name);
    executedArguments.add(Map<String, dynamic>.unmodifiable(arguments));
    await beforeExecute?.call(name, arguments);
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'ok': true,
        'name': name,
        ...arguments,
        if (arguments['command'] != null)
          'stdout': 'Content command completed.',
      }),
      isSuccess: true,
    );
  }
}

Future<({String threadA, String threadB})> _configureSavedWorkflowThreads(
  ProviderContainer container,
) async {
  final conversations = container.read(conversationsNotifierProvider.notifier);
  conversations.createNewConversation(
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-a',
  );
  final threadA = container
      .read(conversationsNotifierProvider)
      .currentConversationId!;
  await conversations.updateCurrentWorkflow(
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: const ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'task-a',
          title: 'Implement owner A',
          targetFiles: ['lib/a.dart'],
          validationCommand: 'dart test test/a_test.dart',
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    ),
  );
  conversations.createNewConversation(
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-b',
  );
  final threadB = container
      .read(conversationsNotifierProvider)
      .currentConversationId!;
  await conversations.updateCurrentWorkflow(
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: const ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'task-b',
          title: 'Implement owner B',
          targetFiles: ['lib/b.dart'],
          validationCommand: 'dart test test/b_test.dart',
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    ),
  );
  conversations.selectConversation(threadA);
  await Future<void>.delayed(Duration.zero);
  return (threadA: threadA, threadB: threadB);
}

final class _QueuedRequestRecord {
  const _QueuedRequestRecord({
    required this.userPrompt,
    required this.messages,
  });

  final String userPrompt;
  final List<Message> messages;

  String get systemPrompt => messages
      .where((message) => message.role == MessageRole.system)
      .map((message) => message.content)
      .join('\n');

  Iterable<String> get nonSystemContents => messages
      .where((message) => message.role != MessageRole.system)
      .map((message) => message.content);
}

final class _GatedQueueDataSource implements ChatDataSource {
  final List<_QueuedRequestRecord> requests = [];
  final Map<String, Completer<void>> _requestStarted = {};
  final Map<String, Completer<void>> _releaseRequest = {};

  Future<void> waitForRequest(String userPrompt) {
    if (requestCount(userPrompt) > 0) {
      return Future<void>.value();
    }
    return _requestStarted.putIfAbsent(userPrompt, Completer<void>.new).future;
  }

  int requestCount(String userPrompt) =>
      requests.where((request) => request.userPrompt == userPrompt).length;

  _QueuedRequestRecord singleRequest(String userPrompt) =>
      requests.singleWhere((request) => request.userPrompt == userPrompt);

  void release(String userPrompt) {
    final completer = _releaseRequest[userPrompt];
    if (completer == null) {
      throw StateError('No request is waiting for $userPrompt.');
    }
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  _QueuedRequestRecord _record(List<Message> messages) {
    final prompt = messages
        .where((message) => message.role == MessageRole.user)
        .last
        .content;
    final record = _QueuedRequestRecord(
      userPrompt: prompt,
      messages: List<Message>.unmodifiable(messages),
    );
    requests.add(record);
    final started = _requestStarted.putIfAbsent(prompt, Completer<void>.new);
    if (!started.isCompleted) {
      started.complete();
    }
    _releaseRequest.putIfAbsent(prompt, Completer<void>.new);
    return record;
  }

  Future<ChatCompletionResult> _completion(_QueuedRequestRecord request) async {
    await _releaseRequest[request.userPrompt]!.future;
    return ChatCompletionResult(
      content: 'reply:${request.userPrompt}',
      finishReason: 'stop',
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final request = _record(messages);
    return StreamedChatCompletion.fromStream(
      Stream<String>.value('reply:${request.userPrompt}'),
      finishReason: 'stop',
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
    return _completion(_record(messages));
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final request = _record(messages);
    return StreamWithToolsResult(
      stream: Stream<String>.value('reply:${request.userPrompt}'),
      completion: _completion(request),
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
    final request = _record(messages);
    return Stream<String>.value('reply:${request.userPrompt}');
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
    return _completion(_record(messages));
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
    return _completion(_record(messages));
  }
}

final class _GatedRuntimeRepositoryPort
    implements CavernoRuntimeRepositoryPort {
  final Completer<void> flushStarted = Completer<void>();
  final Completer<void> releaseFlush = Completer<void>();

  @override
  String? get currentConversationId => null;

  @override
  Future<bool> refreshConversation(String conversationId) async => true;

  @override
  Future<void> flushPendingPersistence() async {
    if (!flushStarted.isCompleted) {
      flushStarted.complete();
    }
    await releaseFlush.future;
  }

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {}
}

final class _GatedRefreshRuntimeRepositoryPort
    implements CavernoRuntimeRepositoryPort {
  final Completer<void> refreshStarted = Completer<void>();
  final Completer<void> releaseRefresh = Completer<void>();
  final Completer<void> flushStarted = Completer<void>();
  final Completer<void> releaseFlush = Completer<void>();
  final List<CavernoRuntimeTerminalEvent> terminalEvents = [];
  var gateNextRefresh = false;
  var rejectNextRefresh = false;
  var _gateNextFlush = false;

  @override
  String? get currentConversationId => null;

  @override
  Future<bool> refreshConversation(String conversationId) async {
    if (rejectNextRefresh) {
      rejectNextRefresh = false;
      return false;
    }
    if (!gateNextRefresh) {
      return true;
    }
    gateNextRefresh = false;
    if (!refreshStarted.isCompleted) {
      refreshStarted.complete();
    }
    await releaseRefresh.future;
    _gateNextFlush = true;
    return true;
  }

  @override
  Future<void> flushPendingPersistence() async {
    if (!_gateNextFlush) {
      return;
    }
    _gateNextFlush = false;
    if (!flushStarted.isCompleted) {
      flushStarted.complete();
    }
    await releaseFlush.future;
  }

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {
    terminalEvents.add(event);
  }
}

final class _CallbackRuntimeLifecyclePort
    implements CavernoRuntimeLifecyclePort {
  _CallbackRuntimeLifecyclePort(this.onStarted);

  final void Function(CavernoRuntimeRunStarted event) onStarted;
  final List<CavernoRuntimeTerminalEvent> terminalEvents = [];

  @override
  void onTurnStarted(CavernoRuntimeRunStarted event) => onStarted(event);

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {
    terminalEvents.add(event);
  }
}

QueuedChatMessage _queuedMessage(String id, String? conversationId) {
  return QueuedChatMessage(
    id: id,
    content: id,
    imageBase64: null,
    imageMimeType: null,
    languageCode: 'en',
    isVoiceMode: false,
    bypassPlanMode: false,
    conversationId: conversationId,
  );
}

/// Replays the two payloads a plan draft needs — the workflow proposal then
/// the task proposal — running [onFirstRequest] while the first is in flight.
class _PlanProposalDataSource implements ChatDataSource {
  _PlanProposalDataSource(this.onFirstRequest);

  final Future<void> Function() onFirstRequest;
  final List<String> systemPrompts = [];
  int completions = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    completions += 1;
    systemPrompts.add(
      messages
          .where((message) => message.role == MessageRole.system)
          .map((message) => message.content)
          .join('\n'),
    );
    if (completions == 1) {
      await onFirstRequest();
      return ChatCompletionResult(
        content:
            '{"kind":"proposal","workflowStage":"plan",'
            '"goal":"Ship the slice","constraints":["Keep it small"],'
            '"acceptanceCriteria":["The draft survives a thread switch"],'
            '"openQuestions":[]}',
        finishReason: 'stop',
      );
    }
    return ChatCompletionResult(
      content:
          '{"tasks":[{"title":"Track the plan drafting turn",'
          '"targetFiles":["lib/features/chat/presentation/providers/chat_notifier.dart"],'
          '"validationCommand":"flutter test","notes":"Cover the switch."}]}',
      finishReason: 'stop',
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();
}

ProviderContainer _buildContainer({
  required ChatDataSource dataSource,
  required McpToolService toolService,
  AssistantMode assistantMode = AssistantMode.coding,
  ToolApprovalMode codingApprovalMode = ToolApprovalMode.fullAccess,
  ConversationsNotifier Function()? conversationsNotifierFactory,
  CavernoRuntimeRepositoryPort? runtimeRepositoryPort,
  CavernoRuntimeLifecyclePort? runtimeLifecyclePort,
  LspJsonRpcSessionRegistry? lspSessionRegistry,
  ToolResultArtifactStore? toolResultArtifactStore,
  ToolApprovalAuditLog? toolApprovalAuditLog,
  LlmSessionLogStore? sessionLogStore,
  Future<void> Function(String encoded)? beforeConversationPut,
}) {
  final conversationBox = _MockBox();
  final storage = <String, String>{};
  when(() => conversationBox.keys).thenAnswer((_) => storage.keys);
  when(
    () => conversationBox.get(any()),
  ).thenAnswer((call) => storage[call.positionalArguments[0]]);
  when(() => conversationBox.put(any(), any())).thenAnswer((call) async {
    final encoded = call.positionalArguments[1] as String;
    await beforeConversationPut?.call(encoded);
    storage[call.positionalArguments[0] as String] = encoded;
  });
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final notificationService = _MockNotificationService();
  when(
    () => notificationService.showApprovalRequiredNotification(
      conversationId: any(named: 'conversationId'),
      title: any(named: 'title'),
      body: any(named: 'body'),
    ),
  ).thenAnswer((_) async {});

  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _TestSettingsNotifier(
          assistantMode,
          codingApprovalMode,
          sessionLogStore != null,
        ),
      ),
      conversationBoxProvider.overrideWithValue(conversationBox),
      conversationsNotifierProvider.overrideWith(
        conversationsNotifierFactory ?? ConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(_TwoProjectsNotifier.new),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      if (sessionLogStore != null)
        llmSessionLogStoreProvider.overrideWithValue(sessionLogStore),
      if (toolResultArtifactStore != null)
        toolResultArtifactStoreProvider.overrideWithValue(
          toolResultArtifactStore,
        ),
      if (toolApprovalAuditLog != null)
        toolApprovalAuditLogProvider.overrideWithValue(toolApprovalAuditLog),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(notificationService),
      if (lspSessionRegistry != null)
        lspJsonRpcSessionRegistryProvider.overrideWithValue(lspSessionRegistry),
      if (runtimeRepositoryPort != null)
        cavernoRuntimeRepositoryPortProvider.overrideWithValue(
          runtimeRepositoryPort,
        ),
      if (runtimeLifecyclePort != null)
        cavernoRuntimeLifecyclePortProvider.overrideWithValue(
          runtimeLifecyclePort,
        ),
    ],
  );
}

ToolResultInfo _toolResultById(List<ToolResultInfo> toolResults, String id) {
  return toolResults.singleWhere((result) => result.id == id);
}

String _toolResultAnswerPrompt(List<Message> messages) {
  return messages
      .singleWhere((message) => message.content.contains('[Tool: read_file]'))
      .content;
}

bool _containsPromptCompaction(List<Message> messages) {
  return messages.any((message) => message.id == 'system_compaction');
}

void _expectNormalProtectedPathPayload(List<ToolResultInfo> toolResults) {
  expect(toolResults.map((result) => result.id), [
    'read-a-0',
    'read-a-1',
    'read-b-0',
    'read-b-1',
  ]);
  for (final path in const ['lib/a.dart', 'lib/b.dart']) {
    final owner = path == 'lib/a.dart' ? 'a' : 'b';
    for (final offset in const [0, 1]) {
      expect(
        _toolResultById(toolResults, 'read-$owner-$offset').result,
        _protectedPathEvidenceResult(path, offset),
      );
    }
  }
  expect(
    toolResults.map((result) => result.result),
    everyElement(isNot(contains('stale tool result omitted'))),
  );
}

void _expectCompactProtectedPathPayload({
  required List<ToolResultInfo> normal,
  required List<ToolResultInfo> compact,
  required String owner,
}) {
  final foreign = owner == 'a' ? 'b' : 'a';
  final ownerPath = 'lib/$owner.dart';
  final foreignPath = 'lib/$foreign.dart';
  expect(compact.map((result) => result.id), normal.map((result) => result.id));
  expect(
    _toolResultById(compact, 'read-$owner-0').result,
    _toolResultById(normal, 'read-$owner-0').result,
    reason: 'the owning task older read must remain intact',
  );
  expect(
    _toolResultById(compact, 'read-$owner-0').result,
    contains(_protectedPathEvidenceMarker(ownerPath, 0)),
  );
  expect(
    _toolResultById(compact, 'read-$foreign-0').result,
    allOf(
      contains('stale tool result omitted'),
      contains('newer read_file result for $foreignPath'),
    ),
  );
  expect(
    _toolResultById(compact, 'read-$foreign-0').result,
    isNot(contains(_protectedPathEvidenceMarker(foreignPath, 0))),
  );
  for (final pathOwner in const ['a', 'b']) {
    expect(
      _toolResultById(compact, 'read-$pathOwner-1').result,
      _toolResultById(normal, 'read-$pathOwner-1').result,
      reason: 'the newest evidence must remain unchanged',
    );
  }
}

void _expectNormalProtectedPathPrompt(String prompt) {
  for (final path in const ['lib/a.dart', 'lib/b.dart']) {
    for (final offset in const [0, 1]) {
      expect(prompt, contains(_protectedPathEvidenceResult(path, offset)));
    }
  }
  expect(prompt, isNot(contains('stale tool result omitted')));
}

void _expectCompactProtectedPathPrompt({
  required String prompt,
  required String owner,
}) {
  final foreign = owner == 'a' ? 'b' : 'a';
  final ownerPath = 'lib/$owner.dart';
  final foreignPath = 'lib/$foreign.dart';
  expect(prompt, contains(_protectedPathEvidenceMarker(ownerPath, 0)));
  expect(prompt, contains(_protectedPathEvidenceMarker(ownerPath, 1)));
  expect(prompt, contains(_protectedPathEvidenceMarker(foreignPath, 1)));
  expect(prompt, isNot(contains(_protectedPathEvidenceMarker(foreignPath, 0))));
  expect(prompt, contains('newer read_file result for $foreignPath'));
}

Future<void> _verifyNonStreamingProtectedPathOwner(String owner) async {
  late final ProviderContainer container;
  late String foreignThread;
  final dataSource = _ProtectedPathRetryDataSource(
    mode: _ProtectedPathRetryMode.toolResultCompletion,
    onContextLengthError: () async {
      container
          .read(conversationsNotifierProvider.notifier)
          .selectConversation(foreignThread);
      await Future<void>.delayed(Duration.zero);
    },
  );
  final toolService = _ProtectedPathToolService();
  container = _buildContainer(dataSource: dataSource, toolService: toolService);
  try {
    final owners = await _configureSavedWorkflowThreads(container);
    final ownerThread = owner == 'a' ? owners.threadA : owners.threadB;
    foreignThread = owner == 'a' ? owners.threadB : owners.threadA;
    container
        .read(conversationsNotifierProvider.notifier)
        .selectConversation(ownerThread);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Compare the protected reads for owner $owner.');

    expect(toolService.executedArguments, hasLength(4));
    expect(dataSource.toolResultBatches, hasLength(2));
    expect(dataSource.toolResultRequestMessages, hasLength(2));
    _expectNormalProtectedPathPayload(dataSource.toolResultBatches.first);
    _expectCompactProtectedPathPayload(
      normal: dataSource.toolResultBatches.first,
      compact: dataSource.toolResultBatches.last,
      owner: owner,
    );
    expect(
      dataSource.toolResultRequestMessages,
      everyElement(isNot(predicate<List<Message>>(_containsPromptCompaction))),
      reason:
          'retry eligibility must come from the same owner-protected result '
          'set because the visible foreign thread has no compactable history',
    );
    expect(
      container.read(conversationsNotifierProvider).currentConversationId,
      foreignThread,
    );
  } finally {
    container.dispose();
  }
}

Future<void> _verifyProtectedPathEligibilityPoison({
  required String owner,
  required String duplicateOwner,
  required bool expectCompactRetry,
}) async {
  late final ProviderContainer container;
  late String foreignThread;
  final dataSource = _ProtectedPathRetryDataSource(
    mode: _ProtectedPathRetryMode.toolResultCompletion,
    toolCalls: _protectedPathReadCallsWithDuplicate(duplicateOwner),
    onContextLengthError: () async {
      container
          .read(conversationsNotifierProvider.notifier)
          .selectConversation(foreignThread);
      await Future<void>.delayed(Duration.zero);
    },
  );
  final toolService = _ProtectedPathToolService();
  container = _buildContainer(dataSource: dataSource, toolService: toolService);
  try {
    final owners = await _configureSavedWorkflowThreads(container);
    final ownerThread = owner == 'a' ? owners.threadA : owners.threadB;
    foreignThread = owner == 'a' ? owners.threadB : owners.threadA;
    container
        .read(conversationsNotifierProvider.notifier)
        .selectConversation(ownerThread);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage(
          'Check eligibility for owner $owner with duplicate $duplicateOwner.',
        );

    expect(toolService.executedArguments, hasLength(3));
    expect(
      dataSource.toolResultRequestMessages,
      everyElement(isNot(predicate<List<Message>>(_containsPromptCompaction))),
      reason: 'eligibility must not be widened by prompt-history compaction',
    );
    if (expectCompactRetry) {
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(dataSource.toolResultRequestMessages, hasLength(2));
      final normal = dataSource.toolResultBatches.first;
      final compact = dataSource.toolResultBatches.last;
      expect(
        compact.map((result) => result.id),
        normal.map((result) => result.id),
      );
      expect(
        _toolResultById(compact, 'read-$duplicateOwner-0').result,
        contains('stale tool result omitted'),
        reason:
            'the foreign duplicate must remain eligible for reduction even '
            'after its thread becomes visible',
      );
      expect(
        _toolResultById(compact, 'read-$duplicateOwner-1').result,
        _toolResultById(normal, 'read-$duplicateOwner-1').result,
      );
    } else {
      expect(
        dataSource.toolResultBatches,
        hasLength(1),
        reason:
            'owner-only stale evidence is protected, so compact budgeting '
            'cannot reduce the payload and must not enable a retry',
      );
      expect(dataSource.toolResultRequestMessages, hasLength(1));
    }
    expect(
      container.read(conversationsNotifierProvider).currentConversationId,
      foreignThread,
    );
  } finally {
    container.dispose();
  }
}

Future<void> _verifyStreamingProtectedPathOwner(String owner) async {
  late final ProviderContainer container;
  late String foreignThread;
  final dataSource = _ProtectedPathRetryDataSource(
    mode: _ProtectedPathRetryMode.streamedConcise,
    onContextLengthError: () async {
      container
          .read(conversationsNotifierProvider.notifier)
          .selectConversation(foreignThread);
      await Future<void>.delayed(Duration.zero);
    },
  );
  final toolService = _ProtectedPathToolService();
  container = _buildContainer(dataSource: dataSource, toolService: toolService);
  try {
    final owners = await _configureSavedWorkflowThreads(container);
    final ownerThread = owner == 'a' ? owners.threadA : owners.threadB;
    foreignThread = owner == 'a' ? owners.threadB : owners.threadA;
    container
        .read(conversationsNotifierProvider.notifier)
        .selectConversation(ownerThread);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Stream the protected reads for owner $owner.');

    expect(toolService.executedArguments, hasLength(4));
    expect(dataSource.toolResultBatches, hasLength(1));
    _expectNormalProtectedPathPayload(dataSource.toolResultBatches.single);
    expect(dataSource.finalAnswerRequestMessages, hasLength(2));
    expect(dataSource.conciseRecoveryRequestMessages, hasLength(1));
    _expectNormalProtectedPathPrompt(
      _toolResultAnswerPrompt(dataSource.finalAnswerRequestMessages.first),
    );
    _expectCompactProtectedPathPrompt(
      prompt: _toolResultAnswerPrompt(
        dataSource.finalAnswerRequestMessages.last,
      ),
      owner: owner,
    );
    _expectCompactProtectedPathPrompt(
      prompt: _toolResultAnswerPrompt(
        dataSource.conciseRecoveryRequestMessages.single,
      ),
      owner: owner,
    );
    expect(
      dataSource.finalAnswerRequestMessages,
      everyElement(isNot(predicate<List<Message>>(_containsPromptCompaction))),
      reason:
          'the streamed retry must be enabled by owner-scoped tool-result '
          'reduction rather than foreign prompt history',
    );
    expect(
      container.read(conversationsNotifierProvider).currentConversationId,
      foreignThread,
    );
  } finally {
    container.dispose();
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<({String threadA, String threadB})> _configureParticipantThreads(
  ProviderContainer container, {
  required List<ConversationParticipant> participantsA,
  required List<ConversationParticipant> participantsB,
  ParticipantTurnConfig configA = const ParticipantTurnConfig(),
  ParticipantTurnConfig configB = const ParticipantTurnConfig(),
}) async {
  final conversations = container.read(conversationsNotifierProvider.notifier);
  conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
  final threadA = container
      .read(conversationsNotifierProvider)
      .currentConversationId!;
  await conversations.updateConversationParticipants(
    threadA,
    participants: participantsA,
    participantTurnConfig: configA,
  );
  conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
  final threadB = container
      .read(conversationsNotifierProvider)
      .currentConversationId!;
  await conversations.updateConversationParticipants(
    threadB,
    participants: participantsB,
    participantTurnConfig: configB,
  );
  conversations.selectConversation(threadA);
  await Future<void>.delayed(Duration.zero);
  return (threadA: threadA, threadB: threadB);
}

Future<void> _verifyDetachedHiddenPromptPersistence({
  required bool persistAssistantResponse,
}) async {
  const ownerAPrompt = 'OWNER_A_DETACHED_HIDDEN_PROMPT';
  const ownerAResponse = 'OWNER_A_DETACHED_HIDDEN_RESPONSE';
  const ownerBPrompt = 'OWNER_B_VISIBLE_PROMPT';
  const ownerBResponse = 'OWNER_B_VISIBLE_RESPONSE';
  final ownerAStream = StreamController<String>();
  final model = AppSettings.defaults().model;
  final dataSource = _ParticipantOwnershipDataSource()
    ..queuePlain(model, ownerAStream.stream)
    ..queuePlain(model, Stream<String>.value(ownerBResponse));
  final container = _buildContainer(
    dataSource: dataSource,
    toolService: _NoToolService(),
    assistantMode: AssistantMode.general,
  );
  final runtimeEvents = <CavernoRuntimeEvent>[];
  final runtimeSubscription = container
      .read(cavernoExecutionRuntimeProvider)
      .events
      .listen(runtimeEvents.add);

  try {
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final ownerAFuture = notifier.sendHiddenPrompt(
      ownerAPrompt,
      persistAssistantResponse: persistAssistantResponse,
    );
    await _waitUntil(
      () => dataSource.plainRequests.any(
        (messages) =>
            messages.any((message) => message.content == ownerAPrompt),
      ),
    );

    conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final ownerB = await notifier
        .sendMessage(ownerBPrompt)
        .timeout(const Duration(seconds: 2));
    expect(ownerB?.conversationId, threadB);
    await _waitUntil(
      () => runtimeEvents.whereType<CavernoRuntimeTerminalEvent>().any(
        (event) => event.conversationId == threadB,
      ),
    );
    await notifier.flushPendingPersistence();

    final persistedBBeforeOwnerAFinishes = List<Message>.from(
      container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == threadB)
          .messages,
    );
    final visibleBBeforeOwnerAFinishes = List<Message>.from(
      notifier.state.messages,
    );

    ownerAStream.add(ownerAResponse);
    await ownerAStream.close();
    final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
    expect(ownerA?.conversationId, threadA);
    await _waitUntil(
      () => runtimeEvents.whereType<CavernoRuntimeTerminalEvent>().length == 2,
    );
    await notifier.flushPendingPersistence();

    final persisted = container
        .read(conversationsNotifierProvider)
        .conversations;
    final persistedA = persisted.singleWhere(
      (conversation) => conversation.id == threadA,
    );
    final persistedB = persisted.singleWhere(
      (conversation) => conversation.id == threadB,
    );
    final assistantA = persistedA.messages
        .where((message) => message.role == MessageRole.assistant)
        .map((message) => message.content)
        .toList(growable: false);
    expect(assistantA, persistAssistantResponse ? [ownerAResponse] : isEmpty);
    expect(persistedB.messages, persistedBBeforeOwnerAFinishes);
    expect(notifier.conversationId, threadB);
    expect(notifier.state.messages, visibleBBeforeOwnerAFinishes);
    expect(
      notifier.state.messages.map((message) => message.content),
      containsAllInOrder([ownerBPrompt, ownerBResponse]),
    );
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.busyConversationIds, isEmpty);

    final terminalEvents = runtimeEvents
        .whereType<CavernoRuntimeTerminalEvent>()
        .toList(growable: false);
    expect(
      terminalEvents.where((event) => event.conversationId == threadA),
      hasLength(1),
    );
    expect(
      terminalEvents.where((event) => event.conversationId == threadB),
      hasLength(1),
    );
  } finally {
    if (!ownerAStream.isClosed) await ownerAStream.close();
    await runtimeSubscription.cancel();
    container.dispose();
  }
}

void main() {
  // The project roots have to exist on disk: local_execute_command rejects a
  // missing working_directory before the tool service ever sees the call, which
  // silently replaces a fixture's scripted command result with an error and
  // makes assertions about that result fail. These paths are compile-time
  // constants used inside const argument maps, so they are created here rather
  // than allocated from systemTemp.
  final createdProjectRoots = <Directory>[];
  setUpAll(() {
    for (final path in const [_projectARoot, _projectBRoot]) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        continue;
      }
      // Record the highest ancestor that does not exist yet, so teardown can
      // undo the whole chain createSync(recursive: true) is about to make.
      var outermostMissing = directory;
      var parent = directory.parent;
      while (!parent.existsSync() && parent.path != parent.parent.path) {
        outermostMissing = parent;
        parent = parent.parent;
      }
      directory.createSync(recursive: true);
      createdProjectRoots.add(outermostMissing);
    }
  });
  tearDownAll(() {
    // Only remove what this suite created, so a developer's own
    // /tmp/caverno-test survives a test run.
    for (final directory in createdProjectRoots) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    createdProjectRoots.clear();
  });

  test(
    'detached owner keeps its transform when another owner resets',
    () async {
      const transform = 'truncated_tool_call_arguments_feedback';
      final ownerATransformReady = Completer<void>();
      final releaseOwnerA = Completer<void>();
      final sessionLogRoot = await Directory.systemTemp.createTemp(
        'caverno_detached_turn_transform_',
      );
      final sessionLogStore = LlmSessionLogStore(
        rootDirectoryProvider: () async => sessionLogRoot,
      );
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Owner A started a verification command.',
            toolCalls: [
              ToolCallInfo(
                id: 'truncated-owner-a',
                name: 'local_execute_command',
                arguments: const {},
              ),
            ],
            finishReason: 'length',
          ),
          _ownerCommandToolCall(owner: 'b', projectRoot: _projectBRoot),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'Owner A recovered from truncated arguments.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner B completed without owner A transforms.',
            finishReason: 'stop',
          ),
        ],
        beforeToolResultResponse: (requestIndex) async {
          if (requestIndex != 0) return;
          if (!ownerATransformReady.isCompleted) {
            ownerATransformReady.complete();
          }
          await releaseOwnerA.future;
        },
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SavedWorkflowToolService(),
        sessionLogStore: sessionLogStore,
      );
      addTearDown(() async {
        if (!releaseOwnerA.isCompleted) releaseOwnerA.complete();
        container.dispose();
        if (sessionLogRoot.existsSync()) {
          await sessionLogRoot.delete(recursive: true);
        }
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendMessage(
        'Run owner A verification.',
        bypassPlanMode: true,
      );
      await ownerATransformReady.future.timeout(const Duration(seconds: 2));

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      await Future<void>.delayed(Duration.zero);
      final ownerB = await notifier
          .sendMessage('Run owner B verification.', bypassPlanMode: true)
          .timeout(const Duration(seconds: 5));

      expect(ownerB?.conversationId, threadB);
      releaseOwnerA.complete();
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 5));
      expect(ownerA?.conversationId, threadA);

      Future<Map<String, dynamic>> turnExitFor(String conversationId) async {
        final file = await sessionLogStore.fileForContext(
          LlmSessionLogContext(
            workspaceMode: WorkspaceMode.coding,
            sessionId: conversationId,
            conversationId: conversationId,
          ),
          create: false,
        );
        final entries = (await file.readAsLines())
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList(growable: false);
        return entries.lastWhere((entry) => entry['operation'] == 'turn_exit');
      }

      final ownerAExit = await turnExitFor(threadA);
      final ownerBExit = await turnExitFor(threadB);
      final ownerATransforms =
          (ownerAExit['turnExit'] as Map<String, dynamic>)['transforms']
              as List<dynamic>? ??
          const <dynamic>[];
      final ownerBTransforms =
          (ownerBExit['turnExit'] as Map<String, dynamic>)['transforms']
              as List<dynamic>? ??
          const <dynamic>[];
      expect(ownerATransforms, contains(transform));
      expect(ownerBTransforms, isNot(contains(transform)));
    },
  );

  test(
    'detached approval caches stay isolated without clearing their owner',
    () async {
      ToolCallInfo commandCall(String id, String reason) => ToolCallInfo(
        id: id,
        name: 'local_execute_command',
        arguments: {
          'command': 'dart analyze',
          'working_directory': _projectARoot,
          'reason': reason,
        },
      );

      final releaseOwnerARepeat = Completer<void>();
      final auditRoot = await Directory.systemTemp.createTemp(
        'caverno_detached_approval_cache_',
      );
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [commandCall('command-a-1', 'Inspect diagnostics')],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '',
            toolCalls: [commandCall('command-b-1', 'Inspect diagnostics')],
            finishReason: 'tool_calls',
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'write-a',
                name: 'write_file',
                arguments: const {
                  'path': 'lib/cache_owner.dart',
                  'content': 'const owner = "a";\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '',
            toolCalls: [commandCall('command-a-2', 'Verify the fix')],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Owner A verified the change.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner B command was denied.',
            finishReason: 'stop',
          ),
        ],
        beforeToolResultResponse: (requestIndex) async {
          if (requestIndex == 1) await releaseOwnerARepeat.future;
        },
      );
      final toolService = _SavedWorkflowToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        codingApprovalMode: ToolApprovalMode.defaultPermissions,
        toolApprovalAuditLog: ToolApprovalAuditLog(
          rootDirectoryProvider: () async => auditRoot,
        ),
      );
      addTearDown(() async {
        if (!releaseOwnerARepeat.isCompleted) releaseOwnerARepeat.complete();
        container.dispose();
        await auditRoot.delete(recursive: true);
      });
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      final ownerAFuture = notifier.sendMessage(
        'Inspect, fix, and verify owner A.',
        bypassPlanMode: true,
      );
      await _waitUntil(() => notifier.state.pendingLocalCommand != null);
      final commandApprovalA = notifier.state.pendingLocalCommand!;
      notifier.resolveLocalCommand(
        id: commandApprovalA.id,
        approval: const LocalCommandApproval(approved: true),
      );
      await _waitUntil(() => notifier.state.pendingFileOperation != null);
      final fileApprovalA = notifier.state.pendingFileOperation!;
      notifier.resolveFileOperation(id: fileApprovalA.id, approved: true);
      await _waitUntil(() => dataSource.toolResultBatches.length == 2);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      await Future<void>.delayed(Duration.zero);
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final ownerBFuture = notifier.sendMessage(
        'Run the same analyzer command for owner B.',
        bypassPlanMode: true,
      );
      await _waitUntil(() => notifier.state.pendingLocalCommand != null);
      final commandApprovalB = notifier.state.pendingLocalCommand!;

      expect(threadA, isNot(threadB));
      expect(toolService.executedNames, [
        'local_execute_command',
        'write_file',
      ]);

      releaseOwnerARepeat.complete();
      await _waitUntil(
        () =>
            toolService.executedNames
                .where((name) => name == 'local_execute_command')
                .length ==
            2,
      );
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 5));

      expect(ownerA?.conversationId, threadA);
      expect(notifier.state.pendingLocalCommand?.id, commandApprovalB.id);
      expect(toolService.executedNames, [
        'local_execute_command',
        'write_file',
        'local_execute_command',
      ]);

      notifier.resolveLocalCommand(
        id: commandApprovalB.id,
        approval: const LocalCommandApproval(approved: false),
      );
      final ownerB = await ownerBFuture.timeout(const Duration(seconds: 5));

      expect(ownerB?.conversationId, threadB);
      expect(notifier.state.pendingLocalCommand, isNull);
      expect(
        toolService.executedNames.where(
          (name) => name == 'local_execute_command',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'saved validation success stays with its generation in both directions',
    () async {
      late final ProviderContainer container;
      late String threadA;
      late String threadB;
      final toolService = _SavedWorkflowToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Validate owner A.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'validate-a',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart test test/a_test.dart',
                  'working_directory': _projectARoot,
                },
              ),
            ],
          ),
          ChatCompletionResult(
            content: 'Validate owner B.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'validate-b',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart test test/b_test.dart',
                  'working_directory': _projectBRoot,
                },
              ),
            ],
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'Owner A validation completed.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner B validation completed.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (requestIndex) async {
          container
              .read(conversationsNotifierProvider.notifier)
              .selectConversation(requestIndex == 0 ? threadB : threadA);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);
      final owners = await _configureSavedWorkflowThreads(container);
      threadA = owners.threadA;
      threadB = owners.threadB;
      await container
          .read(conversationsNotifierProvider.notifier)
          .recordMutationGeneration(conversationId: threadB);
      final notifier = container.read(chatNotifierProvider.notifier);

      final ownerA = (await notifier.sendMessage('Validate task A.'))!;
      final afterOwnerA = container
          .read(conversationsNotifierProvider)
          .conversations;
      final ownerAAfterValidation = afterOwnerA.singleWhere(
        (conversation) => conversation.id == threadA,
      );
      final ownerBBeforeValidation = afterOwnerA.singleWhere(
        (conversation) => conversation.id == threadB,
      );
      expect(
        ownerAAfterValidation.verificationGeneration,
        ownerAAfterValidation.mutationGeneration,
      );
      expect(ownerBBeforeValidation.mutationGeneration, 1);
      expect(
        ownerBBeforeValidation.verificationGeneration,
        -1,
        reason: 'owner A validation must not settle visible owner B',
      );
      expect(
        notifier.hasVerifierReplayCandidateForOwnerForTest(ownerA),
        isTrue,
      );
      expect(
        notifier.hasVerifierReplayCandidateForOwnerForTest(
          ChatTurnOwner(
            conversationId: threadB,
            interactionGeneration: ownerA.interactionGeneration,
          ),
        ),
        isFalse,
        reason: 'owner A verifier must not poison visible owner B',
      );

      final ownerB = (await notifier.sendMessage('Validate task B.'))!;
      final afterOwnerB = container
          .read(conversationsNotifierProvider)
          .conversations;
      final ownerAAfterBoth = afterOwnerB.singleWhere(
        (conversation) => conversation.id == threadA,
      );
      final ownerBAfterValidation = afterOwnerB.singleWhere(
        (conversation) => conversation.id == threadB,
      );
      expect(
        ownerAAfterBoth.verificationGeneration,
        ownerAAfterBoth.mutationGeneration,
      );
      expect(
        ownerBAfterValidation.verificationGeneration,
        ownerBAfterValidation.mutationGeneration,
      );
      expect(
        notifier.hasVerifierReplayCandidateForOwnerForTest(ownerB),
        isTrue,
      );

      expect(
        toolService.executedArguments
            .map((arguments) => arguments['command'])
            .toList(),
        ['dart test test/a_test.dart', 'dart test test/b_test.dart'],
      );
      expect(dataSource.toolResultToolNames, hasLength(2));
      expect(
        dataSource.toolResultToolNames,
        everyElement(isEmpty),
        reason:
            'each owning saved validation must withhold follow-up tools even '
            'while the other task is visible',
      );
    },
  );

  test(
    'foreign validation stays ordinary while owner suffix is blocked',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final toolService = _SavedWorkflowToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Run both commands.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'foreign-b-validation',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart test test/b_test.dart',
                  'working_directory': _projectARoot,
                },
              ),
              ToolCallInfo(
                id: 'modified-a-validation',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart test test/a_test.dart && echo poison',
                  'working_directory': _projectARoot,
                },
              ),
            ],
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'The command checks completed.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (_) async {
          container
              .read(conversationsNotifierProvider.notifier)
              .selectConversation(threadB);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);
      final owners = await _configureSavedWorkflowThreads(container);
      threadB = owners.threadB;

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Check task A commands.');

      expect(toolService.executedNames, ['local_execute_command']);
      expect(
        toolService.executedArguments.single['command'],
        'dart test test/b_test.dart',
        reason: 'the visible task command remains an ordinary command for A',
      );
      final guardPayloads = dataSource.toolResultBatches
          .expand((batch) => batch)
          .map((result) => jsonDecode(result.result))
          .whereType<Map<String, dynamic>>()
          .where(
            (payload) => payload['code'] == 'saved_validation_command_modified',
          )
          .toList();
      expect(guardPayloads, hasLength(1));
      expect(
        guardPayloads.single,
        containsPair('saved_validation_command', 'dart test test/a_test.dart'),
      );
      expect(
        guardPayloads.single,
        containsPair(
          'attempted_command',
          'dart test test/a_test.dart && echo poison',
        ),
      );
      expect(
        dataSource.toolResultToolNames.first,
        contains('local_execute_command'),
        reason: 'foreign B success must not receive A validation credit',
      );
    },
  );

  test('saved target scope stays with A and B generations', () async {
    late final ProviderContainer container;
    late String threadA;
    late String threadB;
    final toolService = _SavedWorkflowToolService();
    ChatCompletionResult mutationBatch(
      String owner,
      String ownPath,
      String foreignPath,
    ) {
      return ChatCompletionResult(
        content: 'Mutate owner $owner files.',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'write-$owner-own',
            name: 'write_file',
            arguments: {'path': ownPath, 'content': 'owner $owner\n'},
          ),
          ToolCallInfo(
            id: 'write-$owner-foreign',
            name: 'write_file',
            arguments: {'path': foreignPath, 'content': 'poison\n'},
          ),
        ],
      );
    }

    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        mutationBatch('a', 'lib/a.dart', 'lib/b.dart'),
        mutationBatch('b', 'lib/b.dart', 'lib/a.dart'),
      ],
      toolResultResponses: [
        ChatCompletionResult(
          content: 'Owner A file update completed.',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content: 'Owner B file update completed.',
          finishReason: 'stop',
        ),
      ],
      beforeInitialResponse: (requestIndex) async {
        container
            .read(conversationsNotifierProvider.notifier)
            .selectConversation(requestIndex == 0 ? threadB : threadA);
        await Future<void>.delayed(Duration.zero);
      },
    );
    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);
    final owners = await _configureSavedWorkflowThreads(container);
    threadA = owners.threadA;
    threadB = owners.threadB;
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendMessage('Update task A.');
    await notifier.sendMessage('Update task B.');

    expect(
      toolService.executedArguments
          .map((arguments) => arguments['path'].toString())
          .map((path) => path.replaceAll(r'\', '/'))
          .toList(),
      everyElement(anyOf(endsWith('/lib/a.dart'), endsWith('/lib/b.dart'))),
    );
    expect(toolService.executedArguments, hasLength(2));
    expect(
      toolService.executedArguments[0]['path'].toString().replaceAll(r'\', '/'),
      endsWith('/lib/a.dart'),
    );
    expect(
      toolService.executedArguments[1]['path'].toString().replaceAll(r'\', '/'),
      endsWith('/lib/b.dart'),
    );
    final scopePayloads = dataSource.toolResultBatches
        .expand((batch) => batch)
        .map((result) => jsonDecode(result.result))
        .whereType<Map<String, dynamic>>()
        .where(
          (payload) => payload['code'] == 'saved_task_target_scope_violation',
        )
        .toList();
    expect(scopePayloads, hasLength(2));
    expect(scopePayloads[0]['task_id'], 'task-a');
    expect(scopePayloads[0]['task_title'], 'Implement owner A');
    expect(scopePayloads[0]['attempted_path'], 'lib/b.dart');
    expect(scopePayloads[0]['allowed_target_files'], contains('lib/a.dart'));
    expect(
      scopePayloads[0]['allowed_target_files'],
      isNot(contains('lib/b.dart')),
    );
    expect(scopePayloads[1]['task_id'], 'task-b');
    expect(scopePayloads[1]['task_title'], 'Implement owner B');
    expect(scopePayloads[1]['attempted_path'], 'lib/a.dart');
    expect(scopePayloads[1]['allowed_target_files'], contains('lib/b.dart'));
    expect(
      scopePayloads[1]['allowed_target_files'],
      isNot(contains('lib/a.dart')),
    );
  });

  test(
    'saved continuation question resolves from the owning generation',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final toolService = _SavedWorkflowToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Ask whether to continue.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'ask-owner-a',
                name: 'ask_user_question',
                arguments: const {
                  'question': 'Should I continue with the next saved task?',
                  'options': [
                    {'label': 'Continue'},
                    {'label': 'Pause'},
                  ],
                },
              ),
            ],
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'The saved-task policy was applied.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (_) async {
          container
              .read(conversationsNotifierProvider.notifier)
              .selectConversation(threadB);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);
      final owners = await _configureSavedWorkflowThreads(container);
      threadB = owners.threadB;
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Continue task A autonomously.');

      final result =
          jsonDecode(dataSource.toolResultBatches.first.single.result)
              as Map<String, dynamic>;
      expect(result['status'], 'policy_resolved');
      expect(result['saved_task_id'], 'task-a');
      expect(result['saved_validation_command'], 'dart test test/a_test.dart');
      expect(notifier.state.pendingAskUserQuestion, isNull);
      expect(toolService.executedNames, isEmpty);
    },
  );

  test(
    'duplicate saved validation success uses the owning generation',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final toolService = _SavedWorkflowToolService(
        commandStdout: 'Unhandled exception: fixture signal\n',
      );
      final duplicateValidation = ToolCallInfo(
        id: 'validate-a-duplicate',
        name: 'local_execute_command',
        arguments: const {
          'command': 'dart test test/a_test.dart',
          'working_directory': _projectARoot,
        },
      );
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Validate owner A.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'validate-a-first',
                name: 'local_execute_command',
                arguments: duplicateValidation.arguments,
              ),
            ],
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'I will rerun the same validation.',
            finishReason: 'tool_calls',
            toolCalls: [duplicateValidation],
          ),
        ],
        beforeInitialResponse: (_) async {
          container
              .read(conversationsNotifierProvider.notifier)
              .selectConversation(threadB);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);
      final owners = await _configureSavedWorkflowThreads(container);
      threadB = owners.threadB;

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Validate task A once.');

      expect(toolService.executedNames, ['local_execute_command']);
      final threadA = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == owners.threadA);
      expect(
        threadA.messages.map((message) => message.content).join('\n'),
        contains('saved validation command already succeeded'),
      );
    },
  );

  test(
    'turn finalization keeps validation owner after the early detach check',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final toolService = _SavedWorkflowToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Validate owner A.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'validate-a-finalization',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart test test/a_test.dart',
                  'working_directory': _projectARoot,
                },
              ),
            ],
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'I will edit lib/a.dart next.',
            finishReason: 'stop',
          ),
        ],
        beforeToolResultResponse: (_) async {
          container
              .read(conversationsNotifierProvider.notifier)
              .selectConversation(threadB);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);
      final owners = await _configureSavedWorkflowThreads(container);
      threadB = owners.threadB;
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.selectConversation(threadB);
      await conversations.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-b',
              title: 'Implement owner B',
              targetFiles: ['lib/b.dart'],
              validationCommand: 'dart test test/b_test.dart',
              status: ConversationWorkflowTaskStatus.completed,
            ),
          ],
        ),
      );
      conversations.selectConversation(owners.threadA);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Finish validating task A.');

      expect(dataSource.finishReasonReads, 0);
      expect(dataSource.usageReads, 0);
      expect(
        container.read(conversationsNotifierProvider).currentConversationId,
        threadB,
      );
      expect(
        dataSource.toolResultRequests,
        1,
        reason:
            'A validation is terminal for A even after completion makes B '
            'visible; finalization must not request a recovery completion',
      );
    },
  );

  test(
    'compact non-streaming retries protect only the owning task paths',
    () async {
      await _verifyNonStreamingProtectedPathOwner('a');
      await _verifyNonStreamingProtectedPathOwner('b');
    },
  );

  test(
    'compact retry eligibility uses the owning protected path set',
    () async {
      for (final owner in const ['a', 'b']) {
        final foreign = owner == 'a' ? 'b' : 'a';
        await _verifyProtectedPathEligibilityPoison(
          owner: owner,
          duplicateOwner: foreign,
          expectCompactRetry: true,
        );
        await _verifyProtectedPathEligibilityPoison(
          owner: owner,
          duplicateOwner: owner,
          expectCompactRetry: false,
        );
      }
    },
  );

  test(
    'streamed and concise retries reuse the owning protected paths',
    () async {
      await _verifyStreamingProtectedPathOwner('a');
      await _verifyStreamingProtectedPathOwner('b');
    },
  );

  test('plain stream metrics stay isolated across detached owners', () async {
    final ownerAStream = StreamController<String>();
    final model = AppSettings.defaults().model;
    final dataSource = _ParticipantOwnershipDataSource()
      ..queuePlain(
        model,
        ownerAStream.stream,
        finishReason: 'length',
        usage: const TokenUsage(
          promptTokens: 7,
          completionTokens: 5,
          totalTokens: 12,
        ),
      )
      ..queuePlain(
        model,
        Stream<String>.value('Owner B completed.'),
        usage: const TokenUsage(
          promptTokens: 31,
          completionTokens: 10,
          totalTokens: 41,
        ),
      );
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _NoToolService(),
      assistantMode: AssistantMode.general,
    );
    addTearDown(() async {
      if (!ownerAStream.isClosed) await ownerAStream.close();
      container.dispose();
    });
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final ownerAFuture = notifier.sendMessage('Stream owner A.');
    await _waitUntil(() => dataSource.plainRequests.length == 1);

    conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final ownerBFuture = notifier.sendMessage('Stream owner B.');
    await _waitUntil(() => dataSource.plainRequests.length == 2);
    await _waitUntil(
      () => !notifier.state.busyConversationIds.contains(threadB),
    );

    ownerAStream.add('Owner A reached the token limit.');
    await ownerAStream.close();
    await ownerAFuture;
    await ownerBFuture;
    await _waitUntil(() => notifier.state.busyConversationIds.isEmpty);

    final state = container.read(conversationsNotifierProvider);
    final assistantA = state
        .conversationForId(threadA)!
        .messages
        .where((message) => message.role == MessageRole.assistant)
        .single;
    final assistantB = state
        .conversationForId(threadB)!
        .messages
        .where((message) => message.role == MessageRole.assistant)
        .single;
    expect(assistantA.responseMetrics?.promptTokens, 7);
    expect(assistantA.responseMetrics?.completionTokens, 5);
    expect(assistantA.responseMetrics?.totalTokens, 12);
    expect(assistantA.responseMetrics?.finishReason, 'length');
    expect(assistantA.content, contains(TruncationNotice.maxTokenNotice));
    expect(assistantB.responseMetrics?.totalTokens, 41);
    expect(assistantB.responseMetrics?.finishReason, 'stop');
    expect(
      assistantB.content,
      isNot(contains(TruncationNotice.maxTokenNotice)),
    );
  });

  test(
    'detached ephemeral hidden owner A does not persist after B finishes',
    () =>
        _verifyDetachedHiddenPromptPersistence(persistAssistantResponse: false),
  );

  test(
    'detached persistent hidden owner A persists after B finishes',
    () =>
        _verifyDetachedHiddenPromptPersistence(persistAssistantResponse: true),
  );

  test(
    'concurrent hidden evidence survives reverse completion by exact owner',
    () async {
      const ownerAResponse = 'OWNER_A_HIDDEN_EVIDENCE';
      const ownerBResponse = 'OWNER_B_HIDDEN_EVIDENCE';
      final ownerAStream = StreamController<String>();
      final ownerBStream = StreamController<String>();
      final model = AppSettings.defaults().model;
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(model, ownerAStream.stream)
        ..queuePlain(model, ownerBStream.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
        assistantMode: AssistantMode.general,
      );
      addTearDown(() async {
        if (!ownerAStream.isClosed) await ownerAStream.close();
        if (!ownerBStream.isClosed) await ownerBStream.close();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendHiddenPrompt('Hold hidden owner A.');
      await _waitUntil(() => dataSource.plainRequests.length == 1);

      conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final ownerBFuture = notifier.sendHiddenPrompt('Finish hidden owner B.');
      await _waitUntil(() => dataSource.plainRequests.length == 2);

      ownerBStream.add(ownerBResponse);
      await ownerBStream.close();
      final ownerB = await ownerBFuture.timeout(const Duration(seconds: 2));
      ownerAStream.add(ownerAResponse);
      await ownerAStream.close();
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
      await _waitUntil(
        () => !notifier.state.busyConversationIds.contains(threadA),
      );

      expect(ownerA?.conversationId, threadA);
      expect(ownerB?.conversationId, threadB);
      expect(
        notifier.takeLatestHiddenAssistantResponse(ownerB),
        ownerBResponse,
      );
      expect(notifier.takeLatestHiddenAssistantResponse(ownerB), isNull);
      expect(
        notifier.takeLatestHiddenAssistantResponse(ownerA),
        ownerAResponse,
      );
      expect(notifier.takeLatestHiddenAssistantResponse(ownerA), isNull);
      expect(notifier.takeLatestHiddenAssistantResponse(null), isNull);
    },
  );

  test(
    'finalized save survives A to B to A switch and drains its queue',
    () async {
      const firstPrompt = 'Hold owner A until its finalized save.';
      const firstResponse = 'OWNER_A_FINALIZED_SAVE_CONTENT';
      const queuedPrompt = 'Run owner A queued follow-up.';
      const queuedResponse = 'OWNER_A_QUEUED_RESPONSE';
      final firstStream = StreamController<String>();
      final saveStarted = Completer<void>();
      final releaseSave = Completer<void>();
      var didGateFinalizedSave = false;
      final model = AppSettings.defaults().model;
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(model, firstStream.stream)
        ..queuePlain(model, Stream<String>.value(queuedResponse));
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
        assistantMode: AssistantMode.general,
        beforeConversationPut: (encoded) async {
          if (didGateFinalizedSave || !encoded.contains(firstResponse)) {
            return;
          }
          didGateFinalizedSave = true;
          saveStarted.complete();
          await releaseSave.future;
        },
      );
      final runtimeEvents = <CavernoRuntimeEvent>[];
      final runtimeSubscription = container
          .read(cavernoExecutionRuntimeProvider)
          .events
          .listen(runtimeEvents.add);
      addTearDown(() async {
        if (!releaseSave.isCompleted) releaseSave.complete();
        if (!firstStream.isClosed) await firstStream.close();
        await runtimeSubscription.cancel();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      conversations.selectConversation(threadA);
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(chatNotifierProvider.notifier);
      final firstOwnerFuture = notifier.sendMessage(firstPrompt);
      await _waitUntil(
        () => dataSource.plainRequests.any(
          (messages) =>
              messages.any((message) => message.content == firstPrompt),
        ),
      );
      expect(notifier.state.isLoading, isTrue);
      final queuedOwnerFuture = notifier.sendMessage(queuedPrompt);
      expect(notifier.state.queuedMessages.map((message) => message.content), [
        queuedPrompt,
      ]);

      firstStream.add(firstResponse);
      await firstStream.close();
      await saveStarted.future.timeout(const Duration(seconds: 2));

      conversations.selectConversation(threadB);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.messages, isEmpty);
      conversations.selectConversation(threadA);
      await Future<void>.delayed(Duration.zero);

      releaseSave.complete();
      final firstOwner = await firstOwnerFuture.timeout(
        const Duration(seconds: 2),
      );
      final queuedOwner = await queuedOwnerFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(firstOwner?.conversationId, threadA);
      expect(queuedOwner?.conversationId, threadA);
      expect(
        queuedOwner?.interactionGeneration,
        isNot(firstOwner?.interactionGeneration),
      );
      await _waitUntil(
        () =>
            runtimeEvents.whereType<CavernoRuntimeTerminalEvent>().length == 2,
      );
      await notifier.flushPendingPersistence();

      expect(notifier.conversationId, threadA);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.queuedMessages, isEmpty);
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(
        notifier.state.messages.where(
          (message) =>
              message.role == MessageRole.assistant &&
              message.content == firstResponse &&
              !message.isStreaming,
        ),
        hasLength(1),
      );
      expect(
        notifier.state.messages.map((message) => message.content),
        containsAllInOrder([
          firstPrompt,
          firstResponse,
          queuedPrompt,
          queuedResponse,
        ]),
      );
      expect(
        notifier.state.messages.where((message) => message.isStreaming),
        isEmpty,
      );
      final persisted = container
          .read(conversationsNotifierProvider)
          .conversations;
      final persistedA = persisted.singleWhere(
        (conversation) => conversation.id == threadA,
      );
      final persistedB = persisted.singleWhere(
        (conversation) => conversation.id == threadB,
      );
      expect(
        persistedA.messages.map((message) => message.content),
        containsAllInOrder([
          firstPrompt,
          firstResponse,
          queuedPrompt,
          queuedResponse,
        ]),
      );
      expect(
        persistedA.messages.where((message) => message.isStreaming),
        isEmpty,
      );
      expect(persistedB.messages, isEmpty);

      final terminalEvents = runtimeEvents
          .whereType<CavernoRuntimeTerminalEvent>()
          .toList(growable: false);
      expect(terminalEvents.map((event) => event.turnId).toSet(), hasLength(2));
      for (final turnId in terminalEvents.map((event) => event.turnId)) {
        expect(
          terminalEvents.where((event) => event.turnId == turnId),
          hasLength(1),
        );
      }
    },
  );

  test(
    'detached hidden retry keeps only its owner prompt after B finishes',
    () async {
      const ownerAPrompt = 'OWNER_A_HIDDEN_RETRY_TOKEN';
      const ownerBPrompt = 'OWNER_B_HIDDEN_POISON_TOKEN';
      final ownerAStream = StreamController<String>();
      final model = AppSettings.defaults().model;
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(model, ownerAStream.stream)
        ..queuePlain(model, Stream<String>.value('Owner B completed.'))
        ..queuePlain(model, Stream<String>.value('Owner A retry completed.'));
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
      );
      addTearDown(() async {
        container.dispose();
        if (!ownerAStream.isClosed) await ownerAStream.close();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final historyStart = DateTime(2026, 7, 28, 9);
      await conversations.updateConversationMessages(threadA, [
        for (var index = 0; index < 10; index++)
          Message(
            id: 'owner-a-history-$index',
            content: 'Owner A history $index',
            role: index.isEven ? MessageRole.user : MessageRole.assistant,
            timestamp: historyStart.add(Duration(minutes: index)),
          ),
      ]);
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendHiddenPrompt(ownerAPrompt);
      await _waitUntil(
        () => dataSource.plainRequests.any(
          (messages) =>
              messages.any((message) => message.content == ownerAPrompt),
        ),
      );

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      await Future<void>.delayed(Duration.zero);
      final ownerBFuture = notifier.sendHiddenPrompt(ownerBPrompt);
      await _waitUntil(
        () => dataSource.plainRequests.any(
          (messages) =>
              messages.any((message) => message.content == ownerBPrompt),
        ),
      );
      await ownerBFuture.timeout(const Duration(seconds: 2));

      ownerAStream.addError(
        StateError('This model has a maximum context length of 8192 tokens'),
      );
      await ownerAStream.close();
      await _waitUntil(
        () =>
            dataSource.plainRequests
                .where(
                  (messages) => messages.any(
                    (message) => message.content == ownerAPrompt,
                  ),
                )
                .length ==
            2,
      );
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
      expect(ownerA?.conversationId, threadA);

      final ownerARequests = dataSource.plainRequests
          .where(
            (messages) =>
                messages.any((message) => message.content == ownerAPrompt),
          )
          .toList(growable: false);
      expect(ownerARequests, hasLength(2));
      final retryMessages = ownerARequests.last;
      expect(
        retryMessages
            .where((message) => message.content == ownerAPrompt)
            .length,
        1,
      );
      expect(
        retryMessages,
        isNot(
          contains(
            predicate<Message>(
              (message) => message.content.contains(ownerBPrompt),
            ),
          ),
        ),
      );
      expect(
        retryMessages.any((message) => message.id == 'system_compaction'),
        isTrue,
        reason: 'the injected error must exercise the compact retry path',
      );
    },
  );

  test('detached stream error persists only on its exact owner', () async {
    const failureMarker = 'detached owner A stream failure';
    final failingStream = StreamController<String>();
    final dataSource = _ParticipantOwnershipDataSource()
      ..queuePlain(AppSettings.defaults().model, failingStream.stream);
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _NoToolService(),
    );
    addTearDown(() async {
      if (!failingStream.isClosed) await failingStream.close();
      container.dispose();
    });
    final runtime = container.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(subscription.cancel);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final ownerFuture = notifier.sendMessage('Fail only on thread A.');
    await _waitUntil(() => dataSource.plainRequests.isNotEmpty);

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    failingStream.addError(StateError(failureMarker));
    await failingStream.close();
    final owner = await ownerFuture.timeout(const Duration(seconds: 2));
    await notifier.flushPendingPersistence();

    expect(owner?.conversationId, threadA);
    expect(notifier.conversationId, threadB);
    expect(notifier.state.messages, isEmpty);
    expect(notifier.state.error, isNull);
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.busyConversationIds, isEmpty);
    final persisted = container
        .read(conversationsNotifierProvider)
        .conversations;
    final persistedA = persisted.firstWhere(
      (conversation) => conversation.id == threadA,
    );
    final persistedB = persisted.firstWhere(
      (conversation) => conversation.id == threadB,
    );
    expect(
      persistedA.messages.any(
        (message) => message.error?.contains(failureMarker) == true,
      ),
      isTrue,
    );
    expect(persistedB.messages, isEmpty);
    final terminalsA = events
        .whereType<CavernoRuntimeTerminalEvent>()
        .where((event) => event.conversationId == threadA)
        .toList(growable: false);
    expect(terminalsA, hasLength(1));
    expect(terminalsA.single, isA<CavernoRuntimeRunFailed>());
  });

  test(
    'open plain stream returns its owner before completing exactly once',
    () async {
      final responseStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(AppSettings.defaults().model, responseStream.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
      );
      addTearDown(() async {
        if (!responseStream.isClosed) await responseStream.close();
        container.dispose();
      });
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadId = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      final returnedOwner = await notifier
          .sendMessage('Keep the plain stream open.')
          .timeout(const Duration(seconds: 2));
      expect(returnedOwner, isNotNull);
      final owner = returnedOwner!;
      expect(owner.conversationId, threadId);
      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.busyConversationIds, contains(threadId));
      expect(runtime.hasActiveTurns, isTrue);
      expect(
        events.whereType<CavernoRuntimeTerminalEvent>().where(
          (event) => event.turnId == 'gen-${owner.interactionGeneration}',
        ),
        isEmpty,
      );

      responseStream.add('The plain stream completed.');
      await responseStream.close();
      await _waitUntil(
        () =>
            events
                .whereType<CavernoRuntimeTerminalEvent>()
                .where(
                  (event) =>
                      event.turnId == 'gen-${owner.interactionGeneration}' &&
                      event.conversationId == threadId,
                )
                .length ==
            1,
      );

      final terminals = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where(
            (event) =>
                event.turnId == 'gen-${owner.interactionGeneration}' &&
                event.conversationId == threadId,
          )
          .toList(growable: false);
      expect(terminals.single, isA<CavernoRuntimeRunCompleted>());
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(runtime.hasActiveTurns, isFalse);
    },
  );

  test(
    'plain stream finalization failure fails its exact owner and clears busy',
    () async {
      const failureMarker = 'plain final persistence failure marker';
      final responseStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(AppSettings.defaults().model, responseStream.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
        beforeConversationPut: (encoded) async {
          if (encoded.contains(failureMarker)) {
            throw StateError('plain onDone persistence failed');
          }
        },
      );
      addTearDown(() async {
        if (!responseStream.isClosed) await responseStream.close();
        container.dispose();
      });
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadId = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final returnedOwner = await notifier
          .sendMessage('Fail while finalizing this plain stream.')
          .timeout(const Duration(seconds: 2));
      expect(returnedOwner, isNotNull);
      final owner = returnedOwner!;

      responseStream.add(failureMarker);
      await responseStream.close();
      await _waitUntil(
        () =>
            events
                .whereType<CavernoRuntimeTerminalEvent>()
                .where(
                  (event) =>
                      event.turnId == 'gen-${owner.interactionGeneration}' &&
                      event.conversationId == threadId,
                )
                .length ==
            1,
      );
      await notifier.flushPendingPersistence();

      final terminals = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where(
            (event) =>
                event.turnId == 'gen-${owner.interactionGeneration}' &&
                event.conversationId == threadId,
          )
          .toList(growable: false);
      expect(terminals.single, isA<CavernoRuntimeRunFailed>());
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(runtime.hasActiveTurns, isFalse);
    },
  );

  test('clearMessages terminalizes every active runtime owner', () async {
    final streamA = StreamController<String>();
    final streamB = StreamController<String>();
    final dataSource = _ParticipantOwnershipDataSource()
      ..queuePlain(AppSettings.defaults().model, streamA.stream)
      ..queuePlain(AppSettings.defaults().model, streamB.stream);
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _NoToolService(),
    );
    addTearDown(() async {
      if (!streamA.isClosed) await streamA.close();
      if (!streamB.isClosed) await streamB.close();
      container.dispose();
    });
    final runtime = container.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(subscription.cancel);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final returnedOwnerA = await notifier
        .sendMessage('Keep owner A active until clear.')
        .timeout(const Duration(seconds: 2));
    expect(returnedOwnerA, isNotNull);
    final ownerA = returnedOwnerA!;

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    await Future<void>.delayed(Duration.zero);
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final returnedOwnerB = await notifier
        .sendMessage('Keep owner B active until clear.')
        .timeout(const Duration(seconds: 2));
    expect(returnedOwnerB, isNotNull);
    final ownerB = returnedOwnerB!;
    expect(notifier.state.busyConversationIds, containsAll([threadA, threadB]));

    notifier.clearMessages();
    await _waitUntil(
      () => events.whereType<CavernoRuntimeTerminalEvent>().length == 2,
    );
    await streamA.close();
    await streamB.close();
    await Future<void>.delayed(Duration.zero);

    final terminals = events.whereType<CavernoRuntimeTerminalEvent>().toList(
      growable: false,
    );
    expect(terminals, hasLength(2));
    for (final owner in [ownerA, ownerB]) {
      final ownerTerminals = terminals
          .where(
            (event) =>
                event.conversationId == owner.conversationId &&
                event.turnId == 'gen-${owner.interactionGeneration}',
          )
          .toList(growable: false);
      expect(ownerTerminals, hasLength(1));
      expect(ownerTerminals.single, isA<CavernoRuntimeRunFailed>());
      expect(
        (ownerTerminals.single as CavernoRuntimeRunFailed).code,
        'messages_cleared',
      );
    }
    expect(notifier.state.busyConversationIds, isEmpty);
    expect(runtime.hasActiveTurns, isFalse);
  });

  test('provider disposal terminalizes its active runtime owner', () async {
    final responseStream = StreamController<String>();
    final dataSource = _ParticipantOwnershipDataSource()
      ..queuePlain(AppSettings.defaults().model, responseStream.stream);
    final lifecyclePort = _CallbackRuntimeLifecyclePort((_) {});
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _NoToolService(),
      runtimeLifecyclePort: lifecyclePort,
    );
    var disposed = false;
    addTearDown(() async {
      if (!responseStream.isClosed) await responseStream.close();
      if (!disposed) container.dispose();
    });

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadId = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final returnedOwner = await notifier
        .sendMessage('Keep this stream active until provider disposal.')
        .timeout(const Duration(seconds: 2));
    expect(returnedOwner, isNotNull);
    final owner = returnedOwner!;

    container.dispose();
    disposed = true;
    await _waitUntil(() => lifecyclePort.terminalEvents.length == 1);
    await responseStream.close();
    await Future<void>.delayed(Duration.zero);

    final terminal = lifecyclePort.terminalEvents.single;
    expect(terminal.conversationId, threadId);
    expect(terminal.turnId, 'gen-${owner.interactionGeneration}');
    expect(terminal, isA<CavernoRuntimeRunFailed>());
    expect((terminal as CavernoRuntimeRunFailed).code, 'notifier_disposed');
  });

  test(
    'cancelling visible B fails only B while detached A completes',
    () async {
      final streamA = StreamController<String>();
      final streamB = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(AppSettings.defaults().model, streamA.stream)
        ..queuePlain(AppSettings.defaults().model, streamB.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
      );
      addTearDown(() async {
        if (!streamA.isClosed) await streamA.close();
        if (!streamB.isClosed) await streamB.close();
        container.dispose();
      });
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final returnedOwnerA = await notifier
          .sendMessage('Let detached owner A finish.')
          .timeout(const Duration(seconds: 2));
      expect(returnedOwnerA, isNotNull);
      final ownerA = returnedOwnerA!;

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      await Future<void>.delayed(Duration.zero);
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final returnedOwnerB = await notifier
          .sendMessage('Cancel only visible owner B.')
          .timeout(const Duration(seconds: 2));
      expect(returnedOwnerB, isNotNull);
      final ownerB = returnedOwnerB!;

      notifier.cancelStreaming();
      await _waitUntil(
        () =>
            events
                .whereType<CavernoRuntimeTerminalEvent>()
                .where(
                  (event) =>
                      event.conversationId == threadB &&
                      event.turnId == 'gen-${ownerB.interactionGeneration}',
                )
                .length ==
            1,
      );

      final terminalsBeforeACompletes = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .toList(growable: false);
      final terminalB = terminalsBeforeACompletes.singleWhere(
        (event) => event.conversationId == threadB,
      );
      expect(terminalB, isA<CavernoRuntimeRunFailed>());
      expect((terminalB as CavernoRuntimeRunFailed).code, 'cancelled');
      expect(
        terminalsBeforeACompletes.where(
          (event) => event.conversationId == threadA,
        ),
        isEmpty,
      );
      expect(notifier.state.busyConversationIds, contains(threadA));
      expect(notifier.state.busyConversationIds, isNot(contains(threadB)));

      streamA.add('Detached owner A completed.');
      await streamA.close();
      await _waitUntil(
        () =>
            events
                .whereType<CavernoRuntimeTerminalEvent>()
                .where(
                  (event) =>
                      event.conversationId == threadA &&
                      event.turnId == 'gen-${ownerA.interactionGeneration}',
                )
                .length ==
            1,
      );
      await streamB.close();
      await Future<void>.delayed(Duration.zero);

      final terminals = events.whereType<CavernoRuntimeTerminalEvent>().toList(
        growable: false,
      );
      final terminalA = terminals.singleWhere(
        (event) => event.conversationId == threadA,
      );
      expect(terminalA, isA<CavernoRuntimeRunCompleted>());
      expect(terminals, hasLength(2));
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(runtime.hasActiveTurns, isFalse);
    },
  );

  test(
    'cancellation persists partial transcript before terminal lease release',
    () async {
      const partialResponse = 'Persist this partial cancellation response.';
      final persistenceStarted = Completer<void>();
      final releasePersistence = Completer<void>();
      final responseStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(AppSettings.defaults().model, responseStream.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
        beforeConversationPut: (encoded) async {
          final payload = jsonDecode(encoded) as Map<String, dynamic>;
          final messages = payload['messages'] as List<dynamic>? ?? const [];
          final hasFinalizedPartial = messages.whereType<Map>().any(
            (message) =>
                message['content'] == partialResponse &&
                message['isStreaming'] == false,
          );
          if (!hasFinalizedPartial) return;
          if (!persistenceStarted.isCompleted) {
            persistenceStarted.complete();
          }
          await releasePersistence.future;
        },
      );
      addTearDown(() async {
        if (!releasePersistence.isCompleted) releasePersistence.complete();
        if (!responseStream.isClosed) await responseStream.close();
        container.dispose();
      });
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadId = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final owner = await notifier
          .sendMessage('Stream a response that will be cancelled.')
          .timeout(const Duration(seconds: 2));
      expect(owner, isNotNull);
      final exactOwner = owner!;

      responseStream.add(partialResponse);
      await _waitUntil(
        () => notifier.state.messages.last.content == partialResponse,
      );
      notifier.cancelStreaming();
      await persistenceStarted.future.timeout(const Duration(seconds: 2));
      var ownershipSettled = false;
      final settlement = runtime.ownershipSettled.whenComplete(() {
        ownershipSettled = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        events.whereType<CavernoRuntimeTerminalEvent>().where(
          (event) =>
              event.conversationId == threadId &&
              event.turnId == 'gen-${exactOwner.interactionGeneration}',
        ),
        hasLength(1),
      );
      expect(
        ownershipSettled,
        isFalse,
        reason: 'ownership release must wait for cancelled transcript storage',
      );

      releasePersistence.complete();
      await settlement.timeout(const Duration(seconds: 2));
      await notifier.flushPendingPersistence();
      expect(ownershipSettled, isTrue);

      final terminal = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .singleWhere((event) => event.conversationId == threadId);
      expect(terminal, isA<CavernoRuntimeRunFailed>());
      expect((terminal as CavernoRuntimeRunFailed).code, 'cancelled');
      final persisted = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == threadId);
      expect(
        persisted.messages.any(
          (message) =>
              message.content == partialResponse && !message.isStreaming,
        ),
        isTrue,
      );
    },
  );

  test('thread-scoped queue keeps exact owners and per-owner FIFO', () async {
    final queue = ThreadScopedMessageQueue();
    expect(queue.isEmpty, isTrue);

    final a1Receipt = queue.add(_queuedMessage('a-1', 'thread-a'));
    final b1Receipt = queue.add(_queuedMessage('b-1', 'thread-b'));
    final a2Receipt = queue.add(_queuedMessage('a-2', 'thread-a'));
    final draftReceipt = queue.add(_queuedMessage('draft-only', null));

    expect(queue.isEmpty, isFalse);
    expect(queue.forThread('thread-a').map((message) => message.id), [
      'a-1',
      'a-2',
    ]);
    expect(queue.pendingFor('thread-b'), 1);
    final firstA = queue.takeNextForThread('thread-a')!;
    expect(firstA.id, 'a-1');
    final completedOwner = ChatTurnOwner(
      conversationId: 'thread-a',
      interactionGeneration: 1,
    );
    queue.completeTurnOwner(firstA, completedOwner);
    expect(await a1Receipt, completedOwner);
    expect(queue.takeNextForThread('thread-a')?.id, 'a-2');
    expect(queue.takeNextForThread('thread-a'), isNull);
    expect(queue.forThread(null).map((message) => message.id), ['draft-only']);
    final draft = queue.takeNextForThread(null)!;
    final restoredDraftReceipt = queue.restoreFirstForThread(draft, 'thread-a');
    expect(restoredDraftReceipt, same(draftReceipt));
    final boundDraft = queue.takeNextForThread('thread-a')!;
    expect(boundDraft.conversationId, 'thread-a');
    expect(draft.conversationId, isNull);
    expect(
      queue.restoreFirstForThread(boundDraft, 'thread-a'),
      same(draftReceipt),
    );
    expect(queue.takeNextForThread('thread-a'), same(boundDraft));
    final restoredOnly = _queuedMessage('restored-only', null);
    final restoredOnlyReceipt = queue.restoreFirstForThread(
      restoredOnly,
      'thread-b',
    );
    final boundRestoredOnly = queue.takeNextForThread('thread-b')!;
    final restoredOnlyOwner = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 2,
    );
    queue.completeTurnOwner(boundRestoredOnly, restoredOnlyOwner);
    expect(await restoredOnlyReceipt, restoredOnlyOwner);
    expect(queue.contains(boundDraft), isFalse);
    expect(queue.shouldEnqueue('thread-a'), isFalse);
    unawaited(queue.add(boundDraft));
    expect(queue.contains(boundDraft), isTrue);
    expect(queue.shouldEnqueue('thread-a'), isTrue);
    expect(queue.takeNextForThread('thread-a'), same(boundDraft));
    expect(queue.canStart(boundDraft, 'thread-a', true), isTrue);
    expect(queue.canStart(draft, null, false), isTrue);
    expect(queue.canStart(draft, null, true), isFalse);
    expect(queue.canStart(boundDraft, 'thread-b', false), isFalse);
    expect(queue.canStart(_queuedMessage('blank', ' '), ' ', false), isFalse);
    expect(queue.ownerFor(draft, null, 'thread-a'), 'thread-a');
    expect(queue.ownerFor(boundDraft, 'thread-a', 'thread-a'), 'thread-a');
    expect(queue.ownerFor(boundDraft, 'thread-b', 'thread-a'), isNull);
    expect(queue.ownerFor(_queuedMessage('blank', ' '), ' ', ' '), isNull);
    expect(queue.beginDrain('thread-a'), isTrue);
    expect(queue.beginDrain('thread-a'), isFalse);
    expect(queue.shouldEnqueue('thread-a'), isTrue);
    expect(queue.beginDrain('thread-b'), isTrue);
    queue.endDrain('thread-a');
    queue.endDrain('thread-b');
    expect(queue.beginDrain('thread-a'), isTrue);
    queue.endDrain('thread-a');
    expect(queue.remove('b-1'), isTrue);
    expect(queue.remove('missing'), isFalse);
    expect(await b1Receipt, isNull);

    queue.clear();
    expect(queue.isEmpty, isTrue);
    expect(await a2Receipt, isNull);
    expect(await draftReceipt, isNull);
  });

  test(
    'thread B approval cannot authorize detached thread A release',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final toolService = _ReleaseToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          _productionReleaseToolCall('release-a-generation-1'),
        ],
        beforeInitialResponse: (requestIndex) async {
          if (requestIndex != 0) return;
          final conversations = container.read(
            conversationsNotifierProvider.notifier,
          );
          conversations.createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
          threadB = container
              .read(conversationsNotifierProvider)
              .currentConversationId!;
          final now = DateTime(2026, 7, 28, 10);
          await conversations.updateConversationMessages(threadB, [
            Message(
              id: 'thread-b-assistant-approval',
              role: MessageRole.assistant,
              content: 'Do you approve the production release command now?',
              timestamp: now,
            ),
            Message(
              id: 'thread-b-user-approval',
              role: MessageRole.user,
              content: 'Approve and run the production release now.',
              timestamp: now.add(const Duration(seconds: 1)),
            ),
          ]);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Continue without releasing anything.');

      expect(threadB, isNot(threadA));
      expect(toolService.executions, 0);
      expect(
        dataSource.decodedToolResults,
        contains(
          containsPair('code', 'production_release_explicit_approval_required'),
        ),
        reason:
            'generation 1 belongs to thread A, so thread B approval is poison',
      );
    },
  );

  test(
    'thread B denial cannot revoke detached thread A direct approval',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final toolService = _ReleaseToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          _productionReleaseToolCall('release-a-generation-1'),
        ],
        beforeInitialResponse: (requestIndex) async {
          if (requestIndex != 0) return;
          final conversations = container.read(
            conversationsNotifierProvider.notifier,
          );
          conversations.createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
          threadB = container
              .read(conversationsNotifierProvider)
              .currentConversationId!;
          final now = DateTime(2026, 7, 28, 10);
          await conversations.updateConversationMessages(threadB, [
            Message(
              id: 'thread-b-assistant-approval',
              role: MessageRole.assistant,
              content: 'Do you approve the production release command now?',
              timestamp: now,
            ),
            Message(
              id: 'thread-b-user-denial',
              role: MessageRole.user,
              content: 'Do not release anything.',
              timestamp: now.add(const Duration(seconds: 1)),
            ),
          ]);
          await Future<void>.delayed(Duration.zero);
        },
      );
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Approve and run the production release now.');

      expect(threadB, isNot(threadA));
      expect(toolService.executions, 1);
      expect(
        dataSource.decodedToolResults,
        isNot(
          contains(
            containsPair(
              'code',
              'production_release_explicit_approval_required',
            ),
          ),
        ),
        reason:
            'thread A generation 1 owns its submitted direct approval snapshot',
      );
    },
  );

  test(
    'direct approval from generation N cannot authorize hidden generation N+1',
    () async {
      final toolService = _ReleaseToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Approval recorded for this turn.',
            finishReason: 'stop',
          ),
          _productionReleaseToolCall('release-generation-2'),
        ],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage(
        'I explicitly approve production release execution.',
      );
      await notifier.sendHiddenPrompt('Continue with the next step.');

      expect(toolService.executions, 0);
      expect(
        dataSource.decodedToolResults,
        contains(
          containsPair('code', 'production_release_explicit_approval_required'),
        ),
        reason:
            'generation 2 has no submitted user message and cannot reuse '
            'generation 1 direct approval',
      );
    },
  );

  test(
    'ask approval from generation N cannot authorize hidden generation N+1',
    () async {
      final toolService = _ReleaseToolService();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'I need production release approval.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'ask-release-generation-1',
                name: 'ask_user_question',
                arguments: const {
                  'question':
                      'Approve running the production release command now?',
                  'options': [
                    {'label': 'Approve production release'},
                    {'label': 'Do not release'},
                  ],
                },
              ),
            ],
          ),
          _productionReleaseToolCall('release-generation-2'),
        ],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstTurn = notifier.sendMessage('Ask for release approval.');
      await _waitUntil(() => notifier.state.pendingAskUserQuestion != null);
      final pending = notifier.state.pendingAskUserQuestion!;
      notifier.resolveAskUserQuestion(
        id: pending.id,
        answer: AskUserQuestionAnswer(
          question: pending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'approve-production-release',
              label: 'Approve production release',
            ),
          ],
        ),
      );
      await firstTurn;

      await notifier.sendHiddenPrompt('Continue with the next step.');

      expect(toolService.executions, 0);
      expect(
        dataSource.decodedToolResults,
        contains(
          containsPair('code', 'production_release_explicit_approval_required'),
        ),
        reason:
            'generation 2 cannot reuse the ask_user_question cache from '
            'generation 1',
      );
    },
  );

  test('thread B message preserves thread A pending question', () async {
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: 'Thread B normal reply.',
          finishReason: 'stop',
        ),
      ],
    );
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _ReleaseToolService(),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    var threadACompleted = false;
    final threadAFuture = notifier.requestAskUserQuestion(
      question: 'Which deployment target belongs to thread A?',
      help: 'Choose the target for thread A only.',
      options: const [
        AskUserQuestionOption(
          id: 'thread-a-staging',
          label: 'Thread A staging',
        ),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      targetConversationId: threadA,
    );
    unawaited(
      threadAFuture.then((_) {
        threadACompleted = true;
      }),
    );
    final threadAPending = notifier.state.pendingAskUserQuestion!;

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    await Future<void>.delayed(Duration.zero);

    expect(threadB, isNot(threadA));
    expect(
      notifier.state.pendingAskUserQuestion,
      isNull,
      reason: 'thread B must not project thread A question',
    );

    await notifier.sendMessage('Normal message from thread B.');
    await notifier.flushPendingPersistence();
    await Future<void>.delayed(Duration.zero);

    expect(
      threadACompleted,
      isFalse,
      reason: 'sending and finishing in B must not complete A question',
    );
    final persisted = container
        .read(conversationsNotifierProvider)
        .conversations;
    final persistedA = persisted.firstWhere(
      (conversation) => conversation.id == threadA,
    );
    final persistedB = persisted.firstWhere(
      (conversation) => conversation.id == threadB,
    );
    expect(persistedA.messages, isEmpty);
    expect(
      persistedB.messages.map((message) => message.content),
      containsAllInOrder([
        'Normal message from thread B.',
        'Thread B normal reply.',
      ]),
    );

    conversations.selectConversation(threadA);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.pendingAskUserQuestion, same(threadAPending));
    expect(notifier.state.pendingAskUserQuestion!.id, threadAPending.id);
    expect(
      notifier.state.pendingAskUserQuestion!.question,
      'Which deployment target belongs to thread A?',
    );

    notifier.resolveAskUserQuestion(
      id: threadAPending.id,
      answer: AskUserQuestionAnswer(
        question: threadAPending.question,
        selectedOptions: const [
          AskUserQuestionSelection(
            id: 'thread-a-staging',
            label: 'Thread A staging',
          ),
        ],
      ),
    );
    expect(
      (await threadAFuture)!.selectedOptions.single.id,
      'thread-a-staging',
    );
  });

  test('question resolution and fresh messages stay owner scoped', () async {
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: 'Thread A fresh-message reply.',
          finishReason: 'stop',
        ),
      ],
    );
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _ReleaseToolService(),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    var threadACompleted = false;
    AskUserQuestionAnswer? threadAResult;
    final threadAFuture = notifier.requestAskUserQuestion(
      question: 'Which package should thread A publish?',
      help: 'Choose the package owned by thread A.',
      options: const [
        AskUserQuestionOption(
          id: 'thread-a-package',
          label: 'Thread A package',
        ),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      targetConversationId: threadA,
    );
    unawaited(
      threadAFuture.then((result) {
        threadACompleted = true;
        threadAResult = result;
      }),
    );
    final threadAPending = notifier.state.pendingAskUserQuestion!;

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    await Future<void>.delayed(Duration.zero);
    var threadBCompleted = false;
    final threadBFuture = notifier.requestAskUserQuestion(
      question: 'Which region should thread B deploy to?',
      help: 'Choose the region owned by thread B.',
      options: const [
        AskUserQuestionOption(id: 'thread-b-eu', label: 'Thread B Europe'),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      targetConversationId: threadB,
    );
    unawaited(
      threadBFuture.then((_) {
        threadBCompleted = true;
      }),
    );
    final threadBPending = notifier.state.pendingAskUserQuestion!;
    expect(threadBPending.id, isNot(threadAPending.id));

    conversations.selectConversation(threadA);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.pendingAskUserQuestion, same(threadAPending));

    final threadBAnswer = AskUserQuestionAnswer(
      question: threadBPending.question,
      selectedOptions: const [
        AskUserQuestionSelection(id: 'thread-b-eu', label: 'Thread B Europe'),
      ],
    );
    notifier.resolveAskUserQuestion(
      id: threadBPending.id,
      answer: threadBAnswer,
    );
    expect(await threadBFuture, same(threadBAnswer));
    await Future<void>.delayed(Duration.zero);

    expect(threadBCompleted, isTrue);
    expect(
      threadACompleted,
      isFalse,
      reason: 'resolving B by ID while A is visible must leave A waiting',
    );
    expect(notifier.state.pendingAskUserQuestion, same(threadAPending));

    conversations.selectConversation(threadB);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.pendingAskUserQuestion, isNull);

    var replacementBCompleted = false;
    final replacementBFuture = notifier.requestAskUserQuestion(
      question: 'Which cache should thread B retain?',
      help: 'Choose the cache owned by thread B.',
      options: const [
        AskUserQuestionOption(
          id: 'thread-b-build-cache',
          label: 'Thread B build cache',
        ),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      targetConversationId: threadB,
    );
    unawaited(
      replacementBFuture.then((_) {
        replacementBCompleted = true;
      }),
    );
    final replacementBPending = notifier.state.pendingAskUserQuestion!;
    expect({
      threadAPending.id,
      threadBPending.id,
      replacementBPending.id,
    }, hasLength(3));

    conversations.selectConversation(threadA);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.pendingAskUserQuestion, same(threadAPending));

    await notifier.sendMessage('Fresh thread A message bypasses its dialog.');
    await notifier.flushPendingPersistence();
    await Future<void>.delayed(Duration.zero);

    expect(threadACompleted, isTrue);
    expect(threadAResult, isNull);
    expect(notifier.state.pendingAskUserQuestion, isNull);
    expect(
      replacementBCompleted,
      isFalse,
      reason: 'a fresh A message must not complete B replacement question',
    );
    final persisted = container
        .read(conversationsNotifierProvider)
        .conversations;
    final persistedA = persisted.firstWhere(
      (conversation) => conversation.id == threadA,
    );
    final persistedB = persisted.firstWhere(
      (conversation) => conversation.id == threadB,
    );
    expect(
      persistedA.messages.map((message) => message.content),
      containsAllInOrder([
        'Fresh thread A message bypasses its dialog.',
        'Thread A fresh-message reply.',
      ]),
    );
    expect(
      persistedB.messages
          .map((message) => message.content)
          .contains('Fresh thread A message bypasses its dialog.'),
      isFalse,
    );

    conversations.selectConversation(threadB);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.pendingAskUserQuestion, same(replacementBPending));

    notifier.resolveAskUserQuestion(
      id: replacementBPending.id,
      answer: AskUserQuestionAnswer(
        question: replacementBPending.question,
        selectedOptions: const [
          AskUserQuestionSelection(
            id: 'thread-b-build-cache',
            label: 'Thread B build cache',
          ),
        ],
      ),
    );
    expect(
      (await replacementBFuture)!.selectedOptions.single.id,
      'thread-b-build-cache',
    );
  });

  test('clearMessages dismisses pending questions in every thread', () async {
    final container = _buildContainer(
      dataSource: ScriptedChatDataSource(initialResponses: const []),
      toolService: _ReleaseToolService(),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final threadAFuture = notifier.requestAskUserQuestion(
      question: 'Should thread A keep its global-reset fixture?',
      help: '',
      options: const [
        AskUserQuestionOption(
          id: 'thread-a-keep',
          label: 'Keep thread A fixture',
        ),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      targetConversationId: threadA,
    );

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    await Future<void>.delayed(Duration.zero);
    final threadBFuture = notifier.requestAskUserQuestion(
      question: 'Should thread B keep its global-reset fixture?',
      help: '',
      options: const [
        AskUserQuestionOption(
          id: 'thread-b-keep',
          label: 'Keep thread B fixture',
        ),
      ],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      targetConversationId: threadB,
    );
    final threadBPending = notifier.state.pendingAskUserQuestion;

    notifier.clearMessages();

    expect(
      await Future.wait([threadAFuture, threadBFuture]),
      everyElement(isNull),
    );
    expect(notifier.state.pendingAskUserQuestion, isNull);
    expect(threadBPending, isNotNull);

    conversations.selectConversation(threadA);
    await Future<void>.delayed(Duration.zero);
    expect(
      notifier.state.pendingAskUserQuestion,
      isNull,
      reason: 'the application-global reset must leave no owner map entry',
    );
  });

  test('a detached turn keeps its own project in the system prompt', () async {
    // Regression for the cross-thread contamination observed 2026-07-25: a
    // background turn on one project kept running while another thread was
    // visible, and its next request was assembled with the *visible*
    // thread's coding project. The model was handed its own tool results
    // under another project's root path.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource();
    final toolService = _SwitchingToolService(() async {
      // The user opens the other thread while the tool runs.
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversationsNotifier = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversationsNotifier.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendMessage('list the project');

    expect(
      toolService.executions,
      greaterThan(0),
      reason: 'the tool has to run for the thread switch to interleave',
    );
    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.normalizedProjectId,
      'project-b',
      reason: 'the visible thread must be the other project by now',
    );

    final systemPrompt = dataSource.lastSystemPrompt;
    expect(systemPrompt, isNotNull);
    expect(
      systemPrompt,
      contains(_projectARoot),
      reason: 'the detached turn must keep describing its own project',
    );
    expect(
      systemPrompt,
      isNot(contains(_projectBRoot)),
      reason:
          'inheriting the visible thread project is the contamination: the '
          'turn would report its own tool results under another root',
    );
  });

  test(
    'detached completed and command evidence stays with exact owners',
    () async {
      final releaseOwnerA = Completer<void>();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          _ownerCommandToolCall(owner: 'a', projectRoot: _projectARoot),
          _ownerCommandToolCall(owner: 'b', projectRoot: _projectBRoot),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'Owner B command output recorded.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner A command output recorded.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (requestIndex) async {
          if (requestIndex == 0) await releaseOwnerA.future;
        },
      );
      final toolService = _SavedWorkflowToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(() {
        if (!releaseOwnerA.isCompleted) releaseOwnerA.complete();
        container.dispose();
      });
      final runtimeEvents = <CavernoRuntimeEvent>[];
      final runtimeSubscription = container
          .read(cavernoExecutionRuntimeProvider)
          .events
          .listen(runtimeEvents.add);
      addTearDown(runtimeSubscription.cancel);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendMessage('Collect owner A evidence.');
      await _waitUntil(() => dataSource.initialRequests == 1);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      await Future<void>.delayed(Duration.zero);
      final ownerB = await notifier.sendMessage('Collect owner B evidence.');

      expect(ownerB, isNotNull);
      expect(ownerB!.conversationId, threadB);
      final resultsB = notifier.takeLatestToolResults(ownerB);
      expect(resultsB, hasLength(1));
      expect(resultsB.single.id, 'command-b');
      expect(resultsB.single.name, 'local_execute_command');
      expect(resultsB.single.arguments['command'], 'printf owner-b');
      expect(resultsB.single.arguments['working_directory'], _projectBRoot);
      expect(
        resultsB,
        everyElement(
          isNot(
            predicate(
              (result) =>
                  result is ToolResultInfo &&
                  result.arguments.values.any(
                    (value) => value?.toString().contains('owner-a') ?? false,
                  ),
            ),
          ),
        ),
      );
      expect(notifier.takeLatestToolResults(ownerB), isEmpty);

      releaseOwnerA.complete();
      final ownerA = await ownerAFuture;
      expect(ownerA, isNotNull);
      expect(ownerA!.conversationId, threadA);
      final resultsA = notifier.takeLatestToolResults(ownerA);
      expect(resultsA, hasLength(1));
      expect(resultsA.single.id, 'command-a');
      expect(resultsA.single.name, 'local_execute_command');
      expect(resultsA.single.arguments['command'], 'printf owner-a');
      expect(resultsA.single.arguments['working_directory'], _projectARoot);
      expect(
        resultsA,
        everyElement(
          isNot(
            predicate(
              (result) =>
                  result is ToolResultInfo &&
                  result.arguments.values.any(
                    (value) => value?.toString().contains('owner-b') ?? false,
                  ),
            ),
          ),
        ),
      );
      expect(notifier.takeLatestToolResults(ownerA), isEmpty);
      expect(toolService.executedNames, [
        'local_execute_command',
        'local_execute_command',
      ]);
      expect(
        toolService.executedArguments.map((arguments) => arguments['command']),
        ['printf owner-b', 'printf owner-a'],
        reason: 'owner B must finish before the gated detached owner A',
      );
      final lifecycleEvents = runtimeEvents
          .whereType<CavernoRuntimeToolLifecycle>()
          .toList(growable: false);
      for (final (owner, toolCallId) in [
        (ownerA, 'command-a'),
        (ownerB, 'command-b'),
      ]) {
        final ownerEvents = lifecycleEvents
            .where(
              (event) =>
                  event.conversationId == owner.conversationId &&
                  event.turnId == 'gen-${owner.interactionGeneration}',
            )
            .toList(growable: false);
        expect(
          ownerEvents.map((event) => event.toolCallId),
          everyElement(toolCallId),
        );
        expect(
          ownerEvents.map((event) => event.state),
          containsAllInOrder(CavernoRuntimeToolLifecycleState.values),
        );
        expect(ownerEvents, hasLength(3));
      }
      expect(
        lifecycleEvents,
        hasLength(6),
        reason: 'tool lifecycle events must never attach to another owner',
      );
    },
  );

  test(
    'detached owner mutation invalidates its own read replay generation',
    () async {
      late final ProviderContainer container;
      late String threadB;
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Read owner A before editing.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'read-a-before',
                name: 'read_file',
                arguments: const {'path': 'lib/owner_a.dart'},
              ),
            ],
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'Update owner A after the first read.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'write-a',
                name: 'write_file',
                arguments: const {
                  'path': 'lib/owner_a.dart',
                  'content': 'const owner = "A";\n',
                },
              ),
            ],
          ),
          ChatCompletionResult(
            content: 'Read owner A again after the edit.',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'read-a-after',
                name: 'read_file',
                arguments: const {'path': 'lib/owner_a.dart'},
              ),
            ],
          ),
          ChatCompletionResult(
            content: 'Owner A edit and verification completed.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (_) async {
          final conversations = container.read(
            conversationsNotifierProvider.notifier,
          );
          conversations.createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
          threadB = container
              .read(conversationsNotifierProvider)
              .currentConversationId!;
          await Future<void>.delayed(Duration.zero);
        },
      );
      final toolService = _SavedWorkflowToolService(includeReadFile: true);
      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final ownerA = await container
          .read(chatNotifierProvider.notifier)
          .sendMessage('Read, update, and reread owner A.');

      expect(ownerA?.conversationId, threadA);
      expect(
        container.read(conversationsNotifierProvider).currentConversationId,
        threadB,
      );
      expect(
        toolService.executedNames,
        ['read_file', 'write_file', 'read_file'],
        reason:
            'A mutation must invalidate A read replay even while B is visible',
      );
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.id),
        ['read-a-before', 'write-a', 'read-a-after'],
      );
      final persisted = container
          .read(conversationsNotifierProvider)
          .conversations;
      expect(
        persisted
            .singleWhere((conversation) => conversation.id == threadA)
            .mutationGeneration,
        1,
      );
      expect(
        persisted
            .singleWhere((conversation) => conversation.id == threadB)
            .mutationGeneration,
        0,
        reason: 'detached owner A must never increment visible owner B',
      );
    },
  );

  test('detached content evidence stays with exact owners', () async {
    final releaseOwnerA = Completer<void>();
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: _ownerContentCommandCall(
            owner: 'a',
            projectRoot: _projectARoot,
          ),
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content: _ownerContentCommandCall(
            owner: 'b',
            projectRoot: _projectBRoot,
          ),
          finishReason: 'stop',
        ),
      ],
      beforeInitialResponse: (requestIndex) async {
        if (requestIndex == 0) await releaseOwnerA.future;
      },
    );
    final toolService = _SavedWorkflowToolService();
    final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
      runtimeRepositoryPort: runtimeRepository,
    );
    addTearDown(() {
      if (!releaseOwnerA.isCompleted) releaseOwnerA.complete();
      container.dispose();
    });

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final ownerAFuture = notifier.sendMessage('Stream owner A evidence.');
    await _waitUntil(() => dataSource.initialRequests == 1);
    await _waitUntil(
      () => toolService.executedArguments.any(
        (arguments) => arguments['command'] == 'printf content-owner-a',
      ),
    );

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    await Future<void>.delayed(Duration.zero);
    final ownerB = await notifier.sendMessage('Stream owner B evidence.');

    expect(ownerB, isNotNull);
    expect(ownerB!.conversationId, threadB);
    final resultsB = notifier.takeLatestToolResults(ownerB);
    expect(resultsB, hasLength(1));
    expect(resultsB.single.name, 'local_execute_command');
    expect(resultsB.single.arguments['command'], 'printf content-owner-b');
    expect(resultsB.single.arguments['working_directory'], _projectBRoot);
    expect(
      resultsB.single.arguments.values,
      everyElement(isNot(contains('content-owner-a'))),
    );
    expect(notifier.takeLatestToolResults(ownerB), isEmpty);

    releaseOwnerA.complete();
    final ownerA = await ownerAFuture;
    expect(ownerA, isNotNull);
    expect(ownerA!.conversationId, threadA);
    final resultsA = notifier.takeLatestToolResults(ownerA);
    expect(resultsA, hasLength(1));
    expect(resultsA.single.name, 'local_execute_command');
    expect(resultsA.single.arguments['command'], 'printf content-owner-a');
    expect(resultsA.single.arguments['working_directory'], _projectARoot);
    expect(
      resultsA.single.arguments.values,
      everyElement(isNot(contains('content-owner-b'))),
    );
    expect(notifier.takeLatestToolResults(ownerA), isEmpty);
    await _waitUntil(() => runtimeRepository.terminalEvents.length == 2);
    final runtimeFailures = runtimeRepository.terminalEvents
        .whereType<CavernoRuntimeRunFailed>()
        .toList(growable: false);
    expect(
      runtimeFailures,
      isEmpty,
      reason: runtimeFailures
          .map((event) => '${event.turnId}:${event.code}:${event.message}')
          .join('\n'),
    );
    expect(
      runtimeRepository.terminalEvents
          .whereType<CavernoRuntimeRunCompleted>()
          .map((event) => event.conversationId),
      containsAll(<String>[threadA, threadB]),
    );
    expect(notifier.state.busyConversationIds, isEmpty);
  });

  test(
    'detached owner waits for pending content tool before terminal event',
    () async {
      final executionStarted = Completer<void>();
      final releaseExecution = Completer<void>();
      final toolService = _GatedContentToolService(
        beforeExecute: (name, arguments) async {
          if (arguments['command'] != 'printf content-owner-a') return;
          if (!executionStarted.isCompleted) executionStarted.complete();
          await releaseExecution.future;
        },
      );
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: _ownerContentCommandCall(
              owner: 'a',
              projectRoot: _projectARoot,
            ),
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner B completed while A was detached.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner A completed after its content tool.',
            finishReason: 'stop',
          ),
        ],
      );
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!releaseExecution.isCompleted) releaseExecution.complete();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendMessage('Wait for owner A content.');
      await executionStarted.future.timeout(const Duration(seconds: 2));

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      await Future<void>.delayed(Duration.zero);
      final ownerB = await notifier
          .sendMessage('Finish owner B while A waits.')
          .timeout(const Duration(seconds: 2));
      expect(ownerB?.conversationId, threadB);
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == threadB,
        ),
      );

      expect(
        runtimeRepository.terminalEvents.where(
          (event) => event.conversationId == threadA,
        ),
        isEmpty,
        reason:
            'owner A must remain active until its queued content tool finishes',
      );

      releaseExecution.complete();
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
      expect(ownerA?.conversationId, threadA);
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == threadA,
        ),
      );

      expect(
        runtimeRepository.terminalEvents.map((event) => event.conversationId),
        [threadB, threadA],
      );
      expect(
        runtimeRepository.terminalEvents,
        everyElement(isA<CavernoRuntimeRunCompleted>()),
      );
    },
  );

  // H1: the two-thread contract expressed through the shared harness, across
  // all five surfaces at once. The neighbouring tests each assert one of them;
  // this one exists because a per-thread runtime proposal has to preserve the
  // combination, and a contract split across five tests can drift apart while
  // each half stays green.
  test(
    'two threads pause, switch, complete and resume with attributable state',
    () async {
      final executionStarted = Completer<void>();
      final releaseExecution = Completer<void>();
      final toolService = _GatedContentToolService(
        beforeExecute: (name, arguments) async {
          if (arguments['command'] != 'printf content-owner-a') return;
          if (!executionStarted.isCompleted) executionStarted.complete();
          await releaseExecution.future;
        },
      );
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: _ownerContentCommandCall(
              owner: 'a',
              projectRoot: _projectARoot,
            ),
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner B answered while A was paused.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Owner A resumed after its content tool.',
            finishReason: 'stop',
          ),
        ],
      );
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!releaseExecution.isCompleted) releaseExecution.complete();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      // Thread A pauses inside its content tool.
      final ownerAFuture = notifier.sendMessage('Wait for owner A content.');
      await executionStarted.future.timeout(const Duration(seconds: 2));
      final requestsBeforeSwitch = dataSource.ledger.length;

      // The user switches away and thread B runs to completion.
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      await Future<void>.delayed(Duration.zero);
      final ownerB = await notifier
          .sendMessage('Finish owner B while A waits.')
          .timeout(const Duration(seconds: 2));
      expect(ownerB?.conversationId, threadB);
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == threadB,
        ),
      );

      // Request surface: B's traffic is attributable to B, and A issued nothing
      // while paused.
      expect(
        dataSource.ledger.length,
        greaterThan(requestsBeforeSwitch),
        reason: 'thread B must have reached the model',
      );
      expect(
        dataSource.ledger.records
            .skip(requestsBeforeSwitch)
            .expand((record) => record.messages)
            .map((message) => message.content),
        contains(contains('Finish owner B while A waits.')),
      );

      // Event surface: B terminalizes first, A has not terminalized at all.
      expect(
        runtimeRepository.terminalEvents.where(
          (event) => event.conversationId == threadA,
        ),
        isEmpty,
        reason: 'a paused thread must not terminalize because another finished',
      );

      // UI surface: the visible thread is B and shows B's answer, while A's
      // pending work is not projected onto it.
      expect(
        notifier.state.messages.last.content,
        contains('Owner B answered'),
      );
      expect(
        notifier.state.messages.map((message) => message.content),
        isNot(contains(contains('Owner A resumed'))),
      );

      // Teardown surface: B released its turn state; A still holds its own.
      expect(
        notifier.turnStateIsClearedForTest(),
        isFalse,
        reason:
            'thread A is still mid-turn, so turn-local state must remain: '
            '${notifier.turnStateReportForTest()}',
      );

      // Thread A resumes and completes.
      releaseExecution.complete();
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
      expect(ownerA?.conversationId, threadA);
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == threadA,
        ),
      );

      // Event surface: ordering is B then A, and both completed.
      expect(
        runtimeRepository.terminalEvents.map((event) => event.conversationId),
        [threadB, threadA],
      );
      expect(
        runtimeRepository.terminalEvents,
        everyElement(isA<CavernoRuntimeRunCompleted>()),
      );

      // Tool surface: the gated content command ran exactly once, for A's
      // project. Content-embedded tool calls fold their output into the
      // continuation's message history rather than the tool-result methods, so
      // the ledger's evidence is the resumed request, not a toolResults entry.
      expect(
        toolService.executedArguments
            .where(
              (arguments) => arguments['command'] == 'printf content-owner-a',
            )
            .length,
        1,
        reason: 'ledger: ${dataSource.ledger}',
      );
      final resumed = dataSource.ledger.records.last;
      expect(resumed.call, ChatDataSourceCall.streamChatCompletion);
      expect(
        resumed.messages.map((message) => message.content),
        contains(contains('Wait for owner A content.')),
        reason: "A's resumed request must carry A's own history, not B's",
      );
      expect(
        resumed.messages.map((message) => message.content),
        isNot(contains(contains('Finish owner B while A waits.'))),
      );

      // Teardown surface: with both turns finished, every turn-local store is
      // released.
      await _waitUntil(() => notifier.turnStateIsClearedForTest());
      expect(
        notifier.turnStateIsClearedForTest(),
        isTrue,
        reason: notifier.turnStateReportForTest().toString(),
      );
    },
  );

  // H2: same-conversation replacement and stale-completion fencing, which is
  // where pilot-gate condition 3 -- reject stale completion by exact identity
  // -- becomes observable. A second message on a busy thread queues rather than
  // replacing, so replacement arrives through cancellation.
  test(
    'a cancelled turn cannot land after the same thread starts another',
    () async {
      final executionStarted = Completer<void>();
      final releaseExecution = Completer<void>();
      final toolService = _GatedContentToolService(
        beforeExecute: (name, arguments) async {
          if (arguments['command'] != 'printf content-owner-a') return;
          if (!executionStarted.isCompleted) executionStarted.complete();
          await releaseExecution.future;
        },
      );
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: _ownerContentCommandCall(
              owner: 'a',
              projectRoot: _projectARoot,
            ),
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Replacement turn answered.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'STALE: the cancelled turn resumed.',
            finishReason: 'stop',
          ),
        ],
      );
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!releaseExecution.isCompleted) releaseExecution.complete();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final thread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      final cancelledFuture = notifier.sendMessage('First attempt.');
      await executionStarted.future.timeout(const Duration(seconds: 2));

      // The user stops the turn while its tool is still resolving, then sends
      // again on the same conversation. That is the replacement.
      notifier.cancelStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isLoading, isFalse);

      final replacement = await notifier
          .sendMessage('Second attempt.')
          .timeout(const Duration(seconds: 2));
      expect(replacement?.conversationId, thread);
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == thread,
        ),
      );
      expect(
        notifier.state.messages.last.content,
        contains('Replacement turn answered.'),
      );

      // The cancelled turn now finishes its tool and resolves.
      releaseExecution.complete();
      await cancelledFuture.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Fencing, stated so it cannot pass vacuously. An earlier draft asserted
      // that the third scripted answer never appeared; the cancelled turn never
      // asks the model again, so that held for the wrong reason and survived a
      // disabled generation guard. What the cancelled turn does still do is
      // resolve its tool and return, so the contract is about that.
      expect(
        dataSource.initialRequests,
        2,
        reason:
            'the cancelled turn must not issue a further model request; a '
            'third would mean it resumed. ledger:\n${dataSource.ledger}',
      );
      expect(
        notifier.state.messages.map((message) => message.content),
        isNot(contains(contains('content-owner-a'))),
        reason: "a cancelled turn's tool output must not land afterwards",
      );
      expect(
        notifier.state.messages.map((message) => message.content),
        isNot(contains(contains('STALE:'))),
      );
      expect(
        notifier.state.messages.last.content,
        contains('Replacement turn answered.'),
        reason: "the replacement's answer stays the last word",
      );

      // Teardown: the stale turn released its state rather than leaving it for
      // the replacement to inherit.
      await _waitUntil(() => notifier.turnStateIsClearedForTest());
      expect(
        notifier.turnStateIsClearedForTest(),
        isTrue,
        reason: notifier.turnStateReportForTest().toString(),
      );
    },
  );

  test(
    'pending content result stays out of visible and hidden owner B turns',
    () async {
      for (final hiddenOwnerB in <bool>[false, true]) {
        final executionStarted = Completer<void>();
        final releaseExecution = Completer<void>();
        final toolService = _GatedContentToolService(
          beforeExecute: (name, arguments) async {
            if (arguments['command'] != 'printf content-owner-a') return;
            if (!executionStarted.isCompleted) executionStarted.complete();
            await releaseExecution.future;
          },
        );
        final dataSource = ScriptedChatDataSource(
          initialResponses: [
            ChatCompletionResult(
              content: _ownerContentCommandCall(
                owner: 'a',
                projectRoot: _projectARoot,
              ),
              finishReason: 'stop',
            ),
            ChatCompletionResult(
              content: 'Owner B completed without owner A evidence.',
              finishReason: 'stop',
            ),
            ChatCompletionResult(
              content: 'Owner A consumed its own content result.',
              finishReason: 'stop',
            ),
          ],
        );
        final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
        final container = _buildContainer(
          dataSource: dataSource,
          toolService: toolService,
          runtimeRepositoryPort: runtimeRepository,
        );

        try {
          final conversations = container.read(
            conversationsNotifierProvider.notifier,
          );
          conversations.createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
          final notifier = container.read(chatNotifierProvider.notifier);
          final ownerAToken =
              'OWNER_A_PENDING_CONTENT_${hiddenOwnerB ? "HIDDEN" : "VISIBLE"}';
          final ownerAFuture = notifier.sendMessage(ownerAToken);
          await executionStarted.future.timeout(const Duration(seconds: 2));

          conversations.createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
          final threadB = container
              .read(conversationsNotifierProvider)
              .currentConversationId!;
          await Future<void>.delayed(Duration.zero);
          final ownerBToken =
              'OWNER_B_${hiddenOwnerB ? "HIDDEN" : "VISIBLE"}_TOKEN';
          final ownerBFuture = hiddenOwnerB
              ? notifier.sendHiddenPrompt(ownerBToken)
              : notifier.sendMessage(ownerBToken);
          final ownerB = await ownerBFuture.timeout(const Duration(seconds: 2));
          expect(ownerB?.conversationId, threadB);
          await _waitUntil(
            () => runtimeRepository.terminalEvents.any(
              (event) => event.conversationId == threadB,
            ),
          );

          final ownerBRequests = dataSource.streamedRequestMessages.where(
            (messages) => messages.any(
              (message) => message.content.contains(ownerBToken),
            ),
          );
          expect(ownerBRequests, hasLength(1));
          expect(
            ownerBRequests.single,
            isNot(
              contains(
                predicate<Message>(
                  (message) =>
                      message.content.contains('content-owner-a') ||
                      message.content.contains('Content command completed.'),
                ),
              ),
            ),
          );

          releaseExecution.complete();
          final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
          expect(ownerA, isNotNull);
          final threadA = ownerA!.conversationId;
          await _waitUntil(
            () => dataSource.streamedRequestMessages.any(
              (messages) => messages.any(
                (message) => message.content.contains(
                  'Continue the task using the following tool results.',
                ),
              ),
            ),
          );
          final contentContinuations = dataSource.streamedRequestMessages.where(
            (messages) => messages.any(
              (message) => message.content.contains(
                'Continue the task using the following tool results.',
              ),
            ),
          );
          expect(contentContinuations, hasLength(1));
          final continuationMessages = contentContinuations.single;
          expect(
            continuationMessages.any(
              (message) => message.content.contains(ownerAToken),
            ),
            isTrue,
          );
          expect(
            continuationMessages.any(
              (message) => message.content.contains('content-owner-a'),
            ),
            isTrue,
          );
          expect(
            continuationMessages.any(
              (message) => message.content.contains(ownerBToken),
            ),
            isFalse,
          );
          await _waitUntil(
            () => runtimeRepository.terminalEvents.any(
              (event) => event.conversationId == threadA,
            ),
          );
          expect(
            runtimeRepository.terminalEvents.singleWhere(
              (event) => event.conversationId == threadA,
            ),
            isA<CavernoRuntimeRunCompleted>(),
          );
        } finally {
          if (!releaseExecution.isCompleted) releaseExecution.complete();
          container.dispose();
        }
      }
    },
  );

  test(
    'complete embedded tool tag arriving after detach executes once for A',
    () async {
      const ownerAPrompt = 'Wait for detached owner A embedded tool.';
      const ownerBPrompt = 'Finish owner B before the embedded tool arrives.';
      const ownerBResponse = 'OWNER_B_BEFORE_DETACHED_EMBEDDED_TOOL';
      const ownerAContinuation = 'OWNER_A_AFTER_DETACHED_EMBEDDED_TOOL';
      final ownerAStream = StreamController<String>();
      final embeddedToolCall =
          '<tool_call>${jsonEncode({
            'name': 'list_directory',
            'arguments': {'path': 'lib'},
          })}</tool_call>';
      final model = AppSettings.defaults().model;
      final dataSource = _ParticipantOwnershipDataSource()
        ..queueTool(
          model,
          _ParticipantToolReply(
            stream: ownerAStream.stream,
            completion: ChatCompletionResult(content: '', finishReason: 'stop'),
          ),
        )
        ..queueTool(
          model,
          _ParticipantToolReply(
            chunks: const [ownerBResponse],
            completion: ChatCompletionResult(
              content: ownerBResponse,
              finishReason: 'stop',
            ),
          ),
        )
        ..queuePlain(model, Stream<String>.value(ownerAContinuation));
      final toolService = _GatedContentToolService();
      final runtimeEvents = <CavernoRuntimeEvent>[];
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        assistantMode: AssistantMode.general,
      );
      final runtimeSubscription = container
          .read(cavernoExecutionRuntimeProvider)
          .events
          .listen(runtimeEvents.add);
      addTearDown(() async {
        if (!ownerAStream.isClosed) await ownerAStream.close();
        await runtimeSubscription.cancel();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendMessage(ownerAPrompt);
      await _waitUntil(() => dataSource.toolRequests.length == 1);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final ownerB = await notifier
          .sendMessage(ownerBPrompt)
          .timeout(const Duration(seconds: 2));
      expect(ownerB?.conversationId, threadB);
      await _waitUntil(
        () => runtimeEvents.whereType<CavernoRuntimeTerminalEvent>().any(
          (event) => event.conversationId == threadB,
        ),
      );
      await notifier.flushPendingPersistence();
      final persistedBBeforeTool = List<Message>.from(
        container
            .read(conversationsNotifierProvider)
            .conversations
            .singleWhere((conversation) => conversation.id == threadB)
            .messages,
      );

      ownerAStream.add(embeddedToolCall);
      await ownerAStream.close();
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 2));
      expect(ownerA?.conversationId, threadA);
      await _waitUntil(
        () => runtimeEvents.whereType<CavernoRuntimeTerminalEvent>().any(
          (event) => event.conversationId == threadA,
        ),
      );
      await notifier.flushPendingPersistence();

      expect(toolService.executedNames, ['list_directory']);
      expect(toolService.executedArguments, hasLength(1));
      final executedPath = toolService.executedArguments.single['path']
          .toString()
          .replaceAll(r'\', '/');
      expect(executedPath, startsWith(_projectARoot));
      expect(executedPath, isNot(contains(_projectBRoot)));
      expect(notifier.takeLatestToolResults(ownerA!), hasLength(1));
      expect(notifier.takeLatestToolResults(ownerB!), isEmpty);

      final persisted = container
          .read(conversationsNotifierProvider)
          .conversations;
      final persistedA = persisted.singleWhere(
        (conversation) => conversation.id == threadA,
      );
      final persistedB = persisted.singleWhere(
        (conversation) => conversation.id == threadB,
      );
      expect(
        persistedA.messages.map((message) => message.content).join('\n'),
        contains(ownerAContinuation),
      );
      expect(persistedB.messages, persistedBBeforeTool);
      expect(notifier.conversationId, threadB);
      expect(
        notifier.state.messages.map((message) => message.content),
        containsAllInOrder([ownerBPrompt, ownerBResponse]),
      );

      final terminalEvents = runtimeEvents
          .whereType<CavernoRuntimeTerminalEvent>()
          .toList(growable: false);
      expect(
        terminalEvents.where((event) => event.conversationId == threadA),
        hasLength(1),
      );
      expect(
        terminalEvents.where((event) => event.conversationId == threadB),
        hasLength(1),
      );
    },
  );

  test(
    'detached relative-path native and embedded calls share owner A dedupe',
    () async {
      final releaseOwnerA = Completer<void>();
      CavernoRuntimeRunStarted? startedOwnerA;
      final lifecyclePort = _CallbackRuntimeLifecyclePort((event) {
        startedOwnerA = event;
      });
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Owner A remains active for dedupe inspection.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (_) => releaseOwnerA.future,
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _GatedContentToolService(),
        runtimeLifecyclePort: lifecyclePort,
      );
      addTearDown(() {
        if (!releaseOwnerA.isCompleted) releaseOwnerA.complete();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendMessage('Hold owner A dedupe state.');
      await _waitUntil(
        () => startedOwnerA != null && dataSource.initialRequests == 1,
      );
      final generation = int.parse(
        startedOwnerA!.turnId.substring('gen-'.length),
      );
      final ownerA = ChatTurnOwner(
        conversationId: threadA,
        interactionGeneration: generation,
      );
      const relativeArguments = <String, dynamic>{'path': 'lib'};
      final markEmbeddedReplay = notifier
          .markNativeThenEmbeddedContentDedupeForTest(
            ownerA,
            const ToolCallData(
              name: 'list_directory',
              arguments: relativeArguments,
            ),
          );

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      expect(
        container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.normalizedProjectId,
        'project-b',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        markEmbeddedReplay(),
        isFalse,
        reason:
            'the embedded replay must normalize against owner A, matching the '
            'native call recorded before project B became visible',
      );

      releaseOwnerA.complete();
      expect(
        (await ownerAFuture.timeout(
          const Duration(seconds: 2),
        ))?.conversationId,
        threadA,
      );
    },
  );

  test(
    'late cancelled owner A artifact callback cannot persist under owner B',
    () async {
      final ownerAStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(AppSettings.defaults().model, ownerAStream.stream);
      final artifactStore = _RecordingToolResultArtifactStore();
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _NoToolService(),
        toolResultArtifactStore: artifactStore,
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() async {
        if (!artifactStore.releasePersist.isCompleted) {
          artifactStore.releasePersist.complete();
        }
        if (!ownerAStream.isClosed) await ownerAStream.close();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerA = await notifier
          .sendMessage('Keep owner A open for a late artifact callback.')
          .timeout(const Duration(seconds: 2));
      expect(ownerA?.conversationId, threadA);

      final largeResult = ToolResultInfo(
        id: 'late-owner-a-large-result',
        name: 'list_directory',
        arguments: const <String, dynamic>{'path': 'lib'},
        result: List<String>.filled(
          ToolResultArtifactStore.defaultPersistenceThresholdChars + 1,
          'x',
        ).join(),
      );
      final latePersistence = notifier.persistToolResultForPromptForTest(
        largeResult,
        ownerA!,
      );
      await artifactStore.persistStarted.future.timeout(
        const Duration(seconds: 2),
      );
      expect(artifactStore.conversationIds, [threadA]);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      conversations.selectConversation(threadA);
      await Future<void>.delayed(Duration.zero);
      notifier.cancelStreaming();
      conversations.selectConversation(threadB);
      await Future<void>.delayed(Duration.zero);

      artifactStore.releasePersist.complete();
      expect(await latePersistence.timeout(const Duration(seconds: 2)), isNull);
      expect(artifactStore.results, [same(largeResult)]);
      expect(artifactStore.conversationIds, [threadA]);
      expect(artifactStore.conversationIds, isNot(contains(threadB)));
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == threadA,
        ),
      );
      expect(
        runtimeRepository.terminalEvents.singleWhere(
          (event) => event.conversationId == threadA,
        ),
        isA<CavernoRuntimeRunFailed>(),
      );
    },
  );

  test(
    'next same-conversation turn retains earlier evidence until exact take',
    () async {
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          _ownerCommandToolCall(owner: 'first', projectRoot: _projectARoot),
          _ownerCommandToolCall(owner: 'second', projectRoot: _projectARoot),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'First command output recorded.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Second command output recorded.',
            finishReason: 'stop',
          ),
        ],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SavedWorkflowToolService(),
      );
      addTearDown(container.dispose);

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      final notifier = container.read(chatNotifierProvider.notifier);

      final firstOwner = await notifier.sendMessage('Collect first evidence.');
      final secondOwner = await notifier.sendMessage(
        'Collect second evidence.',
      );

      expect(firstOwner, isNotNull);
      expect(secondOwner, isNotNull);
      expect(firstOwner!.conversationId, secondOwner!.conversationId);
      expect(
        firstOwner.interactionGeneration,
        isNot(secondOwner.interactionGeneration),
      );

      final firstResults = notifier.takeLatestToolResults(firstOwner);
      final secondResults = notifier.takeLatestToolResults(secondOwner);
      expect(firstResults.map((result) => result.id), ['command-first']);
      expect(firstResults.single.arguments['command'], 'printf owner-first');
      expect(secondResults.map((result) => result.id), ['command-second']);
      expect(secondResults.single.arguments['command'], 'printf owner-second');
      expect(notifier.takeLatestToolResults(firstOwner), isEmpty);
      expect(notifier.takeLatestToolResults(secondOwner), isEmpty);
    },
  );

  test(
    'queued send returns its eventual owner and exact tool evidence',
    () async {
      final releaseFirst = Completer<void>();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'First turn complete.',
            finishReason: 'stop',
          ),
          _ownerCommandToolCall(owner: 'queued', projectRoot: _projectARoot),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'Queued command output recorded.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (requestIndex) async {
          if (requestIndex == 0) await releaseFirst.future;
        },
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SavedWorkflowToolService(),
      );
      addTearDown(() {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        container.dispose();
      });

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstOwnerFuture = notifier.sendMessage('Hold the first turn.');
      await _waitUntil(() => dataSource.initialRequests == 1);

      var queuedOwnerCompleted = false;
      final queuedOwnerFuture = notifier.sendMessage(
        'Collect queued evidence.',
      );
      unawaited(
        queuedOwnerFuture.then((_) {
          queuedOwnerCompleted = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(queuedOwnerCompleted, isFalse);

      releaseFirst.complete();
      final firstOwner = await firstOwnerFuture;
      final queuedOwner = await queuedOwnerFuture.timeout(
        const Duration(seconds: 2),
      );
      expect(firstOwner, isNotNull);
      expect(queuedOwner, isNotNull);
      expect(queuedOwner!.conversationId, firstOwner!.conversationId);
      expect(
        queuedOwner.interactionGeneration,
        isNot(firstOwner.interactionGeneration),
      );

      final queuedResults = notifier.takeLatestToolResults(queuedOwner);
      expect(queuedResults.map((result) => result.id), ['command-queued']);
      expect(queuedResults.single.arguments['command'], 'printf owner-queued');
      expect(
        queuedResults.single.arguments['working_directory'],
        _projectARoot,
      );
      expect(notifier.takeLatestToolResults(queuedOwner), isEmpty);
    },
  );

  test(
    'queued send failure completes its owner receipt without hanging',
    () async {
      final releaseFirst = Completer<void>();
      final conversationsNotifier = _FailingQueuedSendConversationsNotifier();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'First turn complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Queued turn should not reach the model.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (requestIndex) async {
          if (requestIndex == 0) await releaseFirst.future;
        },
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SavedWorkflowToolService(),
        conversationsNotifierFactory: () => conversationsNotifier,
      );
      addTearDown(() {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        container.dispose();
      });

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstOwnerFuture = notifier.sendMessage('Hold the first turn.');
      await _waitUntil(() => dataSource.initialRequests == 1);
      final queuedOwnerFuture = notifier.sendMessage(
        'Fail before queued send.',
      );

      conversationsNotifier.failNextPlanBackfill = true;
      releaseFirst.complete();
      expect(await firstOwnerFuture, isNotNull);
      expect(
        await queuedOwnerFuture.timeout(const Duration(seconds: 2)),
        isNull,
      );
      expect(dataSource.initialRequests, 1);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(notifier.state.queuedMessages, isEmpty);
      expect(notifier.state.error, contains('queued plan backfill failed'));
    },
  );

  test(
    'queued runtime start failure dequeues and resolves its receipt',
    () async {
      final releaseFirst = Completer<void>();
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'First turn complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Rejected queued turn.',
            finishReason: 'stop',
          ),
        ],
        beforeInitialResponse: (requestIndex) async {
          if (requestIndex == 0) await releaseFirst.future;
        },
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SavedWorkflowToolService(),
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        container.dispose();
      });

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstOwnerFuture = notifier.sendMessage('Hold the first turn.');
      await _waitUntil(() => dataSource.initialRequests == 1);
      final queuedOwnerFuture = notifier.sendMessage('Reject queued start.');

      runtimeRepository.rejectNextRefresh = true;
      releaseFirst.complete();
      expect(await firstOwnerFuture, isNotNull);
      expect(
        await queuedOwnerFuture.timeout(const Duration(seconds: 2)),
        isNull,
      );
      expect(dataSource.initialRequests, 1);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(notifier.state.queuedMessages, isEmpty);
    },
  );

  test('post-finalization persistence failure cannot requeue a turn', () async {
    final releaseFirst = Completer<void>();
    final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: 'First turn complete.',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content: 'Queued final response.',
          finishReason: 'stop',
        ),
      ],
      beforeInitialResponse: (requestIndex) async {
        if (requestIndex == 0) await releaseFirst.future;
      },
    );
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _SavedWorkflowToolService(),
      runtimeRepositoryPort: runtimeRepository,
      beforeConversationPut: (encoded) async {
        if (encoded.contains('Queued final response.')) {
          throw StateError('queued final persistence failed');
        }
      },
    );
    addTearDown(() {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      container.dispose();
    });

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );
    final notifier = container.read(chatNotifierProvider.notifier);
    final firstOwnerFuture = notifier.sendMessage('Hold the first turn.');
    await _waitUntil(() => dataSource.initialRequests == 1);
    final queuedOwnerFuture = notifier.sendMessage('Fail after finalization.');

    releaseFirst.complete();
    final firstOwner = await firstOwnerFuture;
    final queuedOwner = await queuedOwnerFuture.timeout(
      const Duration(seconds: 2),
    );
    expect(firstOwner, isNotNull);
    expect(queuedOwner, isNotNull);
    expect(
      queuedOwner!.interactionGeneration,
      isNot(firstOwner!.interactionGeneration),
    );
    await _waitUntil(
      () => runtimeRepository.terminalEvents
          .whereType<CavernoRuntimeRunFailed>()
          .isNotEmpty,
    );
    expect(dataSource.initialRequests, 2);
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.busyConversationIds, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
    expect(
      runtimeRepository.terminalEvents.whereType<CavernoRuntimeRunFailed>().map(
        (event) => event.turnId,
      ),
      ['gen-${queuedOwner.interactionGeneration}'],
    );
  });

  test('a hidden-prompt turn survives the user switching threads', () async {
    // sendHiddenPrompt used to skip the tracking _sendMessageNow does, so an
    // auto-continue turn was not an active response. Switching threads then
    // ran the conversation-change reset over it: the generation was bumped and
    // the turn was cancelled *after* its tools had already run, discarding the
    // work, and its requests logged under the newly visible thread.
    late final ProviderContainer container;
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-list',
              name: 'list_directory',
              arguments: const {'path': 'bin'},
            ),
          ],
        ),
      ],
      toolResultResponses: [
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ],
      // The loop re-sends tool results as a user-role message and streams the
      // answer from a third call; scripting only the first two would assert
      // against the harness's `done` fallback.
      streamedResponses: [
        ChatCompletionResult(
          content: 'ANSWER-BELONGING-TO-THREAD-A',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _SwitchingToolService(() async {
      // The user opens another thread while the hidden turn's tool runs. No
      // new turn starts, so thread A's generation is still the current one.
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);

    // The real hidden continuation is goal auto-continue
    // (chat_notifier_goal_auto_continue.dart:645), which persists its answer.
    // Without the flag the answer lands nowhere, and thread B is empty whether
    // the turn survived or was discarded -- attribution is then unobservable.
    await notifier.sendHiddenPrompt(
      'keep going on thread A',
      persistAssistantResponse: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      toolService.executions,
      greaterThan(0),
      reason: 'the tool has to run for the thread switch to interleave',
    );
    // Sharper than counting completions: the ledger says the tool result
    // reached a follow-up request, and which tool it carried. A turn discarded
    // at the switch records the first request and nothing after it.
    expect(
      dataSource.toolResultRequests,
      greaterThanOrEqualTo(1),
      reason:
          'the tool ran, so its result has to reach a follow-up request '
          'instead of being discarded when the user switched threads',
    );
    expect(
      dataSource.toolResultToolNames.expand((names) => names),
      contains('list_directory'),
      reason: 'the follow-up must carry the result of the tool that ran',
    );
    final visibleContent = container
        .read(chatNotifierProvider)
        .messages
        .map((message) => message.content)
        .join('\n');
    expect(
      visibleContent,
      isNot(contains('ANSWER-BELONGING-TO-THREAD-A')),
      reason:
          'the background turn must not append its answer to the thread the '
          'user switched to',
    );

    // Absence alone passes just as well when the answer was discarded, because
    // thread B is empty either way. Say positively where the answer went, or
    // the scenario cannot tell attribution from loss.
    container.read(conversationsNotifierProvider.notifier).selectConversation(
      threadA,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container
          .read(chatNotifierProvider)
          .messages
          .map((message) => message.content)
          .join('\n'),
      contains('ANSWER-BELONGING-TO-THREAD-A'),
      reason: 'the answer belongs to the thread whose turn produced it',
    );
  });

  test('queued work drains only for its visible idle owner', () async {
    final dataSource = _GatedQueueDataSource();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);

    final firstA = notifier.sendMessage('a-first');
    await dataSource
        .waitForRequest('a-first')
        .timeout(const Duration(seconds: 2));
    unawaited(notifier.sendMessage('a-queued-1'));
    unawaited(notifier.sendMessage('a-queued-2'));

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    expect(
      notifier.state.queuedMessages,
      isEmpty,
      reason: 'thread B must not project thread A queued work',
    );

    final firstB = notifier.sendMessage('b-first');
    await dataSource
        .waitForRequest('b-first')
        .timeout(const Duration(seconds: 2));
    unawaited(notifier.sendMessage('b-queued-1'));
    unawaited(notifier.sendMessage('b-queued-2'));

    dataSource.release('a-first');
    await firstA;

    expect(
      dataSource.requestCount('a-queued-1'),
      0,
      reason:
          'finishing detached A must not run A work through visible B state',
    );
    expect(notifier.state.queuedMessages.map((message) => message.content), [
      'b-queued-1',
      'b-queued-2',
    ]);

    dataSource.release('b-first');
    await dataSource
        .waitForRequest('b-queued-1')
        .timeout(const Duration(seconds: 2));
    expect(dataSource.requestCount('a-queued-1'), 0);
    final queuedBRequest = dataSource.singleRequest('b-queued-1');
    expect(queuedBRequest.systemPrompt, contains(_projectBRoot));
    expect(queuedBRequest.systemPrompt, isNot(contains(_projectARoot)));
    dataSource.release('b-queued-1');
    await dataSource
        .waitForRequest('b-queued-2')
        .timeout(const Duration(seconds: 2));
    dataSource.release('b-queued-2');
    await firstB;

    conversations.selectConversation(threadA);
    expect(
      notifier.state.queuedMessages.map((message) => message.content),
      ['a-queued-1', 'a-queued-2'],
      reason: 'selecting idle A must first restore its exact FIFO projection',
    );
    await dataSource
        .waitForRequest('a-queued-1')
        .timeout(const Duration(seconds: 2));
    final queuedARequest = dataSource.singleRequest('a-queued-1');
    expect(queuedARequest.systemPrompt, contains(_projectARoot));
    expect(queuedARequest.systemPrompt, isNot(contains(_projectBRoot)));
    expect(
      queuedARequest.nonSystemContents,
      containsAll(['a-first', 'reply:a-first', 'a-queued-1']),
    );
    expect(queuedARequest.nonSystemContents, isNot(contains('b-first')));
    dataSource.release('a-queued-1');
    await dataSource
        .waitForRequest('a-queued-2')
        .timeout(const Duration(seconds: 2));
    dataSource.release('a-queued-2');
    await _waitUntil(
      () => !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
    );
    await notifier.flushPendingPersistence();

    expect(
      dataSource.requests
          .map((request) => request.userPrompt)
          .where((prompt) => prompt.startsWith('a-')),
      ['a-first', 'a-queued-1', 'a-queued-2'],
    );
    expect(
      dataSource.requests
          .map((request) => request.userPrompt)
          .where((prompt) => prompt.startsWith('b-')),
      ['b-first', 'b-queued-1', 'b-queued-2'],
    );
    final persisted = container
        .read(conversationsNotifierProvider)
        .conversations;
    final persistedA = persisted.firstWhere(
      (conversation) => conversation.id == threadA,
    );
    final persistedB = persisted.firstWhere(
      (conversation) => conversation.id == threadB,
    );
    expect(
      persistedA.messages.map((message) => message.content),
      containsAllInOrder([
        'a-first',
        'reply:a-first',
        'a-queued-1',
        'reply:a-queued-1',
        'a-queued-2',
        'reply:a-queued-2',
      ]),
    );
    expect(
      persistedB.messages.map((message) => message.content),
      containsAllInOrder([
        'b-first',
        'reply:b-first',
        'b-queued-1',
        'reply:b-queued-1',
        'b-queued-2',
        'reply:b-queued-2',
      ]),
    );
  });

  test(
    'switching during ownership settlement keeps queued work with its owner',
    () async {
      final dataSource = _GatedQueueDataSource();
      final runtimeRepository = _GatedRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!runtimeRepository.releaseFlush.isCompleted) {
          runtimeRepository.releaseFlush.complete();
        }
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstA = notifier.sendMessage('settled-a-first');
      await dataSource
          .waitForRequest('settled-a-first')
          .timeout(const Duration(seconds: 2));
      unawaited(notifier.sendMessage('settled-a-queued'));
      dataSource.release('settled-a-first');
      await runtimeRepository.flushStarted.future.timeout(
        const Duration(seconds: 2),
      );

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      runtimeRepository.releaseFlush.complete();
      await firstA;

      expect(dataSource.requestCount('settled-a-queued'), 0);
      expect(
        notifier.state.queuedMessages,
        isEmpty,
        reason: 'visible B must not project A work after the post-wait check',
      );

      conversations.selectConversation(threadA);
      expect(notifier.state.queuedMessages.map((message) => message.content), [
        'settled-a-queued',
      ]);
      await dataSource
          .waitForRequest('settled-a-queued')
          .timeout(const Duration(seconds: 2));
      dataSource.release('settled-a-queued');
      await _waitUntil(
        () =>
            !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
      );
      expect(dataSource.requestCount('settled-a-queued'), 1);
    },
  );

  test(
    'fresh same-owner work queues behind a dequeued settling item',
    () async {
      final dataSource = _GatedQueueDataSource();
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!runtimeRepository.releaseRefresh.isCompleted) {
          runtimeRepository.releaseRefresh.complete();
        }
        if (!runtimeRepository.releaseFlush.isCompleted) {
          runtimeRepository.releaseFlush.complete();
        }
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstA = notifier.sendMessage('fifo-first');
      await dataSource
          .waitForRequest('fifo-first')
          .timeout(const Duration(seconds: 2));
      unawaited(notifier.sendMessage('fifo-old'));

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      dataSource.release('fifo-first');
      await firstA;

      runtimeRepository.gateNextRefresh = true;
      conversations.selectConversation(threadA);
      await runtimeRepository.refreshStarted.future.timeout(
        const Duration(seconds: 2),
      );
      unawaited(notifier.sendMessage('fifo-fresh'));

      expect(dataSource.requestCount('fifo-old'), 0);
      expect(dataSource.requestCount('fifo-fresh'), 0);
      expect(notifier.state.queuedMessages.map((message) => message.content), [
        'fifo-fresh',
      ]);

      runtimeRepository.releaseRefresh.complete();
      runtimeRepository.releaseFlush.complete();
      await dataSource
          .waitForRequest('fifo-old')
          .timeout(const Duration(seconds: 2));
      dataSource.release('fifo-old');
      await dataSource
          .waitForRequest('fifo-fresh')
          .timeout(const Duration(seconds: 2));
      dataSource.release('fifo-fresh');
      await _waitUntil(
        () =>
            !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
      );

      expect(
        dataSource.requests
            .map((request) => request.userPrompt)
            .where((prompt) => prompt.startsWith('fifo-')),
        ['fifo-first', 'fifo-old', 'fifo-fresh'],
      );
    },
  );

  test('a rejected queued runtime start cannot be resurrected', () async {
    final dataSource = _GatedQueueDataSource();
    final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
      runtimeRepositoryPort: runtimeRepository,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    final notifier = container.read(chatNotifierProvider.notifier);
    final firstA = notifier.sendMessage('reject-first');
    await dataSource
        .waitForRequest('reject-first')
        .timeout(const Duration(seconds: 2));
    final queuedOwnerFuture = notifier.sendMessage('reject-queued');

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    dataSource.release('reject-first');
    await firstA;

    runtimeRepository.rejectNextRefresh = true;
    conversations.selectConversation(threadA);
    expect(await queuedOwnerFuture.timeout(const Duration(seconds: 2)), isNull);
    expect(notifier.state.queuedMessages, isEmpty);
    expect(dataSource.requestCount('reject-queued'), 0);

    conversations.selectConversation(threadB);
    conversations.selectConversation(threadA);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.queuedMessages, isEmpty);
    expect(dataSource.requestCount('reject-queued'), 0);
  });

  test(
    'switching during queued runtime start restores the owner FIFO',
    () async {
      final dataSource = _GatedQueueDataSource();
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!runtimeRepository.releaseRefresh.isCompleted) {
          runtimeRepository.releaseRefresh.complete();
        }
        if (!runtimeRepository.releaseFlush.isCompleted) {
          runtimeRepository.releaseFlush.complete();
        }
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final firstA = notifier.sendMessage('runtime-a-first');
      await dataSource
          .waitForRequest('runtime-a-first')
          .timeout(const Duration(seconds: 2));
      final queuedOwner1Future = notifier.sendMessage('runtime-a-queued-1');
      final queuedOwner2Future = notifier.sendMessage('runtime-a-queued-2');

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      dataSource.release('runtime-a-first');
      await firstA;

      runtimeRepository.gateNextRefresh = true;
      conversations.selectConversation(threadA);
      await runtimeRepository.refreshStarted.future.timeout(
        const Duration(seconds: 2),
      );
      conversations.selectConversation(threadB);
      runtimeRepository.releaseRefresh.complete();

      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) =>
              event is CavernoRuntimeRunFailed &&
              event.code == 'turn_cancelled_before_start',
        ),
      );
      await runtimeRepository.flushStarted.future.timeout(
        const Duration(seconds: 2),
      );

      expect(
        dataSource.requestCount('runtime-a-queued-1'),
        0,
        reason:
            'the owner changed before request assembly, so A must be restored '
            'instead of submitted with B state',
      );
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.queuedMessages, isEmpty);
      final failed = runtimeRepository.terminalEvents
          .whereType<CavernoRuntimeRunFailed>()
          .singleWhere((event) => event.code == 'turn_cancelled_before_start');
      expect(failed.conversationId, threadA);
      // A turn that failed to start must leave no release scope behind. The
      // scope is now registered before the acquisition guards, so this is the
      // path where a stranded registration would first appear.
      expect(
        notifier.turnStateIsClearedForTest(),
        isTrue,
        reason: notifier.turnStateReportForTest().toString(),
      );
      var firstReceiptCompleted = false;
      unawaited(
        queuedOwner1Future.then((_) {
          firstReceiptCompleted = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        firstReceiptCompleted,
        isFalse,
        reason: 'a restored queued item must keep its original receipt pending',
      );
      runtimeRepository.releaseFlush.complete();

      conversations.selectConversation(threadA);
      expect(
        notifier.state.queuedMessages.map((message) => message.content),
        ['runtime-a-queued-1', 'runtime-a-queued-2'],
        reason: 'the dequeued item must be restored at the front',
      );
      await dataSource
          .waitForRequest('runtime-a-queued-1')
          .timeout(const Duration(seconds: 2));
      dataSource.release('runtime-a-queued-1');
      await dataSource
          .waitForRequest('runtime-a-queued-2')
          .timeout(const Duration(seconds: 2));
      dataSource.release('runtime-a-queued-2');
      await _waitUntil(
        () =>
            !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
      );
      final queuedOwner1 = await queuedOwner1Future.timeout(
        const Duration(seconds: 2),
      );
      final queuedOwner2 = await queuedOwner2Future.timeout(
        const Duration(seconds: 2),
      );
      expect(queuedOwner1?.conversationId, threadA);
      expect(queuedOwner2?.conversationId, threadA);
      expect(
        queuedOwner1?.interactionGeneration,
        isNot(queuedOwner2?.interactionGeneration),
      );
      await notifier.flushPendingPersistence();

      expect(dataSource.requestCount('runtime-a-queued-1'), 1);
      expect(dataSource.requestCount('runtime-a-queued-2'), 1);
      expect(
        dataSource.singleRequest('runtime-a-queued-1').systemPrompt,
        allOf(contains(_projectARoot), isNot(contains(_projectBRoot))),
      );
      final persistedB = container
          .read(conversationsNotifierProvider)
          .conversations
          .firstWhere((conversation) => conversation.id == threadB);
      expect(persistedB.messages, isEmpty);
    },
  );

  test(
    'direct owner change after runtime start keeps its receipt pending',
    () async {
      final dataSource = _GatedQueueDataSource();
      late ProviderContainer container;
      var switchedAtRuntimeStart = false;
      final lifecyclePort = _CallbackRuntimeLifecyclePort((_) {
        if (switchedAtRuntimeStart) return;
        switchedAtRuntimeStart = true;
        container.read(chatNotifierProvider.notifier).conversationId =
            'foreign-during-runtime-start';
      });
      container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        runtimeLifecyclePort: lifecyclePort,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerFuture = notifier.sendMessage('post-start-owner-change');
      await _waitUntil(() => switchedAtRuntimeStart);
      await Future<void>.delayed(Duration.zero);

      expect(dataSource.requestCount('post-start-owner-change'), 0);
      expect(notifier.conversationId, isNot(threadA));
      expect(
        lifecyclePort.terminalEvents
            .whereType<CavernoRuntimeRunFailed>()
            .single
            .code,
        'queue_owner_changed',
      );
      var receiptCompleted = false;
      unawaited(
        ownerFuture.then((_) {
          receiptCompleted = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(receiptCompleted, isFalse);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      conversations.selectConversation(threadA);
      expect(
        notifier.state.queuedMessages.single.content,
        'post-start-owner-change',
      );
      await dataSource
          .waitForRequest('post-start-owner-change')
          .timeout(const Duration(seconds: 2));
      dataSource.release('post-start-owner-change');
      final restoredOwner = await ownerFuture.timeout(
        const Duration(seconds: 2),
      );

      expect(restoredOwner?.conversationId, threadA);
      expect(dataSource.requestCount('post-start-owner-change'), 1);
    },
  );

  test(
    'switching during planning entry terminalizes the pre-tracked runtime',
    () async {
      final planningPersistenceStarted = Completer<void>();
      final releasePlanningPersistence = Completer<void>();
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort();
      final dataSource = _GatedQueueDataSource();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        assistantMode: AssistantMode.plan,
        runtimeRepositoryPort: runtimeRepository,
        beforeConversationPut: (encoded) async {
          final payload = jsonDecode(encoded) as Map<String, dynamic>;
          if (payload['executionMode'] != 'planning') return;
          if (!planningPersistenceStarted.isCompleted) {
            planningPersistenceStarted.complete();
          }
          await releasePlanningPersistence.future;
        },
      );
      addTearDown(() {
        if (!releasePlanningPersistence.isCompleted) {
          releasePlanningPersistence.complete();
        }
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerFuture = notifier.sendMessage('Enter planning for owner A.');
      await planningPersistenceStarted.future.timeout(
        const Duration(seconds: 2),
      );

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      await Future<void>.delayed(Duration.zero);
      releasePlanningPersistence.complete();
      final owner = await ownerFuture.timeout(const Duration(seconds: 2));

      expect(owner?.conversationId, threadA);
      expect(dataSource.requestCount('Enter planning for owner A.'), 0);
      await _waitUntil(
        () => runtimeRepository.terminalEvents.any(
          (event) => event.conversationId == threadA,
        ),
      );
      final terminal = runtimeRepository.terminalEvents.singleWhere(
        (event) => event.conversationId == threadA,
      );
      expect(terminal, isA<CavernoRuntimeRunFailed>());
      expect(
        (terminal as CavernoRuntimeRunFailed).code,
        'turn_cancelled_before_start',
      );
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(
        container.read(cavernoExecutionRuntimeProvider).hasActiveTurns,
        isFalse,
      );
    },
  );

  test(
    'switching during a null-owned draft start restores it to the new owner',
    () async {
      final dataSource = _GatedQueueDataSource();
      final runtimeRepository = _GatedRefreshRuntimeRepositoryPort()
        ..gateNextRefresh = true;
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        runtimeRepositoryPort: runtimeRepository,
      );
      addTearDown(() {
        if (!runtimeRepository.releaseRefresh.isCompleted) {
          runtimeRepository.releaseRefresh.complete();
        }
        if (!runtimeRepository.releaseFlush.isCompleted) {
          runtimeRepository.releaseFlush.complete();
        }
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final draftSend = notifier.sendMessage('runtime-null-draft');
      await runtimeRepository.refreshStarted.future.timeout(
        const Duration(seconds: 2),
      );
      final draftOwner = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      runtimeRepository.releaseRefresh.complete();
      await runtimeRepository.flushStarted.future.timeout(
        const Duration(seconds: 2),
      );

      expect(dataSource.requestCount('runtime-null-draft'), 0);
      expect(notifier.state.queuedMessages, isEmpty);
      var draftSendCompleted = false;
      unawaited(
        draftSend.then((_) {
          draftSendCompleted = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(draftSendCompleted, isFalse);
      runtimeRepository.releaseFlush.complete();

      conversations.selectConversation(draftOwner);
      expect(
        notifier.state.queuedMessages.single.conversationId,
        draftOwner,
        reason: 'a materialized draft must be restored under its assigned id',
      );
      await dataSource
          .waitForRequest('runtime-null-draft')
          .timeout(const Duration(seconds: 2));
      dataSource.release('runtime-null-draft');
      await _waitUntil(
        () =>
            !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
      );
      final restoredOwner = await draftSend.timeout(const Duration(seconds: 2));
      expect(restoredOwner?.conversationId, draftOwner);
      expect(dataSource.requestCount('runtime-null-draft'), 1);
    },
  );

  test(
    'switching during draft persistence restores the materialized owner',
    () async {
      final persistenceStarted = Completer<void>();
      final releasePersistence = Completer<void>();
      final dataSource = _GatedQueueDataSource();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        beforeConversationPut: (encoded) async {
          final payload = jsonDecode(encoded) as Map<String, dynamic>;
          final messages = payload['messages'] as List<dynamic>? ?? const [];
          if (messages.isEmpty) return;
          if (!persistenceStarted.isCompleted) persistenceStarted.complete();
          await releasePersistence.future;
        },
      );
      addTearDown(() {
        if (!releasePersistence.isCompleted) releasePersistence.complete();
        container.dispose();
      });

      final notifier = container.read(chatNotifierProvider.notifier);
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.startDraftConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(conversationsNotifierProvider).currentConversationId,
        isNull,
      );
      notifier.state = notifier.state.copyWith(
        messages: [
          Message(
            id: 'draft-history',
            content: 'draft history',
            role: MessageRole.user,
            timestamp: DateTime(2026, 7, 28),
          ),
        ],
      );
      final draftSend = notifier.sendMessage('persisted-null-draft');
      await persistenceStarted.future.timeout(const Duration(seconds: 2));
      final draftOwner = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      await Future<void>.delayed(Duration.zero);
      expect(notifier.conversationId, isNot(draftOwner));
      releasePersistence.complete();

      expect(dataSource.requestCount('persisted-null-draft'), 0);
      expect(notifier.state.queuedMessages, isEmpty);
      var draftSendCompleted = false;
      unawaited(
        draftSend.then((_) {
          draftSendCompleted = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(draftSendCompleted, isFalse);
      conversations.selectConversation(draftOwner);
      expect(notifier.state.queuedMessages.single.conversationId, draftOwner);
      await dataSource
          .waitForRequest('persisted-null-draft')
          .timeout(const Duration(seconds: 2));
      dataSource.release('persisted-null-draft');
      await _waitUntil(
        () =>
            !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
      );
      final restoredOwner = await draftSend.timeout(const Duration(seconds: 2));
      expect(restoredOwner?.conversationId, draftOwner);
      expect(dataSource.requestCount('persisted-null-draft'), 1);
    },
  );

  test(
    'a hidden draft turn materializes its owner before queueing user work',
    () async {
      final dataSource = _GatedQueueDataSource();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatNotifierProvider.notifier);
      container
          .read(conversationsNotifierProvider.notifier)
          .startDraftConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-a',
          );
      await Future<void>.delayed(Duration.zero);
      expect(notifier.conversationId, isNull);
      final hiddenTurn = notifier.sendHiddenPrompt('held-hidden-draft');
      await dataSource
          .waitForRequest('held-hidden-draft')
          .timeout(const Duration(seconds: 2));

      final owner = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(notifier.conversationId, owner);
      expect(notifier.state.busyConversationIds, contains(owner));
      unawaited(notifier.sendMessage('queued-after-hidden'));

      expect(notifier.state.queuedMessages.single.conversationId, owner);
      expect(dataSource.requestCount('queued-after-hidden'), 0);
      dataSource.release('held-hidden-draft');
      await dataSource
          .waitForRequest('queued-after-hidden')
          .timeout(const Duration(seconds: 2));
      dataSource.release('queued-after-hidden');
      await hiddenTurn.timeout(const Duration(seconds: 2));
      await _waitUntil(
        () =>
            !notifier.state.isLoading && notifier.state.queuedMessages.isEmpty,
      );
      expect(dataSource.requestCount('held-hidden-draft'), 1);
      expect(dataSource.requestCount('queued-after-hidden'), 1);
      expect(notifier.state.busyConversationIds, isNot(contains(owner)));
    },
  );

  test(
    'a finished plan draft is still there after leaving the thread',
    () async {
      // Reported 2026-07-25: the review sheet never appeared for a plan drafted
      // while the user was on another thread; the plan only showed after
      // pressing expand. The sheet auto-presents from the draft fields, and the
      // thread switch rebuilt ChatState without them.
      late final ProviderContainer container;
      final dataSource = _PlanProposalDataSource(() async {});

      container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        assistantMode: AssistantMode.plan,
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final draftingThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await container
          .read(chatNotifierProvider.notifier)
          .generatePlanProposal();
      expect(
        container.read(chatNotifierProvider).workflowProposalDraft,
        isNotNull,
        reason:
            'the draft has to exist before the switch for this to mean much',
      );

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(chatNotifierProvider).workflowProposalDraft,
        isNull,
        reason: "the other thread must not show this thread's draft",
      );

      conversations.selectConversation(draftingThread);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(chatNotifierProvider).workflowProposalDraft,
        isNotNull,
        reason:
            'coming back must restore the draft, otherwise the review sheet '
            'never auto-presents and the plan looks lost',
      );
    },
  );


  test(
    'a plan drafted while the user leaves lands on the drafting thread',
    () async {
      // The finished-draft case above covers a switch *after* drafting ends.
      // This is the switch *during* it, which had no coverage: the draft has to
      // reach the thread that asked for it even though a different thread is
      // visible when the LLM returns.
      //
      // Covers generatePlanProposal, which routes its writes. The UI's other
      // entry point, generateWorkflowProposal, does not -- it ends with a bare
      // `state = state.copyWith(...)` (chat_notifier.dart:3118) after awaiting
      // the model. That path is not covered here; see the P2 notes in
      // docs/chat_notifier_state_authority_by_lifetime.md.
      final releaseProposal = Completer<void>();
      final proposalRequested = Completer<void>();
      late final ProviderContainer container;
      final dataSource = _PlanProposalDataSource(() async {
        if (!proposalRequested.isCompleted) proposalRequested.complete();
        await releaseProposal.future;
      });

      container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        assistantMode: AssistantMode.plan,
      );
      addTearDown(() {
        if (!releaseProposal.isCompleted) releaseProposal.complete();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final draftingThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      final drafting = notifier.generatePlanProposal();
      await proposalRequested.future.timeout(const Duration(seconds: 3));

      // The user opens another thread while the plan is still being drafted.
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final otherThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(otherThread, isNot(draftingThread));

      releaseProposal.complete();
      await drafting;
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(chatNotifierProvider).workflowProposalDraft,
        isNull,
        reason: "the other thread never asked for a plan",
      );
      expect(
        container.read(chatNotifierProvider).isGeneratingWorkflowProposal,
        isFalse,
        reason: 'the other thread is not drafting anything',
      );

      conversations.selectConversation(draftingThread);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(chatNotifierProvider).workflowProposalDraft,
        isNotNull,
        reason: 'the plan belongs to the thread that asked for it',
      );
      expect(
        container.read(chatNotifierProvider).isGeneratingWorkflowProposal,
        isFalse,
        reason: 'the drafting thread must not be left spinning',
      );
    },
  );


  test(
    'a workflow proposal drafted while the user leaves lands on its thread',
    () async {
      // generatePlanProposal routes its writes; generateWorkflowProposal --
      // the entry point the UI uses (chat_page_workflow_builders.dart:119,
      // :661) -- ends with a bare `state = state.copyWith(...)` after awaiting
      // the model, guarded only by ref.mounted.
      final releaseProposal = Completer<void>();
      final proposalRequested = Completer<void>();
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(content: 'ok', finishReason: 'stop'),
        ],
        completionSteps: [
          // Plan mode routes the opening message through four secondary
          // completions before any drafting call; the assertion below fails
          // loudly if that changes.
          for (var i = 0; i < 3; i++)
            ScriptedStep(
              ChatCompletionResult(content: 'done', finishReason: 'stop'),
            ),
          ScriptedStep(
            ChatCompletionResult(
              content:
                  '{"kind":"proposal","workflowStage":"plan",'
                  '"goal":"Ship the slice","constraints":["Keep it small"],'
                  '"acceptanceCriteria":["Lands on its own thread"],'
                  '"openQuestions":[]}',
              finishReason: 'stop',
            ),
            barrier: () async {
              if (!proposalRequested.isCompleted) proposalRequested.complete();
              await releaseProposal.future;
            },
          ),
          ScriptedStep(
            ChatCompletionResult(
              content:
                  '{"tasks":[{"title":"Route the drafting write",'
                  '"targetFiles":["lib/features/chat/presentation/providers/chat_notifier.dart"],'
                  '"validationCommand":"flutter test","notes":"Cover it."}]}',
              finishReason: 'stop',
            ),
          ),
        ],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SwitchingToolService(() async {}),
        assistantMode: AssistantMode.plan,
      );
      addTearDown(() {
        if (!releaseProposal.isCompleted) releaseProposal.complete();
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final draftingThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      // This path asserts a positive interaction generation, so a turn has to
      // have happened. The harness scripts the turn and the drafting request
      // on separate counters, so the turn does not consume the barrier.
      await notifier.sendMessage('start the drafting thread');
      expect(
        dataSource.completionRequests,
        3,
        reason: 'the barrier below is placed after the opening turn',
      );

      final drafting = notifier.generateWorkflowProposal();
      await proposalRequested.future.timeout(const Duration(seconds: 5));

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final otherThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(otherThread, isNot(draftingThread));

      releaseProposal.complete();
      await drafting;
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(chatNotifierProvider).workflowProposalDraft,
        isNull,
        reason: 'the other thread never asked for a plan',
      );
      expect(
        container.read(chatNotifierProvider).isGeneratingWorkflowProposal,
        isFalse,
        reason: 'the other thread is not drafting anything',
      );
    },
  );


  // LL34. The first version of this test asserted the outcome could not
  // survive, blaming the four-string single-result datasource API. That was
  // wrong: the notifier never calls it. The fact was being dropped by
  // `ToolResultPromptBuilder.budgetToolResults`, which rebuilds every
  // ToolResultInfo to shorten its payload and did not copy the outcome across.
  test('a reported exit status survives prompt budgeting', () async {
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'call-exit',
              name: 'list_directory',
              arguments: const {'path': 'bin'},
            ),
          ],
        ),
      ],
      toolResultResponses: [
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ],
      streamedResponses: [
        ChatCompletionResult(content: 'done', finishReason: 'stop'),
      ],
    );
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _ReportedOutcomeToolService(
        const ToolOutcome(exitCode: 2),
      ),
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container.read(chatNotifierProvider.notifier).sendMessage('go');

    expect(dataSource.toolResultBatches, isNotEmpty);
    final carried = dataSource.toolResultBatches.last.single;
    expect(
      carried.outcome?.exitCode,
      2,
      reason:
          'budgeting shortens the payload text; it must not discard what the '
          'tool reported about its own execution',
    );
  });

  test('a pending approval follows its thread and is announced', () async {
    // Leaving a thread that is waiting on the user used to drop the approval
    // outright. It has to survive, stay off the other thread, and be visible
    // to the sidebar so the thread can say "waiting for you" instead of
    // spinning.
    final container = _buildContainer(
      dataSource: _RecordingDataSource(),
      toolService: _SwitchingToolService(() async {}),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final waitingThread = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    final notifier = container.read(chatNotifierProvider.notifier);
    notifier.state = notifier.state.copyWith(
      pendingLocalCommand: PendingLocalCommand(
        owner: ChatTurnOwner(
          conversationId: waitingThread,
          interactionGeneration: 1,
        ),
        id: 'call-1',
        command: 'rm -rf build',
        workingDirectory: _projectARoot,
        reason: 'clean the build directory',
        warningTitle: 'Destructive command',
        warningMessage: 'This deletes files.',
        completer: Completer<LocalCommandApproval>(),
      ),
    );

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    await Future<void>.delayed(Duration.zero);

    final onOtherThread = container.read(chatNotifierProvider);
    expect(
      onOtherThread.pendingLocalCommand,
      isNull,
      reason: "the other thread must not be asked to answer this thread's tool",
    );
    expect(
      onOtherThread.approvalRequiredConversationIds,
      contains(waitingThread),
      reason:
          'the sidebar needs this to replace the spinner with an approval '
          'prompt for the thread that is actually blocked',
    );

    conversations.selectConversation(waitingThread);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(chatNotifierProvider).pendingLocalCommand,
      isNotNull,
      reason: 'coming back must restore the approval, not discard it',
    );
  });

  test('a plan finished in the background lands on its own thread', () async {
    // Reported 2026-07-26: two threads drafting at once. The first finished
    // while the user was reading the second, and its draft was written into
    // the visible ChatState — so the second thread's own draft overwrote it,
    // the first thread showed nothing on return, and the dialog the user
    // approved was not necessarily the plan they were looking at.
    late final ProviderContainer container;
    final dataSource = _PlanProposalDataSource(() async {
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
      assistantMode: AssistantMode.plan,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final draftingThread = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();

    final onOtherThread = container.read(chatNotifierProvider);
    expect(
      onOtherThread.workflowProposalDraft,
      isNull,
      reason:
          "the thread the user switched to must not display another thread's "
          'plan, which is what made the approved dialog ambiguous',
    );
    expect(
      onOtherThread.approvalRequiredConversationIds,
      contains(draftingThread),
      reason: 'a finished plan is waiting on the user, so announce it',
    );

    conversations.selectConversation(draftingThread);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(chatNotifierProvider).workflowProposalDraft,
      isNotNull,
      reason: 'the thread that drafted the plan has to show it on return',
    );
  });

  test('an exhausted quality gate still yields a plan to review', () async {
    // Live 2026-07-25: the task-proposal gate rejected three usable drafts for
    // a single-file CLI project, the heuristic fallback tripped the same
    // rules, and the plan run failed outright — the user got an error instead
    // of a plan. A gate may ask for better; it may not destroy the only draft
    // there is. This fixture's single-task proposal trips the gate 3/3.
    final container = _buildContainer(
      dataSource: _PlanProposalDataSource(() async {}),
      toolService: _SwitchingToolService(() async {}),
      assistantMode: AssistantMode.plan,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();

    expect(
      container.read(chatNotifierProvider).taskProposalDraft,
      isNotNull,
      reason:
          'the rejected draft is still the best answer available, and the '
          'review sheet is where the user would fix it',
    );
    expect(
      container.read(chatNotifierProvider).taskProposalError,
      isNull,
      reason: 'presenting a plan and an error at once would be contradictory',
    );
  });

  test('an approval raised by a background turn goes to its own thread', () {
    // Approval prompts are raised from tool handlers that do not know which
    // thread they serve, so they landed on whoever the user was reading.
    final byThread = <String, ThreadScopedChatState>{};
    final visible = ChatState.initial();
    PendingLocalCommand pending() => PendingLocalCommand(
      owner: ChatTurnOwner(
        conversationId: 'thread-a',
        interactionGeneration: 1,
      ),
      id: 'call-1',
      command: 'rm -rf build',
      workingDirectory: _projectARoot,
      reason: 'clean the build directory',
      warningTitle: 'Destructive command',
      warningMessage: 'This deletes files.',
      completer: Completer<LocalCommandApproval>(),
    );

    final afterBackground = ThreadScopedChatState.routeToThread(
      byThread: byThread,
      turnThread: 'thread-a',
      visibleThread: 'thread-b',
      current: visible,
      apply: (s) => s.copyWith(pendingLocalCommand: pending()),
    );
    expect(
      afterBackground.pendingLocalCommand,
      isNull,
      reason: 'the reader of thread-b was never asked to approve this',
    );
    expect(
      byThread['thread-a']?.pendingLocalCommand,
      isNotNull,
      reason: 'it belongs to the thread whose turn asked for it',
    );
    expect(
      afterBackground.approvalRequiredConversationIds,
      contains('thread-a'),
      reason: 'and the sidebar has to be able to announce it',
    );

    final afterForeground = ThreadScopedChatState.routeToThread(
      byThread: byThread,
      turnThread: 'thread-b',
      visibleThread: 'thread-b',
      current: visible,
      apply: (s) => s.copyWith(pendingLocalCommand: pending()),
    );
    expect(
      afterForeground.pendingLocalCommand,
      isNotNull,
      reason: 'a turn on the visible thread still prompts inline as before',
    );
  });

  test('the runtime workspace follows the thread, not the sidebar', () async {
    // Live 2026-07-25: a plan run on run20 asked to lease run19's workspace
    // and failed as "workspace:todo is already owned by flutterGui process N",
    // because the snapshot took the project from CodingProjectsState's
    // selectedProjectId — the sidebar selection, left on the thread opened
    // before it. _TwoProjectsNotifier keeps project-a selected, so a thread on
    // project-b reproduces exactly that skew.
    final container = _buildContainer(
      dataSource: _RecordingDataSource(),
      toolService: _SwitchingToolService(() async {}),
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-b',
        );

    final snapshot = container.read(cavernoRuntimeSettingsPortProvider).current;
    expect(
      snapshot.workspace,
      _projectBRoot,
      reason:
          'the lease is taken on this path; using the sidebar selection makes '
          'one thread collide with another project\'s running turn',
    );
  });

  test('a relative tool path resolves against the turn project', () async {
    // Observed live on 2026-07-25: a turn on run19 asked for
    // read_file {"path":"todo_app.md"} and the resolver turned it into
    // run20/todo/todo_app.md because the user had that thread open. A relative
    // write would have landed in the other project.
    late final ProviderContainer container;
    final toolService = _SwitchingToolService(() async {});
    final dataSource = _RecordingDataSource(
      onFirstRequest: () async {
        // The user opens the other thread while the request is in flight, so
        // the tool call is dispatched with a different thread visible.
        container
            .read(conversationsNotifierProvider.notifier)
            .createNewConversation(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-b',
            );
        await Future<void>.delayed(Duration.zero);
      },
    );

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container.read(chatNotifierProvider.notifier).sendMessage('look');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      toolService.receivedPaths,
      isNotEmpty,
      reason: 'the tool has to run for its path to be resolved',
    );
    for (final path in toolService.receivedPaths) {
      expect(
        path,
        startsWith(_projectARoot),
        reason:
            'the relative path belongs to the thread that asked for it; '
            'resolving it into the visible project reads — and would write — '
            'another project',
      );
    }
  });

  test('detached run_tests uses the owner project root', () async {
    late final ProviderContainer container;
    final toolService = _ProjectRootProbeToolService('run_tests');
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: 'Run the owner A test.',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'run-owner-a-tests',
              name: 'run_tests',
              arguments: const {
                'test_path': 'test/owner_a_test.dart',
                'runner': 'dart',
              },
            ),
          ],
        ),
      ],
      toolResultResponses: [
        ChatCompletionResult(
          content: 'Owner A tests passed.',
          finishReason: 'stop',
        ),
      ],
      beforeInitialResponse: (_) async {
        container
            .read(conversationsNotifierProvider.notifier)
            .createNewConversation(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-b',
            );
        await Future<void>.delayed(Duration.zero);
      },
    );
    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Run test/owner_a_test.dart.');

    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.normalizedProjectId,
      'project-b',
      reason: 'the visible project must be poisoned before tool dispatch',
    );
    expect(toolService.executedNames, ['local_execute_command']);
    expect(toolService.executedArguments, hasLength(1));
    final arguments = toolService.executedArguments.single;
    expect(arguments['working_directory'], _projectARoot);
    expect(arguments['command'], contains('test/owner_a_test.dart'));
    expect(
      arguments.values.map((value) => value?.toString() ?? ''),
      everyElement(isNot(contains(_projectBRoot))),
    );
  });

  test('detached lsp_go_to_definition uses the owner project root', () async {
    late final ProviderContainer container;
    final lspRegistry = _RecordingLspSessionRegistry();
    final toolService = _ProjectRootProbeToolService('lsp_go_to_definition');
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: 'Find the owner A definition.',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'find-owner-a-definition',
              name: 'lsp_go_to_definition',
              arguments: const {
                'path': 'lib/owner_a.dart',
                'line': 1,
                'column': 1,
              },
            ),
          ],
        ),
      ],
      toolResultResponses: [
        ChatCompletionResult(
          content: 'Found the owner A definition.',
          finishReason: 'stop',
        ),
      ],
      beforeInitialResponse: (_) async {
        container
            .read(conversationsNotifierProvider.notifier)
            .createNewConversation(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-b',
            );
        await Future<void>.delayed(Duration.zero);
      },
    );
    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
      lspSessionRegistry: lspRegistry,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage('Find the definition in lib/owner_a.dart.');

    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.normalizedProjectId,
      'project-b',
      reason: 'the visible project must be poisoned before tool dispatch',
    );
    expect(lspRegistry.receivedProjectRoot, _projectARoot);
    expect(
      lspRegistry.receivedPath?.replaceAll(r'\', '/'),
      '$_projectARoot/lib/owner_a.dart',
    );
    expect(lspRegistry.receivedLine, 0);
    expect(lspRegistry.receivedCharacter, 0);
    expect(lspRegistry.receivedProjectRoot, isNot(_projectBRoot));
    expect(lspRegistry.receivedPath, isNot(contains(_projectBRoot)));
    expect(
      toolService.executedNames,
      isEmpty,
      reason: 'LSP requests must stay on the injected owner-scoped registry',
    );
  });

  test('a plan draft keeps its own project after a thread switch', () async {
    // Observed live on 2026-07-25 (build 96d23ed7): a plan draft on run19 kept
    // running while the user opened a second project, and its task proposal
    // went out describing run20 and was logged under that thread. The proposal
    // builders pass the turn's conversation to the user message but built the
    // system message from the visible thread. Plan drafting takes tens of
    // seconds, so a switch lands inside it easily.
    final sessionLogRoot = await Directory.systemTemp.createTemp(
      'caverno_execution_shadow_owner_',
    );
    final sessionLogStore = LlmSessionLogStore(
      rootDirectoryProvider: () async => sessionLogRoot,
    );
    late final ProviderContainer container;
    late final String draftingThreadId;
    String? visibleThreadId;
    var didSwitch = false;
    File? draftingLogFile;
    List<Map<String, dynamic>> executionShadowEntries() {
      final file = draftingLogFile;
      if (file == null || !file.existsSync()) return const [];
      return file
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .where((entry) => entry['operation'] == 'execution_shadow')
          .toList(growable: false);
    }

    final dataSource = _PlanProposalDataSource(() async {
      expect(
        container.read(conversationsNotifierProvider).currentConversationId,
        visibleThreadId,
      );
      expect(visibleThreadId, isNot(draftingThreadId));
    });
    final toolService = _SwitchingToolService(() async {
      if (didSwitch) return;
      didSwitch = true;
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      visibleThreadId = container
          .read(conversationsNotifierProvider)
          .currentConversationId;
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
      assistantMode: AssistantMode.plan,
      sessionLogStore: sessionLogStore,
    );
    addTearDown(() async {
      container.dispose();
      if (sessionLogRoot.existsSync()) {
        await sessionLogRoot.delete(recursive: true);
      }
    });

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );
    draftingThreadId = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    draftingLogFile = await sessionLogStore.fileForContext(
      LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: draftingThreadId,
        conversationId: draftingThreadId,
      ),
      create: false,
    );

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();

    final conversations = container
        .read(conversationsNotifierProvider)
        .conversations;
    final draftingThread = conversations.firstWhere(
      (conversation) => conversation.id == draftingThreadId,
    );
    final otherThread = conversations.firstWhere(
      (conversation) => conversation.id != draftingThreadId,
    );
    expect(
      draftingThread.planArtifact?.hasContent ?? false,
      isTrue,
      reason: 'the plan belongs to the thread it was drafted for',
    );
    expect(
      otherThread.planArtifact?.hasContent ?? false,
      isFalse,
      reason:
          'persisting to the visible thread is why the user saw no plan: the '
          'draft was filed under the thread they had just opened',
    );

    expect(
      dataSource.systemPrompts.length,
      greaterThanOrEqualTo(2),
      reason: 'the workflow proposal landed, so the task proposal follows',
    );
    // The first request goes out before the switch; the later ones are the
    // ones that used to inherit the newly visible thread.
    for (final prompt in dataSource.systemPrompts.skip(1)) {
      expect(
        prompt,
        contains(_projectARoot),
        reason: 'the draft must keep describing the project it was started on',
      );
      expect(
        prompt,
        isNot(contains(_projectBRoot)),
        reason:
            'this is the live 2026-07-25 failure: the run19 draft proposed '
            'against run20 once that thread became visible',
      );
    }

    await _waitUntil(() => executionShadowEntries().isNotEmpty);
    final executionShadows = executionShadowEntries();
    expect(executionShadows, isNotEmpty);
    for (final entry in executionShadows) {
      final context = entry['context'] as Map<String, dynamic>;
      expect(context['conversationId'], draftingThreadId);
      expect(context['sessionId'], draftingThreadId);
      expect(context['conversationId'], isNot(otherThread.id));
    }
  });

  test('a finished background turn hands its thread back complete', () async {
    // Observed live on 2026-07-26 (build 08199a3b), with two coding threads
    // running at once. The thread the user was not reading finished its turn —
    // the conversation store proves it, and so does the session log's final
    // response — yet opening that thread showed the transcript snapshot taken
    // when the user left it, under a spinner that never stopped. Quitting and
    // relaunching the app healed both, because startup reads the store while a
    // thread switch prefers the in-flight registration.
    //
    // So the invariant is: once a background turn is over, its thread must
    // present what the turn produced, and must not still look busy.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource(
      finalContent: 'ANSWER-FROM-THE-BACKGROUND-TURN',
    );
    final toolService = _SwitchingToolService(() async {
      // The user opens another thread while the first thread's tool runs.
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final backgroundThreadId = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .id;
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendMessage('list the project');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      toolService.executions,
      greaterThan(0),
      reason: 'the tool has to run for the thread switch to interleave',
    );

    // The user goes back to the thread that was working.
    conversations.selectConversation(backgroundThreadId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(chatNotifierProvider);
    expect(
      state.messages.map((message) => message.content).join('\n'),
      contains('ANSWER-FROM-THE-BACKGROUND-TURN'),
      reason:
          'the turn finished while this thread was in the background, so its '
          'answer has to be here — showing the snapshot taken at switch time '
          'is the data loss the user sees until an app restart',
    );
    expect(
      state.isLoading,
      isFalse,
      reason:
          'the turn is over, so the thread must not come back holding a '
          'spinner and a stop button',
    );
    expect(
      state.busyConversationIds,
      isNot(contains(backgroundThreadId)),
      reason: 'a finished turn must not leave its thread listed as busy',
    );
  });

  test('an ephemeral hidden-prompt turn releases its thread', () async {
    // The branch that drops a hidden prompt's answer from the visible history
    // (chat_notifier.dart, "Hidden prompt responses are ephemeral") returns
    // without releasing the turn's active-response registration. A registration
    // that outlives its turn is what a thread switch shows instead of the
    // persisted transcript, and what the spinner is derived from — so the
    // thread is left looking busy, on a frozen snapshot, until the app is
    // relaunched.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource(finalContent: 'EPHEMERAL-ANSWER');
    final toolService = _SwitchingToolService(() async {});

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadId = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .id;
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendHiddenPrompt('check on the build');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container.read(chatNotifierProvider).busyConversationIds,
      isNot(contains(threadId)),
      reason:
          'the hidden turn is over, so its registration has to be handed back; '
          'holding it keeps the thread spinning and freezes what a switch back '
          'to it will show',
    );
    expect(
      container.read(chatNotifierProvider).isLoading,
      isFalse,
      reason: 'nothing is running once the hidden turn has finished',
    );
  });

  test('a background plan decision waits on its own thread', () async {
    // Measured live 2026-07-27 (gen-5): plan drafting raised its decision
    // prompt with a bare `state = state.copyWith(...)`, so a background draft's
    // question landed on whichever thread was on screen, and that thread's own
    // flow cleared it moments later. Nothing could reach the completer after
    // that, so the turn kept its registration, its runtime handle and its
    // workspace lease until the app was quit.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource();
    final toolService = _SwitchingToolService(() async {});

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final draftingThread = container
        .read(conversationsNotifierProvider)
        .currentConversation!
        .id;
    final notifier = container.read(chatNotifierProvider.notifier);

    // The user opens another thread, and only then does the background draft
    // reach its question. Raising it while the drafting thread is still on
    // screen proves nothing: the un-routed write lands on the right thread by
    // accident and the negative control passes.
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final answer = TurnThread.runScoped(
      draftingThread,
      () => notifier.requestWorkflowDecision(
        decision: const WorkflowPlanningDecision(
          id: 'decision-1',
          question: 'Which runtime?',
          options: <WorkflowPlanningDecisionOption>[
            WorkflowPlanningDecisionOption(id: 'dart', label: 'Dart'),
            WorkflowPlanningDecisionOption(id: 'node', label: 'Node'),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      container.read(chatNotifierProvider).pendingWorkflowDecision,
      isNull,
      reason:
          'the question belongs to the other thread, so it must not be put in '
          'front of the thread the user is reading',
    );
    expect(
      container.read(chatNotifierProvider).approvalRequiredConversationIds,
      contains(draftingThread),
      reason:
          'the drafting thread has stopped and cannot proceed alone, so the '
          'sidebar has to say so rather than spin',
    );

    // Going back to it hands the question over, and answering completes the
    // turn's future instead of stranding it.
    conversations.selectConversation(draftingThread);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final restored = container
        .read(chatNotifierProvider)
        .pendingWorkflowDecision;
    expect(
      restored,
      isNotNull,
      reason: 'opening the thread must present the question it is waiting on',
    );
    notifier.resolveWorkflowDecision(
      id: restored!.id,
      answer: const WorkflowPlanningDecisionAnswer(
        decisionId: 'decision-1',
        question: 'Which runtime?',
        optionId: 'dart',
        optionLabel: 'Dart',
      ),
    );

    expect(
      await answer.timeout(const Duration(seconds: 2)),
      isNotNull,
      reason:
          'the drafting turn must resume; a completer nobody can reach is what '
          'held the registration, runtime handle and workspace lease open',
    );
  });

  test(
    'detached participant approval and handoff remain owned by thread A',
    () async {
      final primaryStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain(
          'a-primary-model',
          primaryStream.stream,
          usage: const TokenUsage(
            promptTokens: 10,
            completionTokens: 6,
            totalTokens: 16,
          ),
        )
        ..queuePlain(
          'b-primary-model',
          Stream<String>.value('B completed independently.'),
          usage: const TokenUsage(
            promptTokens: 20,
            completionTokens: 9,
            totalTokens: 29,
          ),
        )
        ..queueTool(
          'a-reviewer-model',
          _ParticipantToolReply(
            completion: ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'read-a-source',
                  name: 'read_file',
                  arguments: const {
                    'path': 'lib/a.dart',
                    'reason': 'Verify the owner A implementation.',
                  },
                ),
              ],
            ),
          ),
        )
        ..queueTool(
          'a-reviewer-model',
          _ParticipantToolReply(
            chunks: const ['A reviewer completed with evidence.'],
            completion: ChatCompletionResult(
              content: 'A reviewer completed with evidence.',
              finishReason: 'stop',
              usage: const TokenUsage(
                promptTokens: 30,
                completionTokens: 7,
                totalTokens: 37,
              ),
            ),
          ),
        );
      final toolService = _ParticipantReadToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        assistantMode: AssistantMode.general,
      );
      addTearDown(() async {
        if (!primaryStream.isClosed) {
          await primaryStream.close();
        }
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-primary',
            displayName: 'A Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Coordinate owner A.',
            model: 'a-primary-model',
            facilitatesTurns: true,
            order: 0,
          ),
          ConversationParticipant(
            id: 'a-reviewer',
            displayName: 'A Reviewer',
            roleLabel: 'Reviewer',
            roleSystemPrompt: 'Review owner A with evidence.',
            model: 'a-reviewer-model',
            toolsEnabled: true,
            order: 1,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-primary',
            displayName: 'B Primary',
            roleLabel: 'Facilitator',
            model: 'b-primary-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final sendA = notifier.sendMessage('Review owner A.');
      await _waitUntil(
        () => dataSource.plainRequestModels.contains('a-primary-model'),
      );
      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      primaryStream.add(
        'A primary delegates the evidence review.\nHandoff: A Reviewer',
      );
      await primaryStream.close();
      await _waitUntil(
        () =>
            dataSource.toolRequestModels.contains('a-reviewer-model') &&
            notifier.state.approvalRequiredConversationIds.contains(
              owners.threadA,
            ),
      );

      expect(notifier.state.pendingParticipantToolApproval, isNull);
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(toolService.executedArguments, isEmpty);
      await notifier.sendMessage('Complete owner B.');

      final persistedBBeforeApproval = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == owners.threadB);
      final bSnapshot = [
        for (final message in persistedBBeforeApproval.messages)
          (
            id: message.id,
            content: message.content,
            role: message.role,
            participantId: message.participantId,
            error: message.error,
          ),
      ];
      expect(
        persistedBBeforeApproval.messages
            .where((message) => message.role == MessageRole.assistant)
            .single
            .content,
        'B completed independently.',
      );
      expect(
        persistedBBeforeApproval.messages
            .where((message) => message.role == MessageRole.assistant)
            .single
            .responseMetrics
            ?.totalTokens,
        29,
      );
      expect(notifier.state.busyConversationIds, contains(owners.threadA));

      conversations.selectConversation(owners.threadA);
      await _waitUntil(
        () => notifier.state.pendingParticipantToolApproval != null,
      );
      final pending = notifier.state.pendingParticipantToolApproval!;
      expect(pending.participantId, 'a-reviewer');
      expect(pending.participantName, 'A Reviewer');
      expect(pending.participantRoleLabel, 'Reviewer');
      expect(pending.toolName, 'read_file');
      expect(pending.arguments, {
        'path': 'lib/a.dart',
        'reason': 'Verify the owner A implementation.',
      });
      final approvalEvent = events
          .whereType<CavernoRuntimeApprovalRequired>()
          .single;
      expect(approvalEvent.conversationId, owners.threadA);
      expect(approvalEvent.request.id, pending.id);

      notifier.resolveParticipantToolApproval(id: pending.id, approved: true);
      await sendA.timeout(const Duration(seconds: 2));

      expect(toolService.executedArguments, [
        {'path': 'lib/a.dart', 'reason': 'Verify the owner A implementation.'},
      ]);
      final persistedA = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == owners.threadA);
      final assistantA = persistedA.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantA.map((message) => message.participantId), [
        'a-primary',
        'a-reviewer',
      ]);
      expect(
        assistantA.first.content,
        'A primary delegates the evidence review.',
      );
      expect(assistantA.first.content, isNot(contains('Handoff:')));
      expect(assistantA.first.handoffTargetParticipantId, 'a-reviewer');
      expect(assistantA.last.content, 'A reviewer completed with evidence.');
      expect(assistantA.last.participantToolNames, ['read_file']);
      expect(assistantA.first.responseMetrics?.totalTokens, 16);
      expect(assistantA.last.responseMetrics?.totalTokens, 37);
      expect(assistantA.last.responseMetrics?.finishReason, 'stop');

      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      final persistedBAfterApproval = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == owners.threadB);
      expect([
        for (final message in persistedBAfterApproval.messages)
          (
            id: message.id,
            content: message.content,
            role: message.role,
            participantId: message.participantId,
            error: message.error,
          ),
      ], bSnapshot);
      expect(notifier.state.pendingParticipantToolApproval, isNull);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      final terminals = events.whereType<CavernoRuntimeTerminalEvent>();
      expect(
        terminals
            .where((event) => event.conversationId == owners.threadA)
            .length,
        1,
      );
      expect(
        terminals
            .where((event) => event.conversationId == owners.threadB)
            .length,
        1,
      );
    },
  );

  test(
    'active participant tool name remains scoped to detached owner A',
    () async {
      final executionStarted = Completer<void>();
      final releaseExecution = Completer<void>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queueTool(
          'a-active-tool-model',
          _ParticipantToolReply(
            completion: ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'active-read-a',
                  name: 'read_file',
                  arguments: const {
                    'path': 'lib/a.dart',
                    'reason': 'Keep the read active across a thread switch.',
                  },
                ),
              ],
            ),
          ),
        )
        ..queueTool(
          'a-active-tool-model',
          _ParticipantToolReply(
            chunks: const ['A completed after the gated read.'],
            completion: ChatCompletionResult(
              content: 'A completed after the gated read.',
              finishReason: 'stop',
            ),
          ),
        );
      final toolService = _ParticipantReadToolService(
        executionStarted: executionStarted,
        executionGate: releaseExecution.future,
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        assistantMode: AssistantMode.general,
      );
      addTearDown(() {
        if (!releaseExecution.isCompleted) releaseExecution.complete();
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-active-tool',
            displayName: 'A Active Tool',
            roleLabel: 'Facilitator',
            model: 'a-active-tool-model',
            facilitatesTurns: true,
            toolsEnabled: true,
            toolApprovalMode: ToolApprovalMode.fullAccess,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-active-tool',
            displayName: 'B Active Tool',
            roleLabel: 'Facilitator',
            model: 'b-active-tool-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);

      final sendA = notifier.sendMessage('Run the gated owner A read.');
      await executionStarted.future.timeout(const Duration(seconds: 2));
      expect(
        notifier.state.participantTurnRuntime?.activeToolName,
        'read_file',
      );
      expect(
        notifier.state.participantTurnRuntime?.activeParticipantId,
        'a-active-tool',
      );

      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.error, isNull);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(
        container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.messages,
        isEmpty,
      );

      conversations.selectConversation(owners.threadA);
      await _waitUntil(
        () =>
            notifier.state.participantTurnRuntime?.activeToolName ==
            'read_file',
      );
      expect(
        notifier.state.participantTurnRuntime?.activeParticipantId,
        'a-active-tool',
      );
      releaseExecution.complete();
      await sendA.timeout(const Duration(seconds: 2));

      expect(toolService.executedArguments, [
        {
          'path': 'lib/a.dart',
          'reason': 'Keep the read active across a thread switch.',
        },
      ]);
      expect(
        notifier.state.messages
            .where((message) => message.role == MessageRole.assistant)
            .single
            .content,
        'A completed after the gated read.',
      );
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.participantTurnRuntime, isNull);
    },
  );

  test(
    'cancelling restored participant approval terminalizes only owner A',
    () async {
      final dataSource = _ParticipantOwnershipDataSource()
        ..queueTool(
          'a-cancel-model',
          _ParticipantToolReply(
            completion: ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'read-before-cancel',
                  name: 'read_file',
                  arguments: const {
                    'path': 'lib/a.dart',
                    'reason': 'Read only if owner A approves.',
                  },
                ),
              ],
            ),
          ),
        )
        ..queueTool(
          'a-cancel-model',
          _ParticipantToolReply(
            completion: ChatCompletionResult(
              content: 'This cancelled continuation must be ignored.',
              finishReason: 'stop',
            ),
          ),
        )
        ..queuePlain(
          'b-cancel-model',
          Stream<String>.value('B completed after A began waiting.'),
        );
      final toolService = _ParticipantReadToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        assistantMode: AssistantMode.general,
      );
      addTearDown(container.dispose);
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-cancel',
            displayName: 'A Cancel',
            roleLabel: 'Facilitator',
            model: 'a-cancel-model',
            facilitatesTurns: true,
            toolsEnabled: true,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-cancel',
            displayName: 'B Cancel',
            roleLabel: 'Facilitator',
            model: 'b-cancel-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final sendA = notifier.sendMessage('Wait for owner A approval.');
      await _waitUntil(
        () => notifier.state.pendingParticipantToolApproval != null,
      );
      final pending = notifier.state.pendingParticipantToolApproval!;
      final staleApprovalId = pending.id;
      expect(pending.ownerConversationId, owners.threadA);
      expect(toolService.executedArguments, isEmpty);

      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.pendingParticipantToolApproval, isNull);
      await notifier.sendMessage('Finish newer owner B.');
      conversations.selectConversation(owners.threadA);
      await _waitUntil(
        () => notifier.state.pendingParticipantToolApproval != null,
      );
      expect(
        notifier.state.pendingParticipantToolApproval!.id,
        staleApprovalId,
      );

      notifier.cancelStreaming();

      expect(notifier.state.pendingParticipantToolApproval, isNull);
      expect(
        await pending.completer.future.timeout(const Duration(seconds: 2)),
        isFalse,
      );
      await sendA.timeout(const Duration(seconds: 2));
      expect(toolService.executedArguments, isEmpty);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      final terminalsA = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(terminalsA, hasLength(1));
      expect(terminalsA.single, isA<CavernoRuntimeRunFailed>());
      expect((terminalsA.single as CavernoRuntimeRunFailed).code, 'cancelled');

      notifier.resolveParticipantToolApproval(
        id: staleApprovalId,
        approved: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(toolService.executedArguments, isEmpty);
      expect(
        events.whereType<CavernoRuntimeTerminalEvent>().where(
          (event) => event.conversationId == owners.threadA,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'detached participant auto-review excludes visible thread B poison',
    () async {
      const ownerToken = 'A_OWNER_TRANSCRIPT_TOKEN';
      const poisonToken = 'B_VISIBLE_POISON_TOKEN';
      final releaseToolCall = Completer<void>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queueTool(
          'a-review-model',
          _ParticipantToolReply(
            completionGate: releaseToolCall.future,
            completion: ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'review-owner-snapshot',
                  name: 'read_file',
                  arguments: const {
                    'path': 'lib/a.dart',
                    'reason': 'Review owner A evidence.',
                  },
                ),
              ],
            ),
          ),
        )
        ..queueTool(
          'a-review-model',
          _ParticipantToolReply(
            chunks: const ['A completed after auto-review denial.'],
            completion: ChatCompletionResult(
              content: 'A completed after auto-review denial.',
              finishReason: 'stop',
            ),
          ),
        )
        ..queuePlain(
          'b-poison-model',
          Stream<String>.value('B response with $poisonToken.'),
        )
        ..queueAutoReview(
          ChatCompletionResult(
            content:
                '{"outcome":"deny","riskLevel":"medium",'
                '"userAuthorization":"low",'
                '"rationale":"Keep the deterministic test read-only."}',
            finishReason: 'stop',
          ),
        );
      final toolService = _ParticipantReadToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        assistantMode: AssistantMode.general,
      );
      addTearDown(() {
        if (!releaseToolCall.isCompleted) releaseToolCall.complete();
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-auto-review',
            displayName: 'A Auto Review',
            roleLabel: 'Facilitator',
            model: 'a-review-model',
            facilitatesTurns: true,
            toolsEnabled: true,
            toolApprovalMode: ToolApprovalMode.autoReview,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-poison',
            displayName: 'B Poison',
            roleLabel: 'Facilitator',
            model: 'b-poison-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);

      final sendA = notifier.sendMessage('Inspect $ownerToken.');
      await _waitUntil(
        () => dataSource.toolRequestModels.contains('a-review-model'),
      );
      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      await notifier.sendMessage('Display $poisonToken.');
      releaseToolCall.complete();
      await sendA.timeout(const Duration(seconds: 2));

      expect(dataSource.autoReviewRequests, hasLength(1));
      final reviewPrompt = dataSource.autoReviewRequests.single
          .map((message) => message.content)
          .join('\n');
      expect(reviewPrompt, contains(ownerToken));
      expect(reviewPrompt, isNot(contains(poisonToken)));
      expect(toolService.executedArguments, isEmpty);
      expect(
        container.read(conversationsNotifierProvider).currentConversationId,
        owners.threadB,
      );
      expect(
        notifier.state.messages.map((message) => message.content).join('\n'),
        contains(poisonToken),
      );
    },
  );

  test(
    'cancelled auto-review cannot restore participant manual approval',
    () async {
      final releaseAutoReview = Completer<void>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queueTool(
          'a-review-cancel-model',
          _ParticipantToolReply(
            completion: ChatCompletionResult(
              content: '',
              finishReason: 'tool_calls',
              toolCalls: [
                ToolCallInfo(
                  id: 'review-then-cancel',
                  name: 'read_file',
                  arguments: const {
                    'path': 'lib/a.dart',
                    'reason': 'Review before owner A cancellation.',
                  },
                ),
              ],
            ),
          ),
        )
        ..queueTool(
          'a-review-cancel-model',
          _ParticipantToolReply(
            completion: ChatCompletionResult(
              content: 'This cancelled continuation must be ignored.',
              finishReason: 'stop',
            ),
          ),
        )
        ..queuePlain(
          'b-review-cancel-model',
          Stream<String>.value('B completed while A review waited.'),
        )
        ..queueAutoReview(
          ChatCompletionResult(
            content: 'invalid auto-review response',
            finishReason: 'stop',
          ),
          completionGate: releaseAutoReview.future,
        );
      final toolService = _ParticipantReadToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
        assistantMode: AssistantMode.general,
      );
      addTearDown(() {
        if (!releaseAutoReview.isCompleted) releaseAutoReview.complete();
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-review-cancel',
            displayName: 'A Review Cancel',
            roleLabel: 'Facilitator',
            model: 'a-review-cancel-model',
            facilitatesTurns: true,
            toolsEnabled: true,
            toolApprovalMode: ToolApprovalMode.autoReview,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-review-cancel',
            displayName: 'B Review Cancel',
            roleLabel: 'Facilitator',
            model: 'b-review-cancel-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final sendA = notifier.sendMessage('Start owner A auto-review.');
      await _waitUntil(() => dataSource.autoReviewRequests.isNotEmpty);
      expect(notifier.state.pendingParticipantToolApproval, isNull);
      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      await notifier.sendMessage('Complete newer owner B.');
      conversations.selectConversation(owners.threadA);
      await Future<void>.delayed(Duration.zero);

      notifier.cancelStreaming();
      expect(notifier.state.pendingParticipantToolApproval, isNull);
      releaseAutoReview.complete();
      await sendA.timeout(const Duration(seconds: 2));

      expect(notifier.state.pendingParticipantToolApproval, isNull);
      expect(toolService.executedArguments, isEmpty);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      final terminalsA = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(terminalsA, hasLength(1));
      expect(terminalsA.single, isA<CavernoRuntimeRunFailed>());
      expect((terminalsA.single as CavernoRuntimeRunFailed).code, 'cancelled');
      expect(
        events.whereType<CavernoRuntimeApprovalRequired>().where(
          (event) => event.conversationId == owners.threadA,
        ),
        isEmpty,
      );
    },
  );

  test(
    'cancellation wins while participant failure persistence is gated',
    () async {
      const failureMarker = 'gated participant persistence failure';
      final persistenceStarted = Completer<void>();
      final releasePersistence = Completer<void>();
      final failingStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain('a-persistence-failure-model', failingStream.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _ParticipantReadToolService(),
        assistantMode: AssistantMode.general,
        beforeConversationPut: (encoded) async {
          final payload = jsonDecode(encoded) as Map<String, dynamic>;
          final messages = payload['messages'] as List<dynamic>? ?? const [];
          final persistsFailure = messages.whereType<Map>().any(
            (message) =>
                message['error']?.toString().contains(failureMarker) == true,
          );
          if (!persistsFailure) return;
          if (!persistenceStarted.isCompleted) persistenceStarted.complete();
          await releasePersistence.future;
        },
      );
      addTearDown(() async {
        if (!releasePersistence.isCompleted) releasePersistence.complete();
        if (!failingStream.isClosed) await failingStream.close();
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-persistence-failure',
            displayName: 'A Persistence Failure',
            roleLabel: 'Facilitator',
            model: 'a-persistence-failure-model',
            facilitatesTurns: true,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-persistence-idle',
            displayName: 'B Persistence Idle',
            roleLabel: 'Facilitator',
            model: 'b-persistence-idle-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final sendA = notifier.sendMessage('Fail during owner A persistence.');
      await _waitUntil(
        () => dataSource.plainRequestModels.contains(
          'a-persistence-failure-model',
        ),
      );
      failingStream.addError(StateError(failureMarker));
      await failingStream.close();
      await persistenceStarted.future.timeout(const Duration(seconds: 2));

      notifier.cancelStreaming();
      final cancelledMessages = List<Message>.from(notifier.state.messages);
      expect(
        cancelledMessages.any((message) => message.error != null),
        isFalse,
      );
      expect(notifier.state.error, isNull);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      releasePersistence.complete();
      await sendA.timeout(const Duration(seconds: 2));
      await notifier.flushPendingPersistence();

      expect(notifier.state.messages, cancelledMessages);
      expect(notifier.state.error, isNull);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      final terminalsA = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(terminalsA, hasLength(1));
      expect(terminalsA.single, isA<CavernoRuntimeRunFailed>());
      expect((terminalsA.single as CavernoRuntimeRunFailed).code, 'cancelled');
    },
  );

  test(
    'detached participant stream failure persists only on thread A',
    () async {
      final failingStream = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain('a-failure-model', failingStream.stream);
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _ParticipantReadToolService(),
        assistantMode: AssistantMode.general,
      );
      addTearDown(() async {
        if (!failingStream.isClosed) {
          await failingStream.close();
        }
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-failure',
            displayName: 'A Failure',
            roleLabel: 'Facilitator',
            model: 'a-failure-model',
            facilitatesTurns: true,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-idle',
            displayName: 'B Idle',
            roleLabel: 'Facilitator',
            model: 'b-idle-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final sendA = notifier.sendMessage('Fail only owner A.');
      await _waitUntil(
        () => dataSource.plainRequestModels.contains('a-failure-model'),
      );
      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      failingStream.addError(StateError('detached participant failure'));
      await failingStream.close();
      await sendA.timeout(const Duration(seconds: 2));

      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.error, isNull);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      final persistedB = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == owners.threadB);
      expect(persistedB.messages, isEmpty);

      final persistedA = container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere((conversation) => conversation.id == owners.threadA);
      final failedMessage = persistedA.messages
          .where((message) => message.role == MessageRole.assistant)
          .single;
      expect(failedMessage.isStreaming, isFalse);
      expect(failedMessage.error, contains('detached participant failure'));
      final terminals = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(terminals, hasLength(1));
      expect(terminals.single, isA<CavernoRuntimeRunFailed>());
    },
  );

  test(
    'detached participant pause resumes in a new owner A generation',
    () async {
      final firstTurn = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain('a-primary-pause', firstTurn.stream)
        ..queuePlain(
          'a-primary-pause',
          Stream<String>.value('A primary round two.'),
        )
        ..queuePlain(
          'a-reviewer-pause',
          Stream<String>.value('A reviewer round one.'),
        )
        ..queuePlain(
          'a-reviewer-pause',
          Stream<String>.value('A reviewer round two.'),
        );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _ParticipantReadToolService(),
        assistantMode: AssistantMode.general,
      );
      addTearDown(() async {
        if (!firstTurn.isClosed) {
          await firstTurn.close();
        }
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-primary-pause',
            displayName: 'A Primary',
            roleLabel: 'Coordinator',
            model: 'a-primary-pause',
            order: 0,
          ),
          ConversationParticipant(
            id: 'a-reviewer-pause',
            displayName: 'A Reviewer',
            roleLabel: 'Reviewer',
            model: 'a-reviewer-pause',
            order: 1,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-idle-pause',
            displayName: 'B Idle',
            roleLabel: 'Facilitator',
            model: 'b-idle-pause',
            facilitatesTurns: true,
          ),
        ],
        configA: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 2,
        ),
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      final sendA = notifier.sendMessage('Pause owner A.');
      await _waitUntil(
        () => dataSource.plainRequestModels.contains('a-primary-pause'),
      );
      firstTurn.add('A primary round one.');
      await _waitUntil(
        () => notifier.state.messages.last.content == 'A primary round one.',
      );
      notifier.requestParticipantTurnStop();
      expect(notifier.state.participantTurnRuntime?.stopRequested, isTrue);
      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      await firstTurn.close();
      await sendA.timeout(const Duration(seconds: 2));

      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.participantTurnRuntime, isNull);
      final initialTerminals = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(initialTerminals, hasLength(1));
      final initialTurnId = initialTerminals.single.turnId;

      conversations.selectConversation(owners.threadA);
      await _waitUntil(
        () => notifier.state.participantTurnRuntime?.paused == true,
      );
      expect(notifier.state.isLoading, isFalse);
      await notifier.continueParticipantTurns();

      final assistantContents = notifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .map((message) => message.content)
          .toList(growable: false);
      expect(assistantContents, [
        'A primary round one.',
        'A reviewer round one.',
        'A primary round two.',
        'A reviewer round two.',
      ]);
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
      final starts = events
          .whereType<CavernoRuntimeRunStarted>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      final terminals = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(starts, hasLength(2));
      expect(terminals, hasLength(2));
      expect(starts.map((event) => event.turnId).toSet(), hasLength(2));
      expect(terminals.map((event) => event.turnId).toSet(), hasLength(2));
      expect(starts.last.turnId, isNot(initialTurnId));

      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.participantTurnRuntime, isNull);
    },
  );

  test(
    'two detached participant owners pause and resume independently',
    () async {
      final firstTurnA = StreamController<String>();
      final firstTurnB = StreamController<String>();
      final dataSource = _ParticipantOwnershipDataSource()
        ..queuePlain('a-first-pause', firstTurnA.stream)
        ..queuePlain(
          'a-second-resume',
          Stream<String>.value('A second completed.'),
        )
        ..queuePlain('b-first-pause', firstTurnB.stream)
        ..queuePlain(
          'b-second-resume',
          Stream<String>.value('B second completed.'),
        );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _ParticipantReadToolService(),
        assistantMode: AssistantMode.general,
      );
      addTearDown(() async {
        if (!firstTurnA.isClosed) await firstTurnA.close();
        if (!firstTurnB.isClosed) await firstTurnB.close();
        container.dispose();
      });
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-first',
            displayName: 'A First',
            model: 'a-first-pause',
            order: 0,
          ),
          ConversationParticipant(
            id: 'a-second',
            displayName: 'A Second',
            model: 'a-second-resume',
            order: 1,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-first',
            displayName: 'B First',
            model: 'b-first-pause',
            order: 0,
          ),
          ConversationParticipant(
            id: 'b-second',
            displayName: 'B Second',
            model: 'b-second-resume',
            order: 1,
          ),
        ],
      );
      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);

      final sendA = notifier.sendMessage('Pause owner A independently.');
      await _waitUntil(
        () => dataSource.plainRequestModels.contains('a-first-pause'),
      );
      firstTurnA.add('A first paused.');
      await _waitUntil(
        () => notifier.state.messages.last.content == 'A first paused.',
      );
      notifier.requestParticipantTurnStop();
      expect(notifier.state.participantTurnRuntime?.stopRequested, isTrue);

      conversations.selectConversation(owners.threadB);
      await Future<void>.delayed(Duration.zero);
      final sendB = notifier.sendMessage('Pause owner B independently.');
      await _waitUntil(
        () => dataSource.plainRequestModels.contains('b-first-pause'),
      );
      firstTurnB.add('B first paused.');
      await _waitUntil(
        () => notifier.state.messages.last.content == 'B first paused.',
      );
      notifier.requestParticipantTurnStop();
      expect(notifier.state.participantTurnRuntime?.stopRequested, isTrue);
      await firstTurnB.close();
      await sendB.timeout(const Duration(seconds: 2));
      expect(notifier.state.participantTurnRuntime?.paused, isTrue);

      conversations.selectConversation(owners.threadA);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.participantTurnRuntime?.stopRequested, isTrue);
      await firstTurnA.close();
      await sendA.timeout(const Duration(seconds: 2));
      expect(notifier.state.participantTurnRuntime?.paused, isTrue);

      await notifier.continueParticipantTurns();
      expect(
        notifier.state.messages
            .where((message) => message.role == MessageRole.assistant)
            .map((message) => message.content),
        ['A first paused.', 'A second completed.'],
      );
      expect(notifier.state.participantTurnRuntime, isNull);

      conversations.selectConversation(owners.threadB);
      await _waitUntil(
        () => notifier.state.participantTurnRuntime?.paused == true,
      );
      await notifier.continueParticipantTurns();
      expect(
        notifier.state.messages
            .where((message) => message.role == MessageRole.assistant)
            .map((message) => message.content),
        ['B first paused.', 'B second completed.'],
      );
      expect(notifier.state.participantTurnRuntime, isNull);
      expect(notifier.state.busyConversationIds, isEmpty);
    },
  );

  test(
    'participant tool-definition setup failure terminalizes runtime once',
    () async {
      final dataSource = _ParticipantOwnershipDataSource();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _ThrowingParticipantToolDefinitionService(),
        assistantMode: AssistantMode.general,
      );
      addTearDown(container.dispose);
      final owners = await _configureParticipantThreads(
        container,
        participantsA: const [
          ConversationParticipant(
            id: 'a-setup-failure',
            displayName: 'A Setup Failure',
            roleLabel: 'Facilitator',
            model: 'a-setup-failure-model',
            facilitatesTurns: true,
            toolsEnabled: true,
          ),
        ],
        participantsB: const [
          ConversationParticipant(
            id: 'b-setup-idle',
            displayName: 'B Setup Idle',
            roleLabel: 'Facilitator',
            model: 'b-setup-idle-model',
            facilitatesTurns: true,
          ),
        ],
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      final runtime = container.read(cavernoExecutionRuntimeProvider);
      final events = <CavernoRuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      await notifier.sendMessage('Fail during participant tool setup.');

      expect(dataSource.plainRequestModels, isEmpty);
      expect(dataSource.toolRequestModels, isEmpty);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.busyConversationIds, isEmpty);
      expect(runtime.hasActiveTurns, isFalse);
      final terminals = events
          .whereType<CavernoRuntimeTerminalEvent>()
          .where((event) => event.conversationId == owners.threadA)
          .toList(growable: false);
      expect(terminals, hasLength(1));
      expect(terminals.single, isA<CavernoRuntimeRunFailed>());
      expect(
        (terminals.single as CavernoRuntimeRunFailed).code,
        'turn_preparation_failed',
      );
    },
  );

  test('disabled participant roster terminalizes exactly once', () async {
    final dataSource = _ParticipantOwnershipDataSource();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _ParticipantReadToolService(),
      assistantMode: AssistantMode.general,
    );
    addTearDown(container.dispose);
    final owners = await _configureParticipantThreads(
      container,
      participantsA: const [
        ConversationParticipant(
          id: 'a-disabled',
          displayName: 'A Disabled',
          roleLabel: 'Facilitator',
          model: 'a-disabled-model',
          facilitatesTurns: true,
          enabled: false,
        ),
      ],
      participantsB: const [
        ConversationParticipant(
          id: 'b-idle-disabled',
          displayName: 'B Idle',
          roleLabel: 'Facilitator',
          model: 'b-idle-disabled',
          facilitatesTurns: true,
        ),
      ],
    );
    final notifier = container.read(chatNotifierProvider.notifier);
    final runtime = container.read(cavernoExecutionRuntimeProvider);
    final events = <CavernoRuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    addTearDown(subscription.cancel);

    await notifier.sendMessage('No participant can run.');

    expect(dataSource.plainRequestModels, isEmpty);
    expect(dataSource.toolRequestModels, isEmpty);
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.participantTurnRuntime, isNull);
    expect(notifier.state.busyConversationIds, isEmpty);
    final starts = events
        .whereType<CavernoRuntimeRunStarted>()
        .where((event) => event.conversationId == owners.threadA)
        .toList(growable: false);
    final terminals = events
        .whereType<CavernoRuntimeTerminalEvent>()
        .where((event) => event.conversationId == owners.threadA)
        .toList(growable: false);
    expect(starts, hasLength(1));
    expect(terminals, hasLength(1));
    expect(terminals.single, isA<CavernoRuntimeRunCompleted>());
    expect(terminals.single.turnId, starts.single.turnId);
  });

  test(
    'detached failed evidence cannot block visible owner completion',
    () async {
      final ownerAFinalPersistenceStarted = Completer<void>();
      final releaseOwnerAPersistence = Completer<void>();
      final ownerBFinalPersistenceStarted = Completer<void>();
      final releaseOwnerBPersistence = Completer<void>();
      String? ownerAConversationForGate;
      String? ownerBConversationForGate;
      var ownerAFinalResponseReady = false;
      var ownerBFinalResponseReady = false;
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Owner A is running a failing verification command.',
            toolCalls: [
              ToolCallInfo(
                id: 'failed-owner-a-verification',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'dart test test/owner_a_test.dart',
                  'working_directory': _projectARoot,
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Owner B is reporting completion.',
            toolCalls: [
              ToolCallInfo(
                id: 'complete-owner-b-goal',
                name: 'update_goal',
                arguments: const {'completed': true},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'Owner A still has a failing verification command.',
            finishReason: 'stop',
            usage: const TokenUsage(totalTokens: 11),
          ),
          ChatCompletionResult(
            content: 'Owner B completion report recorded.',
            finishReason: 'stop',
            usage: const TokenUsage(totalTokens: 97),
          ),
        ],
        beforeToolResultResponse: (requestIndex) async {
          if (requestIndex == 0) {
            ownerAFinalResponseReady = true;
            return;
          }
          if (requestIndex == 1) {
            ownerBFinalResponseReady = true;
          }
        },
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _FailedVerificationGoalToolService(),
        beforeConversationPut: (encoded) async {
          final payload = jsonDecode(encoded) as Map<String, dynamic>;
          if (ownerAFinalResponseReady &&
              payload['id'] == ownerAConversationForGate) {
            if (!ownerAFinalPersistenceStarted.isCompleted) {
              ownerAFinalPersistenceStarted.complete();
            }
            await releaseOwnerAPersistence.future;
          }
          if (ownerBFinalResponseReady &&
              payload['id'] == ownerBConversationForGate) {
            if (!ownerBFinalPersistenceStarted.isCompleted) {
              ownerBFinalPersistenceStarted.complete();
            }
            await releaseOwnerBPersistence.future;
          }
        },
      );
      addTearDown(() {
        if (!releaseOwnerAPersistence.isCompleted) {
          releaseOwnerAPersistence.complete();
        }
        if (!releaseOwnerBPersistence.isCompleted) {
          releaseOwnerBPersistence.complete();
        }
        container.dispose();
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final threadA = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      ownerAConversationForGate = threadA;
      await conversations.saveCurrentGoal(
        objective: 'Repair owner A verification',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      final notifier = container.read(chatNotifierProvider.notifier);
      final ownerAFuture = notifier.sendMessage(
        'Run owner A verification.',
        bypassPlanMode: true,
      );
      await ownerAFinalPersistenceStarted.future.timeout(
        const Duration(seconds: 5),
      );

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-b',
      );
      final threadB = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      ownerBConversationForGate = threadB;
      await conversations.saveCurrentGoal(
        objective: 'Complete owner B acceptance checks',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );
      final ownerBFuture = notifier.sendMessage(
        'Finish owner B goal.',
        bypassPlanMode: true,
      );
      await ownerBFinalPersistenceStarted.future.timeout(
        const Duration(seconds: 5),
      );

      var ownerBGoal = _goalFor(container, threadB);
      expect(ownerBGoal?.status, ConversationGoalStatus.active);
      expect(ownerBGoal?.turnsUsed, 0);

      releaseOwnerAPersistence.complete();
      final ownerA = await ownerAFuture.timeout(const Duration(seconds: 5));
      expect(ownerA?.conversationId, threadA);
      final poisonEvidence = ToolResultPromptBuilder.completionEvidence(
        dataSource.toolResultBatches.first,
      );
      expect(poisonEvidence.hasFailedExecutionVerification, isTrue);

      final ownerAGoal = _goalFor(container, threadA);
      ownerBGoal = _goalFor(container, threadB);
      expect(ownerAGoal?.status, ConversationGoalStatus.active);
      expect(ownerAGoal?.turnsUsed, 1);
      expect(ownerAGoal?.tokenUsage, 11);
      expect(
        container
            .read(conversationsNotifierProvider)
            .conversationForId(threadA)!
            .messages
            .lastWhere((message) => message.role == MessageRole.assistant)
            .responseMetrics
            ?.totalTokens,
        11,
      );
      expect(ownerBGoal?.status, ConversationGoalStatus.active);
      expect(ownerBGoal?.turnsUsed, 0);

      releaseOwnerBPersistence.complete();
      final ownerB = await ownerBFuture.timeout(const Duration(seconds: 5));
      expect(ownerB?.conversationId, threadB);
      ownerBGoal = _goalFor(container, threadB);
      expect(ownerBGoal?.status, ConversationGoalStatus.completed);
      expect(ownerBGoal?.turnsUsed, 1);
      expect(ownerBGoal?.tokenUsage, 97);
      expect(ownerBGoal?.completedAt, isNotNull);
      expect(dataSource.finishReasonReads, 0);
      expect(dataSource.usageReads, 0);
      expect(
        container
            .read(conversationsNotifierProvider)
            .conversationForId(threadB)!
            .messages
            .lastWhere((message) => message.role == MessageRole.assistant)
            .responseMetrics
            ?.totalTokens,
        97,
      );
    },
  );

  test(
    'hidden goal evidence is seeded only when explicitly supplied',
    () async {
      final dataSource = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(
            content: 'Checking the seeded completion claim.',
            toolCalls: [
              ToolCallInfo(
                id: 'seeded-goal-claim',
                name: 'update_goal',
                arguments: const {'completed': true},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Checking the unseeded completion claim.',
            toolCalls: [
              ToolCallInfo(
                id: 'unseeded-goal-claim',
                name: 'update_goal',
                arguments: const {'completed': true},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        toolResultResponses: [
          ChatCompletionResult(
            content: 'First report acknowledged.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Second report acknowledged.',
            finishReason: 'stop',
          ),
        ],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _GoalUpdateToolService(),
      );
      addTearDown(container.dispose);

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      await conversations.saveCurrentGoal(
        objective: 'Verify explicit hidden-turn evidence handoff',
        enabled: true,
        status: ConversationGoalStatus.active,
        tokenBudget: 1000,
        turnBudget: 5,
      );

      final notifier = container.read(chatNotifierProvider.notifier);
      final seededOwner = await notifier.sendHiddenPrompt(
        'Reject the seeded completion claim.',
        persistAssistantResponse: true,
        initialGoalCompletionEvidence: const ToolResultCompletionEvidence(
          hasFailedExecutionVerification: true,
        ),
        allowedToolNames: const {'update_goal'},
      );
      expect(seededOwner, isNotNull);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(
        dataSource.toolResultBatches.first.single.result,
        allOf(
          contains('Completion not recorded'),
          contains('the last verification command failed'),
        ),
      );
      var goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(goal?.status, ConversationGoalStatus.active);
      expect(goal?.turnsUsed, 1);

      final unseededOwner = await notifier.sendHiddenPrompt(
        'Accept the fresh completion claim.',
        persistAssistantResponse: true,
        allowedToolNames: const {'update_goal'},
      );
      expect(unseededOwner, isNotNull);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.last.single.result,
        contains('Completion accepted'),
      );
      goal = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(goal?.status, ConversationGoalStatus.completed);
      expect(goal?.turnsUsed, 2);
    },
  );

  test('detached accepted goal claim completes only its exact owner', () async {
    final ownerAClaimReady = Completer<void>();
    final releaseOwnerA = Completer<void>();
    final sessionLogRoot = await Directory.systemTemp.createTemp(
      'caverno_detached_goal_claim_',
    );
    final sessionLogStore = LlmSessionLogStore(
      rootDirectoryProvider: () async => sessionLogRoot,
    );
    final dataSource = ScriptedChatDataSource(
      initialResponses: [
        ChatCompletionResult(
          content: 'Owner A is recording its completion claim.',
          toolCalls: [
            ToolCallInfo(
              id: 'complete-owner-a-goal',
              name: 'update_goal',
              arguments: const {
                'completed': true,
                'message': 'Owner A acceptance checks passed.',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Owner B is still working on its goal.',
          finishReason: 'stop',
        ),
      ],
      toolResultResponses: [
        ChatCompletionResult(
          content: 'Owner A ran its acceptance checks.',
          finishReason: 'stop',
        ),
      ],
      beforeToolResultResponse: (requestIndex) async {
        if (requestIndex != 0) return;
        if (!ownerAClaimReady.isCompleted) {
          ownerAClaimReady.complete();
        }
        await releaseOwnerA.future;
      },
    );
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: _GoalUpdateToolService(),
      sessionLogStore: sessionLogStore,
    );
    addTearDown(() async {
      if (!releaseOwnerA.isCompleted) releaseOwnerA.complete();
      container.dispose();
      if (sessionLogRoot.existsSync()) {
        await sessionLogRoot.delete(recursive: true);
      }
    });

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    await conversations.saveCurrentGoal(
      objective: 'Complete owner A acceptance checks',
      enabled: true,
      status: ConversationGoalStatus.active,
      tokenBudget: 1000,
      turnBudget: 5,
    );

    final notifier = container.read(chatNotifierProvider.notifier);
    final ownerAFuture = notifier.sendMessage(
      'Finish owner A goal.',
      bypassPlanMode: true,
    );
    await ownerAClaimReady.future.timeout(const Duration(seconds: 2));

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final threadB = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    await conversations.saveCurrentGoal(
      objective: 'Continue owner B implementation',
      enabled: true,
      status: ConversationGoalStatus.active,
      tokenBudget: 1000,
      turnBudget: 5,
    );
    final ownerB = await notifier
        .sendMessage('Continue owner B goal.', bypassPlanMode: true)
        .timeout(const Duration(seconds: 5));

    expect(ownerB?.conversationId, threadB);
    final ownerBGoalBeforeRelease = container
        .read(conversationsNotifierProvider)
        .conversations
        .singleWhere((conversation) => conversation.id == threadB)
        .goal;
    expect(ownerBGoalBeforeRelease?.status, ConversationGoalStatus.active);

    releaseOwnerA.complete();
    final ownerA = await ownerAFuture.timeout(const Duration(seconds: 5));
    expect(ownerA?.conversationId, threadA);

    final persisted = container
        .read(conversationsNotifierProvider)
        .conversations;
    final ownerAGoal = persisted
        .singleWhere((conversation) => conversation.id == threadA)
        .goal;
    final ownerBGoal = persisted
        .singleWhere((conversation) => conversation.id == threadB)
        .goal;
    expect(ownerAGoal?.status, ConversationGoalStatus.completed);
    expect(ownerAGoal?.turnsUsed, 1);
    expect(ownerAGoal?.completedAt, isNotNull);
    expect(ownerBGoal?.status, ConversationGoalStatus.active);
    expect(ownerBGoal?.turnsUsed, 1);
    expect(ownerBGoal?.completedAt, isNull);

    Future<List<Map<String, dynamic>>> shadowEntriesFor(
      String conversationId,
    ) async {
      final file = await sessionLogStore.fileForContext(
        LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: conversationId,
          conversationId: conversationId,
        ),
        create: false,
      );
      final entries = (await file.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      return entries
          .where((entry) => entry['operation'] == 'goal_completion_shadow')
          .toList(growable: false);
    }

    final ownerAShadows = await shadowEntriesFor(threadA);
    final ownerBShadows = await shadowEntriesFor(threadB);
    expect(ownerAShadows, hasLength(1));
    expect(
      ownerAShadows.single['goalCompletionShadow'],
      containsPair('label', 'goal_completion_tool_accepted_lexical_missed'),
    );
    expect(
      ownerAShadows.single['goalCompletionShadow'],
      containsPair('toolOutcome', 'completionRecorded'),
    );
    expect(
      ownerAShadows.single['goalCompletionShadow'],
      containsPair('lexicalCompleted', false),
    );
    expect(ownerBShadows, isEmpty);
  });
}

final class _GoalUpdateToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'update_goal',
        'description': 'Record progress or completion for the active goal',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    throw StateError('update_goal must be intercepted by ChatNotifier');
  }
}

final class _FailedVerificationGoalToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    for (final name in ['local_execute_command', 'update_goal'])
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': 'Test tool $name',
          'parameters': const <String, dynamic>{'type': 'object'},
        },
      },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name == 'update_goal') {
      throw StateError('update_goal must be intercepted by ChatNotifier');
    }
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'command': arguments['command'],
        'working_directory': arguments['working_directory'],
        'exit_code': 1,
        'stdout': '',
        'stderr': 'Owner A test failed.',
      }),
      isSuccess: true,
    );
  }
}

/// Returns a fixed structured outcome so the loop's carrying of it is testable.
class _ReportedOutcomeToolService extends McpToolService {
  _ReportedOutcomeToolService(this.outcome);

  final ToolOutcome outcome;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'list_directory',
        'description': 'List a directory',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async => McpToolResult(
    toolName: name,
    result: '{"exit_code":2}',
    isSuccess: true,
    outcome: outcome,
  );
}

// Live canary for mid-turn interruption (steering).
//
// The unit tests prove delivery: the interrupting message reaches the request
// payload in the right order with its directive attached. They cannot prove
// obedience -- whether a real model actually changes course when it arrives.
// That is what this canary measures, and it measures it from the filesystem
// rather than from the model's prose.
//
// Two arms share one scenario. The turn is told to create `alpha`, and a
// message arrives mid-flight telling it to create `beta` instead and to leave
// `alpha` alone:
//
//   steer arm (interrupt: true)   -> expect beta only
//   queue arm (interrupt: false)  -> expect alpha AND beta
//
// The discriminator is whether `alpha` was ever created. Without the queue arm
// the canary would prove nothing, because the model reaches `beta` either way:
// queued, it just gets there one turn later.
//
// Delivery and obedience are asserted separately on purpose. Both failure
// modes -- "the steer was silently requeued" and "the steer arrived and was
// ignored" -- leave the same `alpha` on disk, and only the separate delivery
// assertion says which one happened. That is the difference between moving the
// directive and rethinking the approach.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/turn_steering_prompt_builder.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const String _alphaPath = 'lib/alpha_note.txt';
const String _betaPath = 'lib/beta_note.txt';
const String _alphaMarker = 'ALPHA_MARKER_OK';
const String _betaMarker = 'BETA_MARKER_OK';
const String _seedPath = 'lib/plan_note.txt';

// The opening instruction withholds the target file, so the write cannot be
// batched into the same assistant response as the read: the model has to see
// the read result before it can name anything. That is what puts the mutation
// decision inside the continuation request -- the one an interruption rides
// in on. A prompt that names the target up front measures nothing, because
// the model emits both tool calls at once and the interruption arrives after
// the write is already committed.
const String _openingPrompt =
    'Read $_seedPath with read_file. It names exactly one file to create and '
    'the exact content to put in it. Do what it says, then finish with a '
    'one-line summary of what you wrote.';

const String _redirectPrompt =
    'Change of plan: whatever $_seedPath told you to create, do NOT create '
    'it. Create $_betaPath instead, containing exactly $_betaMarker. If you '
    'already created the other file, say so plainly.';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_TURN_STEERING_LIVE_CANARY'] == '1';
  final runLabel = Platform.environment['CAVERNO_TURN_STEERING_RUN_LABEL']
      ?.trim();
  final prefix = runLabel == null || runLabel.isEmpty ? '' : '[$runLabel] ';
  final skipReason = liveEnabled
      ? null
      : 'Set CAVERNO_TURN_STEERING_LIVE_CANARY=1 and CAVERNO_LLM_* to run.';

  test(
    '${prefix}an interruption redirects the turn it joined',
    () => _runArm(interrupt: true, runLabel: runLabel),
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    '${prefix}a queued message cannot redirect the turn it waited behind',
    () => _runArm(interrupt: false, runLabel: runLabel),
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _runArm({
  required bool interrupt,
  required String? runLabel,
}) async {
  final env = _SteeringLiveEnv.fromEnvironment();
  final arm = interrupt ? 'steer' : 'queue';
  final fixture = _SteeringFixture.create(env.workspaceRoot, arm: arm);
  final dataSource = _RecordingDataSource(
    ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
  );
  final toolService = _SteeringSandboxToolService(fixture.root);
  final container = _buildContainer(
    env: env,
    dataSource: dataSource,
    toolService: toolService,
    project: fixture.project,
  );

  try {
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: fixture.project.id,
    );

    final notifier = container.read(chatNotifierProvider.notifier);

    // Fire on the first tool execution. The turn is mid-flight and has at
    // least one more request to build, so the carried path is reached without
    // depending on wall-clock timing.
    Future<ChatTurnOwner?>? redirect;
    toolService.onFirstToolExecution = () {
      redirect ??= notifier.sendMessage(
        _redirectPrompt,
        bypassPlanMode: true,
        interrupt: interrupt,
      );
    };

    await notifier.sendMessage(_openingPrompt, bypassPlanMode: true);
    await redirect;
    await _waitUntilSettled(
      container,
      dataSource,
      // The queue arm must run a second turn before it is done; the steer arm
      // must not need one.
      minTurns: interrupt ? 1 : 2,
    );

    final alphaExists = fixture.file(_alphaPath).existsSync();
    final betaExists = fixture.file(_betaPath).existsSync();
    final betaContent = betaExists
        ? fixture.file(_betaPath).readAsStringSync()
        : '';
    final snapshot = <String, dynamic>{
      'schemaName': 'turn_steering_live_canary_snapshot',
      'schemaVersion': 1,
      'runLabel': runLabel ?? '',
      'arm': arm,
      'model': env.model,
      'turnCount': dataSource.turnCount,
      'requestCount': dataSource.requestCount,
      'steerCarriedInRequests': dataSource.requestIndexesCarryingSteer,
      'directiveCarriedInRequests': dataSource.requestIndexesCarryingDirective,
      'alphaCreated': alphaExists,
      'betaCreated': betaExists,
      'betaHasMarker': betaContent.contains(_betaMarker),
      // Only the tools that reached the sandbox service. File mutations are
      // dispatched by the notifier's own file handler and never appear here,
      // which is why the verdict below reads the filesystem instead.
      'sandboxExecutedTools': toolService.executedToolNames,
      // The verdict this arm exists to produce. Recorded rather than only
      // asserted so a repeated run can be read as a rate instead of a
      // pass/fail on a single sample of a probabilistic behavior.
      'redirected': interrupt
          ? betaExists && !alphaExists
          : betaExists && alphaExists,
    };
    // ignore: avoid_print
    print('TURN_STEERING_CANARY_SNAPSHOT ${jsonEncode(snapshot)}');

    final diagnostic = _diagnostic(snapshot, container);

    if (interrupt) {
      // Delivery. Mechanical, so this must hold on every run; when it fails
      // the model never saw the interruption and its behavior says nothing.
      expect(
        dataSource.requestIndexesCarryingSteer,
        isNotEmpty,
        reason: 'No request carried the interrupting message.\n$diagnostic',
      );
      expect(
        dataSource.requestIndexesCarryingDirective,
        isNotEmpty,
        reason: 'No request carried the steering directive.\n$diagnostic',
      );
      expect(
        dataSource.turnCount,
        1,
        reason:
            'Steering must join the running turn, not start another.\n'
            '$diagnostic',
      );

      // Obedience. This is the model-behavior claim and the reason the canary
      // exists.
      expect(
        betaExists,
        isTrue,
        reason: 'The redirected file was never created.\n$diagnostic',
      );
      expect(
        betaContent,
        contains(_betaMarker),
        reason: 'The redirected file lacks its marker.\n$diagnostic',
      );
      expect(
        alphaExists,
        isFalse,
        reason:
            'The turn finished its original instruction despite the '
            'interruption.\n$diagnostic',
      );
    } else {
      // The control arm. Its job is to show the discriminator is real: with
      // the same words queued instead of steered, the original file is still
      // created because the turn ran to completion first.
      expect(
        dataSource.requestIndexesCarryingDirective,
        isEmpty,
        reason:
            'A queued message must not engage steering.\n$diagnostic',
      );
      expect(
        dataSource.turnCount,
        greaterThanOrEqualTo(2),
        reason: 'The queued message never ran as its own turn.\n$diagnostic',
      );
      expect(
        alphaExists,
        isTrue,
        reason:
            'The control arm did not create the original file, so this '
            'scenario cannot discriminate steering from queueing. Fix the '
            'scenario before reading the steer arm.\n$diagnostic',
      );
      expect(
        betaExists,
        isTrue,
        reason: 'The queued turn never created its file.\n$diagnostic',
      );
    }
  } finally {
    container.dispose();
    fixture.dispose();
  }
}

String _diagnostic(Map<String, dynamic> snapshot, ProviderContainer container) {
  final messages = container.read(chatNotifierProvider).messages;
  final transcript = messages
      .map((message) {
        final role = message.role.name;
        final content = message.content.trim().replaceAll('\n', ' ');
        final clipped = content.length > 240
            ? '${content.substring(0, 240)}...'
            : content;
        return '  $role: $clipped';
      })
      .join('\n');
  return 'snapshot: ${jsonEncode(snapshot)}\ntranscript:\n$transcript';
}

/// Waits for the arm to be finished rather than merely between requests.
///
/// `isLoading` drops in the gap between a finished turn and the queue drain
/// that follows it, so the queue arm would otherwise be read as done one turn
/// early. The condition has to hold across consecutive polls for the same
/// reason.
Future<void> _waitUntilSettled(
  ProviderContainer container,
  _RecordingDataSource dataSource, {
  required int minTurns,
  Duration timeout = const Duration(minutes: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  var stableChecks = 0;
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    // A turn that errored is never going to settle into the shape below, and
    // waiting out the timeout buries the endpoint error that actually explains
    // the run.
    final error = state.error;
    if (error != null && error.isNotEmpty) {
      throw StateError('The turn failed before the canary could judge it: $error');
    }
    final settled =
        !state.isLoading &&
        state.queuedMessages.isEmpty &&
        state.steeringMessages.isEmpty &&
        dataSource.turnCount >= minTurns &&
        state.messages.any(
          (message) =>
              message.role == MessageRole.assistant && !message.isStreaming,
        );
    stableChecks = settled ? stableChecks + 1 : 0;
    if (stableChecks >= 5) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for the turn steering canary to settle '
    '(turns=${dataSource.turnCount}, wanted>=$minTurns).',
  );
}

ProviderContainer _buildContainer({
  required _SteeringLiveEnv env,
  required _RecordingDataSource dataSource,
  required _SteeringSandboxToolService toolService,
  required CodingProject project,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(() => _LiveSettingsNotifier(env)),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _LiveCodingProjectsNotifier(project),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

class _SteeringLiveEnv {
  const _SteeringLiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    required this.workspaceRoot,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;
  final String? workspaceRoot;

  static _SteeringLiveEnv fromEnvironment() {
    return _SteeringLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_TURN_STEERING_MAX_TOKENS'] ?? '',
          ) ??
          4096,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_TURN_STEERING_TEMPERATURE'] ?? '',
          ) ??
          0.1,
      workspaceRoot:
          Platform.environment['CAVERNO_TURN_STEERING_WORK_ROOT']?.trim(),
    );
  }

  static String _requiredEnv(String name) {
    final value = Platform.environment[name]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('$name must be set for the turn steering live canary.');
    }
    return value;
  }
}

class _SteeringFixture {
  _SteeringFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;

  File file(String relativePath) => File('${root.path}/$relativePath');

  static _SteeringFixture create(String? workspaceRoot, {required String arm}) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('turn_steering_canary_')
        : Directory('$workspaceRoot/$arm');
    if (root.existsSync() && !deleteOnDispose) {
      root.deleteSync(recursive: true);
    }
    root.createSync(recursive: true);
    final lib = Directory('${root.path}/lib')..createSync(recursive: true);
    File('${lib.path}/plan_note.txt').writeAsStringSync(
      'TASK: create the file $_alphaPath containing exactly $_alphaMarker '
      'and nothing else.\n',
    );
    return _SteeringFixture(
      root: root,
      project: CodingProject(
        id: 'turn-steering-canary',
        name: 'Turn Steering Canary',
        rootPath: root.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  void dispose() {
    if (!deleteOnDispose) return;
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// Records what each outgoing request carried.
///
/// This is the delivery instrument: it answers "did the interruption reach the
/// model, and in which request" independently of what the model then did.
class _RecordingDataSource implements ChatDataSource {
  _RecordingDataSource(this.delegate);

  final ChatRemoteDataSource delegate;

  /// Every request this arm issued, in order, as flattened payload text.
  final List<String> requests = [];

  /// One per turn: the opening request of a turn is the only tool-aware
  /// stream it makes, so counting them counts turns.
  int turnCount = 0;

  int get requestCount => requests.length;

  List<int> get requestIndexesCarryingSteer => _indexesContaining(
    _redirectPrompt.substring(0, 40),
  );

  List<int> get requestIndexesCarryingDirective =>
      _indexesContaining(TurnSteeringPromptBuilder.marker);

  List<int> _indexesContaining(String needle) {
    final result = <int>[];
    for (var index = 0; index < requests.length; index += 1) {
      if (requests[index].contains(needle)) result.add(index);
    }
    return result;
  }

  void _record(List<Message> messages) {
    requests.add(messages.map((message) => message.content).join('\n'));
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    _record(messages);
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
    _record(messages);
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
    turnCount += 1;
    _record(messages);
    return delegate.streamChatCompletionWithTools(
      messages: messages,
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
    _record(messages);
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
    _record(messages);
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
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    _record(messages);
    return delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

/// A real tool service over a sandbox directory, with a hook on the first
/// execution so the interruption lands at a deterministic point in the turn.
class _SteeringSandboxToolService extends McpToolService {
  _SteeringSandboxToolService(this.root);

  final Directory root;
  final List<String> executedToolNames = [];
  final List<String> writtenPaths = [];
  void Function()? onFirstToolExecution;
  bool _fired = false;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': 'list_directory',
          'description': 'List files in the turn steering canary fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'description': 'Read a UTF-8 text file from the fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
            'required': ['path'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description': 'Write a UTF-8 text file into the fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
            },
            'required': ['path', 'content'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeFileTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (!_fired) {
      _fired = true;
      onFirstToolExecution?.call();
    }
    return _execute(name, arguments);
  }

  Future<McpToolResult> _execute(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      switch (name) {
        case 'list_directory':
          final target = _resolve(arguments['path'] as String?, allowEmpty: true);
          final entries = Directory(target)
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => _relative(file.path))
              .toList(growable: false)
            ..sort();
          return _ok(name, jsonEncode({'entries': entries}));
        case 'read_file':
          final target = _resolve(arguments['path'] as String?);
          final file = File(target);
          if (!file.existsSync()) {
            return _fail(name, 'File not found: ${_relative(target)}');
          }
          return _ok(name, file.readAsStringSync());
        case 'write_file':
          final target = _resolve(arguments['path'] as String?);
          final content = arguments['content'] as String? ?? '';
          final file = File(target)..createSync(recursive: true);
          file.writeAsStringSync(content);
          final relative = _relative(target);
          writtenPaths.add(relative);
          return _ok(
            name,
            jsonEncode({
              'status': 'written',
              'path': relative,
              'bytes': content.length,
            }),
          );
        default:
          return _fail(name, 'code=tool_not_available name=$name');
      }
    } on Object catch (error) {
      return _fail(name, error.toString());
    }
  }

  McpToolResult _ok(String name, String result) =>
      McpToolResult(toolName: name, result: result, isSuccess: true);

  McpToolResult _fail(String name, String result) =>
      McpToolResult(toolName: name, result: result, isSuccess: false);

  String _resolve(String? path, {bool allowEmpty = false}) {
    final trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) {
      if (allowEmpty) return root.path;
      throw ArgumentError('path is required');
    }
    final absolute = trimmed.startsWith('/')
        ? trimmed
        : '${root.path}/$trimmed';
    final normalized = File(absolute).absolute.path;
    if (!normalized.startsWith(root.path)) {
      throw ArgumentError('path escapes the fixture root: $trimmed');
    }
    return normalized;
  }

  String _relative(String absolute) {
    if (!absolute.startsWith(root.path)) return absolute;
    return absolute
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
  }
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env);

  final _SteeringLiveEnv env;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.coding,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: true,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      demoMode: false,
    );
  }
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  _LiveCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() {
    return CodingProjectsState(
      projects: [project],
      selectedProjectId: project.id,
    );
  }

  @override
  Future<bool> ensureProjectAccess(String? projectId) async {
    return projectId == project.id;
  }
}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
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

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

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

class _MockConversationBox extends Mock implements Box<String> {}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

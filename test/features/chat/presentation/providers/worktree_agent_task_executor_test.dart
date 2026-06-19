import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  late List<WorktreeAgentTaskExecutionContext> contexts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    contexts = <WorktreeAgentTaskExecutionContext>[];
    container = _container(
      prefs,
      delegate: (context) async {
        contexts.add(context);
        return const WorktreeAgentTaskExecutionOutcome(
          resultSummary: 'Implemented the assigned change.',
          verifiedGreen: true,
          verificationSummary: 'flutter test passed',
        );
      },
    );
  });

  tearDown(() {
    container.dispose();
  });

  WorktreeAgentTaskRegistryNotifier registry() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider.notifier);

  WorktreeAgentTaskRegistryState registryState() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider);

  WorktreeAgentTaskExecutor executor() =>
      container.read(worktreeAgentTaskExecutorProvider);

  test('executes a running task and stores completion metadata', () async {
    final task = await _registerRunningTask(registry());

    final result = await executor().execute(task.id);

    expect(result.success, isTrue);
    expect(result.resultSummary, 'Implemented the assigned change.');
    expect(result.verifiedGreen, isTrue);
    expect(result.verificationSummary, 'flutter test passed');
    expect(contexts, hasLength(1));
    expect(contexts.single.taskId, task.id);
    expect(contexts.single.worktreePath, '/tmp/caverno-worktrees/fix-test');
    expect(contexts.single.branchName, 'feature/ll13-fix-test');
    expect(contexts.single.checkpointLineageId, 'checkpoint-1');
    expect(contexts.single.endpointId, 'mesh-1');

    final completed = registryState().byId(task.id)!;
    expect(completed.status, WorktreeAgentTaskStatus.completed);
    expect(completed.resultSummary, 'Implemented the assigned change.');
    expect(completed.verifiedGreen, isTrue);
    expect(completed.verificationSummary, 'flutter test passed');
  });

  test('marks a running task failed when the delegate throws', () async {
    container.dispose();
    contexts = <WorktreeAgentTaskExecutionContext>[];
    container = _container(
      prefs,
      delegate: (context) async {
        contexts.add(context);
        throw StateError('agent failed');
      },
    );
    final task = await _registerRunningTask(registry());

    final result = await executor().execute(task.id);

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('agent failed'));
    expect(contexts.single.taskId, task.id);
    final failed = registryState().byId(task.id)!;
    expect(failed.status, WorktreeAgentTaskStatus.failed);
    expect(failed.error, contains('agent failed'));
    expect(failed.finishedAt, isNotNull);
  });

  test('does not execute tasks that are not running', () async {
    final task = await registry().registerTask(
      title: 'Fix test',
      prompt: 'Fix the failing test.',
      branchName: 'feature/ll13-fix-test',
      worktreePath: '/tmp/caverno-worktrees/fix-test',
    );

    final result = await executor().execute(task.id);

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('running'));
    expect(contexts, isEmpty);
    expect(
      registryState().byId(task.id)!.status,
      WorktreeAgentTaskStatus.queued,
    );
  });

  test(
    'default delegate verifies a completed worktree-scoped subagent',
    () async {
      container.dispose();
      final dataSource = _RecordingChatDataSource(
        result: ChatCompletionResult(
          content: 'Updated lib/example.dart.',
          finishReason: 'stop',
        ),
      );
      final verificationCommands = <WorktreeAgentVerificationCommand>[];
      container = _containerWithDefaultDelegate(
        prefs,
        dataSource: dataSource,
        toolService: _RecordingMcpToolService(
          toolDefinitions: const [
            _readFileToolDefinition,
            _editFileToolDefinition,
            _localCommandToolDefinition,
          ],
        ),
        verificationRunner: WorktreeAgentVerificationRunner(
          commandRunner: (command, timeout) async {
            verificationCommands.add(command);
            return const WorktreeAgentVerificationCommandOutput(
              exitCode: 0,
              stdout: 'All tests passed.',
            );
          },
        ),
      );
      final task = await _registerRunningTask(
        registry(),
        verificationCommand: 'fvm flutter test test/widget_test.dart',
      );

      final result = await executor().execute(task.id);

      expect(result.success, isTrue);
      expect(result.resultSummary, 'Updated lib/example.dart.');
      expect(result.verifiedGreen, isTrue);
      expect(result.verificationSummary, contains('Verification passed'));
      expect(result.verificationSummary, contains('All tests passed.'));
      expect(dataSource.createChatCompletionCount, 1);
      expect(verificationCommands, hasLength(1));
      expect(verificationCommands.single.executable, 'fvm');
      expect(verificationCommands.single.arguments, [
        'flutter',
        'test',
        'test/widget_test.dart',
      ]);
      expect(
        verificationCommands.single.workingDirectory,
        '/tmp/caverno-worktrees/fix-test',
      );
      final prompt = dataSource.lastMessages
          .map((message) => message.content)
          .join('\n');
      expect(
        prompt,
        contains('Assigned git worktree: /tmp/caverno-worktrees/fix-test'),
      );
      expect(prompt, contains('Assigned branch: feature/ll13-fix-test'));
      expect(prompt, contains('Checkpoint lineage: checkpoint-1'));
      expect(prompt, contains('Assigned endpoint: mesh-1'));
      expect(
        prompt,
        contains(
          'Verification command: fvm flutter test test/widget_test.dart',
        ),
      );
      expect(prompt, contains('Available tools: read_file, edit_file'));
      expect(prompt, isNot(contains('local_execute_command')));

      final completed = registryState().byId(task.id)!;
      expect(completed.status, WorktreeAgentTaskStatus.completed);
      expect(completed.verifiedGreen, isTrue);
      expect(completed.verificationSummary, contains('Verification passed'));
    },
  );

  test(
    'default delegate records a failed verification without failing the task',
    () async {
      container.dispose();
      final dataSource = _RecordingChatDataSource(
        result: ChatCompletionResult(
          content: 'Updated lib/example.dart.',
          finishReason: 'stop',
        ),
      );
      container = _containerWithDefaultDelegate(
        prefs,
        dataSource: dataSource,
        toolService: _RecordingMcpToolService(
          toolDefinitions: const [_readFileToolDefinition],
        ),
        verificationRunner: WorktreeAgentVerificationRunner(
          commandRunner: (command, timeout) async {
            return const WorktreeAgentVerificationCommandOutput(
              exitCode: 1,
              stderr: 'Expected true but was false.',
            );
          },
        ),
      );
      final task = await _registerRunningTask(
        registry(),
        verificationCommand: 'dart test test/failing_test.dart',
      );

      final result = await executor().execute(task.id);

      expect(result.success, isTrue);
      expect(result.verifiedGreen, isFalse);
      expect(result.verificationSummary, contains('Verification failed'));
      expect(result.verificationSummary, contains('Expected true'));
      final completed = registryState().byId(task.id)!;
      expect(completed.status, WorktreeAgentTaskStatus.completed);
      expect(completed.verifiedGreen, isFalse);
      expect(completed.error, isEmpty);
    },
  );

  test(
    'scoped dispatcher confines file paths to the assigned worktree',
    () async {
      final toolService = _RecordingMcpToolService(
        toolDefinitions: const [
          _readFileToolDefinition,
          _searchFilesToolDefinition,
        ],
      );
      final dispatcher = WorktreeAgentScopedToolDispatcher(
        toolService: toolService,
        worktreePath: '/tmp/caverno-worktrees/fix-test',
      );

      final readResult = await dispatcher.dispatch(
        ToolCallInfo(
          id: 'call-read',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
        ),
      );
      final searchResult = await dispatcher.dispatch(
        ToolCallInfo(
          id: 'call-search',
          name: 'search_files',
          arguments: const {'query': 'WorktreeAgent'},
        ),
      );
      final outsideResult = await dispatcher.dispatch(
        ToolCallInfo(
          id: 'call-outside',
          name: 'read_file',
          arguments: const {'path': '../outside.dart'},
        ),
      );

      expect(readResult.isSuccess, isTrue);
      expect(searchResult.isSuccess, isTrue);
      expect(outsideResult.isSuccess, isFalse);
      expect(outsideResult.errorMessage, contains('outside'));
      expect(toolService.executedToolNames, ['read_file', 'search_files']);
      expect(
        toolService.executedToolArguments[0]['path'],
        '/tmp/caverno-worktrees/fix-test/lib/main.dart',
      );
      expect(
        toolService.executedToolArguments[1]['path'],
        '/tmp/caverno-worktrees/fix-test',
      );
    },
  );
}

ProviderContainer _container(
  SharedPreferences prefs, {
  required WorktreeAgentTaskExecutionDelegate delegate,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      worktreeAgentTaskExecutionDelegateProvider.overrideWithValue(delegate),
    ],
  );
}

ProviderContainer _containerWithDefaultDelegate(
  SharedPreferences prefs, {
  required ChatDataSource dataSource,
  required McpToolService toolService,
  WorktreeAgentVerificationRunner? verificationRunner,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      mcpToolServiceProvider.overrideWithValue(toolService),
      if (verificationRunner != null)
        worktreeAgentVerificationRunnerProvider.overrideWithValue(
          verificationRunner,
        ),
    ],
  );
}

Future<WorktreeAgentTask> _registerRunningTask(
  WorktreeAgentTaskRegistryNotifier registry, {
  String verificationCommand = '',
}) async {
  final task = await registry.registerTask(
    title: 'Fix test',
    prompt: 'Fix the failing test.',
    branchName: 'feature/ll13-fix-test',
    worktreePath: '/tmp/caverno-worktrees/fix-test',
    checkpointLineageId: 'checkpoint-1',
    endpointId: 'mesh-1',
    verificationCommand: verificationCommand,
  );
  await registry.markRunning(task.id);
  return task.copyWith(status: WorktreeAgentTaskStatus.running);
}

const Map<String, dynamic> _readFileToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'read_file',
    'description': 'Read a file.',
    'parameters': {'type': 'object'},
  },
};

const Map<String, dynamic> _editFileToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'edit_file',
    'description': 'Edit a file.',
    'parameters': {'type': 'object'},
  },
};

const Map<String, dynamic> _searchFilesToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'search_files',
    'description': 'Search files.',
    'parameters': {'type': 'object'},
  },
};

const Map<String, dynamic> _localCommandToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'local_execute_command',
    'description': 'Run a local command.',
    'parameters': {'type': 'object'},
  },
};

class _RecordingChatDataSource extends ChatDataSource {
  _RecordingChatDataSource({required this.result});

  final ChatCompletionResult result;
  int createChatCompletionCount = 0;
  List<Message> lastMessages = const <Message>[];
  String? lastModel;
  double? lastTemperature;
  int? lastMaxTokens;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    createChatCompletionCount++;
    lastMessages = messages;
    lastModel = model;
    lastTemperature = temperature;
    lastMaxTokens = maxTokens;
    return result;
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => const Stream<String>.empty();

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
  }) => const Stream<String>.empty();

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
  }) async => result;
}

class _RecordingMcpToolService extends McpToolService {
  _RecordingMcpToolService({required this.toolDefinitions});

  final List<Map<String, dynamic>> toolDefinitions;
  final List<String> executedToolNames = <String>[];
  final List<Map<String, dynamic>> executedToolArguments =
      <Map<String, dynamic>>[];

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return toolDefinitions;
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedToolArguments.add(Map<String, dynamic>.from(arguments));
    return McpToolResult(toolName: name, result: 'ok', isSuccess: true);
  }
}

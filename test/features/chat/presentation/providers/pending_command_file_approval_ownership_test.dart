import 'dart:async';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingToolApprovalRegistry command and file requests', () {
    test('finds requests by type without removing them', () {
      final registry = PendingToolApprovalRegistry();
      final owner = _owner('conversation-a', 1);
      final pending = _local(owner: owner, id: 'local-1');

      registry.register(pending);

      expect(registry.length, 1);
      expect(registry.find<PendingLocalCommand>(pending.id), same(pending));
      expect(registry.find<PendingGitCommand>(pending.id), isNull);
      expect(registry.length, 1);
    });

    test('take rejects stale and cross-conversation owners', () {
      final registry = PendingToolApprovalRegistry();
      final owner = _owner('conversation-a', 1);
      final staleOwner = _owner('conversation-a', 2);
      final otherOwner = _owner('conversation-b', 1);
      final pending = _local(owner: owner, id: 'local-1');
      registry.register(pending);

      expect(
        registry.take<PendingLocalCommand>(owner: staleOwner, id: pending.id),
        isNull,
      );
      expect(
        registry.take<PendingLocalCommand>(owner: otherOwner, id: pending.id),
        isNull,
      );
      expect(registry.cancel(owner: staleOwner, id: pending.id), isFalse);
      expect(registry.find<PendingLocalCommand>(pending.id), same(pending));

      expect(
        registry.take<PendingLocalCommand>(owner: owner, id: pending.id),
        same(pending),
      );
      expect(
        registry.take<PendingLocalCommand>(owner: owner, id: pending.id),
        isNull,
      );
      expect(registry.isEmpty, isTrue);
    });

    test('registerCurrent never presents an already-stale request', () async {
      final registry = PendingToolApprovalRegistry();
      final pending = _file(
        owner: _owner('conversation-a', 1),
        id: 'file-stale',
      );
      var showCount = 0;

      final result = registry.registerCurrent(
        pending,
        ownerIsCurrent: false,
        show: () => showCount += 1,
      );

      expect(await result, isFalse);
      expect(showCount, 0);
      expect(registry.isEmpty, isTrue);
    });

    test('takeCurrent cancels only the stale owner request', () async {
      final registry = PendingToolApprovalRegistry();
      final staleOwner = _owner('conversation-a', 1);
      final currentOwner = _owner('conversation-a', 2);
      final stale = _local(owner: staleOwner, id: 'local-stale');
      final current = _local(owner: currentOwner, id: 'local-current');
      final cleared = <String>[];
      registry
        ..register(stale)
        ..register(current);

      expect(
        registry.takeCurrent<PendingLocalCommand>(
          id: stale.id,
          ownerIsCurrent: (owner) => owner == currentOwner,
          clear: (request) => cleared.add(request.id),
        ),
        isNull,
      );

      expect((await stale.completer.future).approved, isFalse);
      expect(cleared, [stale.id]);
      expect(registry.find<PendingLocalCommand>(current.id), same(current));
      expect(
        registry.takeCurrent<PendingLocalCommand>(
          id: current.id,
          ownerIsCurrent: (owner) => owner == currentOwner,
          clear: (request) => cleared.add(request.id),
        ),
        same(current),
      );
      expect(cleared, [stale.id, current.id]);
    });

    test(
      'cancelOwner completes every request with its safe denial value',
      () async {
        final registry = PendingToolApprovalRegistry();
        final owner = _owner('conversation-a', 1);
        final sshConnect = _sshConnect(owner: owner, id: 'ssh-connect-1');
        final sshCommand = _sshCommand(owner: owner, id: 'ssh-command-1');
        final git = _git(owner: owner, id: 'git-1');
        final local = _local(owner: owner, id: 'local-1');
        final file = _file(owner: owner, id: 'file-1');
        for (final request in <PendingToolApproval<dynamic>>[
          sshConnect,
          sshCommand,
          git,
          local,
          file,
        ]) {
          registry.register(request);
        }

        expect(registry.cancelOwner(owner), hasLength(5));

        expect(await sshConnect.completer.future, isNull);
        expect(await sshCommand.completer.future, isFalse);
        expect(await git.completer.future, isFalse);
        final localDecision = await local.completer.future;
        expect(localDecision.approved, isFalse);
        expect(localDecision.shouldRemember, isFalse);
        expect(await file.completer.future, isFalse);
        expect(registry.isEmpty, isTrue);
      },
    );

    test('owner cancellation leaves another owner pending', () async {
      final registry = PendingToolApprovalRegistry();
      final ownerA = _owner('conversation-a', 1);
      final ownerB = _owner('conversation-b', 1);
      final local = _local(owner: ownerA, id: 'local-a');
      final file = _file(owner: ownerB, id: 'file-b');
      registry
        ..register(local)
        ..register(file);

      expect(registry.cancelOwner(ownerA), hasLength(1));

      expect((await local.completer.future).approved, isFalse);
      expect(file.completer.isCompleted, isFalse);
      expect(registry.find<PendingFileOperation>(file.id), same(file));
      expect(registry.cancel(owner: ownerB, id: file.id), isTrue);
      expect(await file.completer.future, isFalse);
    });

    test('cancelAll removes requests before late resolutions', () async {
      final registry = PendingToolApprovalRegistry();
      final ownerA = _owner('conversation-a', 1);
      final ownerB = _owner('conversation-b', 1);
      final ssh = _sshCommand(owner: ownerA, id: 'ssh-a');
      final git = _git(owner: ownerB, id: 'git-b');
      registry
        ..register(ssh)
        ..register(git);

      expect(registry.cancelAll(), 2);

      expect(await ssh.completer.future, isFalse);
      expect(await git.completer.future, isFalse);
      expect(registry.cancelAll(), 0);
      expect(registry.cancel(owner: ownerA, id: ssh.id), isFalse);
      expect(
        registry.take<PendingSshCommand>(owner: ownerA, id: ssh.id),
        isNull,
      );
    });

    test('duplicate ids and type mismatches preserve the original request', () {
      final registry = PendingToolApprovalRegistry();
      final ownerA = _owner('conversation-a', 1);
      final ownerB = _owner('conversation-b', 1);
      final original = _local(owner: ownerA, id: 'shared-id');
      final duplicate = _file(owner: ownerB, id: 'shared-id');
      registry.register(original);

      expect(() => registry.register(duplicate), throwsA(isA<StateError>()));
      expect(
        registry.take<PendingFileOperation>(owner: ownerA, id: original.id),
        isNull,
      );
      expect(registry.find<PendingLocalCommand>(original.id), same(original));
      expect(duplicate.completer.isCompleted, isFalse);
      expect(registry.cancelAll(), 1);
    });

    test(
      'cancel removes an already-completed request without completing twice',
      () async {
        final registry = PendingToolApprovalRegistry();
        final owner = _owner('conversation-a', 1);
        final pending = _git(owner: owner, id: 'git-1');
        registry.register(pending);
        pending.completer.complete(true);

        expect(registry.cancel(owner: owner, id: pending.id), isTrue);
        expect(await pending.completer.future, isTrue);
        expect(registry.cancel(owner: owner, id: pending.id), isFalse);
      },
    );
  });

  test(
    'accepted command cannot persist permission or execute after clear',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_stale_command_approval_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
      );
      final repository = _InMemoryConversationRepository();
      final dataSource = _SingleCommandDataSource(projectRoot.path);
      final toolService = _CountingMcpToolService();
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ApprovalPoisonSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _NoopSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final notifier = container.read(chatNotifierProvider.notifier);
      final send = notifier.sendMessage(
        'Run the command.',
        bypassPlanMode: true,
      );
      await _waitUntil(() => notifier.state.pendingLocalCommand != null);
      final pending = notifier.state.pendingLocalCommand!;

      notifier.resolveLocalCommand(
        id: pending.id,
        approval: const LocalCommandApproval(
          approved: true,
          rememberedRuleAction: LocalCommandPermissionAction.allow,
          rememberedRuleMatch: LocalCommandPermissionMatch.exact,
        ),
      );
      notifier.clearMessages();
      await send.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      final settings =
          container.read(settingsNotifierProvider.notifier)
              as _ApprovalPoisonSettingsNotifier;
      expect(settings.upsertCount, 0);
      expect(
        container.read(settingsNotifierProvider).localCommandPermissionRules,
        isEmpty,
      );
      expect(toolService.executedToolNames, isEmpty);
    },
  );
}

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

PendingSshConnect _sshConnect({
  required ChatTurnOwner owner,
  required String id,
}) {
  return PendingSshConnect(
    owner: owner,
    id: id,
    host: 'host.example',
    port: 22,
    username: 'developer',
    savedCredential: null,
    identityCandidates: const [],
    completer: Completer<SshConnectApproval?>(),
  );
}

PendingSshCommand _sshCommand({
  required ChatTurnOwner owner,
  required String id,
}) {
  return PendingSshCommand(
    owner: owner,
    id: id,
    command: 'uname -a',
    reason: 'Inspect the host',
    host: 'host.example',
    username: 'developer',
    completer: Completer<bool>(),
  );
}

PendingGitCommand _git({required ChatTurnOwner owner, required String id}) {
  return PendingGitCommand(
    owner: owner,
    id: id,
    command: 'git commit',
    workingDirectory: '/workspace',
    reason: 'Save the change',
    completer: Completer<bool>(),
  );
}

PendingLocalCommand _local({required ChatTurnOwner owner, required String id}) {
  return PendingLocalCommand(
    owner: owner,
    id: id,
    command: 'dart analyze',
    workingDirectory: '/workspace',
    reason: 'Verify the change',
    warningTitle: null,
    warningMessage: null,
    completer: Completer<LocalCommandApproval>(),
  );
}

PendingFileOperation _file({required ChatTurnOwner owner, required String id}) {
  return PendingFileOperation(
    owner: owner,
    id: id,
    operation: 'edit',
    path: '/workspace/lib/main.dart',
    preview: 'void main() {}',
    reason: 'Apply the change',
    completer: Completer<bool>(),
  );
}

class _ApprovalPoisonSettingsNotifier extends SettingsNotifier {
  int upsertCount = 0;

  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.general,
    mcpEnabled: true,
    demoMode: false,
    enableLlmSessionLogs: false,
  );

  @override
  Future<void> upsertLocalCommandPermissionRule(
    LocalCommandPermissionRule rule,
  ) async {
    upsertCount += 1;
    state = state.copyWith(
      localCommandPermissionRules: [...state.localCommandPermissionRules, rule],
    );
  }
}

class _FixedCodingProjectsNotifier extends CodingProjectsNotifier {
  _FixedCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);

  @override
  Future<bool> ensureProjectAccess(String? projectId) async => true;
}

class _InMemoryConversationRepository implements ConversationRepositoryApi {
  final Map<String, Conversation> _conversations = {};

  @override
  List<Conversation> getAll() => _conversations.values.toList(growable: false);

  @override
  Conversation? getById(String id) => _conversations[id];

  @override
  Future<Conversation?> refresh(String id) async => _conversations[id];

  @override
  Future<void> save(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _conversations.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _conversations.clear();
  }

  @override
  Future<List<Conversation>> search(String query) async => getAll();
}

class _NoopChatMemoryRepository implements ChatMemoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(_NoopChatMemoryRepository());

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

class _CountingMcpToolService extends McpToolService {
  final List<String> executedToolNames = [];

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
        'name': 'local_execute_command',
        'description': 'Execute a local command.',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    return McpToolResult(toolName: name, result: 'executed', isSuccess: true);
  }
}

class _SingleCommandDataSource implements ChatDataSource {
  _SingleCommandDataSource(this.workingDirectory);

  final String workingDirectory;

  ChatCompletionResult get _stop =>
      ChatCompletionResult(content: 'Stopped.', finishReason: 'stop');

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future.value(
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'command-1',
              name: 'local_execute_command',
              arguments: {
                'command': 'touch stale-command-marker',
                'working_directory': workingDirectory,
                'reason': 'Exercise owner cancellation.',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ),
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(
    Stream<String>.value('Stopped.'),
    finishReason: 'stop',
  );

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _stop;

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
  }) => Stream.value('Stopped.');

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
  }) async => _stop;

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _stop;
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

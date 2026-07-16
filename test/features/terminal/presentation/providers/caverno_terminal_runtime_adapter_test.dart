import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/presentation/providers/caverno_terminal_runtime_adapter.dart';

void main() {
  late ProviderContainer container;
  late CavernoTerminalRuntimeAdapter adapter;
  late ChatNotifier notifier;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        chatNotifierProvider.overrideWith(_TerminalTestChatNotifier.new),
      ],
    );
    adapter = CavernoTerminalRuntimeAdapter(
      container: container,
      environment: const <String, String>{},
    );
    notifier = container.read(chatNotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('resolves a production local-command pending action', () async {
    final result = notifier.requestLocalCommand(
      command: 'dart test',
      workingDirectory: '/tmp/project',
    );
    final id = container.read(chatNotifierProvider).pendingLocalCommand!.id;

    await adapter.resolveApproval(id: id, approved: true);

    expect((await result).approved, isTrue);
    expect(container.read(chatNotifierProvider).pendingLocalCommand, isNull);
  });

  test(
    'maps a terminal option index to the production question answer',
    () async {
      final result = notifier.requestAskUserQuestion(
        question: 'Choose a target',
        help: '',
        options: const <AskUserQuestionOption>[
          AskUserQuestionOption(id: 'local', label: 'Local'),
          AskUserQuestionOption(id: 'remote', label: 'Remote'),
        ],
        allowMultiple: false,
        allowOther: false,
        otherPlaceholder: '',
      );
      final id = container
          .read(chatNotifierProvider)
          .pendingAskUserQuestion!
          .id;

      await adapter.resolveQuestion(id: id, answer: '2');

      final answer = await result;
      expect(answer, isNotNull);
      expect(answer!.selectedOptions.single.id, 'remote');
    },
  );

  test('maps a terminal option index to a workflow decision', () async {
    final result = notifier.requestWorkflowDecision(
      decision: const WorkflowPlanningDecision(
        id: 'decision-1',
        question: 'Continue?',
        options: <WorkflowPlanningDecisionOption>[
          WorkflowPlanningDecisionOption(id: 'continue', label: 'Continue'),
          WorkflowPlanningDecisionOption(id: 'stop', label: 'Stop'),
        ],
      ),
    );
    final id = container.read(chatNotifierProvider).pendingWorkflowDecision!.id;

    await adapter.resolveQuestion(id: id, answer: '1');

    final answer = await result;
    expect(answer, isNotNull);
    expect(answer!.optionId, 'continue');
  });

  test('waits for pending persistence before closing the runtime', () async {
    final testNotifier = notifier as _TerminalTestChatNotifier;
    await adapter.resolveApproval(id: 'missing', approved: false);
    final runtimeSubscription = adapter.events.listen((_) {});
    final runtime = container.read(cavernoExecutionRuntimeProvider);

    final closeFuture = adapter.close();
    await Future<void>.delayed(Duration.zero);

    expect(runtime.isClosed, isFalse);
    testNotifier.completePendingPersistence();
    await closeFuture;
    expect(runtime.isClosed, isTrue);
    await runtimeSubscription.cancel();
  });

  test(
    'closing an unused adapter does not initialize the chat runtime',
    () async {
      var buildCount = 0;
      final lazyContainer = ProviderContainer(
        overrides: [
          chatNotifierProvider.overrideWith(
            () => _CountingChatNotifier(() {
              buildCount += 1;
            }),
          ),
        ],
      );
      final lazyAdapter = CavernoTerminalRuntimeAdapter(
        container: lazyContainer,
        environment: const <String, String>{},
      );

      await lazyAdapter.close();

      expect(buildCount, 0);
      lazyContainer.dispose();
    },
  );

  group('conversation resume preparation', () {
    test(
      'selects an exact chat conversation before chat initialization',
      () async {
        final savedMessage = Message(
          id: 'message-1',
          content: 'Persisted context',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 7, 16, 10),
        );
        final fixture = await _ResumeFixture.create(
          conversations: <Conversation>[
            _conversation(
              id: 'conversation-1',
              messages: <Message>[savedMessage],
            ),
          ],
        );
        addTearDown(fixture.dispose);

        await fixture.adapter.prepare(
          CavernoCliInvocation.parse(const [
            'conversations',
            'resume',
            'conversation-1',
            'Continue',
          ]),
        );

        expect(
          fixture.container
              .read(conversationsNotifierProvider)
              .currentConversationId,
          'conversation-1',
        );
        expect(
          fixture.container.read(settingsNotifierProvider).assistantMode,
          AssistantMode.general,
        );
        expect(fixture.chatBuild.buildCount, 0);

        fixture.container.read(chatNotifierProvider);
        expect(fixture.chatBuild.buildCount, 1);
        expect(fixture.chatBuild.conversationId, 'conversation-1');
        expect(fixture.chatBuild.messages, <Message>[savedMessage]);
      },
    );

    test('restores a saved planning worktree and project', () async {
      final projectDirectory = Directory.systemTemp.createTempSync(
        'caverno_resume_project_',
      );
      final worktreeDirectory = Directory.systemTemp.createTempSync(
        'caverno_resume_worktree_',
      );
      addTearDown(() {
        projectDirectory.deleteSync(recursive: true);
        worktreeDirectory.deleteSync(recursive: true);
      });
      final project = CodingProject(
        id: 'project-1',
        name: 'Saved project',
        rootPath: projectDirectory.path,
        createdAt: DateTime(2026, 7, 15),
        updatedAt: DateTime(2026, 7, 16),
      );
      final conversation = _conversation(
        id: 'planning-1',
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        worktreePath: worktreeDirectory.path,
        executionMode: ConversationExecutionMode.planning,
      );
      final fixture = await _ResumeFixture.create(
        conversations: <Conversation>[conversation],
        projects: <CodingProject>[project],
      );
      addTearDown(fixture.dispose);

      await fixture.adapter.prepare(
        CavernoCliInvocation.parse(const [
          'conversations',
          'resume',
          'planning-1',
          'Continue',
        ]),
      );

      expect(
        fixture.container
            .read(codingProjectsNotifierProvider)
            .selectedProjectId,
        project.id,
      );
      expect(
        fixture.container
            .read(conversationsNotifierProvider)
            .currentConversationId,
        conversation.id,
      );
      expect(
        fixture.container.read(settingsNotifierProvider).assistantMode,
        AssistantMode.plan,
      );
      final runtimeSettings = fixture.container.read(
        cavernoRuntimeSettingsPortProvider,
      );
      expect(runtimeSettings.current.mode, AssistantMode.plan.name);
      expect(runtimeSettings.current.workspace, worktreeDirectory.path);
    });

    test(
      'rejects a missing exact conversation without initializing chat',
      () async {
        final fixture = await _ResumeFixture.create(
          conversations: <Conversation>[_conversation(id: 'conversation-1')],
        );
        addTearDown(fixture.dispose);

        expect(
          () => fixture.adapter.prepare(
            CavernoCliInvocation.parse(const [
              'conversations',
              'resume',
              'conversation',
              'Continue',
            ]),
          ),
          throwsA(
            isA<CavernoCliFailure>()
                .having((error) => error.code, 'code', 'conversation_not_found')
                .having(
                  (error) => error.exitCode,
                  'exitCode',
                  CavernoCliExitCode.input,
                ),
          ),
        );
        expect(fixture.chatBuild.buildCount, 0);
      },
    );

    test(
      'rejects a coding conversation whose project is unavailable',
      () async {
        final fixture = await _ResumeFixture.create(
          conversations: <Conversation>[
            _conversation(
              id: 'coding-1',
              workspaceMode: WorkspaceMode.coding,
              projectId: 'missing-project',
            ),
          ],
        );
        addTearDown(fixture.dispose);

        expect(
          () => fixture.adapter.prepare(
            CavernoCliInvocation.parse(const [
              'conversations',
              'resume',
              'coding-1',
              'Continue',
            ]),
          ),
          throwsA(
            isA<CavernoCliFailure>().having(
              (error) => error.code,
              'code',
              'conversation_project_unavailable',
            ),
          ),
        );
      },
    );

    test('does not fall back when a saved worktree is unavailable', () async {
      final projectDirectory = Directory.systemTemp.createTempSync(
        'caverno_resume_project_',
      );
      addTearDown(() => projectDirectory.deleteSync(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Saved project',
        rootPath: projectDirectory.path,
        createdAt: DateTime(2026, 7, 15),
        updatedAt: DateTime(2026, 7, 16),
      );
      final fixture = await _ResumeFixture.create(
        conversations: <Conversation>[
          _conversation(
            id: 'coding-1',
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            worktreePath: '${projectDirectory.path}/missing-worktree',
          ),
        ],
        projects: <CodingProject>[project],
      );
      addTearDown(fixture.dispose);

      expect(
        () => fixture.adapter.prepare(
          CavernoCliInvocation.parse(const [
            'conversations',
            'resume',
            'coding-1',
            'Continue',
          ]),
        ),
        throwsA(
          isA<CavernoCliFailure>().having(
            (error) => error.code,
            'code',
            'conversation_worktree_unavailable',
          ),
        ),
      );
    });
  });
}

Conversation _conversation({
  required String id,
  List<Message> messages = const <Message>[],
  WorkspaceMode workspaceMode = WorkspaceMode.chat,
  String projectId = '',
  String worktreePath = '',
  ConversationExecutionMode executionMode = ConversationExecutionMode.normal,
}) {
  return Conversation(
    id: id,
    title: 'Saved conversation',
    messages: messages,
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 16),
    workspaceMode: workspaceMode,
    projectId: projectId,
    worktreePath: worktreePath,
    executionMode: executionMode,
  );
}

final class _ResumeFixture {
  _ResumeFixture({
    required this.container,
    required this.adapter,
    required this.chatBuild,
    required this.artifactDirectory,
  });

  final ProviderContainer container;
  final CavernoTerminalRuntimeAdapter adapter;
  final _ChatBuildObservation chatBuild;
  final Directory artifactDirectory;

  static Future<_ResumeFixture> create({
    required List<Conversation> conversations,
    List<CodingProject> projects = const <CodingProject>[],
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (projects.isNotEmpty)
        'coding_projects': jsonEncode(
          projects.map((project) => project.toJson()).toList(growable: false),
        ),
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = _MemoryConversationRepository(conversations);
    final artifactDirectory = Directory.systemTemp.createTempSync(
      'caverno_resume_artifacts_',
    );
    final chatBuild = _ChatBuildObservation();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        conversationRepositoryProvider.overrideWithValue(repository),
        toolResultArtifactStoreProvider.overrideWithValue(
          ToolResultArtifactStore(baseDirectory: artifactDirectory),
        ),
        deferInitialConversationCreationProvider.overrideWithValue(true),
        chatNotifierProvider.overrideWith(() => _ResumeChatNotifier(chatBuild)),
      ],
    );
    return _ResumeFixture(
      container: container,
      adapter: CavernoTerminalRuntimeAdapter(
        container: container,
        environment: const <String, String>{},
      ),
      chatBuild: chatBuild,
      artifactDirectory: artifactDirectory,
    );
  }

  void dispose() {
    container.dispose();
    if (artifactDirectory.existsSync()) {
      artifactDirectory.deleteSync(recursive: true);
    }
  }
}

final class _MemoryConversationRepository implements ConversationRepositoryApi {
  _MemoryConversationRepository(Iterable<Conversation> conversations)
    : _conversations = <String, Conversation>{
        for (final conversation in conversations) conversation.id: conversation,
      };

  final Map<String, Conversation> _conversations;

  @override
  Future<void> delete(String id) async => _conversations.remove(id);

  @override
  Future<void> deleteAll() async => _conversations.clear();

  @override
  List<Conversation> getAll() {
    final conversations = _conversations.values.toList(growable: false);
    return conversations
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  @override
  Conversation? getById(String id) => _conversations[id];

  @override
  Future<Conversation?> refresh(String id) async => _conversations[id];

  @override
  Future<void> save(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  @override
  Future<List<Conversation>> search(String query) async =>
      const <Conversation>[];
}

final class _ChatBuildObservation {
  int buildCount = 0;
  String? conversationId;
  List<Message> messages = const <Message>[];
}

final class _ResumeChatNotifier extends ChatNotifier {
  _ResumeChatNotifier(this.observation);

  final _ChatBuildObservation observation;

  @override
  ChatState build() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    observation
      ..buildCount += 1
      ..conversationId = conversation?.id
      ..messages = conversation?.messages ?? const <Message>[];
    return ChatState.initial().copyWith(messages: observation.messages);
  }
}

final class _TerminalTestChatNotifier extends ChatNotifier {
  final _pendingPersistence = Completer<void>();

  @override
  ChatState build() => ChatState.initial();

  @override
  Future<void> flushPendingPersistence() => _pendingPersistence.future;

  void completePendingPersistence() {
    if (!_pendingPersistence.isCompleted) {
      _pendingPersistence.complete();
    }
  }
}

final class _CountingChatNotifier extends ChatNotifier {
  _CountingChatNotifier(this.onBuild);

  final void Function() onBuild;

  @override
  ChatState build() {
    onBuild();
    return ChatState.initial();
  }
}

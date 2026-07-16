import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/application/runtime/caverno_execution_runtime.dart';
import 'package:caverno/features/chat/application/runtime/caverno_runtime_event.dart';
import 'package:caverno/features/chat/application/runtime/caverno_runtime_ports.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/semantic_search_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/presentation/providers/caverno_terminal_runtime_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GUI-to-terminal conversation resume', () {
    test('continues a GUI-created Coding conversation', () async {
      await _verifyGuiToTerminalResume(planning: false);
    });

    test('continues a GUI-created Plan Mode conversation', () async {
      await _verifyGuiToTerminalResume(planning: true);
    });
  });
}

Future<void> _verifyGuiToTerminalResume({required bool planning}) async {
  final fixtureRoot = Directory.systemTemp.createTempSync(
    'caverno_gui_terminal_resume_',
  );
  addTearDown(() {
    if (fixtureRoot.existsSync()) {
      fixtureRoot.deleteSync(recursive: true);
    }
  });
  final projectDirectory = Directory('${fixtureRoot.path}/project')
    ..createSync(recursive: true);
  final worktreeDirectory = Directory('${fixtureRoot.path}/worktree')
    ..createSync(recursive: true);
  final artifactDirectory = Directory('${fixtureRoot.path}/artifacts')
    ..createSync(recursive: true);
  final databaseFile = File('${fixtureRoot.path}/caverno.sqlite');

  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final seed = _ResumeSeed(planning: planning);

  final guiStorage = await _openStorage(databaseFile);
  final guiContainer = _buildContainer(
    preferences: preferences,
    storage: guiStorage,
    dataRoot: fixtureRoot,
    artifactDirectory: artifactDirectory,
    terminal: false,
  );
  final project = await guiContainer
      .read(codingProjectsNotifierProvider.notifier)
      .addProject(projectDirectory.path);
  expect(project, isNotNull);
  final conversations = guiContainer.read(
    conversationsNotifierProvider.notifier,
  );
  conversations.createNewConversation(
    workspaceMode: WorkspaceMode.coding,
    projectId: project!.id,
    worktreePath: worktreeDirectory.path,
  );
  final conversationId = guiContainer
      .read(conversationsNotifierProvider)
      .currentConversationId;
  expect(conversationId, isNotNull);
  await conversations.updateCurrentConversation(seed.initialMessages);
  await conversations.updateCurrentWorkflow(
    workflowStage: seed.workflowStage,
    workflowSpec: seed.workflowSpec,
    workflowSourceHash: seed.workflowSourceHash,
    workflowDerivedAt: seed.workflowDerivedAt,
    preserveWorkflowProjection: true,
  );
  if (planning) {
    await conversations.enterPlanningSession();
  }
  final guiConversation = guiContainer
      .read(conversationsNotifierProvider)
      .currentConversation!;
  expect(guiConversation.id, conversationId);
  expect(guiConversation.normalizedProjectId, project.id);
  expect(guiConversation.normalizedWorktreePath, worktreeDirectory.path);
  guiContainer.dispose();
  await guiStorage.close();

  final terminalStorage = await _openStorage(databaseFile);
  final terminalContainer = _buildContainer(
    preferences: preferences,
    storage: terminalStorage,
    dataRoot: fixtureRoot,
    artifactDirectory: artifactDirectory,
    terminal: true,
  );
  final adapter = CavernoTerminalRuntimeAdapter(
    container: terminalContainer,
    environment: const <String, String>{},
  );
  final invocation = CavernoCliInvocation.parse(<String>[
    'conversations',
    'resume',
    conversationId!,
    '--base-url',
    'http://localhost:1234/v1',
    '--model',
    'fixture-model',
    '--api-key',
    'no-key',
    seed.terminalPrompt,
  ]);
  final events = <CavernoRuntimeEvent>[];
  final eventSubscription = adapter.events.listen(events.add);

  await adapter.prepare(invocation);

  final preparedConversation = terminalContainer
      .read(conversationsNotifierProvider)
      .currentConversation!;
  expect(preparedConversation.id, conversationId);
  expect(preparedConversation.messages, seed.initialMessages);
  expect(preparedConversation.workflowSpec, seed.workflowSpec);
  expect(preparedConversation.workflowSourceHash, seed.workflowSourceHash);
  expect(
    terminalContainer.read(codingProjectsNotifierProvider).selectedProjectId,
    project.id,
  );
  expect(
    terminalContainer.read(settingsNotifierProvider).assistantMode,
    planning ? AssistantMode.plan : AssistantMode.coding,
  );

  await adapter.start(invocation: invocation, prompt: seed.terminalPrompt);
  await adapter.close();
  await eventSubscription.cancel();

  final started = events.whereType<CavernoRuntimeRunStarted>().single;
  expect(started.conversationId, conversationId);
  expect(
    started.mode,
    planning ? AssistantMode.plan.name : AssistantMode.coding.name,
  );
  expect(started.workspace, worktreeDirectory.path);
  final completed = events.whereType<CavernoRuntimeRunCompleted>().single;
  expect(completed.content, seed.terminalReply);

  terminalContainer.dispose();
  await terminalStorage.close();

  final assertionStorage = await _openStorage(databaseFile);
  final persisted = assertionStorage.conversationRepository.getById(
    conversationId,
  );
  expect(persisted, isNotNull);
  expect(persisted!.id, conversationId);
  expect(persisted.normalizedProjectId, project.id);
  expect(persisted.normalizedWorktreePath, worktreeDirectory.path);
  expect(
    persisted.executionMode,
    planning
        ? ConversationExecutionMode.planning
        : ConversationExecutionMode.normal,
  );
  expect(persisted.workflowStage, seed.workflowStage);
  expect(persisted.workflowSpec, seed.workflowSpec);
  expect(persisted.workflowSourceHash, seed.workflowSourceHash);
  expect(persisted.workflowDerivedAt, seed.workflowDerivedAt);
  expect(persisted.messages, <Message>[
    ...seed.initialMessages,
    Message(
      id: 'terminal-user',
      content: seed.terminalPrompt,
      role: MessageRole.user,
      timestamp: _TerminalResumeChatNotifier.userTimestamp,
    ),
    Message(
      id: 'terminal-assistant',
      content: seed.terminalReply,
      role: MessageRole.assistant,
      timestamp: _TerminalResumeChatNotifier.assistantTimestamp,
    ),
  ]);
  await assertionStorage.close();
}

ProviderContainer _buildContainer({
  required SharedPreferences preferences,
  required CavernoPersistenceStorage storage,
  required Directory dataRoot,
  required Directory artifactDirectory,
  required bool terminal,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      conversationRepositoryProvider.overrideWithValue(
        storage.conversationRepository,
      ),
      chatMemoryRepositoryProvider.overrideWithValue(
        storage.chatMemoryRepository,
      ),
      appDatabaseProvider.overrideWithValue(storage.database),
      toolResultArtifactStoreProvider.overrideWithValue(
        ToolResultArtifactStore(baseDirectory: artifactDirectory),
      ),
      semanticIndexingServiceProvider.overrideWithValue(null),
      cavernoRuntimeDataRootProvider.overrideWithValue(dataRoot),
      cavernoRuntimeToolPortProvider.overrideWithValue(
        const _EmptyRuntimeToolPort(),
      ),
      if (terminal) ...[
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.terminal,
        ),
        deferInitialConversationCreationProvider.overrideWithValue(true),
        chatNotifierProvider.overrideWith(_TerminalResumeChatNotifier.new),
      ],
    ],
  );
}

final class _EmptyRuntimeToolPort implements CavernoRuntimeToolPort {
  const _EmptyRuntimeToolPort();

  @override
  List<String> get availableToolNames => const <String>[];
}

Future<CavernoPersistenceStorage> _openStorage(File databaseFile) {
  return const CavernoPersistenceBootstrap().open(
    openDatabase: () => openAppDatabase(databaseFile: databaseFile),
    conversationsMigrated: true,
    chatMemoryMigrated: true,
    readLegacyConversations: () async => throw StateError(
      'Legacy conversations must not be read by the fixture.',
    ),
    readLegacyChatMemory: () async =>
        throw StateError('Legacy chat memory must not be read by the fixture.'),
    markConversationsMigrated: () async {},
    markChatMemoryMigrated: () async {},
  );
}

final class _ResumeSeed {
  _ResumeSeed({required this.planning});

  final bool planning;

  List<Message> get initialMessages => <Message>[
    Message(
      id: 'gui-user',
      content: planning ? 'Create the saved plan.' : 'Inspect the saved code.',
      role: MessageRole.user,
      timestamp: DateTime.utc(2026, 7, 16, 1),
    ),
    Message(
      id: 'gui-assistant',
      content: planning
          ? 'The saved plan is ready.'
          : 'The saved code is ready.',
      role: MessageRole.assistant,
      timestamp: DateTime.utc(2026, 7, 16, 1, 1),
    ),
  ];

  ConversationWorkflowStage get workflowStage => planning
      ? ConversationWorkflowStage.tasks
      : ConversationWorkflowStage.implement;

  String get workflowSourceHash =>
      planning ? 'plan-source-hash' : 'coding-source-hash';

  DateTime get workflowDerivedAt => DateTime.utc(2026, 7, 16, 1, 2);

  String get terminalPrompt => planning
      ? 'Continue the saved plan from the terminal.'
      : 'Continue the saved coding thread from the terminal.';

  String get terminalReply => planning
      ? 'Terminal plan continuation complete.'
      : 'Terminal coding continuation complete.';

  ConversationWorkflowSpec get workflowSpec => ConversationWorkflowSpec(
    goal: planning ? 'Deliver the saved plan' : 'Deliver the saved change',
    acceptanceCriteria: const <String>['Preserve the frontend boundary'],
    tasks: <ConversationWorkflowTask>[
      ConversationWorkflowTask(
        id: planning ? 'plan-task' : 'coding-task',
        title: planning ? 'Continue the plan' : 'Continue the implementation',
        targetFiles: const <String>['lib/example.dart'],
        validationCommand: 'dart test',
      ),
    ],
    sources: const <ConversationContractSourceReference>[
      ConversationContractSourceReference(
        id: 'gui-source',
        kind: ConversationContractSourceKind.userMessage,
        locator: 'message:gui-user',
        contentHash: 'gui-source-hash',
      ),
    ],
    provenance: <ConversationContractItemProvenance>[
      ConversationContractItemProvenance(
        itemId: planning ? 'plan-task' : 'coding-task',
        kind: ConversationContractItemKind.task,
        sourceIds: const <String>['gui-source'],
      ),
    ],
  );
}

final class _TerminalResumeChatNotifier extends ChatNotifier {
  static final userTimestamp = DateTime.utc(2026, 7, 16, 2);
  static final assistantTimestamp = DateTime.utc(2026, 7, 16, 2, 1);

  @override
  ChatState build() {
    final messages = ref
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.messages;
    return ChatState.initial().copyWith(
      messages: messages ?? const <Message>[],
    );
  }

  @override
  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
    ChatInteractionOrigin origin = ChatInteractionOrigin.local,
  }) async {
    final conversations = ref.read(conversationsNotifierProvider.notifier);
    final current = ref
        .read(conversationsNotifierProvider)
        .currentConversation!;
    final runtime = ref.read(cavernoExecutionRuntimeProvider);
    final handle = await runtime.startTurn(
      CavernoRuntimeTurnRequest(
        turnId: 'terminal-resume-turn',
        conversationId: current.id,
      ),
    );
    final refreshed = ref
        .read(conversationsNotifierProvider)
        .currentConversation!;
    final reply = refreshed.isPlanningSession
        ? 'Terminal plan continuation complete.'
        : 'Terminal coding continuation complete.';
    final messages = <Message>[
      ...refreshed.messages,
      Message(
        id: 'terminal-user',
        content: content,
        role: MessageRole.user,
        timestamp: userTimestamp,
      ),
      Message(
        id: 'terminal-assistant',
        content: reply,
        role: MessageRole.assistant,
        timestamp: assistantTimestamp,
      ),
    ];
    await conversations.updateCurrentConversation(messages);
    state = state.copyWith(messages: messages);
    handle.emitAssistantDelta(reply);
    handle.complete(content: reply);
  }

  @override
  Future<void> flushPendingPersistence() async {}
}

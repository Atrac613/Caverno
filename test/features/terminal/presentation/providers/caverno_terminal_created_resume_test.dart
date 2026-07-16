import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/semantic_search_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_coding_project_repository.dart';
import 'package:caverno/features/terminal/presentation/providers/caverno_terminal_runtime_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('terminal-created conversation restart', () {
    test('resumes a Coding conversation after the creating process exits', () {
      return _verifyTerminalCreatedResume(planning: false);
    });

    test(
      'resumes a Plan Mode conversation after the creating process exits',
      () {
        return _verifyTerminalCreatedResume(planning: true);
      },
    );
  });
}

Future<void> _verifyTerminalCreatedResume({required bool planning}) async {
  final fixtureRoot = await Directory.systemTemp.createTemp(
    'caverno_terminal_created_resume_',
  );
  addTearDown(() async {
    if (await fixtureRoot.exists()) {
      await fixtureRoot.delete(recursive: true);
    }
  });
  final projectDirectory = Directory('${fixtureRoot.path}/project');
  await projectDirectory.create(recursive: true);
  final canonicalProjectPath = await projectDirectory.resolveSymbolicLinks();
  final databaseFile = File('${fixtureRoot.path}/caverno.sqlite');
  final artifactDirectory = Directory('${fixtureRoot.path}/artifacts');
  final initialMessages = <Message>[
    Message(
      id: 'initial-user',
      content: planning
          ? 'Create a terminal plan.'
          : 'Inspect the terminal code.',
      role: MessageRole.user,
      timestamp: DateTime.utc(2026, 7, 16, 3),
    ),
    Message(
      id: 'initial-assistant',
      content: planning ? 'The terminal plan is ready.' : 'The code is ready.',
      role: MessageRole.assistant,
      timestamp: DateTime.utc(2026, 7, 16, 3, 1),
    ),
  ];

  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final firstStorage = await _openStorage(databaseFile);
  final firstContainer = _buildContainer(
    preferences: preferences,
    storage: firstStorage,
    dataRoot: fixtureRoot,
    artifactDirectory: artifactDirectory,
    deferInitialConversation: false,
  );
  final firstAdapter = CavernoTerminalRuntimeAdapter(
    container: firstContainer,
    environment: const <String, String>{},
  );
  final initialInvocation = _initialInvocation(
    projectPath: projectDirectory.path,
    planning: planning,
  );

  await firstAdapter.prepare(initialInvocation);

  final firstProjects = firstContainer.read(codingProjectsNotifierProvider);
  final project = firstProjects.selectedProject!;
  final firstConversations = firstContainer.read(
    conversationsNotifierProvider.notifier,
  );
  await firstConversations.updateCurrentConversation(initialMessages);
  final createdConversation = firstContainer
      .read(conversationsNotifierProvider)
      .currentConversation!;
  expect(createdConversation.normalizedProjectId, project.id);
  expect(
    createdConversation.executionMode,
    planning
        ? ConversationExecutionMode.planning
        : ConversationExecutionMode.normal,
  );
  expect(
    await firstStorage.conversationRepository.refresh(createdConversation.id),
    isNotNull,
  );
  final conversationId = createdConversation.id;
  firstContainer.dispose();
  await firstStorage.close();

  final secondStorage = await _openStorage(databaseFile);
  final secondContainer = _buildContainer(
    preferences: preferences,
    storage: secondStorage,
    dataRoot: fixtureRoot,
    artifactDirectory: artifactDirectory,
    deferInitialConversation: true,
  );
  final secondAdapter = CavernoTerminalRuntimeAdapter(
    container: secondContainer,
    environment: const <String, String>{},
  );
  final resumeInvocation = _resumeInvocation(conversationId);

  await secondAdapter.prepare(resumeInvocation);

  final restoredProject = secondContainer
      .read(codingProjectsNotifierProvider)
      .selectedProject!;
  final restoredConversation = secondContainer
      .read(conversationsNotifierProvider)
      .currentConversation!;
  expect(restoredProject.id, project.id);
  expect(restoredProject.rootPath, canonicalProjectPath);
  expect(restoredConversation.id, conversationId);
  expect(restoredConversation.messages, initialMessages);
  expect(
    secondContainer.read(settingsNotifierProvider).assistantMode,
    planning ? AssistantMode.plan : AssistantMode.coding,
  );

  final continuedMessages = <Message>[
    ...restoredConversation.messages,
    Message(
      id: 'resumed-user',
      content: 'Continue after restart.',
      role: MessageRole.user,
      timestamp: DateTime.utc(2026, 7, 16, 4),
    ),
    Message(
      id: 'resumed-assistant',
      content: 'Restart continuation complete.',
      role: MessageRole.assistant,
      timestamp: DateTime.utc(2026, 7, 16, 4, 1),
    ),
  ];
  await secondContainer
      .read(conversationsNotifierProvider.notifier)
      .updateCurrentConversation(continuedMessages);
  secondContainer.dispose();
  await secondStorage.close();

  final assertionStorage = await _openStorage(databaseFile);
  final persisted = assertionStorage.conversationRepository.getById(
    conversationId,
  );
  expect(persisted, isNotNull);
  expect(persisted!.normalizedProjectId, project.id);
  expect(persisted.messages, continuedMessages);
  expect(
    persisted.executionMode,
    planning
        ? ConversationExecutionMode.planning
        : ConversationExecutionMode.normal,
  );
  final persistedProjects = createCavernoCliCodingProjectRepository(
    dataDirectory: fixtureRoot,
    preferences: preferences,
  ).loadAll();
  expect(persistedProjects, hasLength(1));
  expect(persistedProjects.single.id, project.id);
  await assertionStorage.close();
}

CavernoCliInvocation _initialInvocation({
  required String projectPath,
  required bool planning,
}) {
  return CavernoCliInvocation.parse(<String>[
    planning ? 'plan' : 'coding',
    '--project',
    projectPath,
    '--base-url',
    'http://localhost:1234/v1',
    '--model',
    'fixture-model',
    '--api-key',
    'no-key',
    'Start the terminal conversation.',
  ]);
}

CavernoCliInvocation _resumeInvocation(String conversationId) {
  return CavernoCliInvocation.parse(<String>[
    'conversations',
    'resume',
    conversationId,
    '--base-url',
    'http://localhost:1234/v1',
    '--model',
    'fixture-model',
    '--api-key',
    'no-key',
    'Continue after restart.',
  ]);
}

ProviderContainer _buildContainer({
  required SharedPreferences preferences,
  required CavernoPersistenceStorage storage,
  required Directory dataRoot,
  required Directory artifactDirectory,
  required bool deferInitialConversation,
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
      codingProjectRepositoryProvider.overrideWithValue(
        createCavernoCliCodingProjectRepository(
          dataDirectory: dataRoot,
          preferences: preferences,
        ),
      ),
      appDatabaseProvider.overrideWithValue(storage.database),
      toolResultArtifactStoreProvider.overrideWithValue(
        ToolResultArtifactStore(baseDirectory: artifactDirectory),
      ),
      semanticIndexingServiceProvider.overrideWithValue(null),
      cavernoRuntimeDataRootProvider.overrideWithValue(dataRoot),
      deferInitialConversationCreationProvider.overrideWithValue(
        deferInitialConversation,
      ),
    ],
  );
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

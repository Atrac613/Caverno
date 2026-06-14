import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _editMarker = 'CODING_GOAL_EDIT_TEST_OK';
const _testCommand = 'dart lib/canary_greeting_test.dart';
const _fileCreateMarker = 'CODING_GOAL_FILE_CREATE_OK';
const _fileUpdateMarker = 'CODING_GOAL_FILE_UPDATE_OK';
const _fileLifecyclePath = 'lib/live_file_ops_note.txt';
const _fileLifecycleDeleteCommand = 'rm lib/live_file_ops_note.txt';
const _fileLifecycleVerifyDeletedCommand =
    'test ! -e lib/live_file_ops_note.txt';
const _gitLifecycleMarker = 'CODING_GOAL_GIT_LIFECYCLE_OK';
const _gitLifecyclePath = 'lib/git_lifecycle_note.txt';
const _gitCommitMessage = 'Add git lifecycle canary';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY'] == '1';
  final runLabel = Platform
      .environment['CAVERNO_CODING_GOAL_LIVE_EDIT_RUN_LABEL']
      ?.trim();
  final testNamePrefix = runLabel == null || runLabel.isEmpty
      ? ''
      : '[$runLabel] ';

  if (!liveEnabled) {
    test('suppresses LL15 harness prompt for measurement controls', () {
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(
          baseUrl: 'http://localhost:1234/v1',
          apiKey: 'no-key',
        ),
        suppressEditHarnessPrompt: true,
      );
      dataSource.streamChatCompletion(
        messages: [
          Message(
            id: 'system',
            role: MessageRole.system,
            timestamp: DateTime.utc(2026, 6, 14),
            content: [
              'Current local date and time: 2026-06-14 12:00',
              'For file changes, prefer edit_file for targeted replacements.',
              'LL15 WEAK-MODEL EDIT HARNESS:',
              'When editing existing files, use edit_file with one valid JSON tool call.',
              'Required edit_file arguments: path, old_text, new_text. Optional arguments: replace_all, reason.',
              'Use JSON with double-quoted keys and strings, no comments, and no trailing commas.',
              'Set old_text to exact current text copied from the latest read_file or inspect_file result; include enough surrounding context to match one location.',
              'Set replace_all=false unless every occurrence should change.',
              'If old_text was not found, is stale, or matches multiple locations, read the current file again and retry with exact current content; do not guess.',
              'Example edit_file arguments: {"path":"lib/example.dart","old_text":"final enabled = false;","new_text":"final enabled = true;","replace_all":false,"reason":"Enable the feature flag."}',
              'If a recent file mutation needs to be undone, use rollback_last_file_change.',
            ].join('\n'),
          ),
        ],
      );

      expect(
        dataSource.firstSystemPrompt,
        isNot(contains('LL15 WEAK-MODEL EDIT HARNESS')),
      );
      expect(
        dataSource.firstSystemPrompt,
        contains('If a recent file mutation needs to be undone'),
      );
    });
  }

  test(
    '${testNamePrefix}live LLM edits code and runs the fixture test for an active coding goal',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.create(env.workspaceRoot);
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        suppressEditHarnessPrompt: env.suppressEditHarnessPrompt,
      );
      final toolService = _SandboxCodingToolService(fixture.root);
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Fix the selected coding project by editing lib/canary_greeting.dart '
              'so canaryGreeting("Ada") returns exactly '
              '"Hello, Ada! $_editMarker". Then run local_execute_command '
              'with command "$_testCommand" in the project root. The goal is '
              'complete only after the command exits with code 0 and prints '
              '$_editMarker.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 12000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Inspect the fixture if needed, make the '
          'smallest code change, run exactly "$_testCommand", and finish only '
          'after the test passes. Mention $_editMarker and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);
        _printLl15EditHarnessSnapshot(container, dataSource, toolService);

        final testResult = await fixture.runTest();
        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          dataSource.firstSystemPrompt,
          contains(project.rootPath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.sourceFile.readAsStringSync(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.executedToolNames,
          anyOf(contains('edit_file'), contains('write_file')),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulTestCommandCount,
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.exitCode,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.stdout,
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    '${testNamePrefix}live LLM repairs code after observing the failing fixture test',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.create(env.workspaceRoot);
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        suppressEditHarnessPrompt: env.suppressEditHarnessPrompt,
      );
      final toolService = _SandboxCodingToolService(fixture.root);
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Repair the selected coding project with a red-green workflow. '
              'First run local_execute_command with command "$_testCommand" '
              'in the project root before any edit_file or write_file call; '
              'that first test failure is expected. Use the failure output to '
              'edit lib/canary_greeting.dart so canaryGreeting("Ada") returns '
              'exactly "Hello, Ada! $_editMarker". Then rerun '
              'local_execute_command with the same command. The goal is '
              'complete only after a later command exits with code 0 and '
              'prints $_editMarker.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 16000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Run exactly "$_testCommand" before '
          'editing any file, inspect the failure, make the smallest repair, '
          'rerun exactly "$_testCommand", and finish only after the rerun '
          'passes. Mention $_editMarker and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);
        _printLl15EditHarnessSnapshot(container, dataSource, toolService);

        final testResult = await fixture.runTest();
        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);
        final testExitCodes = toolService.testCommandExitCodes;
        final sourceBeforeTestCommands =
            toolService.testCommandSourceContainsMarkerBeforeCall;

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          dataSource.firstSystemPrompt,
          contains(project.rootPath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.firstTestCommandIndex,
          isNot(-1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.firstMutationIndex,
          greaterThan(toolService.firstTestCommandIndex),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testExitCodes.length,
          greaterThanOrEqualTo(2),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testExitCodes.first,
          isNot(0),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testExitCodes.last,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          sourceBeforeTestCommands.first,
          isFalse,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.sourceFile.readAsStringSync(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulTestCommandCount,
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.exitCode,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.stdout,
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    '${testNamePrefix}live LLM coordinates a two-file coding goal edit',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.createTwoFile(env.workspaceRoot);
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        suppressEditHarnessPrompt: env.suppressEditHarnessPrompt,
      );
      final toolService = _SandboxCodingToolService(fixture.root);
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Fix the selected coding project by coordinating two source '
              'files. Edit lib/canary_suffix.dart so canarySuffix() returns '
              'exactly "! $_editMarker", and edit lib/canary_greeting.dart '
              'so canaryGreeting("Ada") uses canarySuffix() and returns '
              'exactly "Hello, Ada! $_editMarker". Then run '
              'local_execute_command with command "$_testCommand" in the '
              'project root. The goal is complete only after both production '
              'files are updated and the command exits with code 0 and prints '
              '$_editMarker.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 16000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Inspect both production files, update '
          'lib/canary_suffix.dart and lib/canary_greeting.dart, run exactly '
          '"$_testCommand", and finish only after the test passes. Mention '
          '$_editMarker and say "Goal complete. Tests passed." in the final '
          'answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);
        _printLl15EditHarnessSnapshot(container, dataSource, toolService);

        final testResult = await fixture.runTest();
        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);
        final mutatedPaths = toolService.mutatedRelativePaths;

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          dataSource.firstSystemPrompt,
          contains(project.rootPath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          mutatedPaths,
          containsAll(['lib/canary_greeting.dart', 'lib/canary_suffix.dart']),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.sourceFile.readAsStringSync(),
          contains('canarySuffix()'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.suffixFile.readAsStringSync(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulTestCommandCount,
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.exitCode,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.stdout,
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    '${testNamePrefix}live LLM fixes a package-like parser fixture',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.createParserPackage(
        env.workspaceRoot,
      );
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        suppressEditHarnessPrompt: env.suppressEditHarnessPrompt,
      );
      final toolService = _SandboxCodingToolService(fixture.root);
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Fix the selected package-like Dart CLI fixture without editing '
              'lib/canary_greeting_test.dart. Inspect '
              'lib/src/host_target_parser.dart, lib/src/ping_command.dart, '
              'and lib/canary_greeting_test.dart. Implement --count <number> '
              'parsing, --ipv6 parsing, and positional host selection in the '
              'production files. buildPingCommand(["--count", "3", "--ipv6", '
              '"example.com"]) must return exactly '
              '"ping -6 -c 3 example.com". Then run local_execute_command '
              'with command "$_testCommand" in the project root. The goal is '
              'complete only after the production files are updated and the '
              'command exits with code 0 and prints $_editMarker.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 18000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Read the package-like fixture, update '
          'only the production files under lib/src, run exactly '
          '"$_testCommand", and finish only after the test passes. Do not edit '
          'lib/canary_greeting_test.dart. Mention $_editMarker and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);
        _printLl15EditHarnessSnapshot(container, dataSource, toolService);

        final testResult = await fixture.runTest();
        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);
        final mutatedPaths = toolService.mutatedRelativePaths;

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          dataSource.firstSystemPrompt,
          contains(project.rootPath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          mutatedPaths,
          containsAll([
            'lib/src/host_target_parser.dart',
            'lib/src/ping_command.dart',
          ]),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          mutatedPaths,
          isNot(contains('lib/canary_greeting_test.dart')),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.hostTargetParserFile.readAsStringSync(),
          contains('--count'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.pingCommandFile.readAsStringSync(),
          contains('-6'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulTestCommandCount,
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.exitCode,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.stdout,
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    '${testNamePrefix}live LLM creates, reads, updates, and deletes a file',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.createEmpty(
        env.workspaceRoot,
        projectId: 'coding-goal-live-file-ops-project',
        projectName: 'coding_goal_live_file_ops_fixture',
      );
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        suppressEditHarnessPrompt: env.suppressEditHarnessPrompt,
      );
      final toolService = _SandboxCodingToolService(
        fixture.root,
        acceptedLocalCommands: const {
          _fileLifecycleDeleteCommand,
          _fileLifecycleVerifyDeletedCommand,
        },
      );
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Perform a complete local file lifecycle in the selected coding '
              'project. Create $_fileLifecyclePath with UTF-8 text containing '
              '$_fileCreateMarker, read $_fileLifecyclePath with read_file, '
              'update the same file so it contains $_fileUpdateMarker while '
              'preserving $_fileCreateMarker, read it again with read_file, '
              'delete it by running local_execute_command with command '
              '"$_fileLifecycleDeleteCommand" in the project root, then verify '
              'deletion by running local_execute_command with command '
              '"$_fileLifecycleVerifyDeletedCommand" in the project root. The '
              'goal is complete only after the create, read, update, second '
              'read, delete, and deletion verification all have successful tool '
              'results.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 16000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Actually create, read, update, read '
          'again, delete, and verify deletion for $_fileLifecyclePath. Finish '
          'only after the deletion verification command succeeds. Mention '
          '$_fileCreateMarker, $_fileUpdateMarker, and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);
        _printLl15EditHarnessSnapshot(container, dataSource, toolService);

        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);
        final readContents = toolService.readFileContentsForRelativePath(
          _fileLifecyclePath,
        );
        final target = File('${fixture.root.path}/$_fileLifecyclePath');

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulWritePaths,
          contains(_fileLifecyclePath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          readContents.any((content) => content.contains(_fileCreateMarker)),
          isTrue,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          readContents.any((content) => content.contains(_fileUpdateMarker)),
          isTrue,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulMutationPaths,
          contains(_fileLifecyclePath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulLocalCommandCount(_fileLifecycleDeleteCommand),
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulLocalCommandCount(
            _fileLifecycleVerifyDeletedCommand,
          ),
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          target.existsSync(),
          isFalse,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_fileCreateMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_fileUpdateMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    '${testNamePrefix}live LLM initializes git, commits, and reverts safely',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.createEmpty(
        env.workspaceRoot,
        projectId: 'coding-goal-live-git-ops-project',
        projectName: 'coding_goal_live_git_ops_fixture',
      );
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        suppressEditHarnessPrompt: env.suppressEditHarnessPrompt,
      );
      final toolService = _SandboxCodingToolService(
        fixture.root,
        enableGit: true,
      );
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Perform a safe Git lifecycle in the selected coding project. '
              'Initialize the repository by using git_execute_command with '
              'command "init" in the project root. Create $_gitLifecyclePath '
              'containing $_gitLifecycleMarker. Then use git_execute_command, '
              'one git subcommand per call, to set user.email to '
              'canary@example.com, set user.name to Canary Bot, add '
              '$_gitLifecyclePath, commit with message '
              '"$_gitCommitMessage", inspect status, revert the commit with '
              'revert --no-edit HEAD, and inspect status again. The goal is '
              'complete only after git init, file creation, commit, revert, '
              'and a clean final status all have successful tool results.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 20000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Use git_execute_command with command '
          '"init" for initialization, use git_execute_command for each later '
          'git step, '
          'and finish only after the revert succeeds and final status is '
          'clean. Mention $_gitLifecycleMarker and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container, timeout: const Duration(minutes: 8));
        _printLl15EditHarnessSnapshot(container, dataSource, toolService);

        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);
        final status = await Process.run('git', [
          'status',
          '--short',
        ], workingDirectory: fixture.root.path);
        final log = await Process.run('git', [
          'log',
          '--oneline',
          '--max-count',
          '2',
        ], workingDirectory: fixture.root.path);

        expect(
          Directory('${fixture.root.path}/.git').existsSync(),
          isTrue,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulWritePaths,
          contains(_gitLifecyclePath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulGitCommands,
          containsAll([
            'init',
            'add $_gitLifecyclePath',
            'commit -m "$_gitCommitMessage"',
            'revert --no-edit HEAD',
          ]),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          File('${fixture.root.path}/$_gitLifecyclePath').existsSync(),
          isFalse,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(status.exitCode, 0);
        expect((status.stdout as String).trim(), isEmpty);
        expect(log.exitCode, 0);
        expect(log.stdout as String, contains(_gitCommitMessage));
        expect(
          finalContent.toUpperCase(),
          contains(_gitLifecycleMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

ProviderContainer _buildCodingGoalLiveEditContainer({
  required _CodingGoalLiveEditEnv env,
  required _CodingGoalLiveEditDataSource dataSource,
  required _SandboxCodingToolService toolService,
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

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 6),
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
    'Timed out waiting for coding goal live edit canary completion.\n'
    '${_diagnostic(container, null, null, null)}',
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

ConversationGoal? _currentGoal(ProviderContainer container) {
  return container
      .read(conversationsNotifierProvider)
      .currentConversation
      ?.goal;
}

void _printLl15EditHarnessSnapshot(
  ProviderContainer container,
  _CodingGoalLiveEditDataSource dataSource,
  _SandboxCodingToolService toolService,
) {
  final profile = container
      .read(settingsNotifierProvider)
      .effectiveModelCapabilityProfile;
  final metadata = profile?.probeMetadata ?? const <String, String>{};
  final payload = {
    'schemaName': 'll15_edit_harness_canary_snapshot',
    'schemaVersion': 1,
    'harnessPrompted': dataSource.firstSystemPrompt.contains(
      'LL15 WEAK-MODEL EDIT HARNESS',
    ),
    'attempts':
        int.tryParse(
          metadata[ModelEditApplyTelemetryService.attemptsKey] ?? '',
        ) ??
        0,
    'successes':
        int.tryParse(
          metadata[ModelEditApplyTelemetryService.successesKey] ?? '',
        ) ??
        0,
    'failures':
        int.tryParse(
          metadata[ModelEditApplyTelemetryService.failuresKey] ?? '',
        ) ??
        0,
    'failureRate':
        double.tryParse(
          metadata[ModelEditApplyTelemetryService.failureRateKey] ?? '',
        ) ??
        0.0,
    'lastOutcome':
        metadata[ModelEditApplyTelemetryService.lastOutcomeKey] ?? '',
    'editToolCallCount': toolService.executedCalls
        .where((call) => call.name == 'edit_file')
        .length,
    'writeToolCallCount': toolService.executedCalls
        .where((call) => call.name == 'write_file')
        .length,
  };
  debugPrint('[LL15] edit_harness_snapshot ${jsonEncode(payload)}');
}

String _diagnostic(
  ProviderContainer container,
  _CodingGoalLiveEditDataSource? dataSource,
  _SandboxCodingToolService? toolService,
  _CodingGoalEditFixture? fixture,
) {
  final chatState = container.read(chatNotifierProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final messages = chatState.messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
  return [
    'isLoading=${chatState.isLoading}',
    'error=${chatState.error}',
    'messages=${chatState.messages.length}',
    'goal=${jsonEncode(conversation?.goal?.toJson())}',
    'streamRequests=${dataSource?.streamRequests.length ?? 0}',
    'streamWithToolsRequests=${dataSource?.streamWithToolsRequests.length ?? 0}',
    'fixtureRoot=${fixture?.root.path ?? '(none)'}',
    'sources=${fixture?._sourceDiagnostics() ?? '(missing)'}',
    'toolCalls=${toolService?.executedCalls.map((call) => call.toJson()).map(jsonEncode).join(' | ') ?? '(none)'}',
    messages,
  ].join('\n');
}

class _CodingGoalEditFixture {
  _CodingGoalEditFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;

  File get sourceFile => File('${root.path}/lib/canary_greeting.dart');
  File get suffixFile => File('${root.path}/lib/canary_suffix.dart');
  File get hostTargetParserFile =>
      File('${root.path}/lib/src/host_target_parser.dart');
  File get pingCommandFile => File('${root.path}/lib/src/ping_command.dart');
  File get fileLifecycleNoteFile => File('${root.path}/$_fileLifecyclePath');
  File get gitLifecycleNoteFile => File('${root.path}/$_gitLifecyclePath');

  static _CodingGoalEditFixture create(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_goal_live_edit_')
        : Directory(workspaceRoot);
    _resetRoot(root);
    final lib = Directory('${root.path}/lib')..createSync(recursive: true);
    File('${lib.path}/canary_greeting.dart').writeAsStringSync('''
String canaryGreeting(String name) {
  return 'Hello, \$name.';
}
''');
    File('${lib.path}/canary_greeting_test.dart').writeAsStringSync('''
import 'dart:io';

import 'canary_greeting.dart';

void main() {
  const marker = '$_editMarker';
  final actual = canaryGreeting('Ada');
  const expected = 'Hello, Ada! $_editMarker';
  if (actual != expected) {
    throw StateError('Expected "\$expected" but got "\$actual".');
  }
  stdout.writeln(marker);
}
''');
    final now = DateTime.now();
    return _CodingGoalEditFixture(
      root: root,
      project: CodingProject(
        id: 'coding-goal-live-edit-project',
        name: 'coding_goal_live_edit_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  static _CodingGoalEditFixture createTwoFile(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_goal_live_edit_')
        : Directory(workspaceRoot);
    _resetRoot(root);
    final lib = Directory('${root.path}/lib')..createSync(recursive: true);
    File('${lib.path}/canary_greeting.dart').writeAsStringSync('''
String canaryGreeting(String name) {
  return 'Hello, \$name';
}
''');
    File('${lib.path}/canary_suffix.dart').writeAsStringSync('''
String canarySuffix() {
  return '.';
}
''');
    File('${lib.path}/canary_greeting_test.dart').writeAsStringSync('''
import 'dart:io';

import 'canary_greeting.dart';
import 'canary_suffix.dart';

void main() {
  const marker = '$_editMarker';
  final suffix = canarySuffix();
  const expectedSuffix = '! $_editMarker';
  if (suffix != expectedSuffix) {
    throw StateError('Expected suffix "\$expectedSuffix" but got "\$suffix".');
  }

  final actual = canaryGreeting('Ada');
  const expected = 'Hello, Ada! $_editMarker';
  if (actual != expected) {
    throw StateError('Expected "\$expected" but got "\$actual".');
  }
  stdout.writeln(marker);
}
''');
    final now = DateTime.now();
    return _CodingGoalEditFixture(
      root: root,
      project: CodingProject(
        id: 'coding-goal-live-edit-project',
        name: 'coding_goal_live_edit_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  static _CodingGoalEditFixture createParserPackage(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_goal_live_edit_')
        : Directory(workspaceRoot);
    _resetRoot(root);
    final src = Directory('${root.path}/lib/src')..createSync(recursive: true);
    File('${src.path}/host_target_parser.dart').writeAsStringSync('''
class HostTarget {
  const HostTarget({
    required this.host,
    required this.count,
    required this.useIpv6,
  });

  final String host;
  final int count;
  final bool useIpv6;
}

HostTarget parseHostTarget(List<String> args) {
  final host = args.isEmpty ? 'localhost' : args.first;
  return HostTarget(host: host, count: 1, useIpv6: false);
}
''');
    File('${src.path}/ping_command.dart').writeAsStringSync('''
import 'host_target_parser.dart';

String buildPingCommand(List<String> args) {
  final target = parseHostTarget(args);
  return 'ping -c \${target.count} \${target.host}';
}
''');
    File('${root.path}/lib/canary_greeting_test.dart').writeAsStringSync('''
import 'dart:io';

import 'src/host_target_parser.dart';
import 'src/ping_command.dart';

void main() {
  const marker = '$_editMarker';
  final args = ['--count', '3', '--ipv6', 'example.com'];
  final target = parseHostTarget(args);
  _expectEqual(target.host, 'example.com', 'host');
  _expectEqual(target.count, 3, 'count');
  _expectEqual(target.useIpv6, true, 'useIpv6');

  final command = buildPingCommand(args);
  _expectEqual(command, 'ping -6 -c 3 example.com', 'command');
  stdout.writeln(marker);
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('Expected \$label "\$expected" but got "\$actual".');
  }
}
''');
    final now = DateTime.now();
    return _CodingGoalEditFixture(
      root: root,
      project: CodingProject(
        id: 'coding-goal-live-edit-project',
        name: 'coding_goal_live_edit_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  static _CodingGoalEditFixture createEmpty(
    String? workspaceRoot, {
    required String projectId,
    required String projectName,
  }) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_goal_live_ops_')
        : Directory(workspaceRoot);
    _resetRoot(root);
    Directory('${root.path}/lib').createSync(recursive: true);
    final now = DateTime.now();
    return _CodingGoalEditFixture(
      root: root,
      project: CodingProject(
        id: projectId,
        name: projectName,
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  static void _resetRoot(Directory root) {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
    root.createSync(recursive: true);
  }

  Future<ProcessResult> runTest() {
    return Process.run('dart', [
      'lib/canary_greeting_test.dart',
    ], workingDirectory: root.path);
  }

  void dispose() {
    if (deleteOnDispose && root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }

  String _sourceDiagnostics() {
    final lib = Directory('${root.path}/lib');
    final files = lib.existsSync()
        ? lib
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .toList()
        : <File>[];
    files.sort((a, b) => _relativePath(a).compareTo(_relativePath(b)));
    return files
        .map((file) {
          if (!file.existsSync()) {
            return '${_relativePath(file)}=(missing)';
          }
          return '${_relativePath(file)}=${file.readAsStringSync()}';
        })
        .join('\n');
  }

  String _relativePath(File file) {
    final absolutePath = file.absolute.path;
    final rootPath = root.absolute.path;
    if (absolutePath == rootPath) {
      return '.';
    }
    if (absolutePath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return absolutePath
          .substring(rootPath.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
    }
    return absolutePath;
  }
}

class _CodingGoalLiveEditEnv {
  const _CodingGoalLiveEditEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    required this.suppressEditHarnessPrompt,
    required this.workspaceRoot,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;
  final bool suppressEditHarnessPrompt;
  final String? workspaceRoot;

  static _CodingGoalLiveEditEnv fromEnvironment() {
    return _CodingGoalLiveEditEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_MAX_TOKENS'] ??
                '',
          ) ??
          4096,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_TEMPERATURE'] ??
                '',
          ) ??
          0.1,
      suppressEditHarnessPrompt:
          Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_SUPPRESS_LL15_HARNESS'] ==
              '1' ||
          Platform.environment['CAVERNO_LL15_SUPPRESS_EDIT_HARNESS'] == '1',
      workspaceRoot:
          Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_WORK_ROOT'],
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for coding goal live edit validation.');
  }
  return value;
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env);

  final _CodingGoalLiveEditEnv env;

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
      modelCapabilityProfiles: _modelCapabilityProfilesFromEnvironment(env),
    );
  }

  @override
  Future<void> upsertModelCapabilityProfile(
    ModelCapabilityProfile profile,
  ) async {
    final normalized = profile.normalizedForPersistence();
    if (normalized.normalizedModel.isEmpty) {
      throw ArgumentError('Model capability profile model is required');
    }

    final profiles = List<ModelCapabilityProfile>.from(
      state.modelCapabilityProfiles,
    );
    final index = profiles.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      profiles.add(normalized);
    } else {
      profiles[index] = normalized;
    }
    state = state.copyWith(modelCapabilityProfiles: profiles);
  }
}

List<ModelCapabilityProfile> _modelCapabilityProfilesFromEnvironment(
  _CodingGoalLiveEditEnv env,
) {
  final toolCallStyle = _enumFromEnvironment(
    'CAVERNO_LLM_MODEL_TOOL_CALL_STYLE',
    ModelToolCallStyle.values,
    ModelToolCallStyle.unknown,
  );
  final structuredOutputSupport = _enumFromEnvironment(
    'CAVERNO_LLM_MODEL_STRUCTURED_OUTPUT',
    ModelStructuredOutputSupport.values,
    ModelStructuredOutputSupport.unknown,
  );
  final editFormatPreference = _enumFromEnvironment(
    'CAVERNO_LLM_MODEL_EDIT_FORMAT',
    ModelEditFormatPreference.values,
    ModelEditFormatPreference.unknown,
  );
  final usableContextTokens =
      int.tryParse(
        Platform.environment['CAVERNO_LLM_MODEL_USABLE_CONTEXT_TOKENS'] ?? '',
      ) ??
      0;
  if (toolCallStyle == ModelToolCallStyle.unknown &&
      structuredOutputSupport == ModelStructuredOutputSupport.unknown &&
      editFormatPreference == ModelEditFormatPreference.unknown &&
      usableContextTokens <= 0) {
    return const <ModelCapabilityProfile>[];
  }
  return [
    ModelCapabilityProfile(
      id: '',
      baseUrl: env.baseUrl,
      model: env.model,
      toolCallStyle: toolCallStyle,
      structuredOutputSupport: structuredOutputSupport,
      editFormatPreference: editFormatPreference,
      usableContextTokens: usableContextTokens,
      probedAt: DateTime.now(),
      probeSummary: 'Injected by coding goal live edit canary environment.',
      probeMetadata: const {'source': 'coding_goal_live_edit_canary'},
    ).normalizedForPersistence(),
  ];
}

T _enumFromEnvironment<T extends Enum>(
  String name,
  List<T> values,
  T fallback,
) {
  final raw = Platform.environment[name]?.trim();
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  throw StateError('Unsupported $name "$raw".');
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

class _MockConversationBox extends Mock implements Box<String> {}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(ChatMemoryRepository(_MockMemoryBox()));

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

class _SandboxToolCall {
  const _SandboxToolCall({
    required this.name,
    required this.arguments,
    required this.result,
    required this.success,
    required this.sourceBeforeCall,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final String result;
  final bool success;
  final String? sourceBeforeCall;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'arguments': arguments,
      'success': success,
      'result': result,
      if (sourceBeforeCall != null) 'sourceBeforeCall': sourceBeforeCall,
    };
  }
}

class _SandboxCodingToolService extends McpToolService {
  _SandboxCodingToolService(
    this.root, {
    this.acceptedLocalCommands = const {},
    this.enableGit = false,
  });

  final Directory root;
  final Set<String> acceptedLocalCommands;
  final bool enableGit;
  final List<_SandboxToolCall> executedCalls = [];

  List<String> get executedToolNames =>
      executedCalls.map((call) => call.name).toList(growable: false);

  List<int> get testCommandExitCodes => executedCalls
      .where((call) => call.name == 'local_execute_command')
      .map((call) => _tryDecodeObject(call.result)['exit_code'])
      .whereType<num>()
      .map((code) => code.toInt())
      .toList(growable: false);

  List<bool> get testCommandSourceContainsMarkerBeforeCall => executedCalls
      .where((call) => call.name == 'local_execute_command')
      .map((call) => call.sourceBeforeCall?.contains(_editMarker) ?? false)
      .toList(growable: false);

  int get firstTestCommandIndex =>
      executedCalls.indexWhere((call) => call.name == 'local_execute_command');

  int get firstMutationIndex => executedCalls.indexWhere(
    (call) => call.name == 'edit_file' || call.name == 'write_file',
  );

  List<String> get mutatedRelativePaths {
    final paths = <String>{};
    for (final call in executedCalls) {
      if (call.name != 'edit_file' && call.name != 'write_file') {
        continue;
      }
      final relativePath = _relativePathForToolArgument(
        call.arguments['path'] as String?,
      );
      if (relativePath != null) {
        paths.add(relativePath);
      }
    }
    return paths.toList(growable: false)..sort();
  }

  List<String> get successfulWritePaths =>
      executedCalls
          .where((call) => call.name == 'write_file' && call.success)
          .map(
            (call) =>
                _relativePathForToolArgument(call.arguments['path'] as String?),
          )
          .whereType<String>()
          .toSet()
          .toList(growable: false)
        ..sort();

  List<String> get successfulMutationPaths =>
      executedCalls
          .where(
            (call) =>
                (call.name == 'write_file' || call.name == 'edit_file') &&
                call.success,
          )
          .map(
            (call) =>
                _relativePathForToolArgument(call.arguments['path'] as String?),
          )
          .whereType<String>()
          .toSet()
          .toList(growable: false)
        ..sort();

  List<String> get successfulGitCommands => executedCalls
      .where((call) => call.name == 'git_execute_command' && call.success)
      .map((call) => (call.arguments['command'] as String?)?.trim())
      .whereType<String>()
      .map(GitTools.normalizeCommand)
      .toList(growable: false);

  int get successfulTestCommandCount => executedCalls.where((call) {
    if (call.name != 'local_execute_command' || !call.success) {
      return false;
    }
    final decoded = _tryDecodeObject(call.result);
    return decoded['exit_code'] == 0 &&
        (decoded['stdout'] as String? ?? '').contains(_editMarker);
  }).length;

  int successfulLocalCommandCount(String command) {
    return executedCalls.where((call) {
      if (call.name != 'local_execute_command' || !call.success) {
        return false;
      }
      final decoded = _tryDecodeObject(call.result);
      return decoded['command'] == command && decoded['exit_code'] == 0;
    }).length;
  }

  List<String> readFileContentsForRelativePath(String relativePath) {
    return executedCalls
        .where((call) {
          if (call.name != 'read_file' || !call.success) {
            return false;
          }
          return _relativePathForToolArgument(
                call.arguments['path'] as String?,
              ) ==
              relativePath;
        })
        .map((call) => _tryDecodeObject(call.result)['content'])
        .whereType<String>()
        .toList(growable: false);
  }

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final acceptedCommands = [
      _testCommand,
      ...acceptedLocalCommands,
    ].join(', ');
    final tools = <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': 'list_directory',
          'description':
              'List files in the isolated coding goal edit canary fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'recursive': {'type': 'boolean'},
              'max_entries': {'type': 'integer'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'description':
              'Read a UTF-8 text file from the isolated coding goal edit canary fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'offset': {'type': 'integer'},
              'limit': {'type': 'integer'},
            },
            'required': ['path'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_file',
          'description':
              'Replace exact text inside a file in the isolated fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'old_text': {'type': 'string'},
              'new_text': {'type': 'string'},
              'replace_all': {'type': 'boolean'},
              'reason': {'type': 'string'},
            },
            'required': ['path', 'old_text', 'new_text'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description':
              'Write a full UTF-8 text file in the isolated fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
              'create_parents': {'type': 'boolean'},
              'reason': {'type': 'string'},
            },
            'required': ['path', 'content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'local_execute_command',
          'description':
              'Run approved fixture commands. Accepted commands: '
              '$acceptedCommands.',
          'parameters': {
            'type': 'object',
            'properties': {
              'command': {'type': 'string'},
              'working_directory': {'type': 'string'},
              'reason': {'type': 'string'},
            },
            'required': ['command'],
          },
        },
      },
    ];
    if (enableGit) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'git_execute_command',
          'description':
              'Execute one git subcommand in the isolated canary repository. '
              'Use one tool call per subcommand and avoid shell operators.',
          'parameters': {
            'type': 'object',
            'properties': {
              'command': {
                'type': 'string',
                'description':
                    'Git subcommand and arguments without the leading "git".',
              },
              'working_directory': {
                'type': 'string',
                'description':
                    'Project root. Optional; defaults to the canary root.',
              },
              'reason': {'type': 'string'},
            },
            'required': ['command'],
          },
        },
      });
    }
    return tools;
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final sourceBeforeCall = _sourceText();
    final result = await _executeTool(name: name, arguments: arguments);
    executedCalls.add(
      _SandboxToolCall(
        name: name,
        arguments: Map<String, dynamic>.from(arguments),
        result: result.result,
        success: result.isSuccess,
        sourceBeforeCall: sourceBeforeCall,
      ),
    );
    return result;
  }

  String? _sourceText() {
    final file = File('${root.path}/lib/canary_greeting.dart');
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsStringSync();
  }

  String? _relativePathForToolArgument(String? rawPath) {
    final resolved = FilesystemTools.resolvePath(
      rawPath,
      defaultRoot: root.absolute.path,
    );
    if (resolved == null || resolved.trim().isEmpty) {
      return null;
    }
    final rootPath = root.absolute.path;
    final targetPath = File(resolved).absolute.path;
    if (targetPath == rootPath) {
      return '.';
    }
    if (!targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return null;
    }
    return targetPath
        .substring(rootPath.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
  }

  Future<McpToolResult> _executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    switch (name) {
      case 'list_directory':
        final path = _resolveInsideRoot(
          arguments['path'] as String?,
          allowEmpty: true,
        );
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.listDirectory(
          path: path.value!,
          recursive: arguments['recursive'] as bool? ?? false,
          maxEntries: ((arguments['max_entries'] as num?)?.toInt() ?? 200)
              .clamp(1, 500),
        );
        return _toolResult(name, result);
      case 'read_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.readFile(
          path: path.value!,
          offset: ((arguments['offset'] as num?)?.toInt() ?? 1).clamp(
            1,
            1000000,
          ),
          limit: (arguments['limit'] as num?)?.toInt(),
        );
        return _toolResult(name, result);
      case 'edit_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.editFile(
          path: path.value!,
          oldText: arguments['old_text'] as String? ?? '',
          newText: arguments['new_text'] as String? ?? '',
          replaceAll: arguments['replace_all'] as bool? ?? false,
        );
        return _toolResult(name, result);
      case 'write_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.writeFile(
          path: path.value!,
          content: arguments['content'] as String? ?? '',
          createParents: arguments['create_parents'] as bool? ?? true,
        );
        return _toolResult(name, result);
      case 'local_execute_command':
        return _executeLocalCommand(name, arguments);
      case 'git_execute_command':
        return _executeGitCommand(name, arguments);
      default:
        return _toolError(name, 'Unsupported canary tool: $name');
    }
  }

  Future<McpToolResult> _executeLocalCommand(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = (arguments['command'] as String?)?.trim() ?? '';
    if (!_isAcceptedTestCommand(command) &&
        !acceptedLocalCommands.contains(command)) {
      return _toolError(
        name,
        'Unsupported local command for this canary fixture: $command',
      );
    }
    final workingDirectory = _resolveInsideRoot(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (workingDirectory.error != null) {
      return _toolError(name, workingDirectory.error!);
    }
    if (workingDirectory.value != root.absolute.path) {
      return _toolError(
        name,
        'working_directory must be the canary project root.',
      );
    }

    if (command == _fileLifecycleDeleteCommand) {
      final target = File('${root.path}/$_fileLifecyclePath');
      if (target.existsSync()) {
        await target.delete();
      }
      return _commandResult(name: name, command: command, exitCode: 0);
    }

    if (command == _fileLifecycleVerifyDeletedCommand) {
      final target = File('${root.path}/$_fileLifecyclePath');
      final exists = target.existsSync();
      return _commandResult(
        name: name,
        command: command,
        exitCode: exists ? 1 : 0,
        stderr: exists ? 'File still exists: $_fileLifecyclePath\n' : '',
      );
    }

    final result = await Process.run('dart', [
      'lib/canary_greeting_test.dart',
    ], workingDirectory: root.path).timeout(const Duration(seconds: 30));
    return _processResult(
      name: name,
      command: _testCommand,
      result: result,
      failureMessage: 'Fixture test failed',
    );
  }

  Future<McpToolResult> _executeGitCommand(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    if (!enableGit) {
      return _toolError(name, 'Git commands are not enabled for this fixture.');
    }
    final command = (arguments['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return _toolError(name, 'command is required');
    }
    final workingDirectory = _resolveInsideRoot(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (workingDirectory.error != null) {
      return _toolError(name, workingDirectory.error!);
    }
    if (workingDirectory.value != root.absolute.path) {
      return _toolError(
        name,
        'working_directory must be the canary project root.',
      );
    }

    final result = await GitTools.execute(
      command: command,
      workingDirectory: root.path,
    );
    final decoded = _tryDecodeObject(result);
    final exitCode = decoded['exit_code'];
    final error = decoded['error'];
    final success = error == null && (exitCode == null || exitCode == 0);
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: success,
      errorMessage: success
          ? null
          : (error as String? ?? 'Git command exited with code $exitCode'),
    );
  }

  McpToolResult _processResult({
    required String name,
    required String command,
    required ProcessResult result,
    String? failureMessage,
  }) {
    return _commandResult(
      name: name,
      command: command,
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
      failureMessage: failureMessage,
    );
  }

  McpToolResult _commandResult({
    required String name,
    required String command,
    required int exitCode,
    String stdout = '',
    String stderr = '',
    String? failureMessage,
  }) {
    final payload = jsonEncode({
      'command': command,
      'working_directory': root.absolute.path,
      'exit_code': exitCode,
      'stdout': stdout,
      'stderr': stderr,
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: exitCode == 0,
      errorMessage: exitCode == 0
          ? null
          : (failureMessage ?? 'Command exited with code $exitCode'),
    );
  }

  bool _isAcceptedTestCommand(String command) {
    final normalized = command
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          './lib/canary_greeting_test.dart',
          'lib/canary_greeting_test.dart',
        )
        .trim();
    return normalized == _testCommand ||
        normalized == 'dart --enable-asserts lib/canary_greeting_test.dart';
  }

  _ResolvedPath _resolveInsideRoot(
    String? rawPath, {
    bool allowEmpty = false,
    bool directory = false,
  }) {
    final trimmed = rawPath?.trim();
    final effectivePath = (trimmed == null || trimmed.isEmpty) && allowEmpty
        ? '.'
        : trimmed;
    final resolved = FilesystemTools.resolvePath(
      effectivePath,
      defaultRoot: root.absolute.path,
    );
    if (resolved == null || resolved.trim().isEmpty) {
      return const _ResolvedPath(error: 'path is required');
    }

    final rootPath = root.absolute.path;
    final targetPath = directory
        ? Directory(resolved).absolute.path
        : File(resolved).absolute.path;
    if (targetPath != rootPath &&
        !targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return const _ResolvedPath(
        error: 'Path must stay inside the canary project root.',
      );
    }
    return _ResolvedPath(value: targetPath);
  }

  McpToolResult _toolResult(String name, String result) {
    final decoded = _tryDecodeObject(result);
    final error = decoded['error'] as String?;
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: error == null || error.isEmpty,
      errorMessage: error,
    );
  }

  McpToolResult _toolError(String name, String error) {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': error}),
      isSuccess: false,
      errorMessage: error,
    );
  }
}

class _ResolvedPath {
  const _ResolvedPath({this.value, this.error});

  final String? value;
  final String? error;
}

Map<String, dynamic> _tryDecodeObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

class _CodingGoalLiveEditDataSource implements ChatDataSource {
  _CodingGoalLiveEditDataSource(
    this.delegate, {
    required this.suppressEditHarnessPrompt,
  });

  final ChatRemoteDataSource delegate;
  final bool suppressEditHarnessPrompt;
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> streamWithToolsRequests = [];
  final List<List<Message>> createWithToolResultRequests = [];

  List<String> get systemPrompts {
    return [
          ...streamRequests,
          ...streamWithToolsRequests,
          ...createWithToolResultRequests,
        ]
        .expand((request) => request)
        .where(
          (message) =>
              message.role == MessageRole.system &&
              message.content.startsWith('Current local date and time'),
        )
        .map((message) => message.content)
        .toList(growable: false);
  }

  String get firstSystemPrompt {
    return systemPrompts.firstOrNull ?? '';
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final requestMessages = _requestMessages(messages);
    streamRequests.add(requestMessages);
    return delegate.streamChatCompletion(
      messages: requestMessages,
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
    final requestMessages = _requestMessages(messages);
    return delegate.createChatCompletion(
      messages: requestMessages,
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
    final requestMessages = _requestMessages(messages);
    streamWithToolsRequests.add(requestMessages);
    return delegate.streamChatCompletionWithTools(
      messages: requestMessages,
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
    final requestMessages = _requestMessages(messages);
    createWithToolResultRequests.add(requestMessages);
    return delegate.createChatCompletionWithToolResults(
      messages: requestMessages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
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
    final requestMessages = _requestMessages(messages);
    createWithToolResultRequests.add(requestMessages);
    return delegate.createChatCompletionWithToolResult(
      messages: requestMessages,
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
    final requestMessages = _requestMessages(messages);
    createWithToolResultRequests.add(requestMessages);
    return delegate.streamWithToolResult(
      messages: requestMessages,
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

  List<Message> _requestMessages(List<Message> messages) {
    if (!suppressEditHarnessPrompt) {
      return List<Message>.unmodifiable(messages);
    }
    return messages
        .map((message) {
          if (message.role != MessageRole.system ||
              !message.content.contains('LL15 WEAK-MODEL EDIT HARNESS')) {
            return message;
          }
          return message.copyWith(
            content: _stripLl15EditHarness(message.content),
          );
        })
        .toList(growable: false);
  }

  String _stripLl15EditHarness(String content) {
    final lines = const LineSplitter().convert(content);
    final retained = <String>[];
    var skippingHarness = false;
    for (final line in lines) {
      if (line == 'LL15 WEAK-MODEL EDIT HARNESS:') {
        skippingHarness = true;
        continue;
      }
      if (skippingHarness) {
        if (_isLl15HarnessLine(line)) {
          continue;
        }
        skippingHarness = false;
      }
      retained.add(line);
    }
    return retained.join('\n');
  }

  bool _isLl15HarnessLine(String line) {
    return line.startsWith('When editing existing files,') ||
        line.startsWith('Required edit_file arguments:') ||
        line.startsWith('Use JSON with double-quoted keys') ||
        line.startsWith('Set old_text to exact current text') ||
        line.startsWith('Set replace_all=false') ||
        line.startsWith('If old_text was not found,') ||
        line.startsWith('Example edit_file arguments:') ||
        line.startsWith('Observed edit_file apply failure rate');
  }
}

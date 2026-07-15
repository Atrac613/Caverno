import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _RecoverySettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.coding,
    demoMode: false,
    mcpEnabled: false,
  );
}

class _RecoveryCodingProjectsNotifier extends CodingProjectsNotifier {
  _RecoveryCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);
}

class _RecoveryConversationsNotifier extends ConversationsNotifier {
  _RecoveryConversationsNotifier(this.conversation);

  final Conversation conversation;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

  @override
  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(
      planArtifact: clearPlanArtifact ? null : planArtifact,
      updatedAt: DateTime(2026, 7, 15, 15, 30),
    );
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }

  @override
  Future<bool> refreshCurrentWorkflowProjectionFromApprovedPlan() async => true;

  @override
  Future<void> exitPlanningSession() async {}

  @override
  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    String? workflowSourceHash,
    DateTime? workflowDerivedAt,
    bool clearWorkflowSpec = false,
    bool preserveWorkflowProjection = false,
  }) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(
      workflowStage: workflowStage ?? current.workflowStage,
      workflowSpec: clearWorkflowSpec
          ? null
          : workflowSpec ?? current.workflowSpec,
      workflowSourceHash: workflowSourceHash ?? current.workflowSourceHash,
      workflowDerivedAt: workflowDerivedAt ?? current.workflowDerivedAt,
      updatedAt: DateTime(2026, 7, 15, 15, 30),
    );
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }

  @override
  Future<void> updateCurrentExecutionTaskProgress({
    required String taskId,
    required ConversationWorkflowTaskStatus status,
    bool allowStatusRegression = false,
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? summary,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
    String? eventSummary,
    DateTime? eventTimestamp,
  }) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final progress = [
      ...current.effectiveExecutionProgress.where(
        (item) => item.taskId != taskId,
      ),
      ConversationExecutionTaskProgress(
        taskId: taskId,
        status: status,
        validationStatus:
            validationStatus ?? ConversationExecutionValidationStatus.unknown,
        updatedAt: DateTime(2026, 7, 15, 15, 30),
        lastRunAt: lastRunAt,
        lastValidationAt: lastValidationAt,
        summary: summary ?? '',
        blockedReason: blockedReason ?? '',
        lastValidationCommand: lastValidationCommand ?? '',
        lastValidationSummary: lastValidationSummary ?? '',
      ),
    ];
    final updated = current.copyWith(
      executionProgress: progress,
      updatedAt: DateTime(2026, 7, 15, 15, 30),
    );
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }
}

class _RecoveryChatNotifier extends ChatNotifier {
  final List<String> sentMessages = [];
  final List<String> hiddenPrompts = [];
  var _toolResultReadCount = 0;

  @override
  ChatState build() => ChatState.initial();

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
    sentMessages.add(content);
  }

  @override
  Future<void> sendHiddenPrompt(
    String instruction, {
    bool isVoiceMode = false,
    String languageCode = 'en',
    bool persistAssistantResponse = false,
    bool preserveGoalAutoContinueEvidence = false,
    bool replayVerifierImmediatelyAfterMutation = false,
    bool verifierOnlyContinuation = false,
    Set<String>? allowedToolNames,
  }) async {
    hiddenPrompts.add(instruction);
  }

  @override
  List<ToolResultInfo> takeLatestToolResults() {
    _toolResultReadCount += 1;
    if (_toolResultReadCount != 1) {
      return const [];
    }
    return [
      ToolResultInfo(
        id: 'unexecuted-command',
        name: 'local_execute_command',
        arguments: const {
          'reason': 'No matching successful command result was available.',
        },
        result: jsonEncode({
          'ok': false,
          'code': 'unexecuted_command_action',
          'error': 'The requested command was not executed.',
        }),
      ),
    ];
  }

  @override
  String? takeLatestHiddenAssistantResponse() => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'saved workflow retries after a synthetic unexecuted command result',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final projectRoot = Directory.systemTemp.createTempSync(
        'saved_workflow_recovery_test_',
      );
      addTearDown(() {
        if (projectRoot.existsSync()) {
          projectRoot.deleteSync(recursive: true);
        }
      });
      final now = DateTime(2026, 7, 15, 15, 25);
      final project = CodingProject(
        id: 'project-1',
        name: 'todo',
        rootPath: projectRoot.path,
        createdAt: now,
        updatedAt: now,
      );
      const planMarkdown = '''
# Plan

## Stage
implement

## Tasks
1. Fulfill the sourced user request
   - Task ID: request-test
   - Status: pending
''';
      final conversation = Conversation(
        id: 'conversation-1',
        title: 'TODO app',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Build the TODO app.',
          tasks: [
            ConversationWorkflowTask(
              id: 'request-test',
              title: 'Fulfill the sourced user request',
            ),
          ],
        ),
        planArtifact: const ConversationPlanArtifact(
          draftMarkdown: planMarkdown,
        ),
        workflowSourceHash: computeConversationPlanHash(planMarkdown),
        workflowDerivedAt: now,
      );
      final chatNotifier = _RecoveryChatNotifier();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settingsNotifierProvider.overrideWith(_RecoverySettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            () => _RecoveryConversationsNotifier(conversation),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _RecoveryCodingProjectsNotifier(project),
          ),
          chatNotifierProvider.overrideWith(() => chatNotifier),
          routineSchedulerProvider.overrideWith(RoutineSchedulerController.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          assetLoader: const _TestTranslationLoader(),
          child: Builder(
            builder: (context) => UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const ChatPage(showDashboardOnStartup: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startTaskButton = find.text('Approve and start');
      expect(startTaskButton, findsOneWidget);
      await tester.ensureVisible(startTaskButton);
      await tester.tap(startTaskButton);
      await tester.pumpAndSettle();

      expect(chatNotifier.sentMessages, hasLength(1));
      expect(chatNotifier.hiddenPrompts, hasLength(1));
      expect(
        chatNotifier.hiddenPrompts.single,
        contains('stalled without any concrete tool call'),
      );
      expect(
        container
            .read(conversationsNotifierProvider)
            .currentConversation!
            .projectedExecutionTasks
            .single
            .status,
        ConversationWorkflowTaskStatus.inProgress,
      );
    },
  );
}

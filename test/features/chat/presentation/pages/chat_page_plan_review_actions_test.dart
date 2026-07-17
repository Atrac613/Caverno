import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
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

class _PlanReviewSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.coding,
    demoMode: false,
    mcpEnabled: false,
  );
}

class _PlanReviewCodingProjectsNotifier extends CodingProjectsNotifier {
  _PlanReviewCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);
}

class _PlanReviewConversationsNotifier extends ConversationsNotifier {
  _PlanReviewConversationsNotifier(this.conversation);

  final Conversation conversation;
  var enterPlanningCount = 0;
  var exitPlanningCount = 0;
  var planArtifactWriteCount = 0;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

  @override
  Future<void> enterPlanningSession() async {
    enterPlanningCount += 1;
    _replaceCurrent(
      state.currentConversation!.copyWith(
        executionMode: ConversationExecutionMode.planning,
      ),
    );
  }

  @override
  Future<void> exitPlanningSession() async {
    exitPlanningCount += 1;
    _replaceCurrent(
      state.currentConversation!.copyWith(
        executionMode: ConversationExecutionMode.normal,
      ),
    );
  }

  @override
  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    planArtifactWriteCount += 1;
    _replaceCurrent(
      state.currentConversation!.copyWith(
        planArtifact: clearPlanArtifact ? null : planArtifact,
      ),
    );
  }

  void _replaceCurrent(Conversation updated) {
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }
}

class _PlanReviewChatNotifier extends ChatNotifier {
  var dismissPlanProposalCount = 0;

  @override
  ChatState build() => ChatState.initial();

  @override
  void dismissPlanProposal() {
    dismissPlanProposalCount += 1;
  }
}

class _PlanReviewHarness {
  const _PlanReviewHarness({required this.container});

  final ProviderContainer container;

  Conversation get conversation =>
      container.read(conversationsNotifierProvider).currentConversation!;

  _PlanReviewConversationsNotifier get conversationsNotifier =>
      container.read(conversationsNotifierProvider.notifier)
          as _PlanReviewConversationsNotifier;

  _PlanReviewChatNotifier get chatNotifier =>
      container.read(chatNotifierProvider.notifier) as _PlanReviewChatNotifier;
}

Future<_PlanReviewHarness> _pumpPlanReviewPage(
  WidgetTester tester, {
  required ConversationPlanArtifact planArtifact,
  ConversationExecutionMode executionMode = ConversationExecutionMode.normal,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final now = DateTime(2026, 7, 17, 10);
  final project = CodingProject(
    id: 'project-1',
    name: 'Plan review project',
    rootPath: Directory.systemTemp.path,
    createdAt: now,
    updatedAt: now,
  );
  final conversation = Conversation(
    id: 'conversation-1',
    title: 'Plan review',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workspaceMode: WorkspaceMode.coding,
    projectId: project.id,
    executionMode: executionMode,
    planArtifact: planArtifact,
  );

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsNotifierProvider.overrideWith(_PlanReviewSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(
        () => _PlanReviewConversationsNotifier(conversation),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _PlanReviewCodingProjectsNotifier(project),
      ),
      chatNotifierProvider.overrideWith(_PlanReviewChatNotifier.new),
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
  return _PlanReviewHarness(container: container);
}

Future<void> _tapPlanAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

String _composerText(WidgetTester tester) {
  final textField = find.descendant(
    of: find.byType(MessageInput),
    matching: find.byType(TextField),
  );
  expect(textField, findsOneWidget);
  return tester.widget<TextField>(textField).controller!.text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('editing an approved plan enters planning and prefills composer', (
    tester,
  ) async {
    final harness = await _pumpPlanReviewPage(
      tester,
      planArtifact: const ConversationPlanArtifact(
        approvedMarkdown: '# Plan\n\n## Tasks\n1. Keep behavior stable',
      ),
    );

    await _tapPlanAction(tester, 'Edit approved plan');

    expect(harness.conversationsNotifier.enterPlanningCount, 1);
    expect(harness.conversation.isPlanningSession, isTrue);
    expect(
      _composerText(tester),
      'Please revise the saved plan for this thread based on the following adjustment:\n-',
    );
  });

  testWidgets('cancelling pending edits restores the approved plan', (
    tester,
  ) async {
    const approvedMarkdown = '# Plan\n\n## Tasks\n1. Keep approved task';
    final harness = await _pumpPlanReviewPage(
      tester,
      executionMode: ConversationExecutionMode.planning,
      planArtifact: const ConversationPlanArtifact(
        draftMarkdown: '# Plan\n\n## Tasks\n1. Replace approved task',
        approvedMarkdown: approvedMarkdown,
      ),
    );

    await _tapPlanAction(tester, 'Cancel');

    final artifact = harness.conversation.effectivePlanArtifact;
    expect(artifact.normalizedDraftMarkdown, approvedMarkdown);
    expect(artifact.normalizedApprovedMarkdown, approvedMarkdown);
    expect(artifact.revisions, hasLength(1));
    expect(
      artifact.revisions.single.kind,
      ConversationPlanRevisionKind.restored,
    );
    expect(
      artifact.revisions.single.label,
      'Cancelled draft changes and restored approved plan',
    );
    expect(harness.conversationsNotifier.planArtifactWriteCount, 1);
    expect(harness.conversationsNotifier.exitPlanningCount, 1);
    expect(harness.chatNotifier.dismissPlanProposalCount, 1);
    expect(harness.conversation.isPlanningSession, isFalse);
    expect(_composerText(tester), isEmpty);
  });

  testWidgets('invalid draft approval is blocked before persistence', (
    tester,
  ) async {
    final harness = await _pumpPlanReviewPage(
      tester,
      executionMode: ConversationExecutionMode.planning,
      planArtifact: const ConversationPlanArtifact(
        draftMarkdown: '# Plan\n\nThis document has no task section.',
      ),
    );

    await _tapPlanAction(tester, 'Approve and start');

    expect(
      find.textContaining('Cannot approve this plan yet:'),
      findsOneWidget,
    );
    expect(harness.conversationsNotifier.planArtifactWriteCount, 0);
    expect(harness.conversationsNotifier.exitPlanningCount, 0);
    expect(harness.chatNotifier.dismissPlanProposalCount, 0);
    expect(harness.conversation.isPlanningSession, isTrue);
  });
}

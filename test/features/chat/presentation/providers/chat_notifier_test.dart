import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/services/ssh_credentials_manager.dart';
import 'package:caverno/core/services/ssh_service.dart';
import 'package:caverno/core/services/tool_approval_audit_log.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/domain/services/skill_markdown_parser.dart';
import 'package:caverno/features/chat/domain/services/truncation_notice.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/domain/services/analysis_options_lint_edit_guard.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';
import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';
import 'package:caverno/features/chat/domain/services/participant_turn_coordinator.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/providers/routines_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/primary_model_preparation_service.dart';
import 'package:caverno/features/settings/presentation/providers/local_model_lifecycle_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/core/types/workspace_mode.dart';

part 'chat_notifier_persistence_part.dart';
part 'chat_notifier_git_guardrails_part.dart';
part 'chat_notifier_ask_user_question_part.dart';
part 'chat_notifier_turn_rollback_part.dart';
part 'chat_notifier_context_surgery_part.dart';
part 'chat_notifier_test_doubles_part.dart';
part 'chat_notifier_final_answer_recovery_part.dart';
part 'chat_notifier_continuation_recovery_part.dart';
part 'chat_notifier_auto_review_escalation_part.dart';
part 'chat_notifier_approval_cache_part.dart';
part 'chat_notifier_pending_batch_part.dart';
part 'chat_notifier_goal_auto_continue_part.dart';
part 'chat_notifier_saved_workflow_guardrails_part.dart';
part 'chat_notifier_planning_contract_part.dart';
part 'chat_notifier_terminal_success_part.dart';
part 'chat_notifier_unwritten_file_claim_part.dart';
part 'chat_notifier_verification_claim_part.dart';
part 'chat_notifier_narrated_transcript_part.dart';
part 'chat_notifier_analysis_options_lint_guard_part.dart';
part 'chat_notifier_tool_failure_classification_part.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ChatNotifier notifier;
  late StreamController<String> controller;

  setUp(() {
    controller = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);

    container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(controller),
        ),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    notifier = container.read(chatNotifierProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    if (controller.hasListener) {
      await controller.close();
    } else {
      unawaited(controller.close());
    }
  });

  registerChatNotifierPersistenceTests();
  registerChatNotifierGitGuardrailTests();
  registerChatNotifierAskUserQuestionTests();
  registerChatNotifierTurnRollbackTests();
  registerChatNotifierContextSurgeryTests();
  registerChatNotifierFinalAnswerRecoveryTests();
  registerChatNotifierContinuationRecoveryTests();
  registerChatNotifierAutoReviewEscalationTests();
  registerChatNotifierApprovalCacheTests();
  registerChatNotifierPendingBatchTests();
  registerChatNotifierGoalAutoContinueTests();
  registerChatNotifierSavedWorkflowGuardrailTests();
  registerChatNotifierPlanningContractTests();
  registerChatNotifierUnwrittenFileClaimTests();
  registerChatNotifierVerificationClaimTests();
  registerChatNotifierNarratedTranscriptTests();
  registerChatNotifierAnalysisOptionsLintGuardTests();

  test('failed-command correction notice keeps the original answer', () {
    const notice =
        'A command exited with non-zero exit code 1, so any success, upload, '
        'release, pass, or completion claim is unverified. Treat the command '
        'as failed until a later command-execution tool result exits '
        'successfully.';
    const original =
        'Release completed successfully.\n\n'
        '1. Ran the build\n2. Uploaded the archive\n3. Tagged the release';

    final corrected = notifier
        .messageContentWithPrependedClaimCorrectionNoticeForTest(
          original,
          notice,
        );

    // The original answer must remain visible (the chat log must not look
    // wiped) and the correction must come first to frame it as unverified.
    expect(corrected, startsWith(notice));
    expect(corrected, contains(original));

    // Running the guard again must not stack a second copy of the notice.
    expect(
      notifier.messageContentWithPrependedClaimCorrectionNoticeForTest(
        corrected,
        notice,
      ),
      corrected,
    );
  });

  test('sendMessage marks regular streaming requests as loading', () async {
    await notifier.sendMessage('Inspect the workspace');

    expect(notifier.state.isLoading, isTrue);
    expect(notifier.state.messages, hasLength(2));
    expect(notifier.state.messages.first.role, MessageRole.user);
    expect(notifier.state.messages.first.content, 'Inspect the workspace');
    expect(notifier.state.messages.last.role, MessageRole.assistant);
    expect(notifier.state.messages.last.isStreaming, isTrue);
  });

  test('sendMessage streams attributed participant turns in order', () async {
    final dataSource = _ParticipantStreamingChatDataSource(
      chunkBatches: const [
        ['<think>Hidden planning.</think>\nPrimary answer.'],
        ['Reviewer answer.'],
      ],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final participantContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(participantContainer.dispose);
    final chatNotifier = participantContainer.read(
      chatNotifierProvider.notifier,
    );
    final conversationsNotifier = participantContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final conversation = conversationsNotifier.ensureCurrentConversation()!;
    await conversationsNotifier.updateConversationParticipants(
      conversation.id,
      participants: const [
        ConversationParticipant(
          id: 'primary',
          displayName: 'Primary',
          roleLabel: 'Coordinator',
          roleSystemPrompt: 'Coordinate the discussion.',
          model: 'primary-model',
          colorValue: 0xFF6750A4,
          order: 0,
        ),
        ConversationParticipant(
          id: 'reviewer',
          displayName: 'Reviewer',
          roleLabel: 'Critic',
          roleSystemPrompt: 'Critique the proposal.',
          model: 'review-model',
          colorValue: 0xFF006A6A,
          order: 1,
        ),
      ],
    );

    await chatNotifier.sendMessage('Discuss the proposal');

    final assistantMessages = chatNotifier.state.messages
        .where((message) => message.role == MessageRole.assistant)
        .toList(growable: false);
    expect(assistantMessages, hasLength(2));
    expect(
      assistantMessages[0].content,
      '<think>Hidden planning.</think>\nPrimary answer.',
    );
    expect(assistantMessages[0].participantId, 'primary');
    expect(assistantMessages[0].participantDisplayName, 'Primary');
    expect(assistantMessages[0].participantRoleLabel, 'Coordinator');
    expect(assistantMessages[1].content, 'Reviewer answer.');
    expect(assistantMessages[1].participantId, 'reviewer');
    expect(assistantMessages[1].participantColorValue, 0xFF006A6A);
    expect(dataSource.requestedModels, ['primary-model', 'review-model']);
    expect(dataSource.streamRequests, hasLength(2));
    expect(dataSource.streamRequests.first.first.role, MessageRole.system);
    expect(
      dataSource.streamRequests.first.first.content,
      contains('Participant role instructions for this response:'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('Coordinate the discussion.'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('- Name: Primary'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('- Role: Coordinator'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('- Reviewer · Critic'),
    );
    expect(
      dataSource.streamRequests.first.first.content,
      contains('Handoff: <participant name or role>'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('Critique the proposal.'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('- Name: Reviewer'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('- Role: Critic'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('- Primary · Coordinator'),
    );
    expect(
      dataSource.streamRequests.last.first.content,
      contains('yield the floor'),
    );
    expect(
      dataSource.streamRequests.first.where(
        (message) => message.id.startsWith('participant_role_prompt_'),
      ),
      isEmpty,
    );
    expect(
      dataSource.streamRequests.last
          .map((message) => message.content)
          .join('\n'),
      contains('Primary'),
    );
    expect(
      dataSource.streamRequests.last
          .map((message) => message.content)
          .join('\n'),
      isNot(contains('Hidden planning')),
    );
    expect(chatNotifier.state.participantTurnRuntime, isNull);
  });

  test(
    'facilitator without handoff returns the floor before specialists speak',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          ['This can be answered without specialist input.'],
          ['Unexpected engineer answer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Facilitate the discussion.',
            model: 'primary-model',
            colorValue: 0xFF6750A4,
            order: 0,
          ),
          ConversationParticipant(
            id: 'engineer',
            displayName: 'Engineer',
            roleLabel: 'Senior Engineer',
            roleSystemPrompt: 'Cover implementation details.',
            model: 'engineer-model',
            colorValue: 0xFF006A6A,
            order: 1,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the proposal');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        'primary',
      ]);
      expect(
        assistantMessages.single.content,
        'This can be answered without specialist input.',
      );
      expect(dataSource.requestedModels, ['primary-model']);
      expect(dataSource.streamRequests, hasLength(1));
      expect(
        dataSource.streamRequests.single.first.content,
        contains('the floor returns to the user'),
      );
    },
  );

  test(
    'facilitator question handoff returns the floor before specialists speak',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          ['Which area should we start with?\nHandoff: Senior Engineer'],
          ['Unexpected engineer answer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Facilitate the discussion.',
            model: 'primary-model',
            colorValue: 0xFF6750A4,
            order: 0,
          ),
          ConversationParticipant(
            id: 'engineer',
            displayName: 'Engineer',
            roleLabel: 'Senior Engineer',
            roleSystemPrompt: 'Cover implementation details.',
            model: 'engineer-model',
            colorValue: 0xFF006A6A,
            order: 1,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the proposal');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        'primary',
      ]);
      expect(
        assistantMessages.single.content,
        'Which area should we start with?',
      );
      expect(assistantMessages.single.content, isNot(contains('Handoff:')));
      expect(dataSource.requestedModels, ['primary-model']);
      expect(dataSource.streamRequests, hasLength(1));
    },
  );

  test(
    'facilitator mixed user choice handoff returns the floor before specialists speak',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          [
            'Which scenario should we start with? Please choose one before we proceed.\n\n'
                'Senior Engineer, what implementation risk would you highlight?\n'
                'Handoff: Senior Engineer',
          ],
          ['Unexpected engineer answer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Facilitate the discussion.',
            model: 'primary-model',
            colorValue: 0xFF6750A4,
            order: 0,
          ),
          ConversationParticipant(
            id: 'engineer',
            displayName: 'Engineer',
            roleLabel: 'Senior Engineer',
            roleSystemPrompt: 'Cover implementation details.',
            model: 'engineer-model',
            colorValue: 0xFF006A6A,
            order: 1,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the proposal');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        'primary',
      ]);
      expect(
        assistantMessages.single.content,
        'Which scenario should we start with? Please choose one before we proceed.',
      );
      expect(assistantMessages.single.content, isNot(contains('Handoff:')));
      expect(assistantMessages.single.handoffTargetParticipantId, isNull);
      expect(dataSource.requestedModels, ['primary-model']);
      expect(dataSource.streamRequests, hasLength(1));
    },
  );

  test(
    'participant handoff routes the next turn and hides the marker',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          [
            'The implementation details should be covered next.\n'
                'Senior Engineer, what do you think about this risk?\n'
                'Handoff: Senior Engineer',
          ],
          ['Engineering answer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Facilitate the discussion.',
            model: 'primary-model',
            colorValue: 0xFF6750A4,
            order: 0,
          ),
          ConversationParticipant(
            id: 'critic',
            displayName: 'Critic',
            roleLabel: 'Critic',
            roleSystemPrompt: 'Challenge weak assumptions.',
            model: 'critic-model',
            colorValue: 0xFFB3261E,
            order: 1,
          ),
          ConversationParticipant(
            id: 'engineer',
            displayName: 'Engineer',
            roleLabel: 'Senior Engineer',
            roleSystemPrompt: 'Cover implementation details.',
            model: 'engineer-model',
            colorValue: 0xFF006A6A,
            order: 2,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the implementation');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        'primary',
        'engineer',
      ]);
      expect(
        assistantMessages.first.content,
        'The implementation details should be covered next.\n'
        'Senior Engineer, what do you think about this risk?',
      );
      expect(assistantMessages.first.content, isNot(contains('Handoff:')));
      expect(
        assistantMessages.first.content,
        contains('Senior Engineer, what do you think'),
      );
      expect(assistantMessages.first.handoffTargetParticipantId, 'engineer');
      expect(assistantMessages.first.handoffTargetDisplayName, 'Engineer');
      expect(assistantMessages.first.handoffTargetRoleLabel, 'Senior Engineer');
      expect(assistantMessages.last.content, 'Engineering answer.');
      expect(dataSource.requestedModels, ['primary-model', 'engineer-model']);

      final engineerTranscript = dataSource.streamRequests.last
          .map((message) => message.content)
          .join('\n');
      expect(engineerTranscript, contains('Primary · Facilitator'));
      expect(engineerTranscript, isNot(contains('Handoff: Senior Engineer')));
    },
  );

  test(
    'participant natural invitation routes the next turn without marker',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          [
            'The weak assumptions should be challenged next.\n'
                'Critic, what risk is being overlooked?',
          ],
          ['Critical review.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Facilitator',
            roleSystemPrompt: 'Facilitate the discussion.',
            model: 'primary-model',
            colorValue: 0xFF6750A4,
            order: 0,
          ),
          ConversationParticipant(
            id: 'critic',
            displayName: 'Critic',
            roleLabel: 'Critic',
            roleSystemPrompt: 'Challenge weak assumptions.',
            model: 'critic-model',
            colorValue: 0xFFB3261E,
            order: 1,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the implementation');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        'primary',
        'critic',
      ]);
      expect(
        assistantMessages.first.content,
        'The weak assumptions should be challenged next.\n'
        'Critic, what risk is being overlooked?',
      );
      expect(assistantMessages.first.handoffTargetParticipantId, 'critic');
      expect(assistantMessages.last.content, 'Critical review.');
      expect(dataSource.requestedModels, ['primary-model', 'critic-model']);
    },
  );

  test(
    'full participant approval stores successful tool names on the final message',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        toolResponses: [
          _ParticipantToolStreamResponse(
            chunks: const [
              '<tool_call>{"name":"read_file","arguments":{"path":"README.md"}}</tool_call>',
            ],
            completion: ChatCompletionResult(
              content:
                  '<tool_call>{"name":"read_file","arguments":{"path":"README.md"}}</tool_call>',
              toolCalls: [
                ToolCallInfo(
                  id: 'call_read',
                  name: 'read_file',
                  arguments: const {'path': 'README.md'},
                ),
                ToolCallInfo(
                  id: 'call_write',
                  name: 'write_file',
                  arguments: const {'path': 'README.md', 'content': 'oops'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ),
          _ParticipantToolStreamResponse(
            chunks: const ['Final review grounded in README.'],
            completion: ChatCompletionResult(
              content: 'Final review grounded in README.',
              finishReason: 'stop',
            ),
          ),
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': 'README contents',
          'write_file': 'should not execute',
        },
      );
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'reviewer',
            displayName: 'Reviewer',
            roleLabel: 'Critic',
            roleSystemPrompt: 'Critique the proposal.',
            model: 'review-model',
            toolApprovalMode: ToolApprovalMode.fullAccess,
            toolsEnabled: true,
            colorValue: 0xFF006A6A,
            order: 0,
          ),
        ],
      );

      await chatNotifier.sendMessage('Review with evidence');

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages, hasLength(1));
      expect(
        assistantMessages.single.content,
        'Final review grounded in README.',
      );
      expect(assistantMessages.single.participantId, 'reviewer');
      expect(assistantMessages.single.participantToolNames, ['read_file']);
      expect(toolService.executedToolNames, ['read_file']);
      expect(dataSource.toolStreamRequests, hasLength(2));
      expect(_toolNames(dataSource.toolStreamRequests.first.tools), [
        'read_file',
      ]);
      expect(
        dataSource.toolStreamRequests.last.messages.last.content,
        contains('README contents'),
      );
      expect(
        dataSource.toolStreamRequests.last.messages.last.content,
        contains('participant_tools_require_read_only_allowlist'),
      );
    },
  );

  test('default participant approval waits for manual tool approval', () async {
    final dataSource = _ParticipantStreamingChatDataSource(
      toolResponses: [
        _ParticipantToolStreamResponse(
          completion: ChatCompletionResult(
            content:
                '<tool_call>{"name":"read_file","arguments":{"path":"README.md"}}</tool_call>',
            toolCalls: [
              ToolCallInfo(
                id: 'call_read',
                name: 'read_file',
                arguments: const {
                  'path': 'README.md',
                  'reason': 'Check the proposal evidence.',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ),
        _ParticipantToolStreamResponse(
          chunks: const ['Final answer after denial.'],
          completion: ChatCompletionResult(
            content: 'Final answer after denial.',
            finishReason: 'stop',
          ),
        ),
      ],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolService = _FakeMcpToolService(
      results: const {'read_file': 'README contents'},
    );
    final participantContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(participantContainer.dispose);
    final chatNotifier = participantContainer.read(
      chatNotifierProvider.notifier,
    );
    final conversationsNotifier = participantContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final conversation = conversationsNotifier.ensureCurrentConversation()!;
    await conversationsNotifier.updateConversationParticipants(
      conversation.id,
      participants: const [
        ConversationParticipant(
          id: 'reviewer',
          displayName: 'Reviewer',
          roleLabel: 'Critic',
          roleSystemPrompt: 'Critique the proposal.',
          model: 'review-model',
          toolsEnabled: true,
          order: 0,
        ),
      ],
    );

    final sendFuture = chatNotifier.sendMessage('Review with evidence');
    await _waitForCondition(
      () => chatNotifier.state.pendingParticipantToolApproval != null,
    );

    final pending = chatNotifier.state.pendingParticipantToolApproval;
    expect(pending, isNotNull);
    expect(pending!.participantName, 'Reviewer');
    expect(pending.toolName, 'read_file');
    expect(pending.arguments['path'], 'README.md');
    expect(toolService.executedToolNames, isEmpty);

    chatNotifier.resolveParticipantToolApproval(
      id: pending.id,
      approved: false,
    );
    await sendFuture;

    final assistantMessage = chatNotifier.state.messages.last;
    expect(assistantMessage.content, 'Final answer after denial.');
    expect(assistantMessage.participantToolNames, isEmpty);
    expect(toolService.executedToolNames, isEmpty);
    expect(
      dataSource.toolStreamRequests.last.messages.last.content,
      contains('approval_denied'),
    );
  });

  test('auto-review participant approval can deny tool execution', () async {
    final dataSource = _ParticipantStreamingChatDataSource(
      toolResponses: [
        _ParticipantToolStreamResponse(
          completion: ChatCompletionResult(
            content:
                '<tool_call>{"name":"read_file","arguments":{"path":"secrets.txt"}}</tool_call>',
            toolCalls: [
              ToolCallInfo(
                id: 'call_read',
                name: 'read_file',
                arguments: const {'path': 'secrets.txt'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ),
        _ParticipantToolStreamResponse(
          chunks: const ['Final answer after review denial.'],
          completion: ChatCompletionResult(
            content: 'Final answer after review denial.',
            finishReason: 'stop',
          ),
        ),
      ],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"deny","riskLevel":"medium","userAuthorization":"low","rationale":"The secret file lookup was not requested by the user."}',
          finishReason: 'stop',
        ),
      ],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolService = _FakeMcpToolService(
      results: const {'read_file': 'secret contents'},
    );
    final participantContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(participantContainer.dispose);
    final chatNotifier = participantContainer.read(
      chatNotifierProvider.notifier,
    );
    final conversationsNotifier = participantContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final conversation = conversationsNotifier.ensureCurrentConversation()!;
    await conversationsNotifier.updateConversationParticipants(
      conversation.id,
      participants: const [
        ConversationParticipant(
          id: 'reviewer',
          displayName: 'Reviewer',
          roleLabel: 'Critic',
          roleSystemPrompt: 'Critique the proposal.',
          model: 'review-model',
          toolApprovalMode: ToolApprovalMode.autoReview,
          toolsEnabled: true,
          order: 0,
        ),
      ],
    );

    await chatNotifier.sendMessage('Review with evidence');

    expect(chatNotifier.state.pendingParticipantToolApproval, isNull);
    expect(dataSource.autoReviewRequestMessages, hasLength(1));
    expect(
      dataSource.autoReviewRequestMessages.first.first.content,
      contains('read-only participant tools'),
    );
    expect(toolService.executedToolNames, isEmpty);
    final assistantMessage = chatNotifier.state.messages.last;
    expect(assistantMessage.content, 'Final answer after review denial.');
    expect(assistantMessage.participantToolNames, isEmpty);
    expect(
      dataSource.toolStreamRequests.last.messages.last.content,
      contains('Auto-review denied'),
    );
  });

  test(
    'sendMessage materializes the primary participant for remote-only roster',
    () async {
      final dataSource = _ParticipantStreamingChatDataSource(
        chunkBatches: const [
          ['Primary answer.'],
          ['Reviewer answer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(participantContainer.dispose);
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'reviewer',
            displayName: 'Reviewer',
            roleLabel: 'Critic',
            roleSystemPrompt: 'Critique the proposal.',
            endpointId: 'pc2',
            model: 'review-model',
            colorValue: 0xFF006A6A,
            order: 1,
          ),
        ],
      );

      await chatNotifier.sendMessage('Discuss the proposal');

      final persistedParticipants =
          conversationsNotifier.state.currentConversation!.participants;
      expect(persistedParticipants.map((participant) => participant.id), [
        ParticipantTurnCoordinator.primaryParticipantId,
        'reviewer',
      ]);
      expect(persistedParticipants.first.endpointId, isEmpty);
      expect(persistedParticipants.first.roleLabel, 'Facilitator');
      expect(persistedParticipants.first.facilitatesTurns, isTrue);

      final assistantMessages = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList(growable: false);
      expect(assistantMessages.map((message) => message.participantId), [
        ParticipantTurnCoordinator.primaryParticipantId,
      ]);
      expect(assistantMessages.map((message) => message.content), [
        'Primary answer.',
      ]);
    },
  );

  test('participant turns pause after current speaker and continue', () async {
    final firstTurn = StreamController<String>();
    final dataSource = _ParticipantStreamingChatDataSource(
      manualStreams: [firstTurn],
      chunkBatches: const [
        ['Reviewer round one.'],
        ['Primary round two.'],
        ['Reviewer round two.'],
      ],
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final participantContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(() async {
      participantContainer.dispose();
      if (!firstTurn.isClosed) {
        await firstTurn.close();
      }
    });
    final chatNotifier = participantContainer.read(
      chatNotifierProvider.notifier,
    );
    final conversationsNotifier = participantContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final conversation = conversationsNotifier.ensureCurrentConversation()!;
    await conversationsNotifier.updateConversationParticipants(
      conversation.id,
      participants: const [
        ConversationParticipant(
          id: 'primary',
          displayName: 'Primary',
          roleLabel: 'Coordinator',
          model: 'primary-model',
          order: 0,
        ),
        ConversationParticipant(
          id: 'reviewer',
          displayName: 'Reviewer',
          roleLabel: 'Critic',
          model: 'review-model',
          order: 1,
        ),
      ],
      participantTurnConfig: const ParticipantTurnConfig(
        depth: ParticipantTurnDepth.multiRound,
        maxRounds: 2,
      ),
    );

    final sendFuture = chatNotifier.sendMessage('Discuss twice');
    for (var i = 0; i < 10 && dataSource.streamRequests.isEmpty; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(dataSource.streamRequests, hasLength(1));
    expect(
      chatNotifier.state.participantTurnRuntime?.activeParticipantId,
      'primary',
    );
    expect(chatNotifier.state.participantTurnRuntime?.currentRound, 1);
    expect(chatNotifier.state.participantTurnRuntime?.maxRounds, 2);

    firstTurn.add('Primary round one.');
    await Future<void>.delayed(Duration.zero);
    chatNotifier.requestParticipantTurnStop();
    expect(chatNotifier.state.participantTurnRuntime?.stopRequested, isTrue);
    await firstTurn.close();
    await sendFuture;

    expect(chatNotifier.state.isLoading, isFalse);
    expect(chatNotifier.state.participantTurnRuntime?.paused, isTrue);
    expect(dataSource.streamRequests, hasLength(1));
    expect(
      chatNotifier.state.messages.where(
        (message) => message.role == MessageRole.assistant,
      ),
      hasLength(1),
    );

    await chatNotifier.continueParticipantTurns();

    final assistantContents = chatNotifier.state.messages
        .where((message) => message.role == MessageRole.assistant)
        .map((message) => message.content)
        .toList(growable: false);
    expect(assistantContents, [
      'Primary round one.',
      'Reviewer round one.',
      'Primary round two.',
      'Reviewer round two.',
    ]);
    expect(dataSource.streamRequests, hasLength(4));
    expect(chatNotifier.state.participantTurnRuntime, isNull);
  });

  test(
    'queued user input stops remaining participant turns and starts fresh pass',
    () async {
      final firstTurn = StreamController<String>();
      final dataSource = _ParticipantStreamingChatDataSource(
        manualStreams: [firstTurn],
        chunkBatches: const [
          ['Queued primary.'],
          ['Queued reviewer.'],
        ],
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final participantContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        participantContainer.dispose();
        if (!firstTurn.isClosed) {
          await firstTurn.close();
        }
      });
      final chatNotifier = participantContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = participantContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation()!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'primary',
            displayName: 'Primary',
            roleLabel: 'Coordinator',
            model: 'primary-model',
            order: 0,
          ),
          ConversationParticipant(
            id: 'reviewer',
            displayName: 'Reviewer',
            roleLabel: 'Critic',
            model: 'review-model',
            order: 1,
          ),
        ],
      );

      final sendFuture = chatNotifier.sendMessage('Original topic');
      for (var i = 0; i < 10 && dataSource.streamRequests.isEmpty; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(dataSource.streamRequests, hasLength(1));

      await chatNotifier.sendMessage('Interject with a new constraint');

      expect(chatNotifier.state.queuedMessages, hasLength(1));
      expect(chatNotifier.state.participantTurnRuntime?.stopRequested, isTrue);

      firstTurn.add('Original primary.');
      await firstTurn.close();
      await sendFuture;

      final userContents = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .toList(growable: false);
      final assistantContents = chatNotifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .map((message) => message.content)
          .toList(growable: false);

      expect(userContents, [
        'Original topic',
        'Interject with a new constraint',
      ]);
      expect(assistantContents, [
        'Original primary.',
        'Queued primary.',
        'Queued reviewer.',
      ]);
      expect(dataSource.streamRequests, hasLength(3));
      expect(chatNotifier.state.queuedMessages, isEmpty);
      expect(chatNotifier.state.isLoading, isFalse);
      expect(chatNotifier.state.participantTurnRuntime, isNull);
    },
  );

  test(
    'sendMessage ignores participant turns outside chat workspace',
    () async {
      final codingController = StreamController<String>();
      final project = CodingProject(
        id: 'project-1',
        name: 'Project 1',
        rootPath: '/tmp/project-1',
        createdAt: DateTime(2026, 6, 23, 10),
        updatedAt: DateTime(2026, 6, 23, 10),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final codingContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(
            _StreamingChatDataSource(codingController),
          ),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        codingContainer.dispose();
        if (codingController.hasListener) {
          await codingController.close();
        } else {
          unawaited(codingController.close());
        }
      });
      final codingNotifier = codingContainer.read(
        chatNotifierProvider.notifier,
      );
      final conversationsNotifier = codingContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final conversation = conversationsNotifier.ensureCurrentConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      )!;
      await conversationsNotifier.updateConversationParticipants(
        conversation.id,
        participants: const [
          ConversationParticipant(
            id: 'reviewer',
            displayName: 'Reviewer',
            roleLabel: 'Critic',
            model: 'review-model',
            order: 0,
          ),
        ],
      );

      await codingNotifier.sendMessage(
        'Inspect the code',
        bypassPlanMode: true,
      );

      expect(codingNotifier.state.participantTurnRuntime, isNull);
      expect(codingNotifier.state.messages, hasLength(2));
      expect(codingNotifier.state.messages.last.role, MessageRole.assistant);
      expect(codingNotifier.state.messages.last.participantId, isNull);
      expect(codingNotifier.state.messages.last.isStreaming, isTrue);
    },
  );

  test('sendMessage prepares changed primary model before request', () async {
    final prepController = StreamController<String>();
    final preparedModelIds = <String>[];
    final unloadedModelIds = <String>[];
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final prepContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(prepController),
        ),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        primaryModelPreparationServiceProvider.overrideWithValue(
          PrimaryModelPreparationService(
            listManagedModels: ({bool refresh = false}) async {
              expect(refresh, isTrue);
              return LocalModelLifecycleCatalog.supported(
                models: [
                  for (final modelId in unloadedModelIds)
                    LocalManagedModel(
                      id: modelId,
                      state: LocalModelLifecycleState.unloaded,
                      statusValue: 'unloaded',
                    ),
                  LocalManagedModel(
                    id: 'qwen3.6-35b-a3b-vision',
                    state: LocalModelLifecycleState.unloaded,
                    statusValue: 'unloaded',
                  ),
                ],
              );
            },
            unloadManagedModel: (modelId) async {
              unloadedModelIds.add(modelId);
              return LocalModelLifecycleActionResult.success(
                message: 'Requested unload for "$modelId".',
              );
            },
            loadManagedModel: (modelId) async {
              preparedModelIds.add(modelId);
              return LocalModelLifecycleActionResult.success(
                message: 'Requested load for "$modelId".',
              );
            },
          ),
        ),
      ],
    );
    addTearDown(() async {
      prepContainer.dispose();
      if (!prepController.isClosed) {
        await prepController.close();
      }
    });

    final prepNotifier = prepContainer.read(chatNotifierProvider.notifier);
    prepNotifier.updateConnectionSettings(
      AppSettings.defaults().copyWith(
        model: 'qwen3.6-35b-a3b-vision',
        mcpEnabled: false,
      ),
    );

    await prepNotifier.sendMessage('Use the selected model');

    expect(unloadedModelIds, hasLength(1));
    expect(unloadedModelIds.single, isNot('qwen3.6-35b-a3b-vision'));
    expect(preparedModelIds, ['qwen3.6-35b-a3b-vision']);
    expect(prepNotifier.state.isLoading, isTrue);
  });

  test('flags a final answer truncated at the max-token limit', () async {
    final truncController = StreamController<String>();
    final truncContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(truncController, lastFinishReason: 'length'),
        ),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(() async {
      truncContainer.dispose();
      if (!truncController.isClosed) await truncController.close();
    });

    final truncNotifier = truncContainer.read(chatNotifierProvider.notifier);
    final sendFuture = truncNotifier.sendMessage('Explain quicksort in detail');
    truncController.add('Quicksort picks a pivot and');
    await truncController.close();
    await sendFuture;
    for (var i = 0; i < 10; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      truncNotifier.state.messages.last.content,
      contains(TruncationNotice.maxTokenNotice),
    );
  });

  test('does not flag a normally-completed final answer', () async {
    final sendFuture = notifier.sendMessage('Say hello');
    controller.add('Hello there!');
    await controller.close();
    await sendFuture;
    for (var i = 0; i < 10; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      notifier.state.messages.last.content,
      isNot(contains(TruncationNotice.maxTokenNotice)),
    );
  });

  test(
    'sendMessage notifies when a streaming response completes in the background',
    () async {
      final backgroundController = StreamController<String>();
      final notificationService = _FakeNotificationService();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(true);
      final backgroundContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(
            _StreamingChatDataSource(backgroundController),
          ),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
          notificationServiceProvider.overrideWithValue(notificationService),
        ],
      );
      addTearDown(() async {
        backgroundContainer.dispose();
        if (!backgroundController.isClosed) {
          await backgroundController.close();
        }
      });

      final backgroundNotifier = backgroundContainer.read(
        chatNotifierProvider.notifier,
      );
      final sendFuture = backgroundNotifier.sendMessage('Run a long task');
      backgroundController.add('Done\nThe result is ready.');
      await backgroundController.close();
      await sendFuture;
      for (var i = 0; i < 10 && notificationService.calls.isEmpty; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(notificationService.calls, hasLength(1));
      expect(notificationService.calls.single.title, 'Done');
      expect(notificationService.calls.single.body, 'The result is ready.');
    },
  );

  test(
    'sendMessage uses tool-aware streaming for Apple Foundation Models with tools enabled',
    () async {
      final appleController = StreamController<String>();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolService = _FakeMcpToolService(results: {'diagnose': 'ok'});
      final dataSource = _ToolAwareStreamingChatDataSource(appleController);
      final appleContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _AppleToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        appleContainer.dispose();
        if (!appleController.isClosed) {
          await appleController.close();
        }
      });

      final appleNotifier = appleContainer.read(chatNotifierProvider.notifier);

      final sendFuture = appleNotifier.sendMessage('Run live LLM diagnostics');
      await _waitForCondition(() => dataSource.toolAwareRequestCount == 1);
      appleController.add('diagnostic response');
      await appleController.close();
      await sendFuture;
      await _waitForCondition(() => !appleNotifier.state.isLoading);

      expect(
        appleNotifier.state.messages.last.content,
        contains('diagnostic response'),
      );
      expect(toolService.executedToolNames, isEmpty);
      expect(dataSource.toolAwareRequestCount, 1);
      expect(dataSource.requestedToolNames, contains('diagnose'));
    },
  );

  test(
    'sendMessage falls back when Foundation Models tool bridge exceeds context',
    () async {
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolService = _FakeMcpToolService(
        results: {for (var index = 0; index < 80; index++) 'tool_$index': 'ok'},
      );
      final dataSource = _FoundationModelsContextFallbackDataSource();
      final appleContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _AppleToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(appleContainer.dispose);

      final appleNotifier = appleContainer.read(chatNotifierProvider.notifier);

      await appleNotifier.sendMessage('Hello');
      await _waitForCondition(() => !appleNotifier.state.isLoading);

      expect(dataSource.toolAwareRequestCount, 1);
      expect(dataSource.normalRequestCount, 1);
      expect(toolService.executedToolNames, isEmpty);
      expect(appleNotifier.state.error, isNull);
      expect(appleNotifier.state.messages.last.content, 'fallback response');
    },
  );

  test(
    'suggestCurrentGoal validates LLM clarification against pending request',
    () async {
      const request =
          '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3092';
      const expectedObjective =
          '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3059\u308b';
      const scriptClarification =
          '\u5929\u6c17\u60c5\u5831\u3092\u53d6\u5f97\u3057\u3066Markdown\u30d5\u30a1\u30a4\u30eb\u306b\u4fdd\u5b58\u3059\u308b\u30b9\u30af\u30ea\u30d7\u30c8\u3092\u4f5c\u6210\u3059\u308b\u306e\u3067\u3057\u3087\u3046\u304b\uff1f';
      final dataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content: jsonEncode({
            'status': 'needs_clarification',
            'objective': '',
            'question': scriptClarification,
          }),
          finishReason: 'stop',
        ),
      ]);
      final now = DateTime(2026, 6, 1, 10);
      final conversation = Conversation(
        id: 'coding-goal-thread',
        title: 'Coding goal',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final goalContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final goalNotifier = goalContainer.read(chatNotifierProvider.notifier);

        final suggestion = await goalNotifier.suggestCurrentGoal(
          languageCode: 'ja',
          pendingUserMessage: request,
        );

        expect(suggestion.kind, ConversationGoalSuggestionKind.suggested);
        expect(suggestion.objective, expectedObjective);
        expect(
          suggestion.objective,
          isNot(contains('\u30b9\u30af\u30ea\u30d7\u30c8')),
        );
        expect(dataSource.requests, hasLength(1));
        expect(dataSource.requests.single.last.content, contains(request));
      } finally {
        goalContainer.dispose();
      }
    },
  );

  test(
    'requestAskUserQuestion exposes pending question and resolves answer',
    () async {
      final future = notifier.requestAskUserQuestion(
        question: 'Which path should we take?',
        help: 'Choose the implementation direction.',
        options: const [
          AskUserQuestionOption(
            id: 'small',
            label: 'Small change',
            description: 'Keep the change narrow.',
            preview: 'One file',
          ),
        ],
        allowMultiple: false,
        allowOther: true,
        otherPlaceholder: 'Describe another direction',
      );

      final pending = notifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      expect(pending!.question, 'Which path should we take?');
      expect(pending.options.single.preview, 'One file');

      final answer = AskUserQuestionAnswer(
        question: pending.question,
        selectedOptions: const [
          AskUserQuestionSelection(
            id: 'small',
            label: 'Small change',
            description: 'Keep the change narrow.',
            preview: 'One file',
          ),
        ],
      );
      notifier.resolveAskUserQuestion(id: pending.id, answer: answer);

      expect(await future, answer);
      expect(notifier.state.pendingAskUserQuestion, isNull);
    },
  );

  test('requestAskUserQuestion ignores a second pending question', () async {
    final firstFuture = notifier.requestAskUserQuestion(
      question: 'Which path should we take?',
      help: 'Choose the implementation direction.',
      options: const [
        AskUserQuestionOption(id: 'small', label: 'Small change'),
      ],
      allowMultiple: false,
      allowOther: true,
      otherPlaceholder: 'Describe another direction',
    );
    final firstPending = notifier.state.pendingAskUserQuestion;
    expect(firstPending, isNotNull);

    final secondFuture = notifier.requestAskUserQuestion(
      question: 'Which refactor should we do?',
      help: 'Choose a refactor direction.',
      options: const [
        AskUserQuestionOption(id: 'large', label: 'Large refactor'),
      ],
      allowMultiple: false,
      allowOther: true,
      otherPlaceholder: 'Describe another direction',
    );

    expect(await secondFuture, isNull);
    expect(notifier.state.pendingAskUserQuestion!.id, firstPending!.id);
    expect(
      notifier.state.pendingAskUserQuestion!.question,
      'Which path should we take?',
    );

    final answer = AskUserQuestionAnswer(
      question: firstPending.question,
      selectedOptions: const [
        AskUserQuestionSelection(id: 'small', label: 'Small change'),
      ],
    );
    notifier.resolveAskUserQuestion(id: firstPending.id, answer: answer);

    expect(await firstFuture, answer);
    expect(notifier.state.pendingAskUserQuestion, isNull);
  });

  test(
    'read-only project tools default to current directory when path is omitted',
    () {
      expect(
        notifier.resolveProjectScopedArgumentsForTest('list_directory', {
          'recursive': true,
        }),
        containsPair('path', '.'),
      );
      expect(
        notifier.resolveProjectScopedArgumentsForTest('find_files', {
          'pattern': '*.dart',
        }),
        containsPair('path', '.'),
      );
      expect(
        notifier.resolveProjectScopedArgumentsForTest('search_files', {
          'query': 'SettingsScreen',
        }),
        containsPair('path', '.'),
      );
    },
  );

  test(
    'sendMessage recovers when a named skill is promised but not loaded',
    () async {
      final dataSource = _SkippedSkillLoadChatDataSource(
        initialContent:
            'I will load the Release Check skill before verifying readiness.',
        finalAnswerChunks: const [
          'SKILL_LIVE_OK\n1. Run verification.\n2. Draft release notes.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          skillsNotifierProvider.overrideWith(_ReleaseCheckSkillsNotifier.new),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(toolService.executedToolArguments.single['id'], 'release-check');
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.toolResultBatches.single.single.name, 'load_skill');
      expect(dataSource.finalAnswerRequests, hasLength(1));
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
    },
  );

  test(
    'sendMessage recovers when a Japanese skill load is promised but not loaded',
    () async {
      final dataSource = _SkippedSkillLoadChatDataSource(
        initialContent: 'ユーザーがリリースチェックを依頼したので、Release Checkスキルをロードして手順を確認します。',
        finalAnswerChunks: const [
          'SKILL_LIVE_OK\n1. Run verification.\n2. Draft release notes.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          skillsNotifierProvider.overrideWith(_ReleaseCheckSkillsNotifier.new),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(toolService.executedToolArguments.single['id'], 'release-check');
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.toolResultBatches.single.single.name, 'load_skill');
      expect(dataSource.finalAnswerRequests, hasLength(1));
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
    },
  );

  test(
    'sendMessage recovers when a browser action is promised without a tool',
    () async {
      const skippedBrowserClaim = 'Wikipedia has been opened.';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: skippedBrowserClaim,
        initialStreamChunks: const [skippedBrowserClaim],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-click-wikipedia',
            name: 'browser_click',
            arguments: const {
              'ref': 7,
              'reason': 'Open the Wikipedia search result.',
            },
          ),
        ],
        toolRoleResponseContent: '',
        finalAnswerChunks: const [
          'Opened Wikipedia from browser tool results.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_snapshot': 'Capture browser elements.',
          'browser_click': 'Click a browser element.',
        },
        results: {
          'browser_snapshot': jsonEncode({
            'ok': true,
            'url': 'https://www.google.com/search?q=hydrangea',
            'elements': [
              {'ref': 7, 'role': 'link', 'label': 'Hydrangea - Wikipedia'},
            ],
          }),
          'browser_click': jsonEncode({
            'ok': true,
            'url': 'https://en.wikipedia.org/wiki/Hydrangea',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final request =
          'Wikipedia${String.fromCharCodes(const [0x3092, 0x30af, 0x30ea, 0x30c3, 0x30af])}';
      final sendFuture = chatNotifier.sendMessage(request);
      await _waitForCondition(
        () => chatNotifier.state.pendingBrowserAction != null,
      );
      final pendingBrowserAction = chatNotifier.state.pendingBrowserAction!;
      expect(pendingBrowserAction.toolName, 'browser_click');

      chatNotifier.resolveBrowserAction(
        id: pendingBrowserAction.id,
        approved: true,
      );
      await sendFuture;

      expect(toolService.executedToolNames, [
        'browser_snapshot',
        'browser_click',
      ]);
      expect(toolService.executedToolArguments.first, {'max_elements': 80});
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.first.single.name,
        'browser_snapshot',
      );
      expect(dataSource.toolResultBatches.last.single.name, 'browser_click');
      expect(
        dataSource.followUpToolDefinitionBatches.first
            .map((definition) => (definition['function'] as Map)['name'])
            .toList(),
        contains('browser_click'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(skippedBrowserClaim)),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains('Opened Wikipedia from browser tool results.'),
      );
    },
  );

  test(
    'sendMessage reports unexecuted browser action after failed recovery',
    () async {
      const skippedBrowserClaim = 'Wikipedia のリンク（ref 11）をクリックしました。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: skippedBrowserClaim,
        initialStreamChunks: const [skippedBrowserClaim],
        toolRoleResponseContent: skippedBrowserClaim,
        finalAnswerChunks: const [
          'browser_click was not executed after refreshing the page snapshot.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_snapshot': 'Capture browser elements.',
          'browser_click': 'Click a browser element.',
        },
        results: {
          'browser_snapshot': jsonEncode({
            'ok': true,
            'url': 'https://www.google.com/search?q=hydrangea',
            'elements': [
              {'ref': 11, 'role': 'link', 'label': 'Hydrangea - Wikipedia'},
            ],
          }),
          'browser_click': jsonEncode({
            'ok': true,
            'url': 'https://en.wikipedia.org/wiki/Hydrangea',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);

      await chatNotifier.sendMessage('Click the Wikipedia result');

      expect(toolService.executedToolNames, ['browser_snapshot']);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.first.single.name,
        'browser_snapshot',
      );
      expect(dataSource.toolResultBatches.last.single.name, 'browser_snapshot');
      final finalPrompt = dataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('browser_click'));
      expect(finalPrompt, contains('unexecuted_browser_action'));
      expect(
        chatNotifier.state.messages.last.content,
        contains('browser_click was not executed'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(skippedBrowserClaim)),
      );
    },
  );

  test(
    'sendMessage marks CJK future file creation without tool call as unexecuted',
    () async {
      const finalContent = '1.3.3+14 から 1.3.4+15 への変更点を調べてリリースノートを作成します。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'write_file': 'Write a file to the selected project.',
        },
        results: const {'write_file': '{"ok":true}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('はい');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'I could not execute the additional tool request above in this final-answer step.',
        ),
      );
    },
  );

  test(
    'sendMessage marks CJK UI edit claims without tool call as unexecuted',
    () async {
      final editAction = String.fromCharCodes(const [
        0x7de8,
        0x96c6,
        0x3092,
        0x884c,
        0x3044,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final section = String.fromCharCodes(const [
        0x30bb,
        0x30af,
        0x30b7,
        0x30e7,
        0x30f3,
      ]);
      final mobileHiddenFuture = String.fromCharCodes(const [
        0x3092,
        0x30e2,
        0x30d0,
        0x30a4,
        0x30eb,
        0x975e,
        0x8868,
        0x793a,
        0x306b,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final wrappingComplete = String.fromCharCodes(const [
        0x30e9,
        0x30c3,
        0x30d4,
        0x30f3,
        0x30b0,
        0x5b8c,
        0x4e86,
        0x3002,
      ]);
      final next = String.fromCharCodes(const [0x6b21, 0x306b]);
      final alsoHiddenCompleted = String.fromCharCodes(const [
        0x3082,
        0x30e2,
        0x30d0,
        0x30a4,
        0x30eb,
        0x975e,
        0x8868,
        0x793a,
        0x306b,
        0x3057,
        0x307e,
        0x3057,
        0x305f,
        0x3002,
      ]);
      final confirmChanges = String.fromCharCodes(const [
        0x5909,
        0x66f4,
        0x3092,
        0x78ba,
        0x8a8d,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final finalContent =
          '$editAction\n\n'
          'Hand Settings $section$mobileHiddenFuture\n\n'
          '$wrappingComplete$next App Close Behavior $alsoHiddenCompleted\n\n'
          '$confirmChanges';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'edit_file': 'Edit a file in the selected project.',
          'write_file': 'Write a file to the selected project.',
        },
        results: const {'edit_file': '{"ok":true}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Update the mobile settings UI.');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'I could not execute the additional tool request above in this final-answer step.',
        ),
      );
    },
  );

  test(
    'sendMessage marks future command execution without tool call as unexecuted',
    () async {
      const finalContent =
          'I will run the dry-run release script now using a local command.';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': '{"exit_code":0}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('yes');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
        ),
      );
    },
  );

  test(
    'sendMessage marks future command execution after earlier command success as unexecuted',
    () async {
      const inspectionCommand = 'pwd';
      const finalContent =
          'The workspace inspection command succeeded. I will run the dry-run release script now using a local command.';
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'inspect-workspace',
            name: 'local_execute_command',
            arguments: const {
              'command': inspectionCommand,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': 'unexpected fallback'},
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': inspectionCommand,
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': '/tmp/project',
              'stderr': '',
            }),
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('continue');

      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
        ),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(finalContent)),
      );
    },
  );

  test(
    'sendMessage accepts completed command final answer after successful command result',
    () async {
      const finalContent =
          'The local command `python3 prime_numbers.py` completed successfully. '
          'The script output confirmed 168 prime numbers and all checks passed.';
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'run-prime-script',
            name: 'local_execute_command',
            arguments: const {
              'command': 'python3 prime_numbers.py',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': 'unexpected fallback'},
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'python3 prime_numbers.py',
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': '168 primes\nchecks passed\n',
              'stderr': '',
            }),
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Run and verify the prime script');

      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(chatNotifier.state.messages.last.content, contains(finalContent));
      expect(
        chatNotifier.state.messages.last.content,
        isNot(
          contains(
            'I could not execute the additional tool request above in this final-answer step.',
          ),
        ),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(
          contains(
            'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
          ),
        ),
      );
    },
  );

  test(
    'sendMessage gates prose-only coding continuation before memory update',
    () async {
      const incompleteFinalAnswer =
          'Next I will inspect the Dart entrypoint before porting the script.';
      const recoveredFinalAnswer =
          'Dart porting can continue after the entrypoint inspection.';
      final conversationRepository = _FakeConversationRepository();
      final memoryService = _TrackingSessionMemoryService();
      final recoveryResponseGate = Completer<void>();
      addTearDown(() {
        if (!recoveryResponseGate.isCompleted) {
          recoveryResponseGate.complete();
        }
      });
      final project = CodingProject(
        id: 'project-finalization-gate',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 18),
        updatedAt: DateTime(2026, 6, 18),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'inspect-workspace',
            name: 'local_execute_command',
            arguments: const {
              'command': 'pwd',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Workspace command completed.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Recovering by inspecting the Dart entrypoint.',
            toolCalls: [
              ToolCallInfo(
                id: 'read-entrypoint-after-finalization-gate',
                name: 'read_file',
                arguments: const {
                  'path': '/tmp/project/prime_numbers/bin/prime_numbers.dart',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Dart entrypoint was inspected.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunkBatches: const [
          [incompleteFinalAnswer],
          [recoveredFinalAnswer],
        ],
        toolLoopResponseGates: {2: recoveryResponseGate.future},
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local command.',
          'read_file': 'Read a local file.',
        },
        results: const {
          'local_execute_command': 'unexpected fallback',
          'read_file': 'unexpected fallback',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'pwd',
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': '/tmp/project\n',
              'stderr': '',
            }),
          ],
          'read_file': [
            '{"path":"/tmp/project/prime_numbers/bin/prime_numbers.dart","content":"void main() {}"}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(memoryService),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(toolContainer.dispose);

      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage(
        'Port the script to Dart',
        bypassPlanMode: true,
      );
      await _waitForCondition(() => dataSource.toolResultBatches.length >= 2);

      expect(chatNotifier.state.isLoading, isTrue);
      expect(chatNotifier.state.messages.last.isStreaming, isTrue);
      expect(
        chatNotifier.state.messages.last.content,
        contains(incompleteFinalAnswer),
      );

      recoveryResponseGate.complete();
      await sendFuture;
      await memoryService.firstUpdate.future.timeout(
        const Duration(seconds: 1),
      );

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'read_file',
      ]);
      expect(dataSource.finalAnswerTemperatures, hasLength(2));
      expect(dataSource.toolResultBatches, hasLength(3));
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('prose_only_coding_continuation'),
      );
      expect(memoryService.updateCount, 1);
      final savedAssistantContent = memoryService.updateMessages.single
          .where((message) => message.role == MessageRole.assistant)
          .last
          .content;
      expect(savedAssistantContent, contains(recoveredFinalAnswer));
      expect(savedAssistantContent, isNot(contains(incompleteFinalAnswer)));
      expect(
        chatNotifier.state.messages.last.content,
        contains(recoveredFinalAnswer),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(incompleteFinalAnswer)),
      );
    },
  );

  test(
    'sendMessage ignores pre-final tool prose when final answer is complete',
    () async {
      final initialToolProse = String.fromCharCodes(const [
        0x7d20,
        0x6570,
        0x3092,
        0x8a08,
        0x7b97,
        0x3059,
        0x308b,
        0x0050,
        0x0079,
        0x0074,
        0x0068,
        0x006f,
        0x006e,
        0x30b9,
        0x30af,
        0x30ea,
        0x30d7,
        0x30c8,
        0x3092,
        0x4f5c,
        0x6210,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final followUpToolProse = String.fromCharCodes(const [
        0x4f5c,
        0x6210,
        0x3057,
        0x307e,
        0x3057,
        0x305f,
        0x3002,
        0x5b9f,
        0x884c,
        0x3057,
        0x3066,
        0x78ba,
        0x8a8d,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final finalAnswer = String.fromCharCodes(const [
        0x7d20,
        0x6570,
        0x3092,
        0x8a08,
        0x7b97,
        0x3059,
        0x308b,
        0x0050,
        0x0079,
        0x0074,
        0x0068,
        0x006f,
        0x006e,
        0x30b9,
        0x30af,
        0x30ea,
        0x30d7,
        0x30c8,
        0x0020,
        0x0060,
        0x0070,
        0x0072,
        0x0069,
        0x006d,
        0x0065,
        0x005f,
        0x006e,
        0x0075,
        0x006d,
        0x0062,
        0x0065,
        0x0072,
        0x0073,
        0x002e,
        0x0070,
        0x0079,
        0x0060,
        0x0020,
        0x3092,
        0x4f5c,
        0x6210,
        0x3057,
        0x3001,
        0x5b9f,
        0x884c,
        0x3057,
        0x3066,
        0x6b63,
        0x5e38,
        0x306b,
        0x52d5,
        0x4f5c,
        0x3059,
        0x308b,
        0x3053,
        0x3068,
        0x3092,
        0x78ba,
        0x8a8d,
        0x3057,
        0x307e,
        0x3057,
        0x305f,
        0x3002,
      ]);
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-final-answer-complete-after-tool-prose',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 18),
        updatedAt: DateTime(2026, 6, 18),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'write-prime-script',
            name: 'write_file',
            arguments: const {
              'path': '/tmp/project/prime_numbers.py',
              'content': 'print([2, 3, 5, 7])\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: followUpToolProse,
            toolCalls: [
              ToolCallInfo(
                id: 'run-prime-script',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 prime_numbers.py',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: [finalAnswer],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'write_file': 'Write a file.',
          'local_execute_command': 'Execute a local command.',
        },
        results: const {
          'write_file': 'unexpected fallback',
          'local_execute_command': 'unexpected fallback',
        },
        queuedResults: {
          'write_file': [
            '{"path":"/tmp/project/prime_numbers.py","created":true}',
          ],
          'local_execute_command': [
            jsonEncode({
              'command': 'python3 prime_numbers.py',
              'working_directory': '/tmp/project',
              'exit_code': 0,
              'stdout': '[2, 3, 5, 7]\n',
              'stderr': '',
            }),
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(toolContainer.dispose);

      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = toolContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(initialToolProse, bypassPlanMode: true);

      expect(toolService.executedToolNames, [
        'write_file',
        'local_execute_command',
      ]);
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        isNot(contains('coding_continuation_recovery')),
      );
      expect(chatNotifier.state.messages.last.content, contains(finalAnswer));
    },
  );

  test(
    'sendMessage recovers bracketed coding tool request before memory update',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_bracketed_edit_recovery_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final sourceFile = File('${projectRoot.path}/lib/src/ping_command.dart')
        ..createSync(recursive: true);
      sourceFile.writeAsStringSync('return command;\n');
      final bracketedFinalAnswer =
          'I need to apply the pending parser fix.\n\n'
          '[Tool: edit_file]\n'
          'Arguments: ${jsonEncode({'path': sourceFile.path, 'old_text': 'return command;', 'new_text': 'return commandWithIpv6;'})}';
      const recoveredFinalAnswer =
          'The ping command now includes the IPv6 flag.';
      final conversationRepository = _FakeConversationRepository();
      final memoryService = _TrackingSessionMemoryService();
      final project = CodingProject(
        id: 'project-bracketed-finalization-gate',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 6, 18),
        updatedAt: DateTime(2026, 6, 18),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'inspect-workspace-for-bracketed-gate',
            name: 'local_execute_command',
            arguments: {
              'command': 'pwd',
              'working_directory': projectRoot.path,
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Workspace command completed.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Recovering by applying the pending parser fix.',
            toolCalls: [
              ToolCallInfo(
                id: 'edit-ping-command-after-finalization-gate',
                name: 'edit_file',
                arguments: {
                  'path': sourceFile.path,
                  'old_text': 'return command;',
                  'new_text': 'return commandWithIpv6;',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Parser fix was applied.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunkBatches: [
          [bracketedFinalAnswer],
          [recoveredFinalAnswer],
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local command.',
          'edit_file': 'Edit a file.',
        },
        results: const {
          'local_execute_command': 'unexpected fallback',
          'edit_file': 'unexpected fallback',
        },
        queuedResults: {
          'local_execute_command': [
            jsonEncode({
              'command': 'pwd',
              'working_directory': projectRoot.path,
              'exit_code': 0,
              'stdout': '${projectRoot.path}\n',
              'stderr': '',
            }),
          ],
          'edit_file': [
            jsonEncode({'path': sourceFile.path, 'replacements': 1}),
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(memoryService),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(toolContainer.dispose);

      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final chatNotifier = toolContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Fix the ping command parser',
        bypassPlanMode: true,
      );
      await memoryService.firstUpdate.future.timeout(
        const Duration(seconds: 1),
      );

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'edit_file',
      ]);
      expect(
        toolService.executedToolArguments.last,
        containsPair('path', sourceFile.path),
      );
      expect(dataSource.finalAnswerTemperatures, hasLength(2));
      expect(dataSource.toolResultBatches, hasLength(3));
      expect(
        dataSource.toolResultBatches[1].single.result,
        contains('bracketed_coding_tool_request'),
      );
      expect(memoryService.updateCount, 1);
      final savedAssistantContent = memoryService.updateMessages.single
          .where((message) => message.role == MessageRole.assistant)
          .last
          .content;
      expect(savedAssistantContent, contains(recoveredFinalAnswer));
      expect(savedAssistantContent, isNot(contains('[Tool: edit_file]')));
      expect(
        savedAssistantContent,
        isNot(
          contains(
            'I could not execute the additional tool request above in this final-answer step.',
          ),
        ),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains(recoveredFinalAnswer),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('[Tool: edit_file]')),
      );
    },
  );

  test(
    'sendMessage marks Japanese static analysis without tool call as unexecuted',
    () async {
      const finalContent = '静的解析を実行します。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': '{"exit_code":0}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('continue');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
        ),
      );
    },
  );

  test(
    'sendMessage marks Japanese release execution claim without tool call as unexecuted',
    () async {
      const finalContent = '本番リリースを開始しました。まず macOS 側が進行中です。進捗を確認します。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: finalContent,
        initialStreamChunks: const [finalContent],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Execute a local shell command.',
        },
        results: const {'local_execute_command': '{"exit_code":0}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('yes');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains(
          'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action.',
        ),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('開始しました')),
      );
      expect(chatNotifier.state.messages.last.content, isNot(contains('進行中')));
    },
  );

  test(
    'sendMessage shows resolved browser save target before approval',
    () async {
      final saveDirectory = Directory.systemTemp.createTempSync(
        'browser_save_approval_',
      );
      addTearDown(() => saveDirectory.deleteSync(recursive: true));
      final savedPath =
          '${saveDirectory.path}${Platform.pathSeparator}アジサイ_概要.md';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-save-data',
            name: 'browser_save_data',
            arguments: const {
              'filename': 'アジサイ_概要.md',
              'data': '# Hydrangea',
              'format': 'md',
              'reason': 'Save extracted page data.',
            },
          ),
        ],
        toolRoleResponseContent:
            'Saved to $savedPath.\n\nIf you want another format, let me know.',
        finalAnswerChunks: const ['WRONG_FINAL_アジサイ_概要.md'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_save_data': 'Save browser data to a file.',
        },
        results: {
          'browser_save_data': jsonEncode({
            'ok': true,
            'path': savedPath,
            'directory': saveDirectory.path,
            'filename': 'アジサイ_概要.md',
            'requestedFilename': 'アジサイ_概要.md',
            'filenameChanged': false,
            'bytes': 11,
            'format': 'md',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final browserSessionService = BrowserSessionService(
        saveDirectoryOverride: saveDirectory,
      );
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          browserSessionServiceProvider.overrideWithValue(
            browserSessionService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage(
        'Save the overview as Markdown.',
      );
      await _waitForCondition(
        () => chatNotifier.state.pendingBrowserAction != null,
      );
      final pendingBrowserAction = chatNotifier.state.pendingBrowserAction!;
      expect(pendingBrowserAction.toolName, 'browser_save_data');
      expect(
        pendingBrowserAction.details,
        contains('Destination: Caverno application storage'),
      );
      expect(pendingBrowserAction.details, contains('Final file: アジサイ_概要.md'));
      expect(
        pendingBrowserAction.details,
        contains('Save location: ${saveDirectory.path}'),
      );
      expect(pendingBrowserAction.details, contains('Full path: $savedPath'));

      chatNotifier.resolveBrowserAction(
        id: pendingBrowserAction.id,
        approved: true,
      );
      await sendFuture;

      expect(dataSource.finalAnswerRequestMessages, isEmpty);
      expect(chatNotifier.state.messages.last.content, contains(savedPath));
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('WRONG_FINAL_アジサイ_概要.md')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('let me know')),
      );
    },
  );

  test(
    'full chat approval access runs sensitive browser actions without prompting',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-click',
            name: 'browser_click',
            arguments: const {
              'ref': 7,
              'reason': 'Open the Wikipedia search result.',
            },
          ),
        ],
        toolRoleResponseContent: 'Clicked the link.',
        finalAnswerChunks: const ['Opened the Wikipedia article.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'browser_click': 'Click a browser element.'},
        results: {
          'browser_click': jsonEncode({
            'ok': true,
            'url': 'https://en.wikipedia.org/wiki/Hydrangea',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatFullAccessSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      // No approval is resolved: full access must let the action run on its own.
      await chatNotifier.sendMessage('Open the Wikipedia article');

      expect(chatNotifier.state.pendingBrowserAction, isNull);
      expect(toolService.executedToolNames, ['browser_click']);
      expect(dataSource.autoReviewRequestMessages, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Opened the Wikipedia article.'),
      );
    },
  );

  test(
    'auto-review chat approval consults the reviewer before a browser action',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-click',
            name: 'browser_click',
            arguments: const {
              'ref': 7,
              'reason': 'Open the Wikipedia search result.',
            },
          ),
        ],
        toolRoleResponseContent: 'Clicked the link.',
        finalAnswerChunks: const ['Opened the Wikipedia article.'],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"User asked to open the link."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'browser_click': 'Click a browser element.'},
        results: {
          'browser_click': jsonEncode({'ok': true}),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatAutoReviewSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Open the Wikipedia article');

      // The reviewer is consulted and, on "allow", the action runs without a
      // manual approval prompt.
      expect(chatNotifier.state.pendingBrowserAction, isNull);
      expect(dataSource.autoReviewRequestMessages, hasLength(1));
      expect(
        dataSource.autoReviewRequestMessages.first.first.content,
        contains('built-in browser'),
      );
      expect(toolService.executedToolNames, ['browser_click']);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Opened the Wikipedia article.'),
      );
    },
  );

  test(
    'full chat approval auto-connects SSH when a password is saved',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-ssh',
            name: 'ssh_connect',
            arguments: const {
              'host': 'example.com',
              'port': 22,
              'username': 'me',
            },
          ),
        ],
        toolRoleResponseContent: 'Connected.',
        finalAnswerChunks: const ['SSH session is ready.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'ssh_connect': 'Open an SSH session.'},
        results: const {'ssh_connect': '{"ok":true}'},
      );
      final sshService = _MockSshService();
      when(
        () => sshService.connect(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {});
      final creds = _MockSshCredentialsManager();
      when(
        () => creds.loadPassword(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
        ),
      ).thenAnswer((_) async => 'secret');
      when(
        () => creds.savePassword(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {});
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatFullAccessSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
          sshServiceProvider.overrideWithValue(sshService),
          sshCredentialsManagerProvider.overrideWithValue(creds),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Connect to my server');

      // Full access + a stored credential connects without raising the dialog.
      expect(chatNotifier.state.pendingSshConnect, isNull);
      verify(
        () => sshService.connect(
          host: 'example.com',
          port: 22,
          username: 'me',
          password: 'secret',
        ),
      ).called(1);
      expect(dataSource.autoReviewRequestMessages, isEmpty);
    },
  );

  test(
    'full chat approval falls back to the SSH dialog without a saved password',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-ssh',
            name: 'ssh_connect',
            arguments: const {
              'host': 'example.com',
              'port': 22,
              'username': 'me',
            },
          ),
        ],
        toolRoleResponseContent: 'Cancelled.',
        finalAnswerChunks: const ['No session was opened.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'ssh_connect': 'Open an SSH session.'},
        results: const {'ssh_connect': '{"ok":true}'},
      );
      final sshService = _MockSshService();
      final creds = _MockSshCredentialsManager();
      when(
        () => creds.loadPassword(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
        ),
      ).thenAnswer((_) async => null);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatFullAccessSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
          sshServiceProvider.overrideWithValue(sshService),
          sshCredentialsManagerProvider.overrideWithValue(creds),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage('Connect to my server');

      // No stored credential: full access still needs the interactive dialog.
      await _waitForCondition(
        () => chatNotifier.state.pendingSshConnect != null,
      );
      expect(chatNotifier.state.pendingSshConnect!.host, 'example.com');

      // Cancel so sendMessage can finish.
      chatNotifier.resolveSshConnect(
        id: chatNotifier.state.pendingSshConnect!.id,
        approval: null,
      );
      await sendFuture;

      verifyNever(
        () => sshService.connect(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),
      );
    },
  );

  test('auto-review verdicts are written to the approval audit log', () async {
    final auditDir = Directory.systemTemp.createTempSync('chat_audit_');
    addTearDown(() => auditDir.deleteSync(recursive: true));
    final auditLog = ToolApprovalAuditLog(
      rootDirectoryProvider: () async => auditDir,
    );

    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-click',
          name: 'browser_click',
          arguments: const {'ref': 7, 'reason': 'Open the link.'},
        ),
      ],
      toolRoleResponseContent: 'Reviewed.',
      finalAnswerChunks: const ['Stopped before clicking.'],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"deny","riskLevel":"high","userAuthorization":"low","rationale":"Looks like a credential submit."}',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {'browser_click': 'Click a browser element.'},
      results: const {'browser_click': '{"ok":true}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledChatAutoReviewSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        toolApprovalAuditLogProvider.overrideWithValue(auditLog),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Open the link');

    final auditFiles = Directory(
      '${auditDir.path}/approval_audit',
    ).listSync().whereType<File>().toList();
    expect(auditFiles, isNotEmpty);
    final entries = auditFiles
        .expand((file) => file.readAsLinesSync())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final clickEntry = entries.firstWhere((e) => e['tool'] == 'browser_click');
    expect(clickEntry['outcome'], 'denied');
    expect(clickEntry['decisionSource'], 'auto_review');
    expect(clickEntry['mode'], 'autoReview');
    expect(clickEntry['domain'], 'browser');
    expect(clickEntry['rationale'], contains('credential'));
  });

  test(
    'sendMessage marks browser save claims unexecuted without save tool result',
    () async {
      const unsupportedSaveClaim = 'Saved as azusa_overview.md.';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-get-content',
            name: 'browser_get_content',
            arguments: const {'format': 'html', 'max_chars': 50000},
          ),
        ],
        toolRoleResponseContent: unsupportedSaveClaim,
        finalAnswerChunks: const [unsupportedSaveClaim],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_get_content': 'Extract browser page content.',
          'browser_save_data': 'Save browser data to a file.',
        },
        results: {
          'browser_get_content': jsonEncode({
            'ok': true,
            'url': 'https://example.com/article',
            'content': 'Overview content',
          }),
          'browser_save_data': jsonEncode({
            'ok': true,
            'path': '/tmp/azusa_overview.md',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final saveMarker = String.fromCharCodes(const [0x4fdd, 0x5b58]);
      await chatNotifier.sendMessage(
        'Extract the overview and $saveMarker it as Markdown.',
      );

      expect(toolService.executedToolNames, ['browser_get_content']);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.finalAnswerMessages, isNotEmpty);
      final finalPrompt = dataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('unexecuted_file_save'));
      expect(finalPrompt, contains('browser_save_data'));
      expect(
        dataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n'),
        contains('unexecuted_file_save'),
      );
    },
  );

  test(
    'sendMessage marks release completion claims unexecuted without command tool result',
    () async {
      final buildSuccess = String.fromCharCodes(const [
        0x30d3,
        0x30eb,
        0x30c9,
        0x6210,
        0x529f,
      ]);
      final uploadSuccess = String.fromCharCodes(const [
        0x30a2,
        0x30c3,
        0x30d7,
        0x30ed,
        0x30fc,
        0x30c9,
        0x6210,
        0x529f,
      ]);
      final releaseComplete = String.fromCharCodes(const [
        0x30ea,
        0x30ea,
        0x30fc,
        0x30b9,
        0x5b8c,
        0x4e86,
      ]);
      final unsupportedReleaseClaim =
          'iOS IPA $buildSuccess\n'
          'App Store Connect $uploadSuccess\n'
          'iOS $releaseComplete';
      final dataSource = _NoToolStreamingWithToolsDataSource(
        streamChunks: [unsupportedReleaseClaim],
        completionContent: unsupportedReleaseClaim,
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'local_execute_command': 'Run a local shell command.',
          'process_start': 'Start a background process.',
          'process_wait': 'Wait for a background process.',
        },
        results: const {'local_execute_command': '{}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Retry the iOS release upload');

      expect(toolService.executedToolNames, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('iOS IPA')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains('The requested command was not executed'),
      );
    },
  );

  test('sendMessage splits tool-loop and final prose temperatures', () async {
    final dataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-read-pubspec',
          name: 'read_file',
          arguments: const {'path': 'pubspec.yaml'},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ],
      finalAnswerChunks: const ['Read completed.'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {'read_file': 'Read a file from the project.'},
      results: const {'read_file': '{"content":"name: caverno"}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledHighTemperatureSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Read pubspec.yaml');

    expect(dataSource.initialToolTemperature, 0.2);
    expect(dataSource.toolLoopTemperatures, [0.2]);
    expect(dataSource.finalAnswerTemperatures, [1.7]);
    expect(
      chatNotifier.state.messages.last.content,
      contains('Read completed.'),
    );
  });

  test(
    'sendMessage blocks command after unexecuted version file mutation claim',
    () async {
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read-pubspec',
            name: 'read_file',
            arguments: const {'path': 'pubspec.yaml'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The current version is 1.3.5+17. I will increment pubspec.yaml to build 18, then run the release build.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-build-ios',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'fvm flutter build ios --release --no-codesign',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The version file still needs to be edited first.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'read_file': 'Read a file from the project.',
          'edit_file': 'Edit a file in the project.',
          'write_file': 'Write a file in the project.',
          'local_execute_command': 'Run a local shell command.',
        },
        results: const {
          'read_file': '{"path":"pubspec.yaml","content":"version: 1.3.5+17"}',
          'local_execute_command': 'unexpected command execution',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Release iOS after bumping the build number',
      );

      expect(toolService.executedToolNames, ['read_file']);
      expect(dataSource.toolResultBatches, hasLength(2));
      final blockedPayload =
          jsonDecode(dataSource.toolResultBatches.last.single.result)
              as Map<String, dynamic>;
      expect(blockedPayload, containsPair('code', 'unexecuted_file_save'));
      expect(
        blockedPayload['blocked_tool']?.toString(),
        'local_execute_command',
      );
      expect(
        dataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n'),
        contains('unexecuted_file_save'),
      );
    },
  );

  test('sendMessage does not mark loaded skill steps as unexecuted', () async {
    const preamble =
        'I will verify release readiness with the saved skill before answering.\n\n';
    const finalAnswer =
        'SKILL_LIVE_OK\n\n'
        '## リリース readiness チェック - 2つの検証ステップ\n\n'
        '1. **ビルド・テストの健全性確認**\n'
        '2. **リリース設定とバージョンの整合性確認**\n\n'
        '---\n\n'
        '実際にプロジェクトに対してこれらを実行して検証しますか？'
        '（例：`flutter analyze`・テスト実行・バージョン確認を自動で走らせる）';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-load-skill',
          name: 'load_skill',
          arguments: const {'id': 'release-check'},
        ),
      ],
      initialCompletionContent: preamble,
      initialStreamChunks: const [preamble],
      toolRoleResponseContent: finalAnswer,
      finalAnswerChunks: const ['FALLBACK_FINAL_SHOULD_NOT_STREAM'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'load_skill': 'Load the full markdown instructions for a skill.',
      },
      results: {
        'load_skill': jsonEncode({
          'id': 'release-check',
          'name': 'Release Check',
          'content':
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage(
      'Use the Release Check skill if relevant. Verify release readiness.',
    );

    expect(toolService.executedToolNames, ['load_skill']);
    expect(dataSource.finalAnswerRequestMessages, isEmpty);
    expect(chatNotifier.state.messages.last.content, contains('SKILL_LIVE_OK'));
    expect(
      chatNotifier.state.messages.last.content,
      isNot(contains('FALLBACK_FINAL_SHOULD_NOT_STREAM')),
    );
    expect(
      chatNotifier.state.messages.last.content,
      isNot(contains('実際にプロジェクトに対してこれらを実行して検証しますか')),
    );
    expect(
      chatNotifier.state.messages.last.content,
      isNot(
        contains(
          'I could not execute the additional tool request above in this final-answer step.',
        ),
      ),
    );
  });

  test(
    'sendMessage executes follow-up tools after constrained skill continuation',
    () async {
      const preamble =
          'I will verify release readiness with the saved skill before answering.\n\n';
      const constrainedAnswer =
          'SKILL_LIVE_OK\n\n'
          'リリース readiness チェックを開始します。以下の2つの検証ステップを実行します：\n\n'
          '1. **Git ステータス・変更確認** — 未コミットの変更、ステージング状態、ブランチ状況をチェック\n'
          '2. **ビルド・テスト実行** — プロジェクトのビルドとテストスイートを実行し、エラーがないか確認\n\n'
          'では、まずステップ1から進めます。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-load-skill',
            name: 'load_skill',
            arguments: const {'id': 'release-check'},
          ),
        ],
        initialCompletionContent: preamble,
        initialStreamChunks: const [preamble],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-read-pubspec',
            name: 'read_file',
            arguments: const {'path': 'pubspec.yaml'},
          ),
        ],
        intermediateToolRoleResponseContent: constrainedAnswer,
        finalAnswerChunks: const ['Release status inspected.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
          'read_file': 'Read a file from disk.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
          'read_file': jsonEncode({
            'path': 'pubspec.yaml',
            'content': 'version: 1.3.4+15',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill', 'read_file']);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(dataSource.finalAnswerRequestMessages, hasLength(1));
      expect(
        chatNotifier.state.messages.last.content,
        contains('Release status inspected.'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('では、まずステップ1から進めます')),
      );
    },
  );

  test('sendMessage executes follow-up tools after skill start marker', () async {
    const preamble = 'リリース準備チェックのスキルをまず読み込んでから進めます。\n\n';
    const constrainedAnswer =
        'SKILL_LIVE_OK\n\n'
        'リリース準備チェックを開始します。プロジェクトの現状を確認させてください。';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-load-skill',
          name: 'load_skill',
          arguments: const {'id': 'release-check'},
        ),
      ],
      initialCompletionContent: preamble,
      initialStreamChunks: const [preamble],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'tool-list-directory',
          name: 'list_directory',
          arguments: const {'path': '/project'},
        ),
        ToolCallInfo(
          id: 'tool-read-pubspec',
          name: 'read_file',
          arguments: const {'path': '/project/pubspec.yaml'},
        ),
      ],
      intermediateToolRoleResponseContent: constrainedAnswer,
      finalAnswerChunks: const ['Release project files inspected.'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'load_skill': 'Load the full markdown instructions for a skill.',
        'list_directory': 'List files in a directory.',
        'read_file': 'Read a file from disk.',
      },
      results: {
        'load_skill': jsonEncode({
          'id': 'release-check',
          'name': 'Release Check',
          'content':
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
        }),
        'list_directory': jsonEncode({
          'path': '/project',
          'entries': ['pubspec.yaml'],
        }),
        'read_file': jsonEncode({
          'path': '/project/pubspec.yaml',
          'content': 'version: 1.3.4+15',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('ios,macosアプリをリリース処理したい');

    expect(toolService.executedToolNames, [
      'load_skill',
      'list_directory',
      'read_file',
    ]);
    expect(dataSource.toolResultBatches, hasLength(2));
    expect(dataSource.finalAnswerRequestMessages, hasLength(1));
    expect(
      chatNotifier.state.messages.last.content,
      contains('Release project files inspected.'),
    );
  });

  test(
    'sendMessage executes follow-up tools after skill search intent',
    () async {
      const preamble = 'リリース準備チェックのスキルを読み込みます。\n\n';
      const constrainedAnswer = 'SKILL_LIVE_OK\n\nリリース手順の資料を探します。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-load-skill',
            name: 'load_skill',
            arguments: const {'id': 'release-check'},
          ),
        ],
        initialCompletionContent: preamble,
        initialStreamChunks: const [preamble],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-find-release',
            name: 'find_files',
            arguments: const {'pattern': '*release*', 'recursive': true},
          ),
        ],
        intermediateToolRoleResponseContent: constrainedAnswer,
        finalAnswerChunks: const ['Release documentation search completed.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
          'find_files': 'Find files by glob pattern.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
          'find_files': jsonEncode({
            'path': '/project',
            'pattern': '*release*',
            'matches': ['docs/ios_macos_release.md'],
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('ios,macosアプリをリリース処理したい 資料にリリース手順があるはず');

      expect(toolService.executedToolNames, ['load_skill', 'find_files']);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(dataSource.finalAnswerRequestMessages, hasLength(1));
      expect(
        chatNotifier.state.messages.last.content,
        contains('Release documentation search completed.'),
      );
    },
  );

  test('sendMessage executes look-around skill follow-up tools', () async {
    const preamble = 'リリースチェックのスキルをロードして進めます。\n\n';
    const constrainedAnswer =
        'SKILL_LIVE_OK\n\n'
        'リリース準備状況を確認するために、以下の2つの検証ステップを実行します：\n\n'
        '1. **コードベースのリリース関連チェック** – バージョン番号、変更ログ、ビルド設定ファイルが最新かつ整合性を持っているか確認します。\n'
        '2. **テストとビルドの健全性チェック** – テストスイートの結果とビルドが正常に完了しているか確認します。\n\n'
        '現在のプロジェクトの状態を確認するために、まずリポジトリの構造と Git ステータスを見てみましょう。';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-load-skill',
          name: 'load_skill',
          arguments: const {'id': 'release-check'},
        ),
      ],
      initialCompletionContent: preamble,
      initialStreamChunks: const [preamble],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'tool-list-directory',
          name: 'list_directory',
          arguments: const {'recursive': false, 'max_entries': 30},
        ),
        ToolCallInfo(
          id: 'tool-read-pubspec',
          name: 'read_file',
          arguments: const {'path': 'pubspec.yaml'},
        ),
      ],
      intermediateToolRoleResponseContent: constrainedAnswer,
      finalAnswerChunks: const ['Repository structure inspected.'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'load_skill': 'Load the full markdown instructions for a skill.',
        'list_directory': 'List files in a directory.',
        'read_file': 'Read a file from disk.',
      },
      results: {
        'load_skill': jsonEncode({
          'id': 'release-check',
          'name': 'Release Check',
          'content':
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
        }),
        'list_directory': jsonEncode({
          'path': '.',
          'entries': ['pubspec.yaml'],
        }),
        'read_file': jsonEncode({
          'path': 'pubspec.yaml',
          'content': 'version: 1.3.4+15',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage(
      'Use the Release Check skill if relevant. Verify release readiness.',
    );

    expect(toolService.executedToolNames, [
      'load_skill',
      'list_directory',
      'read_file',
    ]);
    expect(dataSource.toolResultBatches, hasLength(2));
    expect(dataSource.finalAnswerRequestMessages, hasLength(1));
    expect(
      chatNotifier.state.messages.last.content,
      contains('Repository structure inspected.'),
    );
    expect(
      chatNotifier.state.messages.last.content,
      isNot(contains('リポジトリの構造と Git ステータスを見てみましょう')),
    );
  });

  test('sendMessage executes actual-check skill follow-up tools', () async {
    const preamble = 'リリースチェックのスキルをロードして、リリース準備状況を確認します。\n\n';
    const constrainedAnswer =
        'SKILL_LIVE_OK\n\n'
        'リリース準備状況の確認として、以下の2つの検証ステップを行います。\n\n'
        '1. **プロジェクト構造と設定ファイルの確認** — `pubspec.yaml`、`build.yaml` などの設定がリリースビルドに適切に設定されているか確認します。\n'
        '2. **Git ステータスの確認** — 未コミットの変更、未プッシュのコミット、ブランチ状態を確認して、リリース対象が正しい状態か検証します。\n\n'
        'では実際に確認を進めます。';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-load-skill',
          name: 'load_skill',
          arguments: const {'id': 'release-check'},
        ),
      ],
      initialCompletionContent: preamble,
      initialStreamChunks: const [preamble],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'tool-list-directory',
          name: 'list_directory',
          arguments: const {'path': '.'},
        ),
        ToolCallInfo(
          id: 'tool-read-pubspec',
          name: 'read_file',
          arguments: const {'path': 'pubspec.yaml'},
        ),
      ],
      intermediateToolRoleResponseContent: constrainedAnswer,
      finalAnswerChunks: const ['Release readiness inputs inspected.'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'load_skill': 'Load the full markdown instructions for a skill.',
        'list_directory': 'List files in a directory.',
        'read_file': 'Read a file from disk.',
      },
      results: {
        'load_skill': jsonEncode({
          'id': 'release-check',
          'name': 'Release Check',
          'content':
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
        }),
        'list_directory': jsonEncode({
          'path': '.',
          'entries': ['pubspec.yaml'],
        }),
        'read_file': jsonEncode({
          'path': 'pubspec.yaml',
          'content': 'version: 1.3.4+15',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage(
      'Use the Release Check skill if relevant. Verify release readiness.',
    );

    expect(toolService.executedToolNames, [
      'load_skill',
      'list_directory',
      'read_file',
    ]);
    expect(dataSource.toolResultBatches, hasLength(2));
    expect(dataSource.finalAnswerRequestMessages, hasLength(1));
    expect(
      chatNotifier.state.messages.last.content,
      contains('Release readiness inputs inspected.'),
    );
    expect(
      chatNotifier.state.messages.last.content,
      isNot(contains('では実際に確認を進めます')),
    );
  });

  test(
    'sendHiddenPrompt preserves the hidden assistant response for follow-up inference',
    () async {
      final sendFuture = notifier.sendHiddenPrompt('Continue the saved task.');
      controller.add('The task is complete. Validation passed.');
      await controller.close();
      await sendFuture;

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.messages, isEmpty);
      expect(
        notifier.takeLatestHiddenAssistantResponse(),
        'The task is complete. Validation passed.',
      );
      expect(notifier.takeLatestHiddenAssistantResponse(), isNull);
    },
  );

  test('sendHiddenPrompt preserves content-tool dedupe guards', () async {
    const executedCallKey = 'executed:write_file:README.md';
    const seenCallHash = 'seen:write_file:README.md';
    notifier.seedContentToolDedupeGuardsForTest(
      executedCallKey: executedCallKey,
      seenCallHash: seenCallHash,
    );

    final sendFuture = notifier.sendHiddenPrompt('Continue the saved task.');
    controller.add('Still working.');
    await controller.close();
    await sendFuture;

    expect(
      notifier.hasContentToolDedupeGuardsForTest(
        executedCallKey: executedCallKey,
        seenCallHash: seenCallHash,
      ),
      isTrue,
    );
  });

  test(
    'syncConversation ignores stale updates for the active conversation while loading',
    () async {
      await notifier.sendMessage('Inspect the workspace');

      final activeConversationId = container
          .read(conversationsNotifierProvider)
          .currentConversationId;

      final messagesBeforeSync = List<Message>.from(notifier.state.messages);
      notifier.syncConversation(
        conversationId: activeConversationId,
        messages: const [],
      );

      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.messages, messagesBeforeSync);
      expect(notifier.state.messages.last.isStreaming, isTrue);
    },
  );

  test(
    'new thread creation while streaming preserves submitted user messages',
    () async {
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final repository = _FakeConversationRepository();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        threadContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await chatNotifier.sendMessage('Repeated request');
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.chat,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));

      await chatNotifier.sendMessage('Repeated request');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final conversations = threadContainer
          .read(conversationsNotifierProvider)
          .conversations;
      final firstConversation = conversations.firstWhere(
        (conversation) => conversation.id == firstConversationId,
      );
      final secondConversation = conversations.firstWhere(
        (conversation) => conversation.id == secondConversationId,
      );

      expect(firstConversation.messages.map((message) => message.content), [
        'Repeated request',
      ]);
      expect(secondConversation.messages.map((message) => message.content), [
        'Repeated request',
      ]);
      expect(dataSource.requests, hasLength(2));
      expect(chatNotifier.state.messages.map((message) => message.content), [
        'Repeated request',
        '',
      ]);
    },
  );

  test('streaming response survives switching away and back', () async {
    final firstController = StreamController<String>();
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from([firstController]),
    );
    final repository = _FakeConversationRepository();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(repository),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(() async {
      threadContainer.dispose();
      if (!firstController.isClosed) {
        await firstController.close();
      }
    });

    final conversationsNotifier = threadContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    final firstConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await chatNotifier.sendMessage('Keep answering after I switch');
    conversationsNotifier.createNewConversation(
      workspaceMode: WorkspaceMode.chat,
    );
    final secondConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    expect(secondConversationId, isNot(firstConversationId));

    firstController.add('Background ');
    firstController.add('answer');
    await firstController.close();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    conversationsNotifier.selectConversation(firstConversationId);
    await Future<void>.delayed(Duration.zero);

    final firstConversation = threadContainer
        .read(conversationsNotifierProvider)
        .conversations
        .firstWhere((conversation) => conversation.id == firstConversationId);
    expect(firstConversation.messages.map((message) => message.content), [
      'Keep answering after I switch',
      'Background answer',
    ]);
    expect(chatNotifier.state.isLoading, isFalse);
    expect(chatNotifier.state.messages.last.content, 'Background answer');
  });

  test(
    'coding thread creation while streaming preserves submitted user messages',
    () async {
      final project = CodingProject(
        id: 'project-thread-switch',
        name: 'Thread switch project',
        rootPath: '/tmp/thread-switch-project',
        createdAt: DateTime(2026, 5, 29, 11),
        updatedAt: DateTime(2026, 5, 29, 11),
      );
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final repository = _FakeConversationRepository();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(repository),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        threadContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await chatNotifier.sendMessage('Implement the same slice');
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));

      await chatNotifier.sendMessage('Implement the same slice');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final conversations = threadContainer
          .read(conversationsNotifierProvider)
          .conversations;
      final firstConversation = conversations.firstWhere(
        (conversation) => conversation.id == firstConversationId,
      );
      final secondConversation = conversations.firstWhere(
        (conversation) => conversation.id == secondConversationId,
      );

      expect(firstConversation.workspaceMode, WorkspaceMode.coding);
      expect(firstConversation.normalizedProjectId, project.id);
      expect(secondConversation.workspaceMode, WorkspaceMode.coding);
      expect(secondConversation.normalizedProjectId, project.id);
      expect(firstConversation.messages.map((message) => message.content), [
        'Implement the same slice',
      ]);
      expect(secondConversation.messages.map((message) => message.content), [
        'Implement the same slice',
      ]);
      expect(dataSource.requests, hasLength(2));
      expect(chatNotifier.state.messages.map((message) => message.content), [
        'Implement the same slice',
        '',
      ]);
    },
  );

  test(
    'sendMessage queues new user input while a reply is in flight',
    () async {
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final queueContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        queueContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });
      final queueNotifier = queueContainer.read(chatNotifierProvider.notifier);

      await queueNotifier.sendMessage('First request');
      await queueNotifier.sendMessage('Second request');

      var userMessages = queueNotifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .toList();

      expect(queueNotifier.state.isLoading, isTrue);
      expect(userMessages, ['First request']);
      expect(queueNotifier.state.messages, hasLength(2));
      expect(queueNotifier.state.queuedMessages, hasLength(1));
      expect(
        queueNotifier.state.queuedMessages.single.content,
        'Second request',
      );
      expect(dataSource.requests, hasLength(1));

      firstController.add('First response');
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      userMessages = queueNotifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .toList();

      expect(dataSource.requests, hasLength(2));
      expect(queueNotifier.state.isLoading, isTrue);
      expect(queueNotifier.state.queuedMessages, isEmpty);
      expect(userMessages, ['First request', 'Second request']);
      expect(queueNotifier.state.messages.map((message) => message.role), [
        MessageRole.user,
        MessageRole.assistant,
        MessageRole.user,
        MessageRole.assistant,
      ]);
      expect(queueNotifier.state.messages.last.isStreaming, isTrue);
      expect(
        dataSource.requests.last
            .where((message) => message.role != MessageRole.system)
            .map((message) => message.content)
            .toList(),
        ['First request', 'First response', 'Second request'],
      );

      secondController.add('Second response');
      await secondController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(queueNotifier.state.isLoading, isFalse);
      expect(queueNotifier.state.messages.map((message) => message.content), [
        'First request',
        'First response',
        'Second request',
        'Second response',
      ]);
    },
  );

  test(
    'queued user input survives same-conversation save synchronization',
    () async {
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final queueContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _DivergingSaveConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        queueContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });
      final queueNotifier = queueContainer.read(chatNotifierProvider.notifier);

      await queueNotifier.sendMessage('First request');
      await queueNotifier.sendMessage('Second request');

      expect(queueNotifier.state.queuedMessages, hasLength(1));

      firstController.add('First response');
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(dataSource.requests, hasLength(2));
      expect(queueNotifier.state.queuedMessages, isEmpty);
      expect(queueNotifier.state.isLoading, isTrue);
      expect(
        dataSource.requests.last
            .where((message) => message.role != MessageRole.system)
            .map((message) => message.content)
            .toList(),
        ['First request', 'First response persisted', 'Second request'],
      );

      secondController.add('Second response');
      await secondController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(queueNotifier.state.isLoading, isFalse);
      expect(queueNotifier.state.messages.map((message) => message.content), [
        'First request',
        'First response persisted',
        'Second request',
        'Second response persisted',
      ]);
    },
  );

  test(
    'removeQueuedMessage drops a pending user input before it is sent',
    () async {
      final firstController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([firstController]),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final queueContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        queueContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
      });
      final queueNotifier = queueContainer.read(chatNotifierProvider.notifier);

      await queueNotifier.sendMessage('First request');
      await queueNotifier.sendMessage('Second request');

      final queuedId = queueNotifier.state.queuedMessages.single.id;
      queueNotifier.removeQueuedMessage(queuedId);

      expect(queueNotifier.state.queuedMessages, isEmpty);

      firstController.add('First response');
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(dataSource.requests, hasLength(1));
      expect(queueNotifier.state.isLoading, isFalse);
      expect(queueNotifier.state.messages.map((message) => message.content), [
        'First request',
        'First response',
      ]);
    },
  );

  test(
    'parseWorkflowProposalForTest recovers malformed JSON-like proposal content',
    () {
      const rawContent = '''
{
  "kind": "decision",
  "workflowStage": "plan",
  "goal": "設定ファイルによるホスト管理機能の実装",
  "constraints": [
    "既存のpingロジックとの統合",
    "依存ライブラリの最小化"
  ],
  "acceptanceCriteria": [
    "設定ファイルからホスト一覧が読み込める",
    "CLI から利用できる"
  ],
  "openQuestions": [
    "設定ファイル形式は YAML でよいか"
  ],
''';

      final proposal = notifier.parseWorkflowProposalForTest(rawContent);

      expect(proposal, isNotNull);
      expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
      expect(proposal.workflowSpec.goal, '設定ファイルによるホスト管理機能の実装');
      expect(
        proposal.workflowSpec.constraints,
        containsAll(<String>['既存のpingロジックとの統合', '依存ライブラリの最小化']),
      );
      expect(
        proposal.workflowSpec.acceptanceCriteria,
        containsAll(<String>['設定ファイルからホスト一覧が読み込める', 'CLI から利用できる']),
      );
      expect(
        proposal.workflowSpec.openQuestions,
        contains('設定ファイル形式は YAML でよいか'),
      );
    },
  );

  test(
    'parseTaskProposalForTest drops research notes and normalizes action titles',
    () {
      const rawContent = '''
{
  "tasks": [
    {
      "title": "The project root seems empty (based on research context).",
      "targetFiles": []
    },
    {
      "title": "I need to scaffold the project.",
      "targetFiles": ["pyproject.toml", "README.md"],
      "validationCommand": "",
      "notes": "Create the initial files."
    },
    {
      "title": "I need to implement the core logic (pinging).",
      "targetFiles": ["ping_cli.py"],
      "validationCommand": "python3 ping_cli.py google.com",
      "notes": "Keep the first version simple."
    }
  ]
}
''';

      final proposal = notifier.parseTaskProposalForTest(rawContent);

      expect(proposal, isNotNull);
      expect(proposal!.tasks, hasLength(2));
      expect(proposal.tasks.first.title, 'Scaffold the project');
      expect(proposal.tasks.last.title, 'Implement the core logic (pinging)');
      expect(
        proposal.tasks.last.validationCommand,
        'python3 ping_cli.py google.com -c 1',
      );
    },
  );

  test(
    'finalizeTaskProposalForTest moves scaffolding ahead in an empty workspace',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: const [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Argparse` for CLI',
            targetFiles: ['main.py'],
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Initialize project structure',
            targetFiles: ['pyproject.toml', 'README.md'],
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(finalized.tasks.first.title, 'Initialize project structure');
      expect(finalized.tasks.last.title, 'Argparse for CLI');
    },
  );

  test(
    'taskProposalNeedsRetryForWorkflowForTest allows explicit single-file task',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Create a single-file Python CLI ping tool',
        constraints: [
          'Only create ping_cli.py',
          'No other files',
          'Validate with python3 ping_cli.py --help',
        ],
        acceptanceCriteria: [
          'The approved implementation must contain exactly one implementation task',
        ],
      );
      const proposal = WorkflowTaskProposalDraft(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create ping_cli.py with argparse and subprocess ping',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Implement the requested single-file CLI directly.',
          ),
        ],
      );

      final needsRetry = notifier.taskProposalNeedsRetryForWorkflowForTest(
        proposal,
        proposal,
        true,
        workflowSpec,
      );

      expect(needsRetry, isFalse);
    },
  );

  test(
    'taskProposalNeedsRetryForWorkflowForTest rejects split scaffold files',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Scaffold a Python host health checker',
        constraints: ['CLI-first tool for one host'],
        acceptanceCriteria: [
          'requirements.txt lists the initial dependencies',
          'README.md documents setup and usage',
        ],
      );
      const proposal = WorkflowTaskProposalDraft(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create requirements.txt',
            targetFiles: ['requirements.txt'],
            validationCommand: 'test -f requirements.txt',
            notes: 'Create the dependency file first.',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Create README.md',
            targetFiles: ['README.md'],
            validationCommand: 'test -f README.md',
            notes: 'Document setup and usage separately.',
          ),
        ],
      );

      final needsRetry = notifier.taskProposalNeedsRetryForWorkflowForTest(
        proposal,
        proposal,
        true,
        workflowSpec,
      );

      expect(needsRetry, isTrue);
    },
  );

  test(
    'taskProposalNeedsRetryForWorkflowForTest accepts bundled scaffold files',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Scaffold a Python host health checker',
        constraints: ['CLI-first tool for one host'],
        acceptanceCriteria: [
          'requirements.txt lists the initial dependencies',
          'README.md documents setup and usage',
        ],
      );
      const proposal = WorkflowTaskProposalDraft(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create requirements.txt and README.md',
            targetFiles: ['requirements.txt', 'README.md'],
            validationCommand: 'test -f requirements.txt && test -f README.md',
            notes: 'Create the initial scaffold files together.',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Implement ping CLI',
            targetFiles: ['main.py'],
            validationCommand: 'python3 main.py --help',
            notes: 'Add the runnable CLI entry point.',
          ),
        ],
      );

      final needsRetry = notifier.taskProposalNeedsRetryForWorkflowForTest(
        proposal,
        proposal,
        true,
        workflowSpec,
      );

      expect(needsRetry, isFalse);
    },
  );

  test(
    'buildTaskProposalRetryContextForTest preserves explicit single-task scope',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Create a single-file Python CLI ping tool',
        constraints: ['Only create ping_cli.py', 'No other files'],
        acceptanceCriteria: [
          'The approved implementation must contain exactly one implementation task',
        ],
      );

      final retryContext = notifier.buildTaskProposalRetryContextForTest(
        null,
        minimalRetry: true,
        projectLooksEmpty: true,
        workflowSpec: workflowSpec,
      );

      expect(
        retryContext,
        contains('Return exactly one concrete implementation task'),
      );
      expect(
        retryContext,
        contains('Do not add a separate verification-only task'),
      );
      expect(
        retryContext,
        isNot(contains('Return two to four concrete tasks')),
      );
    },
  );

  test(
    'buildTaskProposalRetryContextForTest preserves first-slice scaffold scope',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Scaffold a Python host health checker',
        constraints: ['CLI-first tool for one host'],
        acceptanceCriteria: [
          'requirements.txt lists the initial dependencies',
          'README.md documents setup and usage',
        ],
      );

      final retryContext = notifier.buildTaskProposalRetryContextForTest(
        null,
        minimalRetry: true,
        projectLooksEmpty: true,
        workflowSpec: workflowSpec,
      );

      expect(retryContext, contains('The first task targetFiles must include'));
      expect(retryContext, contains('readme.md'));
      expect(retryContext, contains('requirements.txt'));
      expect(
        retryContext,
        contains('Do not split those first-slice scaffold files'),
      );
    },
  );

  test('sendMessage executes every tool call in the same batch', () async {
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_alpha',
          arguments: const {'path': 'alpha.txt'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'read_beta',
          arguments: const {'path': 'beta.txt'},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'read_alpha': 'alpha result', 'read_beta': 'beta result'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Inspect both files');

      expect(toolService.executedToolNames, ['read_alpha', 'read_beta']);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      expect(
        toolDataSource.toolResultBatches.single
            .map((item) => item.name)
            .toList(),
        ['read_alpha', 'read_beta'],
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('[Tool: read_alpha]'),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('[Tool: read_beta]'),
      );
      expect(toolNotifier.state.isLoading, isFalse);
      expect(
        toolNotifier.state.messages.last.content,
        contains('Combined tool summary'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'final tool-result answers do not execute embedded content tool calls',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'lib/main.dart'},
          ),
        ],
        finalAnswerChunks: const [
          'Summary before hidden call.\n'
              '<tool_call>{"name":"search_files","arguments":{"query":"widgets"}}</tool_call>\n'
              '<tool_call>read_file',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': '{"content":"void main() {}"}',
          'search_files': '{"matches":["should-not-run"]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the file');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.finalAnswerRequestMessages, hasLength(1));
        expect(
          toolDataSource.finalAnswerMessages.first.content,
          isNot(contains('Available tools:')),
        );
        final answerPrompt = toolDataSource.finalAnswerMessages.singleWhere(
          (message) => message.content.contains('[Tool: read_file]'),
        );
        expect(
          answerPrompt.content,
          contains('TOOL RESULT EXACT PRESERVATION:'),
        );
        expect(answerPrompt.content, contains('Raw result:'));
        expect(answerPrompt.content, isNot(contains('<tool_use>')));
        expect(
          answerPrompt.content,
          contains('instead of emitting tool-call tags'),
        );
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Summary before hidden call.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('<tool_call>')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage marks read-only inspection claims without tools as unverified',
    () async {
      const inspectionClaim =
          '`exportOptions.plist` exists in both `ios/` and `macos/`. I confirmed the paths.';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: inspectionClaim,
        initialStreamChunks: const [inspectionClaim],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'read_file': 'Read a file from disk.',
          'list_directory': 'List files in a directory.',
        },
        results: const {
          'read_file': '{"content":"unused"}',
          'list_directory': '{"entries":["unused"]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('continue');

        expect(toolService.executedToolNames, isEmpty);
        final finalContent = toolNotifier.state.messages.last.content;
        expect(finalContent, isNot(contains('I confirmed the paths')));
        expect(
          finalContent,
          contains('local file or project state claim above is unverified'),
        );
        expect(
          finalContent,
          contains('no successful read-only inspection tool result'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves inspection claims with successful read-only tools',
    () async {
      const finalClaim =
          '`exportOptions.plist` exists in the inspected directory.';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-list',
            name: 'list_directory',
            arguments: const {'path': 'ios'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const [finalClaim],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'list_directory': '{"path":"ios","entries":["exportOptions.plist"]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Check export options');

        expect(toolService.executedToolNames, ['list_directory']);
        final finalContent = toolNotifier.state.messages.last.content;
        expect(finalContent, contains(finalClaim));
        expect(finalContent, isNot(contains('claim above is unverified')));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage executes pending read-only inspection at tool loop limit',
    () async {
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {'command': 'probe-$index'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Found the target log; read it now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-read-target',
              name: 'read_file',
              arguments: const {'path': '/tmp/session-log.jsonl'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      toolLoopResponses.addAll([
        ChatCompletionResult(
          content: 'Recovery still needs the target log.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-read-target-recovery',
              name: 'read_file',
              arguments: const {'path': '/tmp/session-log.jsonl'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ]);
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {'command': 'probe-0'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const ['Final answer after reading the target log.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
          'read_file':
              '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find and read the interrupted log');

        expect(toolService.executedToolNames.last, 'read_file');
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('[Tool: read_file]'));
        expect(finalPrompt, contains('target log body'));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final answer after reading the target log.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage shows and persists non-streaming tool-call preambles',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read-release-doc',
            name: 'read_file',
            arguments: const {'path': 'docs/release.md'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Release notes found. Inspecting status next.\n\n',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-inspect-status',
                name: 'inspect_status',
                arguments: const {'scope': 'release'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['Release readiness summary.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': '{"content":"Release procedure"}',
          'inspect_status': '{"status":"clean"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        final visibleContent = toolNotifier.state.messages.last.content;
        expect(visibleContent, contains('Release notes found.'));
        expect(visibleContent, contains('Release readiness summary.'));
        expect(visibleContent, contains('<tool_use>'));

        final persistedContent = toolContainer
            .read(conversationsNotifierProvider)
            .currentConversation!
            .messages
            .last
            .content;
        expect(persistedContent, contains('Release notes found.'));
        expect(persistedContent, contains('<tool_use>'));

        expect(toolDataSource.assistantContents, hasLength(2));
        expect(
          toolDataSource.assistantContents.last,
          contains('Release notes found.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage lets run_python_script recover after missing code',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-python-empty',
            name: 'run_python_script',
            arguments: const {},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Retry with a complete Python script.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-python-retry',
                name: 'run_python_script',
                arguments: const {
                  'code': 'print("metadata ok")',
                  'reason': 'Inspect the attached image metadata',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The Python metadata analysis completed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'run_python_script': '{"stdout":"metadata ok\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Analyze the attached image metadata');

        expect(toolService.executedToolNames, ['run_python_script']);
        expect(
          toolService.executedToolArguments.single['code'],
          contains('metadata ok'),
        );
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.first.single.result,
          allOf(contains('code is required'), contains('caverno.inputs[0]')),
        );
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('metadata ok'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage executes pending read-only local command at tool loop limit',
    () async {
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {
                  'command': 'probe-$index',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Found the target log search; run it now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-find-target',
              name: 'local_execute_command',
              arguments: const {
                'command': 'find /tmp -name session-log.jsonl',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      toolLoopResponses.addAll([
        ChatCompletionResult(
          content: 'Recovery still needs the local search.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-find-target-recovery',
              name: 'local_execute_command',
              arguments: const {
                'command': 'find /tmp -name session-log.jsonl',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ]);
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {
              'command': 'probe-0',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'Final answer after running the pending local search.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': ''},
        queuedResults: {
          'local_execute_command': [
            for (var index = 0; index < 12; index += 1)
              '{"command":"probe-$index","exit_code":0,"stdout":"ok $index\\n","stderr":""}',
            '{"command":"find /tmp -name session-log.jsonl","exit_code":0,"stdout":"/tmp/session-log.jsonl\\n","stderr":""}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find the interrupted log path');

        expect(
          toolService.executedToolNames,
          List.filled(13, 'local_execute_command'),
        );
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('/tmp/session-log.jsonl'));
        expect(finalPrompt, isNot(contains('TASK NOT COMPLETE:')));
        expect(
          finalPrompt,
          isNot(
            contains(
              'Tool call was requested after the bounded tool loop stopped',
            ),
          ),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final answer after running the pending local search.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage executes unsafe pending local command after bounded recovery',
    () async {
      final pendingCommand = 'find /tmp -type f -name "*.jsonl" | head -50';
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {
                  'command': 'probe-$index',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Recover with one more project probe.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-recovery-trigger',
              name: 'local_execute_command',
              arguments: const {
                'command': 'probe-recovery',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Recovery asks for one more bounded probe.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-after-recovery-1',
              name: 'local_execute_command',
              arguments: const {
                'command': 'probe-after-recovery-1',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'One more probe before the final search.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-after-recovery-2',
              name: 'local_execute_command',
              arguments: const {
                'command': 'probe-after-recovery-2',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Search for matching logs with a shell pipeline.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-piped-find',
              name: 'local_execute_command',
              arguments: {
                'command': pendingCommand,
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {
              'command': 'probe-0',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'Final answer acknowledges the unexecuted local command.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find the interrupted log path');

        expect(
          toolService.executedToolNames,
          List.filled(15, 'local_execute_command'),
        );
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('[Tool: local_execute_command]'));
        expect(finalPrompt, contains('*.jsonl'));
        expect(finalPrompt, contains('head -50'));
        expect(toolDataSource.toolResultBatches, hasLength(15));
        final completedResults = toolNotifier.takeLatestToolResults();
        expect(
          completedResults.any(
            (result) => result.result.contains('tool_call_not_executed'),
          ),
          isFalse,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final answer acknowledges the unexecuted local command.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage preserves terminal blocker tool-role answers', () async {
    final cjkSourceCode = String.fromCharCodes([
      0x30bd,
      0x30fc,
      0x30b9,
      0x30b3,
      0x30fc,
      0x30c9,
    ]);
    final cjkRequired = String.fromCharCodes([0x5fc5, 0x8981, 0x3067, 0x3059]);
    final cjkRepository = String.fromCharCodes([
      0x30ea,
      0x30dd,
      0x30b8,
      0x30c8,
      0x30ea,
    ]);
    final cjkPath = String.fromCharCodes([0x30d1, 0x30b9]);
    final cjkTeachMe = String.fromCharCodes([
      0x6559,
      0x3048,
      0x3066,
      0x304f,
      0x3060,
      0x3055,
      0x3044,
    ]);
    final blockerResponse =
        'universal_ble $cjkSourceCode$cjkRequired. '
        '$cjkRepository$cjkPath$cjkTeachMe.';
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-read-dependency',
          name: 'read_file',
          arguments: const {
            'path': '/tmp/project/packages/pes1_ble/pubspec.yaml',
          },
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(content: blockerResponse, finishReason: 'stop'),
      ],
      finalAnswerChunks: const ['This final answer should never be requested.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'read_file':
            '{"path":"/tmp/project/packages/pes1_ble/pubspec.yaml","content":"universal_ble:\\n  git:\\n    url: git@example.com:org/universal_ble.git\\n    ref: v1.2.0"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Investigate Android BLE corruption');

      expect(toolService.executedToolNames, ['read_file']);
      expect(toolDataSource.finalAnswerMessages, isEmpty);
      expect(
        toolNotifier.state.messages.last.content,
        contains('universal_ble'),
      );
      expect(
        toolNotifier.state.messages.last.content,
        isNot(contains('This final answer should never be requested.')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage marks command JSON in final tool answers as unexecuted',
    () async {
      final toolLoopResponses = _toolLoopResponsesThroughRecoveredRead();
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {'command': 'probe-0'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'The investigation needs the Android implementation next.\n\n'
              '```json\n'
              '[\n'
              '  {"command": "find . -type d -name universal_ble", "description": "Locate the package"},\n'
              '  {"command": "cat packages/pes1_ble/pubspec.yaml", "description": "Read dependencies"}\n'
              ']\n'
              '```',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
          'read_file':
              '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find and read the interrupted log');

        expect(toolService.executedToolNames.last, 'read_file');
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(
          finalPrompt,
          contains('This final answer request cannot call tools'),
        );
        expect(finalPrompt, contains('Do not output JSON command arrays'));
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'I could not execute the additional tool request above in this final-answer step.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage marks bracketed tool requests in final answers as unexecuted',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': '/tmp/session-log.jsonl'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The tool result is not enough; retry with Python.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'I need to retry the analysis.\n\n'
              '[Tool: run_python_script]\n'
              'Arguments: {"code":"print(1)"}',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file':
              '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find and read the interrupted log');

        expect(toolService.executedToolNames, ['read_file']);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'I could not execute the additional tool request above in this final-answer step.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage marks plan-only final tool answers as unexecuted', () async {
    final toolLoopResponses = _toolLoopResponsesThroughRecoveredRead();
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-command-0',
          name: 'local_execute_command',
          arguments: const {'command': 'probe-0'},
        ),
      ],
      toolLoopResponses: toolLoopResponses,
      finalAnswerChunks: const [
        'Investigation plan\n\n'
            '1. Inspect the universal_ble Android implementation.\n'
            '2. Trace the notification byte flow.\n'
            '3. Check parser conversion boundaries.\n\n'
            'First, I will inspect the universal_ble Android implementation.',
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'local_execute_command':
            '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
        'read_file':
            '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Find and read the interrupted log');

      final finalPrompt = toolDataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('Do not restate an investigation plan'));
      expect(
        toolNotifier.state.messages.last.content,
        contains(
          'I could not execute the additional tool request above in this final-answer step.',
        ),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage discovers a deferred tool with tool_search before execution',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-search-1',
            name: ToolDefinitionSearchService.toolName,
            arguments: const {'query': 'special diagnostics', 'max_results': 3},
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'special-tool-1',
            name: 'special_remote_diagnostics',
            arguments: const {'target': 'router-1'},
          ),
        ],
        finalAnswerChunks: const ['Special diagnostics summary'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          for (var i = 0; i < 30; i++) 'remote_filler_tool_$i': 'filler $i',
          'special_remote_diagnostics': 'special diagnostics result',
        },
        descriptions: const {
          'special_remote_diagnostics':
              'Run special diagnostics against a remote network target.',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run the special diagnostics tool');

        expect(toolService.executedToolNames, [
          ToolDefinitionSearchService.toolName,
          'special_remote_diagnostics',
        ]);
        final initialNames = _toolNamesFromDefinitions(
          toolDataSource.initialToolDefinitionBatches.single,
        );
        expect(initialNames, contains(ToolDefinitionSearchService.toolName));
        expect(initialNames, isNot(contains('special_remote_diagnostics')));
        final initialSystemPrompt =
            toolDataSource.initialRequestMessages.single.first.content;
        expect(initialSystemPrompt, contains('tool_search'));
        expect(
          initialSystemPrompt,
          contains('If the task needs a tool or capability that is not listed'),
        );
        expect(
          initialSystemPrompt,
          isNot(contains('special_remote_diagnostics')),
        );

        final firstFollowUpNames = _toolNamesFromDefinitions(
          toolDataSource.followUpToolDefinitionBatches.first,
        );
        expect(
          firstFollowUpNames,
          contains(ToolDefinitionSearchService.toolName),
        );
        expect(firstFollowUpNames, contains('special_remote_diagnostics'));
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          ToolDefinitionSearchService.toolName,
        );
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'special_remote_diagnostics',
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Special diagnostics summary'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage repairs skipped run_python_script after tool search',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-search-python',
            name: ToolDefinitionSearchService.toolName,
            arguments: const {'query': 'run_python_script'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                '`run_python_script` is available. I will analyze the attached file metadata.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Retrying with the required Python call.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-python-metadata',
                name: 'run_python_script',
                arguments: const {
                  'code': '''
import json
print(json.dumps({"input_count": len(caverno.inputs)}))
''',
                  'reason': 'Inspect attached image metadata',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The attached image metadata analysis completed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'run_python_script': '{"stdout":"{\\"input_count\\":1}\\n"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Use run_python_script to analyze the metadata',
          imageBase64: base64Encode([1, 2, 3, 4]),
          imageMimeType: 'image/png',
        );

        expect(toolService.executedToolNames, [
          ToolDefinitionSearchService.toolName,
          'run_python_script',
        ]);
        expect(
          toolService.executedToolArguments.last['code'],
          contains('caverno.inputs'),
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('input_count'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage repairs run_python_script file path failures for attachments',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-python-guessed-path',
            name: 'run_python_script',
            arguments: const {
              'code': '''
with open("test.jpg", "rb") as file:
    print(len(file.read()))
''',
              'reason': 'Inspect attached image metadata',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The file test.jpg was not found. Please attach the image or provide a path.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Retrying with the staged attachment path.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-python-staged-path',
                name: 'run_python_script',
                arguments: const {
                  'code': '''
path = caverno.inputs[0].path
with open(path, "rb") as file:
    print(len(file.read()))
''',
                  'reason': 'Inspect attached image metadata',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The attached image metadata analysis completed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'run_python_script': '{"stdout":"4\\n"}'},
        queuedResults: const {
          'run_python_script': [
            '{"error":"FileNotFoundError: [Errno 2] No such file or directory: \'test.jpg\'"}',
            '{"stdout":"4\\n"}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Use run_python_script to analyze the metadata',
          imageBase64: base64Encode([1, 2, 3, 4]),
          imageMimeType: 'image/jpeg',
        );

        expect(toolService.executedToolNames, [
          'run_python_script',
          'run_python_script',
        ]);
        expect(
          toolService.executedToolArguments.first['code'],
          contains('test.jpg'),
        );
        expect(
          toolService.executedToolArguments.last['code'],
          contains('caverno.inputs[0].path'),
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('"stdout":"4'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('python attachment repair prompts guide image metadata scripts', () {
    final prompts = [
      notifier.buildSkippedPythonAttachmentAnalysisRepairPromptForTest(),
      notifier.buildPythonAttachmentPathFailureRepairPromptForTest(),
    ];

    for (final prompt in prompts) {
      expect(prompt, contains('caverno.inputs[0].path'));
      expect(prompt, contains('piexif.load(path)'));
      expect(prompt, contains("piexif.TAGS[ifd][tag].get('name'"));
    }
  });

  test(
    'sendMessage retries tool-result follow-up with forced prompt compaction',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
          ),
        ],
        failFirstToolResultCompletionWithContextLength: true,
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'README contents'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final previousMessages = List<Message>.generate(10, (index) {
          return Message(
            id: 'history-$index',
            content:
                'Previous conversation turn $index with enough detail to summarize.',
            role: index.isEven ? MessageRole.user : MessageRole.assistant,
            timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
          );
        });
        toolNotifier.syncConversation(
          conversationId: null,
          messages: previousMessages,
        );

        await toolNotifier.sendMessage('Inspect the README');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(toolDataSource.toolResultRequestMessages, hasLength(2));
        expect(
          toolDataSource.toolResultRequestMessages.first.any(
            (message) => message.id == 'system_compaction',
          ),
          isFalse,
        );
        expect(
          toolDataSource.toolResultRequestMessages.last.any(
            (message) => message.id == 'system_compaction',
          ),
          isTrue,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Combined tool summary'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage injects one-shot model switch handoff brief', () async {
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: const [],
      initialCompletionContent: 'Ready on the new model',
      initialFinishReason: 'stop',
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(
          _FakeMcpToolService(results: const {'noop_tool': 'ok'}),
        ),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final conversation = toolContainer
          .read(conversationsNotifierProvider.notifier)
          .ensureCurrentConversation();
      final previousMessages = List<Message>.generate(10, (index) {
        return Message(
          id: 'history-$index',
          content:
              'Previous conversation turn $index with enough detail to summarize.',
          role: index.isEven ? MessageRole.user : MessageRole.assistant,
          timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
        );
      });
      toolNotifier.syncConversation(
        conversationId: conversation?.id,
        messages: previousMessages,
      );
      toolNotifier.scheduleModelSwitchHandoffForTest(
        previousSettings: AppSettings.defaults(),
        nextSettings: AppSettings.defaults().copyWith(model: 'new-model'),
      );

      await toolNotifier.sendMessage('Continue after model switch');
      await _waitForCondition(() => !toolNotifier.state.isLoading);
      await toolNotifier.sendMessage('Continue again');
      await _waitForCondition(() => !toolNotifier.state.isLoading);

      expect(toolDataSource.initialRequestMessages, hasLength(2));
      expect(
        toolDataSource.initialRequestMessages.first.any(
          (message) => message.id == 'system_model_handoff',
        ),
        isTrue,
      );
      expect(
        toolDataSource.initialRequestMessages.first.any(
          (message) => message.id == 'system_compaction',
        ),
        isTrue,
      );
      expect(
        toolDataSource.initialRequestMessages.last.any(
          (message) => message.id == 'system_model_handoff',
        ),
        isFalse,
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage retries final tool-result answer with forced prompt compaction',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
          ),
        ],
        failFirstFinalAnswerStreamWithContextLength: true,
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'README contents'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final previousMessages = List<Message>.generate(10, (index) {
          return Message(
            id: 'history-$index',
            content:
                'Previous conversation turn $index with enough detail to summarize.',
            role: index.isEven ? MessageRole.user : MessageRole.assistant,
            timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
          );
        });
        toolNotifier.syncConversation(
          conversationId: null,
          messages: previousMessages,
        );

        await toolNotifier.sendMessage('Inspect the README');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(toolDataSource.finalAnswerRequestMessages, hasLength(2));
        expect(
          toolDataSource.finalAnswerRequestMessages.first.any(
            (message) => message.id == 'system_compaction',
          ),
          isFalse,
        );
        expect(
          toolDataSource.finalAnswerRequestMessages.last.any(
            (message) => message.id == 'system_compaction',
          ),
          isTrue,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Combined tool summary'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('<think>')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage retries tool-result follow-up with compact tool results only',
    () async {
      final largeContent = '${'A' * 24000}\nneedle\n${'B' * 24000}';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'large.log'},
          ),
        ],
        failFirstToolResultCompletionWithContextLength: true,
      );
      final toolService = _FakeMcpToolService(
        results: {
          'read_file': jsonEncode({
            'path': '/workspace/large.log',
            'content': largeContent,
            'size_bytes': largeContent.length,
            'start_line': 1,
            'line_count': 2000,
            'total_lines': 4000,
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the large log');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.first.single.result.length,
          greaterThan(
            toolDataSource.toolResultBatches.last.single.result.length,
          ),
        );
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('content_reduced_for_prompt_budget'),
        );
        expect(
          toolDataSource.toolResultRequestMessages.last.any(
            (message) => message.id == 'system_compaction',
          ),
          isFalse,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Combined tool summary'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('approved input actions record post-action observations', () async {
    for (final caseData in const [
      (
        toolName: 'computer_drag',
        arguments: {'from_x': 10, 'from_y': 20, 'to_x': 30, 'to_y': 40},
        result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      ),
      (
        toolName: 'computer_scroll',
        arguments: {'x': 20, 'y': 30, 'delta_y': -5},
        result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      ),
      (
        toolName: 'computer_type_text',
        arguments: {'text': 'secret typed body'},
        result:
            '{"selectedIpcTransport":"xpc_service","code":"ok","characters":17,"text":"secret typed body"}',
      ),
      (
        toolName: 'computer_press_key',
        arguments: {'key': 'escape'},
        result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      ),
      (
        toolName: 'computer_switch_space',
        arguments: {'direction': 'next'},
        result:
            '{"selectedIpcTransport":"xpc_service","code":"ok","schemaName":"macos_computer_use_space_switch","direction":"next"}',
      ),
    ]) {
      MacosComputerUseAuditLog.instance.clear();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-${caseData.toolName}',
            name: caseData.toolName,
            arguments: Map<String, dynamic>.from(caseData.arguments),
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          caseData.toolName: caseData.result,
          'computer_vision_observe':
              '{"ok":true,"schemaName":"macos_computer_use_vision_observation","selectedIpcTransport":"xpc_service","code":"ok","target":{"resolved":"front_window"},"coordinateSpace":"window_pixels","imageBase64":"secret","imageMimeType":"image/png"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final sendFuture = toolNotifier.sendMessage('Use ${caseData.toolName}');

        PendingComputerUseAction? pending;
        for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
          await Future<void>.delayed(Duration.zero);
          pending = toolNotifier.state.pendingComputerUseAction;
        }
        expect(pending, isNotNull, reason: caseData.toolName);
        expect(pending!.requiresSmokeArming, isTrue);
        toolNotifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        );

        await sendFuture;

        expect(toolService.executedToolNames, [
          caseData.toolName,
          'computer_vision_observe',
        ]);
        final entry = MacosComputerUseAuditLog.instance.redactedEntries.single;
        expect(entry['toolName'], caseData.toolName);
        expect(entry['postActionObservationRequired'], isTrue);
        expect(
          entry['postActionObservationToolName'],
          'computer_vision_observe',
        );
        expect(entry['postActionObservationSuccess'], isTrue);
        expect(entry['postActionObservationTransport'], 'xpc_service');
        expect(
          entry['postActionObservationSchemaName'],
          'macos_computer_use_vision_observation',
        );
        expect(entry['postActionObservationCoordinateSpace'], 'window_pixels');
        expect(entry['postActionObservationImageAttached'], isTrue);
        expect(entry.containsKey('text'), isFalse);
        expect(entry.containsKey('imageBase64'), isFalse);
      } finally {
        toolContainer.dispose();
        MacosComputerUseAuditLog.instance.clear();
      }
    }
  });

  test('computer-use actions return a post-action vision observation', () async {
    MacosComputerUseAuditLog.instance.clear();
    final initialObservation =
        '{"ok":true,"schemaName":"macos_computer_use_vision_observation","observationId":"vision-1","target":{"resolved":"window","windowId":123},"coordinateSpace":"window_pixels","coordinateGuidance":{"sourceWidth":640,"sourceHeight":480,"windowId":123},"allowedNextTools":["computer_move_mouse"],"approvalRequiredTools":["computer_move_mouse"],"imageBase64":"initial-image","imageMimeType":"image/png"}';
    final postActionObservation =
        '{"ok":true,"schemaName":"macos_computer_use_vision_observation","observationId":"vision-2","target":{"resolved":"window","windowId":123},"coordinateSpace":"window_pixels","coordinateGuidance":{"sourceWidth":640,"sourceHeight":480,"windowId":123},"imageBase64":"post-image","imageMimeType":"image/png"}';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'observe-1',
          name: 'computer_vision_observe',
          arguments: const {'target': 'front_window', 'max_width': 640},
        ),
      ],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'move-1',
          name: 'computer_move_mouse',
          arguments: const {
            'x': 20,
            'y': 30,
            'window_id': 123,
            'source_width': 640,
            'source_height': 480,
            'coordinate_space': 'window_pixels',
            'vision_observation_id': 'vision-1',
            'reason': 'Move to the highlighted control.',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'computer_move_mouse':
            '{"ok":true,"selectedIpcTransport":"xpc_service","code":"ok"}',
      },
      queuedResults: {
        'computer_vision_observe': [initialObservation, postActionObservation],
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Move after observing');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 20 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(
        pending!.visionObservationSummary,
        contains('latest vision observation'),
      );
      expect(
        pending.visionObservationDetails,
        contains('Observation ID: vision-1'),
      );
      expect(
        pending.visionObservationDetails,
        contains('Coordinate space: window_pixels'),
      );
      expect(
        pending.visionObservationDetails,
        contains('Source screenshot: 640 x 480 px'),
      );
      toolNotifier.resolveComputerUseAction(
        id: pending.id,
        approved: true,
        armed: true,
      );

      await sendFuture;

      expect(toolService.executedToolNames, [
        'computer_vision_observe',
        'computer_move_mouse',
        'computer_vision_observe',
      ]);
      final actionBatch = toolDataSource.toolResultBatches.last;
      final actionResult = jsonDecode(actionBatch.single.result) as Map;
      expect(actionResult['schemaName'], 'macos_computer_use_action_result');
      expect(actionResult['imageBase64'], 'post-image');
      expect(actionResult['nextAction'], contains('post-action observation'));
      final postObservation =
          actionResult['postActionObservation'] as Map<String, dynamic>;
      expect(postObservation['toolName'], 'computer_vision_observe');
      expect(postObservation['imageAttached'], isTrue);
      final entry = MacosComputerUseAuditLog.instance.redactedEntries.last;
      expect(entry['toolName'], 'computer_move_mouse');
      expect(entry['postActionObservationToolName'], 'computer_vision_observe');
      expect(entry['postActionObservationImageAttached'], isTrue);
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test('Space switch actions return a post-action vision observation', () async {
    MacosComputerUseAuditLog.instance.clear();
    final postActionObservation =
        '{"ok":true,"schemaName":"macos_computer_use_vision_observation","observationId":"vision-space-2","target":{"resolved":"front_window"},"coordinateSpace":"display_pixels","imageBase64":"space-image","imageMimeType":"image/png"}';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'space-1',
          name: 'computer_switch_space',
          arguments: const {
            'direction': 'next',
            'reason': 'Find the target window on the next Space.',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'computer_switch_space':
            '{"ok":true,"schemaName":"macos_computer_use_space_switch","direction":"next","key":"right","modifiers":["control"],"selectedIpcTransport":"xpc_service","requiresPostActionObservation":true}',
        'computer_vision_observe': postActionObservation,
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Switch Spaces');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 20 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(pending!.summary, contains('next macOS Space'));
      expect(pending.details, contains('Direction: next'));
      expect(pending.details, contains('Shortcut: control+right'));
      expect(pending.warningMessage, contains('observe again'));
      toolNotifier.resolveComputerUseAction(
        id: pending.id,
        approved: true,
        armed: true,
      );

      await sendFuture;

      expect(toolService.executedToolNames, [
        'computer_switch_space',
        'computer_vision_observe',
      ]);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final actionResult =
          jsonDecode(toolDataSource.toolResultBatches.single.single.result)
              as Map<String, dynamic>;
      expect(actionResult['schemaName'], 'macos_computer_use_action_result');
      expect(actionResult['toolName'], 'computer_switch_space');
      expect(actionResult['postActionObservationRequired'], isTrue);
      expect(actionResult['imageBase64'], 'space-image');
      expect(actionResult['nextAction'], contains('post-action observation'));
      final postObservation =
          actionResult['postActionObservation'] as Map<String, dynamic>;
      expect(postObservation['toolName'], 'computer_vision_observe');
      expect(postObservation['success'], isTrue);
      expect(postObservation['observationId'], 'vision-space-2');
      expect(postObservation['coordinateSpace'], 'display_pixels');
      expect(postObservation['imageAttached'], isTrue);
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test(
    'computer-use approvals surface target context and exact text',
    () async {
      MacosComputerUseAuditLog.instance.clear();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-type-targeted',
            name: 'computer_type_text',
            arguments: const {
              'text': 'Good morning from Caverno',
              'window_id': 321,
              'element_id': 'ax-0007',
              'vision_observation_id': 'vision-99',
              'coordinate_space': 'window_pixels',
              'source_width': 800,
              'source_height': 600,
              'target': {
                'label': 'Post composer',
                'role': 'AXTextArea',
                'elementId': 'ax-0007',
                'appName': 'Safari',
                'appBundleId': 'com.apple.Safari',
                'windowTitle': 'X / Home',
                'windowId': 321,
                'action': 'type_text',
                'risk': 'input',
              },
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'computer_type_text':
              '{"selectedIpcTransport":"xpc_service","code":"ok"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final sendFuture = toolNotifier.sendMessage('Type into the composer');

        PendingComputerUseAction? pending;
        for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
          await Future<void>.delayed(Duration.zero);
          pending = toolNotifier.state.pendingComputerUseAction;
        }

        expect(pending, isNotNull);
        expect(
          pending!.targetSummary,
          'Review the AXTextArea target "Post composer" before approving.',
        );
        expect(pending.targetDetails, contains('App: Safari'));
        expect(pending.targetDetails, contains('Bundle ID: com.apple.Safari'));
        expect(pending.targetDetails, contains('Window: X / Home (id 321)'));
        expect(pending.targetDetails, contains('Element ID: ax-0007'));
        expect(pending.targetDetails, contains('Role: AXTextArea'));
        expect(pending.targetDetails, contains('Label: Post composer'));
        expect(pending.targetDetails, contains('Intended action: type_text'));
        expect(pending.targetDetails, contains('Target risk: input'));
        expect(pending.exactTextPreview, 'Good morning from Caverno');
        expect(pending.exactTextLength, 25);
        expect(
          pending.visionObservationDetails,
          contains('Observation ID: vision-99'),
        );
        expect(
          pending.visionObservationDetails,
          contains('Source screenshot: 800 x 600 px'),
        );

        toolNotifier.resolveComputerUseAction(id: pending.id, approved: false);
        await sendFuture;

        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
        MacosComputerUseAuditLog.instance.clear();
      }
    },
  );

  test('unsafe computer-use actions require explicit arming', () async {
    MacosComputerUseAuditLog.instance.clear();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-click',
          name: 'computer_click',
          arguments: const {'x': 10, 'y': 20},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'computer_click': '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Click without arming');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(pending!.requiresUserApproval, isTrue);
      expect(pending.requiresSmokeArming, isTrue);
      expect(pending.approvalBoundaries, contains('target'));
      expect(pending.approvalBlockerCodes, isEmpty);
      expect(
        pending.actionProposalNextAction,
        contains('approve the exact target'),
      );
      toolNotifier.resolveComputerUseAction(id: pending.id, approved: true);

      await sendFuture;

      expect(toolService.executedToolNames, isEmpty);
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'computer_click');
      expect(result.result, contains('"code":"arming_missing"'));

      final entry = MacosComputerUseAuditLog.instance.redactedEntries.single;
      expect(entry['toolName'], 'computer_click');
      expect(entry['approvalResult'], 'arming_missing');
      expect(entry['requiresSmokeArming'], isTrue);
      expect(entry['success'], isFalse);
      expect(entry['responseCode'], 'arming_missing');
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test('computer-use approvals surface public action boundaries', () async {
    MacosComputerUseAuditLog.instance.clear();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-post-click',
          name: 'computer_click',
          arguments: const {
            'x': 80,
            'y': 120,
            'target': {
              'label': 'Post',
              'role': 'button',
              'action': 'publish',
              'risk': 'public_action',
            },
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'computer_click': '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Click the post button');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(
        pending!.approvalBoundaries,
        containsAll(['target', 'publicAction']),
      );
      expect(
        pending.approvalBlockerCodes,
        contains('separate_public_action_approval_required'),
      );
      expect(
        pending.actionProposalNextAction,
        contains('separate explicit approval'),
      );
      toolNotifier.resolveComputerUseAction(id: pending.id, approved: false);

      await sendFuture;

      expect(toolService.executedToolNames, isEmpty);
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.result, contains('"code":"approval_denied"'));
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test(
    'computer-use approvals block destructive targets after approval',
    () async {
      MacosComputerUseAuditLog.instance.clear();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-delete-click',
            name: 'computer_click',
            arguments: const {
              'x': 80,
              'y': 120,
              'target': {
                'label': 'Delete workspace',
                'role': 'button',
                'action': 'delete',
                'risk': 'destructive',
              },
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'computer_click':
              '{"selectedIpcTransport":"xpc_service","code":"ok"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final sendFuture = toolNotifier.sendMessage('Click the delete button');

        PendingComputerUseAction? pending;
        for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
          await Future<void>.delayed(Duration.zero);
          pending = toolNotifier.state.pendingComputerUseAction;
        }
        expect(pending, isNotNull);
        expect(
          pending!.approvalBoundaries,
          containsAll(['target', 'destructive']),
        );
        expect(
          pending.approvalBlockerCodes,
          contains('destructive_target_blocked'),
        );
        expect(pending.actionProposalNextAction, contains('Do not execute'));
        toolNotifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        );

        await sendFuture;

        expect(toolService.executedToolNames, isEmpty);
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.result, contains('"code":"action_policy_blocked"'));
        expect(result.result, contains('"destructive_target_blocked"'));

        final entry = MacosComputerUseAuditLog.instance.redactedEntries.single;
        expect(entry['toolName'], 'computer_click');
        expect(entry['approvalResult'], 'blocked');
        expect(entry['responseCode'], 'action_policy_blocked');
        expect(entry['success'], isFalse);
      } finally {
        toolContainer.dispose();
        MacosComputerUseAuditLog.instance.clear();
      }
    },
  );

  test(
    'sendMessage carries computer-use screenshots into final vision prompt',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-display',
            name: 'computer_screenshot',
            arguments: const {'max_width': 800},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The display is visible; I need the window list.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-windows',
                name: 'computer_list_windows',
                arguments: const {'include_current_app': true},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I found the target window and need a focused screenshot.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-window-image',
                name: 'computer_screenshot_window',
                arguments: const {'window_id': 42, 'max_width': 800},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Visual inspection is ready.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Observed the target window.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'computer_screenshot':
              '{"imageBase64":"display-image-payload","imageMimeType":"image/png","width":800,"height":500}',
          'computer_list_windows':
              '{"windows":[{"windowId":42,"appName":"Caverno","title":"Debug","bounds":{"x":0,"y":0,"width":800,"height":500}}],"count":1}',
          'computer_screenshot_window':
              '{"imageBase64":"window-image-payload","imageMimeType":"image/png","width":640,"height":400,"windowId":42}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the desktop visually');

        expect(toolService.executedToolNames, [
          'computer_screenshot',
          'computer_list_windows',
          'computer_screenshot_window',
        ]);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['computer_screenshot'],
            ['computer_list_windows'],
            ['computer_screenshot_window'],
          ],
        );

        final answerPrompt = toolDataSource.finalAnswerMessages.singleWhere(
          (message) => message.content.contains('[Tool: computer_screenshot]'),
        );
        expect(answerPrompt.content, isNot(contains('display-image-payload')));
        expect(answerPrompt.content, isNot(contains('window-image-payload')));
        expect(answerPrompt.content, contains('[attached as image content]'));

        final imageMessages = toolDataSource.finalAnswerMessages
            .where((message) => message.imageBase64 != null)
            .toList();
        expect(imageMessages.map((message) => message.imageBase64).toList(), [
          'display-image-payload',
          'window-image-payload',
        ]);
        expect(
          imageMessages.last.content,
          contains('Visual observation from computer_screenshot_window'),
        );
        expect(
          imageMessages.last.content,
          contains('actionProposalPolicy metadata'),
        );
        expect(
          imageMessages.last.content,
          contains('public action boundaries'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Observed the target window.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage replays repeated read_file results across tool loops',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-2',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        intermediateToolRoleResponseContent:
            'I need to inspect the exact file contents again before retrying the edit.',
        toolRoleResponseContent: 'Retry finished.',
        finalAnswerChunks: const ['Recovered after repeated read_file.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'file contents'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Retry the mismatched ping_cli edit');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches
              .expand((batch) => batch.map((item) => item.name))
              .toList(),
          ['read_file', 'read_file'],
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered after repeated read_file.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage recovers from duplicate follow-up scaffold writes', () async {
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'create_requirements',
          arguments: const {'path': 'requirements.txt', 'content': '# deps\n'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'create_readme',
          arguments: const {'path': 'README.md', 'content': '# demo\n'},
        ),
      ],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'tool-3',
          name: 'create_requirements',
          arguments: const {'path': 'requirements.txt', 'content': '# deps\n'},
        ),
      ],
      intermediateToolRoleResponseContent:
          'I created README.md and will continue with the remaining scaffold files.',
      toolRoleResponseContent: 'This follow-up text should never be streamed.',
      finalAnswerChunks: const ['This final answer should never be requested.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'create_requirements':
            '{"path":"/tmp/requirements.txt","created":true,"bytes_written":8}',
        'create_readme':
            '{"path":"/tmp/README.md","created":true,"bytes_written":8}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Initialize the scaffold files');

      expect(
        toolDataSource.toolResultBatches
            .map((batch) => batch.map((item) => item.name).toList())
            .toList(),
        [
          ['create_requirements', 'create_readme'],
          ['create_requirements', 'create_readme'],
        ],
      );
      expect(toolService.executedToolNames, [
        'create_requirements',
        'create_readme',
      ]);
      expect(toolNotifier.state.isLoading, isFalse);
      expect(
        toolNotifier.takeLatestToolResults().map((item) => item.name).toList(),
        ['create_requirements', 'create_readme'],
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('This final answer should never be requested.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'buildDuplicateFollowUpRecoveryPromptForTest requires a file edit before rerunning validation after reading a failing file',
    () {
      final prompt = notifier.buildDuplicateFollowUpRecoveryPromptForTest(
        [
          ToolCallInfo(
            id: 'tool-validation',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 -m unittest test_ping.py'},
          ),
        ],
        previousToolResults: [
          ToolResultInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'test_ping.py'},
            result: 'import unittest\n',
          ),
        ],
      );

      expect(
        prompt,
        contains(
          'your next action must modify that same file before rerunning the saved validation command',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not rerun the same validation command until a saved target file edit changes the current task.',
        ),
      );
    },
  );

  test(
    'buildDuplicateFollowUpRecoveryPromptForTest prevents unverified file completion claims',
    () {
      final prompt = notifier.buildDuplicateFollowUpRecoveryPromptForTest([
        ToolCallInfo(
          id: 'tool-weather',
          name: 'http_get',
          arguments: const {'url': 'https://example.com/weather'},
        ),
      ]);

      expect(
        prompt,
        contains(
          'If the user requested local file creation or modification and no successful file mutation result is already provided',
        ),
      );
      expect(
        prompt,
        contains('your next action must be write_file or edit_file'),
      );
      expect(
        prompt,
        contains(
          'Do not claim that files were created, edited, saved, moved, or deleted',
        ),
      );
    },
  );

  test(
    'buildDuplicateInspectionRecoveryPromptForTest redirects failed exit-code validation to a target edit',
    () {
      final prompt = notifier.buildDuplicateInspectionRecoveryPromptForTest(
        [
          ToolCallInfo(
            id: 'tool-list',
            name: 'list_directory',
            arguments: const {'path': '.'},
          ),
        ],
        previousToolResults: [
          ToolResultInfo(
            id: 'tool-validation',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 test_ping_cli.py'},
            result:
                '{"command":"python3 test_ping_cli.py","exit_code":1,"stdout":"Testing host: invalid.hostname.that.should.fail.test (Expected exit code: 1)\\nFAIL: invalid.hostname.that.should.fail.test returned 68, expected 1","stderr":""}',
          ),
        ],
      );

      expect(
        prompt,
        contains(
          'The latest validation command failed; use that failure output now instead of inspecting the directory again.',
        ),
      );
      expect(
        prompt,
        contains(
          'edit the verification target to accept any non-zero failure code before rerunning validation',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not repeat identical read-only inspection tools again in this turn: list_directory.',
        ),
      );
    },
  );

  test(
    'buildToolLoopRecoveryToolResultsForTest includes latest read context for edit mismatch recovery',
    () {
      final recoveryToolResults = notifier.buildToolLoopRecoveryToolResultsForTest(
        currentToolResults: [
          ToolResultInfo(
            id: 'tool-edit',
            name: 'edit_file',
            arguments: const {'path': 'main.py'},
            result:
                '{"error":"old_text was not found in the target file","path":"/tmp/main.py"}',
          ),
        ],
        executedToolResults: [
          ToolResultInfo(
            id: 'tool-read-other',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
            result: '# Ping CLI\n',
          ),
          ToolResultInfo(
            id: 'tool-read-main',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
            result: 'import argparse\n',
          ),
        ],
        pendingToolCalls: [
          ToolCallInfo(
            id: 'tool-follow-up',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
          ),
        ],
      );

      expect(
        recoveryToolResults.map((toolResult) => toolResult.name).toList(),
        ['read_file', 'edit_file'],
      );
      expect(
        recoveryToolResults.first.arguments,
        containsPair('path', 'main.py'),
      );
      expect(recoveryToolResults.first.result, contains('import argparse'));
    },
  );

  test(
    'buildDuplicateRecoveryToolResultsForTest includes matching previous result before fallback context',
    () {
      final recoveryToolResults = notifier
          .buildDuplicateRecoveryToolResultsForTest(
            currentToolCalls: [
              ToolCallInfo(
                id: 'tool-backend-repeat',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src/backend'},
              ),
            ],
            executedToolResults: [
              ToolResultInfo(
                id: 'tool-src',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src'},
                result: '{"entries":["backend","core","value_state"]}',
              ),
              ToolResultInfo(
                id: 'tool-backend',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src/backend'},
                result: '{"entries":["bt_backend_type.dart"]}',
              ),
            ],
            fallbackToolResults: [
              ToolResultInfo(
                id: 'tool-src',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src'},
                result: '{"entries":["backend","core","value_state"]}',
              ),
            ],
          );

      expect(recoveryToolResults.map((toolResult) => toolResult.id).toList(), [
        'tool-backend-repeat',
        'tool-src',
      ]);
      final reusedResult =
          jsonDecode(recoveryToolResults.first.result) as Map<String, dynamic>;
      expect(reusedResult['entries'], ['bt_backend_type.dart']);
      expect(reusedResult['execution_reused'], isTrue);
      expect(reusedResult['prior_tool_call_id'], 'tool-backend');
      expect(reusedResult['current_tool_call_id'], 'tool-backend-repeat');
    },
  );

  test(
    'buildDuplicateRecoveryToolResultsForTest matches reworded file mutations',
    () {
      final recoveryToolResults = notifier
          .buildDuplicateRecoveryToolResultsForTest(
            currentToolCalls: [
              ToolCallInfo(
                id: 'edit-repeat',
                name: 'edit_file',
                arguments: const {
                  'path': 'pubspec.yaml',
                  'old_text': 'name: todo',
                  'new_text': 'name: todo_app',
                  'reason': 'Fix package imports.',
                },
              ),
            ],
            executedToolResults: [
              ToolResultInfo(
                id: 'edit-original',
                name: 'edit_file',
                arguments: const {
                  'path': 'pubspec.yaml',
                  'old_text': 'name: todo',
                  'new_text': 'name: todo_app',
                  'reason': 'Align the package name.',
                },
                result: '{"path":"/tmp/project/pubspec.yaml","replacements":1}',
              ),
            ],
            fallbackToolResults: const [],
          );

      expect(recoveryToolResults, hasLength(1));
      expect(recoveryToolResults.single.id, 'edit-repeat');
      final reusedResult =
          jsonDecode(recoveryToolResults.single.result) as Map<String, dynamic>;
      expect(reusedResult['execution_reused'], isTrue);
      expect(reusedResult['prior_tool_call_id'], 'edit-original');
    },
  );

  test(
    'buildToolLoopExhaustionRecoveryPromptForTest forbids rereading edit mismatch files when read context exists',
    () {
      final prompt = notifier.buildToolLoopExhaustionRecoveryPromptForTest(
        [
          ToolCallInfo(
            id: 'tool-follow-up',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
          ),
        ],
        previousToolResults: [
          ToolResultInfo(
            id: 'tool-read-main',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
            result: 'import argparse\n',
          ),
          ToolResultInfo(
            id: 'tool-edit',
            name: 'edit_file',
            arguments: const {'path': 'main.py'},
            result:
                '{"error":"old_text was not found in the target file","path":"/tmp/main.py"}',
          ),
        ],
      );

      expect(
        prompt,
        contains(
          'A recent read_file result for the same path is already provided below.',
        ),
      );
      expect(
        prompt,
        contains('Do not call read_file again for the same path in this turn.'),
      );
      expect(
        prompt,
        contains(
          'Use that exact file content and return only one edit_file call for the same file',
        ),
      );
    },
  );

  test('sendMessage recovers from duplicate read-only follow-up loops', () async {
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'list_directory',
          arguments: const {'path': '.'},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'Inspect main.py before writing the unit tests.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-2',
              name: 'read_file',
              arguments: const {'path': 'main.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-3',
              name: 'list_directory',
              arguments: const {'path': '.'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Write tests/test_ping.py now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-4',
              name: 'write_test_file',
              arguments: const {'path': 'tests/test_ping.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The unit test task is complete.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['Recovered after duplicate inspection loop.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'list_directory': '{"entries":["main.py"]}',
        'read_file': 'print("ping")',
        'write_test_file':
            '{"path":"/tmp/tests/test_ping.py","created":true,"bytes_written":64}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create unit tests for the ping CLI');

      expect(toolService.executedToolNames, [
        'list_directory',
        'read_file',
        'write_test_file',
      ]);
      expect(
        toolDataSource.toolResultBatches
            .map((batch) => batch.map((item) => item.name).toList())
            .toList(),
        [
          ['list_directory'],
          ['read_file'],
          ['list_directory', 'read_file'],
          ['write_test_file'],
        ],
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('Recovered after duplicate inspection loop.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage treats relative and absolute read-only paths as duplicate inspections',
    () async {
      final project = CodingProject(
        id: 'project-path-dedupe',
        name: 'path-dedupe',
        rootPath: '/tmp/caverno-path-dedupe',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'list_directory',
            arguments: const {'path': 'packages/pes1_ble/lib/src/backend'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'list_directory',
                arguments: {
                  'path':
                      '${project.rootPath}/packages/pes1_ble/lib/src/backend',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The duplicate inspection recovery is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'list_directory': '{"entries":["bt_backend_type.dart"]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the BLE backend directory');

        expect(toolService.executedToolNames, ['list_directory']);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['list_directory'],
            ['list_directory'],
          ],
        );
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('The duplicate inspection recovery is complete.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal duplicate inspection recovery text without streaming a final answer',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'list_directory',
            arguments: const {'path': '.'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Inspect src/ping_cli/cli.py before finalizing.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'read_file',
                arguments: const {'path': 'src/ping_cli/cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-3',
                name: 'list_directory',
                arguments: const {'path': '.'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The implementation of the ping CLI tool is complete and verified.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'list_directory': '{"entries":["src/ping_cli/cli.py"]}',
          'read_file': 'print("ping")',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement the ping CLI tool');

        expect(toolService.executedToolNames, ['list_directory', 'read_file']);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['list_directory'],
            ['read_file'],
            ['list_directory', 'read_file'],
          ],
        );
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The implementation of the ping CLI tool is complete and verified.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage ignores read-only follow-up after terminal saved-task text',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_cli',
            arguments: const {
              'path': 'ping_cli.py',
              'content': 'print("json output")',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The task "Add JSON output support to ping_cli.py" is complete. Validation passed.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-read',
                name: 'read_file',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_cli': '{"path":"/tmp/ping_cli.py","bytes_written":20}',
          'read_file': 'print("json output")',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Add JSON output support');

        expect(toolService.executedToolNames, ['write_cli']);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Add JSON output support to ping_cli.py'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage rejects terminal tool-role text with optional follow-up',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'weather.md',
              'content': 'Saved weather report.',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The task "Save the weather report" is complete. Validation passed. Do you want another output format?',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Saved the weather report.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/weather.md","created":true,"bytes_written":21}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoVerificationSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Save the weather report');

        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Saved the weather report.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('Do you want another output format?')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage allows longer saved-task tool loops before fallback',
    () async {
      final toolLoopResponses = <ChatCompletionResult>[
        for (var index = 0; index < 9; index += 1)
          ChatCompletionResult(
            content: 'Continue refining ping_cli.py before validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-${index + 2}',
                name: 'read_file',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'The ping CLI implementation is complete.',
          finishReason: 'stop',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const ['Recovered final answer after long loop.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'print("ping")'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement the ping CLI tool');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(10));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered final answer after long loop.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage requests bounded recovery before fallback when tool loops exhaust',
    () async {
      final toolLoopResponses = <ChatCompletionResult>[
        for (var index = 0; index < 11; index += 1)
          ChatCompletionResult(
            content: 'Continue repairing ping_cli.py before validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-${index + 2}',
                name: 'read_file',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'One final recovery step is needed for the current task.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-13',
              name: 'read_file',
              arguments: const {'path': 'ping_cli.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content:
              'The current saved task is complete. Validation already passed.',
          finishReason: 'stop',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'print("ping")'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Finish the current ping CLI task');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(13));
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('The current saved task is complete.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage recovers from duplicate mutating follow-up loops', () async {
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'create_tests_dir',
          arguments: const {'path': 'tests'},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'Inspect ping_cli.py before writing tests/test_ping.py.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-2',
              name: 'read_file',
              arguments: const {'path': 'ping_cli.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content:
              'Create the tests directory before writing tests/test_ping.py.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-3',
              name: 'create_tests_dir',
              arguments: const {'path': 'tests'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Write tests/test_ping.py now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-4',
              name: 'write_test_file',
              arguments: const {'path': 'tests/test_ping.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The unit test task is complete.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['Recovered after duplicate follow-up loop.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'create_tests_dir':
            '{"path":"/tmp/tests","created":true,"entry_type":"directory"}',
        'read_file': 'print("ping")',
        'write_test_file':
            '{"path":"/tmp/tests/test_ping.py","created":true,"bytes_written":64}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Add unit tests for the ping CLI');

      expect(toolService.executedToolNames, [
        'create_tests_dir',
        'read_file',
        'write_test_file',
      ]);
      expect(
        toolDataSource.toolResultBatches
            .map((batch) => batch.map((item) => item.name).toList())
            .toList(),
        [
          ['create_tests_dir'],
          ['read_file'],
          ['create_tests_dir', 'read_file'],
          ['write_test_file'],
        ],
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('Recovered after duplicate follow-up loop.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage summarizes previous command output for duplicate success intent',
    () async {
      const command = 'python3 get_weather.py';
      final duplicateCommandCall = ToolCallInfo(
        id: 'command-duplicate',
        name: 'local_execute_command',
        arguments: const {'command': command, 'working_directory': '/tmp'},
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'command-1',
            name: 'local_execute_command',
            arguments: const {'command': command, 'working_directory': '/tmp'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Repair the source before rerunning the command.',
            toolCalls: [
              ToolCallInfo(
                id: 'write-fix',
                name: 'write_weather_data',
                arguments: const {'path': 'get_weather.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Rerun the script after the repair.',
            toolCalls: [
              ToolCallInfo(
                id: 'command-2',
                name: 'local_execute_command',
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Now let me run the script to confirm the output.',
            toolCalls: [duplicateCommandCall],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const ['This final answer should not be requested.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command': 'unused',
          'write_weather_data':
              '{"path":"/tmp/get_weather.py","replacements":1}',
        },
        queuedResults: const {
          'local_execute_command': [
            '{"command":"python3 get_weather.py","exit_code":0,"stdout":"# Error\\nNo data found.\\n","stderr":""}',
            '{"command":"python3 get_weather.py","exit_code":0,"stdout":"OUTPUT_FEEDBACK_LIVE_OK\\n","stderr":""}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run the weather script');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'write_weather_data',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('OUTPUT_FEEDBACK_LIVE_OK'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Now let me run'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage streams a final answer when duplicate recovery repeats a tool',
    () async {
      final duplicateDatetimeCall = ToolCallInfo(
        id: 'datetime-duplicate',
        name: 'get_current_datetime',
        arguments: const {},
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'datetime-1',
            name: 'get_current_datetime',
            arguments: const {},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I still need the current time.',
            toolCalls: [duplicateDatetimeCall],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I still need the current time.',
            toolCalls: [duplicateDatetimeCall],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const ['Recovered from the prior datetime result.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'get_current_datetime':
              '{"local_datetime":"2026-05-25 10:39:03","timezone":"JST"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Check the current status');

        expect(toolService.executedToolNames, ['get_current_datetime']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered from the prior datetime result.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('problem executing the tools')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage allows rerunning the same validation command after a file rewrite',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'python3 ping_cli.py --help',
              'working_directory': '/tmp',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Fix ping_cli.py before retrying validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'write_cli',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Retry the saved validation command now.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-3',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 ping_cli.py --help',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The saved task is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Recovered after validation retry.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"exit_code":0,"stdout":"usage: ping_cli.py"}',
          'write_cli':
              '{"path":"/tmp/ping_cli.py","created":false,"bytes_written":12}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement the ping CLI');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'write_cli',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches
              .expand((batch) => batch.map((item) => item.name))
              .toList(),
          ['local_execute_command', 'write_cli', 'local_execute_command'],
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered after validation retry.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops duplicate command follow-up after successful validation',
    () async {
      final conversation = Conversation(
        id: 'conversation-duplicate-validation',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-ping-cli',
              title: 'Implement ping CLI',
              targetFiles: ['ping_cli.py'],
              validationCommand: 'python3 ping_cli.py --help',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_cli',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 ping_cli.py --help',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The validation command already passed, so I will not rerun it.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate-duplicate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 ping_cli.py --help',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_cli': '{"path":"/tmp/ping_cli.py","bytes_written":1200}',
          'local_execute_command':
              '{"command":"python3 ping_cli.py --help","exit_code":0,"stdout":"usage: ping_cli.py [-h] host","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement ping CLI');

        expect(toolService.executedToolNames, [
          'write_cli',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('validation command already passed'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves duplicate read-only command investigation content',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-log-summary',
            name: 'local_execute_command',
            arguments: const {
              'command': 'python3 summarize_session_log.py',
              'working_directory': '/tmp',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The session log shows the conversation reset after a duplicate inspection command.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-log-summary-duplicate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 summarize_session_log.py',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"python3 summarize_session_log.py","exit_code":0,"stdout":"summary\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Investigate the session log');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('conversation reset after a duplicate inspection command'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('saved validation command')),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage recovers next command after duplicate successful command',
    () async {
      const configEmailArgs = {
        'command': 'config user.email canary@example.com',
        'working_directory': '/tmp/project',
      };
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'git-config-email',
            name: 'git_execute_command',
            arguments: configEmailArgs,
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Now I will set the git user email again.',
            toolCalls: [
              ToolCallInfo(
                id: 'git-config-email-duplicate',
                name: 'git_execute_command',
                arguments: configEmailArgs,
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The email already succeeded. Continuing with git add.',
            toolCalls: [
              ToolCallInfo(
                id: 'git-add',
                name: 'git_execute_command',
                arguments: const {
                  'command': 'add lib/git_lifecycle_note.txt',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'Added the file after reusing the previous git config result.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Recovered command progression.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': ''},
        queuedResults: const {
          'git_execute_command': [
            '{"command":"git config user.email canary@example.com","exit_code":0,"stdout":"","stderr":""}',
            '{"command":"git add lib/git_lifecycle_note.txt","exit_code":0,"stdout":"","stderr":""}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Continue the git lifecycle');

        expect(toolService.executedToolNames, [
          'git_execute_command',
          'git_execute_command',
        ]);
        expect(
          toolService.executedToolArguments.map((args) => args['command']),
          [
            'config user.email canary@example.com',
            'add lib/git_lifecycle_note.txt',
          ],
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[1].single.name,
          'git_execute_command',
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered command progression.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage stops follow-up tools after git lifecycle succeeds', () async {
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'git-init',
          name: 'git_execute_command',
          arguments: const {
            'command': 'init',
            'working_directory': '/tmp/project',
          },
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'I will create the lifecycle file now.',
          toolCalls: [
            ToolCallInfo(
              id: 'write-note',
              name: 'write_file',
              arguments: const {
                'path': '/tmp/project/lib/git_lifecycle_note.txt',
                'content': 'CODING_GOAL_GIT_LIFECYCLE_OK',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will configure git email now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-email',
              name: 'git_execute_command',
              arguments: const {
                'command': 'config user.email canary@example.com',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will configure git name now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-name',
              name: 'git_execute_command',
              arguments: const {
                'command': 'config user.name "Canary Bot"',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will add the lifecycle file now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-add',
              name: 'git_execute_command',
              arguments: const {
                'command': 'add lib/git_lifecycle_note.txt',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will commit the lifecycle file now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-commit',
              name: 'git_execute_command',
              arguments: const {
                'command': 'commit -m "Add git lifecycle canary"',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will inspect status after the commit now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-status-after-commit',
              name: 'git_execute_command',
              arguments: const {
                'command': 'status',
                'working_directory': '/tmp/project',
                'reason': 'Inspect status after commit.',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will revert the commit now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-revert',
              name: 'git_execute_command',
              arguments: const {
                'command': 'revert --no-edit HEAD',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'I will inspect final status after the revert now.',
          toolCalls: [
            ToolCallInfo(
              id: 'git-status-after-revert',
              name: 'git_execute_command',
              arguments: const {
                'command': 'status',
                'working_directory': '/tmp/project',
                'reason': 'Inspect final status after revert.',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Now let me run the test to confirm everything passes.',
          toolCalls: [
            ToolCallInfo(
              id: 'wrong-extra-test',
              name: 'local_execute_command',
              arguments: const {
                'command': 'dart lib/canary_greeting_test.dart',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Recovery should not restart the completed lifecycle.',
          toolCalls: [
            ToolCallInfo(
              id: 'wrong-recovery-write',
              name: 'write_file',
              arguments: const {
                'path': '/tmp/project/lib/git_lifecycle_note.txt',
                'content': 'CODING_GOAL_GIT_LIFECYCLE_OK',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ],
      finalAnswerChunks: const ['This final answer should never be requested.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'git_execute_command': '',
        'write_file': '',
        'local_execute_command': '',
      },
      queuedResults: const {
        'git_execute_command': [
          '{"command":"git init","exit_code":0,"stdout":"Initialized empty Git repository\\n","stderr":""}',
          '{"command":"git config user.email canary@example.com","exit_code":0,"stdout":"","stderr":""}',
          '{"command":"git config user.name \\"Canary Bot\\"","exit_code":0,"stdout":"","stderr":""}',
          '{"command":"git add lib/git_lifecycle_note.txt","exit_code":0,"stdout":"","stderr":""}',
          '{"command":"git commit -m \\"Add git lifecycle canary\\"","exit_code":0,"stdout":"[main abc123] Add git lifecycle canary\\n","stderr":""}',
          '{"command":"git status","exit_code":0,"stdout":"On branch main\\nnothing to commit, working tree clean\\n","stderr":""}',
          '{"command":"git revert --no-edit HEAD","exit_code":0,"stdout":"[main def456] Revert \\"Add git lifecycle canary\\"\\n","stderr":""}',
          '{"command":"git status","exit_code":0,"stdout":"On branch main\\nnothing to commit, working tree clean\\n","stderr":""}',
        ],
        'write_file': [
          '{"path":"/tmp/project/lib/git_lifecycle_note.txt","bytes_written":28,"created":true}',
        ],
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _GitLifecycleGoalConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Complete the git lifecycle');

      expect(toolService.executedToolNames, [
        'git_execute_command',
        'write_file',
        'git_execute_command',
        'git_execute_command',
        'git_execute_command',
        'git_execute_command',
        'git_execute_command',
        'git_execute_command',
        'git_execute_command',
      ]);
      expect(
        toolService.executedToolNames,
        isNot(contains('local_execute_command')),
      );
      expect(
        toolService.executedToolNames
            .where((toolName) => toolName == 'write_file')
            .length,
        1,
      );
      expect(
        toolDataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        isNot(contains('coding_continuation_recovery')),
      );
      expect(toolDataSource.finalAnswerMessages, isEmpty);
      expect(
        toolNotifier.state.messages.last.content,
        contains('CODING_GOAL_GIT_LIFECYCLE_OK'),
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('Goal complete. Tests passed.'),
      );
      final goal = toolContainer
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.goal;
      expect(goal?.status, ConversationGoalStatus.completed);
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage flags success claims as unverified after command timeout',
    () async {
      const command = 'fvm flutter test --no-pub';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'test-command',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const [
          'Unit tests passed. 54 tests passed before timeout completed.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': '/tmp/project',
            'error': 'Command timed out after 60 seconds.',
            'timed_out': true,
            'timeout_ms': 60000,
            'process_terminated': true,
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run tests');

        expect(toolDataSource.toolResultBatches, isNotEmpty);
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          'local_execute_command',
        );
        // The original answer stays visible with the timeout correction
        // prepended, so the chat log is not wiped down to the notice.
        expect(
          toolNotifier.state.messages.last.content,
          startsWith('A command timed out'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Unit tests passed'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage repeats delayed process monitor after release timeout', () async {
    const releaseCommand =
        'bash tool/release_ios_macos.sh --macos-release-notes docs/releases/caverno-1.3.4.md';
    const monitorCommand =
        'sleep 30 && ps aux | grep -i "gen_snapshot\\|xcodebuild" | grep -v grep | head -5';
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'release-command',
          name: 'local_execute_command',
          arguments: const {
            'command': releaseCommand,
            'working_directory': '/tmp/project',
          },
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content:
              'The release timed out; I will check whether the build is still running.',
          toolCalls: [
            ToolCallInfo(
              id: 'monitor-command-1',
              name: 'local_execute_command',
              arguments: const {
                'command': monitorCommand,
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content:
              'AOT completed and export started; I will wait again and check export progress.',
          toolCalls: [
            ToolCallInfo(
              id: 'monitor-command-2',
              name: 'local_execute_command',
              arguments: const {
                'command': monitorCommand,
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The export process is no longer running.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['Release monitoring completed.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {'local_execute_command': 'unexpected command'},
      queuedResults: {
        'local_execute_command': [
          jsonEncode({
            'command': releaseCommand,
            'working_directory': '/tmp/project',
            'error': 'Command timed out after 60 seconds.',
            'timed_out': true,
            'timeout_ms': 60000,
          }),
          jsonEncode({
            'command': monitorCommand,
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout': 'gen_snapshot_arm64 is running',
            'stderr': '',
          }),
          jsonEncode({
            'command': monitorCommand,
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout': 'xcodebuild -exportArchive is running',
            'stderr': '',
          }),
        ],
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Release Caverno');

      expect(
        toolService.executedToolArguments
            .map((arguments) => arguments['command'])
            .toList(),
        [releaseCommand, monitorCommand, monitorCommand],
      );
      expect(toolDataSource.toolResultBatches, hasLength(3));
      expect(
        jsonDecode(toolDataSource.toolResultBatches[2].single.result),
        containsPair('stdout', 'xcodebuild -exportArchive is running'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('sendMessage dispatches process_start as command evidence', () async {
    const command = 'pwd';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'process-start-1',
          name: 'process_start',
          arguments: const {
            'command': command,
            'working_directory': '/tmp/project',
            'label': 'workspace check',
          },
        ),
      ],
      initialCompletionContent: 'I will start a background process.',
      finalAnswerChunks: const ['The background process was started.'],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'process_start': jsonEncode({
          'ok': true,
          'status': 'running',
          'job_id': 'proc_test_1',
          'pid': 123,
          'command': command,
          'working_directory': '/tmp/project',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Start a background process');

      expect(toolService.executedToolNames, [
        'process_start',
        'process_wait',
        'process_wait',
      ]);
      expect(
        toolService.executedToolArguments.first,
        containsPair('working_directory', '/tmp/project'),
      );
      expect(toolDataSource.toolResultBatches, hasLength(3));
      expect(
        toolDataSource.toolResultBatches.first.single.name,
        'process_start',
      );
      expect(
        toolNotifier.state.messages.last.content,
        isNot(contains('unexecuted')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('sendMessage blocks stale process_start results', () async {
    const command = 'bash tool/release_ios_macos.sh';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'process-start-stale',
          name: 'process_start',
          arguments: const {
            'command': command,
            'working_directory': '/tmp/project',
            'label': 'release',
          },
        ),
      ],
      initialCompletionContent: 'I will start the release.',
      finalAnswerChunks: const ['The release start result was stale.'],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'process_start': jsonEncode({
          'ok': true,
          'status': 'running',
          'job_id': 'proc_old_1',
          'pid': 123,
          'command': command,
          'working_directory': '/tmp/project',
          'started_at': '2026-01-01T00:00:00.000',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Release the app');

      expect(toolService.executedToolNames.first, 'process_start');
      expect(toolDataSource.toolResultBatches, isNotEmpty);
      final payload =
          jsonDecode(toolDataSource.toolResultBatches.first.single.result)
              as Map<String, dynamic>;
      expect(
        payload,
        containsPair('code', 'background_process_start_stale_result'),
      );
      expect(payload, containsPair('job_id', 'proc_old_1'));
      expect(
        payload['required_action'],
        contains('Do not report the command as newly started'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('sendMessage allows duplicate existing process_start results', () async {
    const command = 'bash tool/release_ios_macos.sh';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'process-start-duplicate',
          name: 'process_start',
          arguments: const {
            'command': command,
            'working_directory': '/tmp/project',
            'label': 'release',
          },
        ),
      ],
      initialCompletionContent: 'I will start the release.',
      finalAnswerChunks: const ['The existing release process is monitored.'],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'process_start': jsonEncode({
          'ok': true,
          'status': 'running',
          'duplicate_existing': true,
          'job_id': 'proc_old_running_1',
          'pid': 123,
          'command': command,
          'working_directory': '/tmp/project',
          'started_at': '2026-01-01T00:00:00.000',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Release the app');

      expect(toolService.executedToolNames.first, 'process_start');
      expect(toolDataSource.toolResultBatches, isNotEmpty);
      final payload =
          jsonDecode(toolDataSource.toolResultBatches.first.single.result)
              as Map<String, dynamic>;
      expect(payload, containsPair('duplicate_existing', true));
      expect(
        payload,
        isNot(containsPair('code', 'background_process_start_stale_result')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage dispatches process_list as read-only monitor query',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-list-1',
            name: 'process_list',
            arguments: const {'include_finished': true},
          ),
        ],
        initialCompletionContent: 'I will list the background jobs.',
        finalAnswerChunks: const ['Background process list is available.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_list': jsonEncode({
            'ok': true,
            'job_count': 1,
            'jobs': [
              {
                'job_id': 'proc_123',
                'status': 'running',
                'command': 'sleep 30',
                'working_directory': '/tmp',
              },
            ],
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Show background process status');

        expect(toolService.executedToolNames, ['process_list']);
        expect(
          toolDataSource.toolResultBatches.single.single.name,
          'process_list',
        );
        expect(
          toolDataSource.toolResultBatches.single.single.result,
          contains('"job_count":1'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('unexecuted')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks completion claims while a background process is running',
    () async {
      const command = 'bash tool/release_ios_macos.sh';
      const jobId = 'proc_release_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-start-release',
            name: 'process_start',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'release',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The release is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'The release is still running, so I will keep monitoring it.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'The release is still running after the follow-up check.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'The release is still running after the second check.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'The release is still running after the second check.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_start': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
        queuedResults: {
          'process_wait': [
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Uploading archive...',
              'stderr_tail': '',
            }),
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Uploading archive...',
              'stderr_tail': '',
            }),
          ],
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Uploading archive...',
              'stderr_tail': '',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        expect(toolService.executedToolNames, [
          'process_start',
          'process_wait',
          'process_wait',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(4));
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          'process_start',
        );
        expect(
          toolDataSource.toolResultBatches[1].single.name,
          'background_process_monitor',
        );
        final monitorPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'process_wait',
        );
        expect(
          monitorPayload,
          containsPair('code', 'background_process_still_running'),
        );
        expect(monitorPayload, containsPair('progress_report_required', true));
        expect(
          monitorPayload['required_action'],
          contains('Inspect stdout_tail, stderr_tail, elapsed_ms, and status'),
        );
        expect(
          monitorPayload['required_action'],
          contains('Do not just wait silently'),
        );
        expect(
          monitorPayload['progress_report_fields'],
          containsAll(const [
            'status',
            'elapsed_ms',
            'stdout_tail',
            'stderr_tail',
          ]),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('process_wait'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('complete.')),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage keeps monitoring when running-process feedback gets prose',
    () async {
      const command = 'bash tool/release_ios_macos.sh';
      const jobId = 'proc_release_prose_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-start-release',
            name: 'process_start',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'release',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The release is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'The release is still running, so I will wait and check again.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'The release is still running after the wait, so I will keep waiting.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'The release completed successfully.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The release completed successfully.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_start': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
        queuedResults: {
          'process_wait': [
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Upload still running',
              'stderr_tail': '',
            }),
            jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 0,
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Upload complete',
              'stderr_tail': '',
            }),
          ],
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Uploading archive...',
              'stderr_tail': '',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        expect(toolService.executedToolNames, [
          'process_start',
          'process_wait',
          'process_wait',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(4));
        expect(
          toolDataSource.toolResultBatches.map(
            (batch) => batch.map((result) => result.name).toList(),
          ),
          containsAllInOrder([
            ['process_start'],
            ['background_process_monitor'],
            ['process_wait'],
            ['process_wait'],
          ]),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('completed successfully'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('wait and check again')),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('still running after the wait')),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage repeats identical process_wait until process exits',
    () async {
      const command = 'bash tool/release_ios_macos.sh';
      const jobId = 'proc_release_repeat_wait_1';
      const waitArguments = {
        'job_id': jobId,
        'wait_ms': 5000,
        'working_directory': '/tmp/project',
      };
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-start-release-repeat-wait',
            name: 'process_start',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'release',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The release is running, so I will wait.',
            toolCalls: [
              ToolCallInfo(
                id: 'process-wait-repeat-1',
                name: 'process_wait',
                arguments: waitArguments,
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The release is still running, so I will wait again.',
            toolCalls: [
              ToolCallInfo(
                id: 'process-wait-repeat-2',
                name: 'process_wait',
                arguments: waitArguments,
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The release is still running, so I will wait again.',
            toolCalls: [
              ToolCallInfo(
                id: 'process-wait-repeat-3',
                name: 'process_wait',
                arguments: waitArguments,
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The release completed successfully.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The release completed successfully.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_start': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': true,
            'status': 'exited',
            'exit_code': 0,
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
            'stdout_tail': 'Release complete',
            'stderr_tail': '',
          }),
        },
        queuedResults: {
          'process_wait': [
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Current status: In Progress...',
              'stderr_tail': '',
            }),
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Current status: In Progress...',
              'stderr_tail': '',
            }),
            jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 0,
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Release complete',
              'stderr_tail': '',
            }),
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        expect(toolService.executedToolNames, [
          'process_start',
          'process_wait',
          'process_wait',
          'process_wait',
        ]);
        expect(toolService.executedToolArguments.sublist(1), [
          waitArguments,
          waitArguments,
          waitArguments,
        ]);
        expect(
          toolDataSource.toolResultBatches.map(
            (batch) => batch.map((result) => result.name).toList(),
          ),
          containsAllInOrder([
            ['process_start'],
            ['process_wait'],
            ['process_wait'],
            ['process_wait'],
          ]),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('completed successfully'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('unexecuted')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks completion claims while a background subagent is running',
    () async {
      const taskId = 'subagent_bg_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'subagent-result-1',
            name: 'get_subagent_result',
            arguments: const {'task_id': taskId},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The subagent task is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'The subagent is still running, so I will keep polling it.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['This final answer should not be requested.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'get_subagent_result': jsonEncode({
            'ok': true,
            'task_id': taskId,
            'status': 'running',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final notifier = toolContainer.read(chatNotifierProvider.notifier);
        final subagentTaskNotifier = toolContainer.read(
          subagentTaskNotifierProvider.notifier,
        );
        subagentTaskNotifier.register(
          SubagentTask(
            id: taskId,
            status: SubagentTaskStatus.running,
            description: 'background subagent compute',
            isBackground: true,
            startedAt: DateTime.now(),
          ),
        );

        await notifier.sendMessage('Check background subagent progress.');

        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          'get_subagent_result',
        );
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'get_subagent_result',
        );
        final monitorPayload =
            jsonDecode(toolDataSource.toolResultBatches.last.single.result)
                as Map<String, dynamic>;
        expect(monitorPayload, containsPair('code', 'subagent_still_running'));
        expect(
          monitorPayload,
          containsPair('required_action', contains('get_subagent_result')),
        );
        final blockedTasks =
            (monitorPayload['tasks'] as List<dynamic>?) ?? const [];
        final blockedTaskIds = blockedTasks
            .whereType<Map<String, dynamic>>()
            .map((task) => task['task_id']?.toString())
            .whereType<String>();
        expect(blockedTaskIds, contains(taskId));
        expect(notifier.state.messages.last.content, contains('still running'));
        expect(
          notifier.state.messages.last.content,
          isNot(contains('complete.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops follow-up tool calls after saved validation succeeds',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand: 'ls README.md',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host health\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'ls README.md',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the README task is complete.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-rewrite-after-validation',
                name: 'write_file',
                arguments: const {
                  'path': 'README.md',
                  'content': '# Host health\n\nRepeated rewrite\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/README.md","bytes_written":14}',
          'local_execute_command':
              '{"command":"ls README.md","exit_code":0,"stdout":"README.md\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolDataSource.toolResultToolDefinitionCounts.first,
          greaterThan(0),
        );
        expect(toolDataSource.toolResultToolDefinitionCounts.last, 0);
        expect(
          toolNotifier.state.messages.last.content,
          contains('README task is complete'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage rejects modified saved validation commands and recovers',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop-wrapper',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand: 'ls README.md',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final wrappedValidationCommand =
          'ls README.md && echo "Validation Successful" || '
          'echo "Validation Failed"';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: {
                  'command': wrappedValidationCommand,
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I will run the saved validation command exactly.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate-exact',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'ls README.md',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the README task is complete.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-rewrite-after-validation',
                name: 'write_file',
                arguments: const {
                  'path': 'README.md',
                  'content': '# Host Health Checker\n\nRepeated rewrite\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
          'local_execute_command':
              '{"exit_code":0,"stdout":"Validation Successful\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        final guardPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          guardPayload,
          containsPair('code', 'saved_validation_command_modified'),
        );
        expect(
          guardPayload,
          containsPair('saved_validation_command', 'ls README.md'),
        );
        expect(
          guardPayload,
          containsPair('attempted_command', wrappedValidationCommand),
        );
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('README task is complete'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage rejects saved validation commands with resolved paths',
    () async {
      final now = DateTime(2026, 4, 24, 12);
      final project = CodingProject(
        id: 'project-1',
        name: 'Tmp project',
        rootPath: '/tmp',
        createdAt: now,
        updatedAt: now,
      );
      final conversation = Conversation(
        id: 'conversation-tool-loop-resolved-validation-path',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 5)),
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand: 'cat README.md',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I will validate the file.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate-resolved',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'cat /tmp/README.md',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I will run the saved command exactly.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate-exact',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'cat README.md',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the README task is complete.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-rewrite-after-validation',
                name: 'write_file',
                arguments: const {
                  'path': 'README.md',
                  'content': '# Host Health Checker\n\nRepeated rewrite\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
          'local_execute_command':
              '{"command":"cat README.md","exit_code":0,"stdout":"# Host Health Checker\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        final guardPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          guardPayload,
          containsPair('code', 'saved_validation_command_modified'),
        );
        expect(
          guardPayload,
          containsPair('saved_validation_command', 'cat README.md'),
        );
        expect(
          guardPayload,
          containsPair('attempted_command', 'cat /tmp/README.md'),
        );
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('README task is complete'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage accepts read_file as cat saved validation evidence', () async {
    final now = DateTime(2026, 4, 24, 12);
    final project = CodingProject(
      id: 'project-1',
      name: 'Tmp project',
      rootPath: '/tmp',
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'conversation-tool-loop-read-file-cat-validation',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: now,
      updatedAt: now.add(const Duration(minutes: 5)),
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-readme',
            title: 'Create README.md with project description',
            targetFiles: ['README.md'],
            validationCommand: 'cat README.md',
            status: ConversationWorkflowTaskStatus.inProgress,
          ),
        ],
      ),
    );
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-write',
          name: 'write_file',
          arguments: const {
            'path': 'README.md',
            'content': '# Host Health Checker\n',
          },
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'I will read the file to validate it.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-read',
              name: 'read_file',
              arguments: const {'path': 'README.md'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content:
              'The saved validation command passed, so the README task is complete.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-rewrite-after-validation',
              name: 'write_file',
              arguments: const {
                'path': 'README.md',
                'content': '# Host Health Checker\n\nRepeated rewrite\n',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ],
      finalAnswerChunks: const ['This final answer should never be requested.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
        'read_file':
            '{"path":"/tmp/README.md","content":"# Host Health Checker\\n","size_bytes":22}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          () => _WorkflowTestConversationsNotifier(conversation),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create the README first');

      expect(toolService.executedToolNames, ['write_file', 'read_file']);
      expect(toolDataSource.finalAnswerMessages, isEmpty);
      expect(
        toolNotifier.state.messages.last.content,
        contains('README task is complete'),
      );
      expect(
        toolNotifier.state.messages.last.content,
        isNot(contains('This final answer should never be requested.')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  const untrustedWrapperCases = <_SavedValidationWrapperCase>[
    _SavedValidationWrapperCase(
      name: 'failure output',
      wrapperCommand: 'ls README.md && echo "Validation Failed"',
      commandResult:
          '{"exit_code":0,"stdout":"Validation Failed\\n","stderr":""}',
    ),
    _SavedValidationWrapperCase(
      name: 'empty success-or-failure output',
      wrapperCommand:
          'ls README.md && echo "Validation Successful" || echo "Validation Failed"',
      commandResult: '{"exit_code":0,"stdout":"","stderr":""}',
    ),
    _SavedValidationWrapperCase(
      name: 'different validation command',
      wrapperCommand:
          'ls CHANGELOG.md && echo "Validation Successful" || echo "Validation Failed"',
      commandResult:
          '{"exit_code":0,"stdout":"Validation Successful\\n","stderr":""}',
    ),
  ];

  for (final wrapperCase in untrustedWrapperCases) {
    test(
      'sendMessage rejects saved validation wrapper with ${wrapperCase.name}',
      () async {
        final outcome = await _runSavedValidationWrapperFollowUpScenario(
          wrapperCommand: wrapperCase.wrapperCommand,
          commandResult: wrapperCase.commandResult,
        );

        expect(
          outcome.executedToolNames,
          wrapperCase.name == 'different validation command'
              ? ['write_file', 'local_execute_command', 'write_file']
              : ['write_file', 'write_file'],
        );
        expect(outcome.finalAnswerMessages, isNotEmpty);
        expect(
          outcome.lastMessageContent,
          contains('rejected validation wrapper'),
        );
        expect(
          outcome.lastMessageContent,
          isNot(contains('saved validation command succeeded')),
        );
      },
    );
  }

  test(
    'sendMessage accepts natural stop after saved validation succeeds',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop-natural-stop',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand:
                  "test -f README.md && grep -q 'Host Health' README.md",
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command':
                      "test -f README.md && grep -q 'Host Health' README.md",
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the README task is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Natural stop final answer.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
          'local_execute_command':
              '{"command":"test -f README.md && grep -q \'Host Health\' README.md","exit_code":0,"stdout":"","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages.singleWhere(
          (message) => message.content.contains('[Tool: write_file]'),
        );
        expect(finalPrompt.content, isNot(contains('UNVERIFIED CHANGE:')));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Natural stop final answer.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage includes tool descriptions and identifier guardrails in the final tool prompt',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'get_router_health',
            arguments: const {'minutes': 30},
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'get_router_health':
              '{"top_affected_devices":[{"device_id":"c891fj-b","event_count":33}]}',
        },
        descriptions: const {
          'get_router_health':
              'Inspect router-side telemetry to assess whether the router or gateway path shows instability.',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Diagnose the router');

        final finalPrompt = toolDataSource.finalAnswerMessages.last.content;
        expect(
          finalPrompt,
          contains(
            'Description: Inspect router-side telemetry to assess whether the router or gateway path shows instability.',
          ),
        );
        expect(
          finalPrompt,
          contains(
            'Scope note: This is infrastructure-side telemetry. Identifiers may refer to the router, gateway, interfaces, or other monitored infrastructure rather than a client device.',
          ),
        );
        expect(
          finalPrompt,
          contains(
            'If the role of an identifier is not explicit in the payload, say it is ambiguous instead of guessing.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves tool-role final text as fallback assistant evidence',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_alpha',
            arguments: const {'path': 'alpha.txt'},
          ),
        ],
        toolRoleResponseContent:
            'The saved task is complete because the validation passed.',
        finalAnswerChunks: const [
          'I reviewed the tool results and outlined the next step.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_alpha': 'alpha result'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the file');

        expect(
          toolNotifier.takeLatestHiddenAssistantResponse(),
          'The saved task is complete because the validation passed.',
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal tool-role completion without final fallback',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 ping_cli.py google.com'},
          ),
        ],
        toolRoleResponseContent:
            'The task "Verify the CLI tool with a single ping execution" is complete. Validation passed successfully.',
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"python3 ping_cli.py google.com","exit_code":0,"stdout":"SUCCESS","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Verify the CLI tool');

        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The task "Verify the CLI tool with a single ping execution" is complete.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal tool-role completion that references a task id',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 test_ping.py'},
          ),
        ],
        toolRoleResponseContent:
            'The task `21871b16-b3eb-4b54-8906-35eef1e742ac` is now complete. Validation passed successfully.',
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"python3 test_ping.py","exit_code":0,"stdout":"TEST PASSED","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Verify the CLI tool');

        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The task `21871b16-b3eb-4b54-8906-35eef1e742ac` is now complete.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal file mutation completion without final fallback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 2),
        updatedAt: DateTime(2026, 6, 2),
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'tokyo_weather_2026-06-03.md',
              'content': '# Tokyo weather',
            },
          ),
        ],
        toolRoleResponseContent:
            'Done. Saved `/tmp/project/tokyo_weather_2026-06-03.md`.',
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this file write."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/project/tokyo_weather_2026-06-03.md","created":false,"bytes_written":648}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledAutoReviewSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Save the Tokyo weather report');

        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('/tmp/project/tokyo_weather_2026-06-03.md'),
        );
        expect(toolService.executedToolNames, ['write_file']);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage rejects terminal file mutation completion with optional follow-up',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 2),
        updatedAt: DateTime(2026, 6, 2),
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'tokyo_weather_2026-06-03.md',
              'content': '# Tokyo weather',
            },
          ),
        ],
        toolRoleResponseContent:
            'Done. Saved `/tmp/project/tokyo_weather_2026-06-03.md`. '
            'Do you want me to check another city?',
        finalAnswerChunks: const ['Final fallback based on the tool result.'],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this file write."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/project/tokyo_weather_2026-06-03.md","created":false,"bytes_written":648}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledAutoReviewSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Save the Tokyo weather report');

        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final fallback based on the tool result.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves tool-loop handoff text before follow-up tool calls',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_readme',
            arguments: const {'path': 'README.md'},
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-2',
            name: 'write_cli',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        intermediateToolRoleResponseContent:
            'I have completed the first task: Create README.md with usage instructions. The next task is Implement the ping CLI tool in ping_cli.py.',
        toolRoleResponseContent: '',
        finalAnswerChunks: const ['I continued with the next saved task.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_readme': '{"path":"README.md","bytes_written":120}',
          'write_cli': '{"path":"ping_cli.py","bytes_written":240}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Handle the first saved task');

        expect(
          toolNotifier.takeLatestHiddenAssistantResponse(),
          'I have completed the first task: Create README.md with usage instructions. The next task is Implement the ping CLI tool in ping_cli.py.',
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage prefers streamed no-tool handoff text over stale completion content',
    () async {
      final toolDataSource = _NoToolStreamingWithToolsDataSource(
        streamChunks: const [
          'The tool result shows that `README.md` was successfully created. The next task is "Create integration test to verify ping functionality".',
        ],
        completionContent:
            'The user wants me to implement the next pending task: "Create `README.md` with usage instructions".',
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_alpha': 'alpha result'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Continue with the next saved task');

        expect(
          toolNotifier.takeLatestHiddenAssistantResponse(),
          'The tool result shows that `README.md` was successfully created. The next task is "Create integration test to verify ping functionality".',
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'content tool calls that require approval are processed sequentially',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          '<tool_call>{"name":"write_file","arguments":{"path":"src/ping_utils.py","content":"print(1)","create_parents":true}}</tool_call>'
              '<tool_call>{"name":"write_file","arguments":{"path":"tests/test_ping_utils.py","content":"print(2)","create_parents":true}}</tool_call>',
        ],
        ['Finished applying the requested files.'],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/content-tools/file.py","bytes_written":1,"created":true}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'tmp',
        rootPath: '/tmp/content-tools-project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the ping utility files');
        await Future<void>.delayed(Duration.zero);

        final firstPending = toolNotifier.state.pendingFileOperation;
        expect(firstPending, isNotNull);
        expect(
          firstPending!.path,
          '/tmp/content-tools-project/src/ping_utils.py',
        );

        toolNotifier.resolveFileOperation(id: firstPending.id, approved: true);
        await Future<void>.delayed(Duration.zero);

        final secondPending = toolNotifier.state.pendingFileOperation;
        expect(secondPending, isNotNull);
        expect(
          secondPending!.path,
          '/tmp/content-tools-project/tests/test_ping_utils.py',
        );

        toolNotifier.resolveFileOperation(id: secondPending.id, approved: true);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolNotifier.state.pendingFileOperation, isNull);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Finished applying the requested files.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('content tool failures are forwarded into continuation prompts', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_call>{"name":"google","arguments":{}}</tool_call>'
            '<tool_call>{"name":"write_file","arguments":{"path":"config/hosts.yaml","content":"hosts: []","create_parents":true}}</tool_call>',
      ],
      ['Continue with the available configuration tooling only.'],
    ]);
    final toolService = _SelectiveFakeMcpToolService(
      results: const {
        'write_file':
            '{"path":"/tmp/content-tools/config/hosts.yaml","bytes_written":9,"created":true}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'tmp',
      rootPath: '/tmp/content-tools-project',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create the config files');
      await Future<void>.delayed(Duration.zero);

      final pending = toolNotifier.state.pendingFileOperation;
      expect(pending, isNotNull);
      toolNotifier.resolveFileOperation(id: pending!.id, approved: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(streamingDataSource.requests, hasLength(2));
      final continuationPrompt = streamingDataSource.requests.last.last.content;
      expect(continuationPrompt, contains('[Result of google]'));
      expect(continuationPrompt, contains('"code":"tool_not_available"'));
      expect(
        continuationPrompt,
        contains(
          'If the latest tool result already completed the current saved task or confirmed the saved validation command, do not call more tools for that task and finish with a brief text answer.',
        ),
      );
      expect(
        continuationPrompt,
        contains(
          'If a tool result reports code=tool_not_available, do not retry that tool name or alias variants',
        ),
      );
      expect(
        continuationPrompt,
        contains(
          'If a tool result reports code=edit_mismatch or says old_text was not found in the target file',
        ),
      );
      expect(continuationPrompt, contains('[Result of write_file]'));
      expect(
        toolNotifier.state.messages.last.content,
        contains('Continue with the available configuration tooling only.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage blocks completion claims while a background local command is running',
    () async {
      const command = 'bash tool/run_long_task.sh';
      const jobId = 'proc_local_background_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'long task',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The long task is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'The long task is still running, so I will keep monitoring.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['This final answer should not be requested.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'task is active',
              'stderr_tail': '',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run a long task');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'process_wait',
        ]);
        expect(
          toolService.executedToolArguments.first,
          containsPair('background', true),
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          'local_execute_command',
        );
        expect(
          toolDataSource.toolResultBatches[1].single.name,
          'background_process_monitor',
        );
        final monitorPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          monitorPayload,
          containsPair('code', 'background_process_still_running'),
        );
        expect(monitorPayload, containsPair('progress_report_required', true));
        expect(
          monitorPayload['required_action'],
          contains('Inspect stdout_tail, stderr_tail, elapsed_ms, and status'),
        );
        expect(
          monitorPayload['required_action'],
          contains('Do not just wait silently'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('process_wait'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('complete.')),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves streamed final answer text on background repair follow-up',
    () async {
      const command = 'bash tool/run_long_task.sh';
      const jobId = 'proc_local_background_stream_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-stream-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'long task',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'process-status-1',
                name: 'process_status',
                arguments: const {'job_id': jobId},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const ['The long task is complete.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'elapsed_ms': 12000,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_status': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
        queuedResults: {
          'process_wait': [
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'elapsed_ms': 14000,
              'command': command,
              'working_directory': '/tmp/project',
            }),
            jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 0,
              'job_id': jobId,
              'pid': 123,
              'elapsed_ms': 30000,
              'command': command,
              'working_directory': '/tmp/project',
            }),
          ],
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'task is running',
              'stderr_tail': '',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run a long task');

        expect(
          toolService.executedToolNames,
          containsAll(<String>[
            'local_execute_command',
            'process_status',
            'process_wait',
            'process_wait',
          ]),
        );
        expect(
          toolDataSource.toolResultBatches,
          hasLength(greaterThanOrEqualTo(4)),
        );
        expect(
          toolService.executedToolNames,
          hasLength(greaterThanOrEqualTo(4)),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('The long task is complete.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('<tool_use>'),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage finishes streaming when final background monitor repair has no follow-up',
    () async {
      const command = 'bash tool/run_long_task.sh';
      const jobId = 'proc_local_finalize_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-finalize-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'long task',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(
            content:
                'Still running. I will continue monitoring status before reporting completion.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'Still running. One more check is required before completion.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I am waiting for the background completion status.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Background task completed successfully.'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
        queuedResults: {
          'process_wait': [
            jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 1,
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
            }),
          ],
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'failed',
              'exit_code': 1,
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'error': 'process exited with error',
              'stdout_tail': 'working',
              'stderr_tail': '',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run a long background task');

        expect(
          toolService.executedToolNames,
          containsAll(<String>['local_execute_command', 'process_wait']),
        );
        expect(
          toolDataSource.toolResultBatches,
          hasLength(greaterThanOrEqualTo(3)),
        );
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'background_process_monitor',
        );
        expect(
          toolDataSource.toolResultBatches[1].single.result,
          contains('"status":"exited"'),
        );
        expect(toolNotifier.state.isLoading, isFalse);
        expect(toolNotifier.state.messages.last.role, MessageRole.assistant);
        expect(toolNotifier.state.messages.last.isStreaming, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'Still running. One more check is required before completion.',
          ),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts completion after local_execute_command background wait succeeds',
    () async {
      const command = 'bash tool/run_long_task.sh';
      const jobId = 'proc_local_wait_success_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'long task',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            toolCalls: [
              ToolCallInfo(
                id: 'process-wait-1',
                name: 'process_wait',
                arguments: {'job_id': jobId, 'wait_ms': 1000},
              ),
            ],
            content: 'I will wait for the background process.',
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The background process completed successfully.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': true,
            'status': 'exited',
            'exit_code': 0,
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run a long task');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'process_wait',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          'local_execute_command',
        );
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'process_wait',
        );
        expect(toolNotifier.state.messages.last.content, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('The requested command was not executed')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage keeps blocking when multiple background jobs are not all complete',
    () async {
      const command1 = 'bash tool/run_long_task.sh';
      const command2 = 'bash tool/run_build_task.sh';
      const jobId1 = 'proc_local_running_1';
      const jobId2 = 'proc_wait_success_2';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command1,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'long task 1',
            },
          ),
          ToolCallInfo(
            id: 'process-wait-1',
            name: 'process_wait',
            arguments: {'job_id': jobId2, 'wait_ms': 1000},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The long task completed and this message should be accepted.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'One process is still running, so I will keep monitoring.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId1,
            'pid': 123,
            'command': command1,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': true,
            'status': 'exited',
            'exit_code': 0,
            'job_id': jobId2,
            'pid': 456,
            'command': command2,
            'working_directory': '/tmp/project',
          }),
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId1: jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId1,
              'pid': 123,
              'command': command1,
              'working_directory': '/tmp/project',
              'stdout_tail': 'task 1 is active',
              'stderr_tail': '',
            }),
            jobId2: jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 0,
              'job_id': jobId2,
              'pid': 456,
              'command': command2,
              'working_directory': '/tmp/project',
              'stdout_tail': 'done',
              'stderr_tail': '',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run two long tasks');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'process_wait',
          'process_wait',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches.first.map((result) => result.name),
          containsAllInOrder(const ['local_execute_command', 'process_wait']),
        );
        expect(
          toolDataSource.toolResultBatches[1].single.name,
          'background_process_monitor',
        );
        final monitorPayload =
            jsonDecode(toolDataSource.toolResultBatches[1].single.result)
                as Map<String, dynamic>;
        expect(
          monitorPayload,
          containsPair('code', 'background_process_still_running'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('process_wait'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('should be accepted')),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks completion when process_wait indicates background process failed',
    () async {
      const command = 'bash tool/run_long_task.sh';
      const jobId = 'proc_local_wait_failed_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'failing long task',
            },
          ),
          ToolCallInfo(
            id: 'process-wait-1',
            name: 'process_wait',
            arguments: {'job_id': jobId, 'wait_ms': 1000},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The long task finished successfully, so I will stop here.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content:
                'The background process exited with an error, so I will keep monitoring.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': true,
            'status': 'exited',
            'exit_code': 1,
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 1,
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': '',
              'stderr_tail': 'command failed',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run a failing long task');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'process_wait',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'background_process_monitor',
        );
        final monitorPayload =
            jsonDecode(toolDataSource.toolResultBatches.last.single.result)
                as Map<String, dynamic>;
        expect(
          monitorPayload,
          containsPair('code', 'background_process_failed'),
        );
        expect(monitorPayload['error']?.toString() ?? '', contains('non-zero'));
        expect(toolNotifier.state.messages.last.content, contains('error'));
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage keeps completion blocked when process status is unverified',
    () async {
      const command = 'bash tool/run_long_task.sh';
      const jobId = 'proc_local_wait_unknown_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'local-exec-background-1',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'background': true,
              'label': 'uncertain long task',
            },
          ),
          ToolCallInfo(
            id: 'process-wait-1',
            name: 'process_wait',
            arguments: {'job_id': jobId, 'wait_ms': 1000},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The long task completed.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Status was unavailable, so I will keep monitoring.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': false,
            'status': 'unknown',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: {
            jobId: jsonEncode({
              'ok': true,
              'status': 'unknown',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': '',
              'stderr_tail': 'status could not be read',
            }),
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run a long task');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'process_wait',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'background_process_monitor',
        );
        final monitorPayload =
            jsonDecode(toolDataSource.toolResultBatches.last.single.result)
                as Map<String, dynamic>;
        expect(
          monitorPayload,
          containsPair('code', 'background_process_status_unverified'),
        );
        expect(monitorPayload['required_action'], contains('process_list'));
        final jobs = monitorPayload['jobs'] as List<dynamic>;
        expect(jobs, hasLength(1));
        final job = jobs.single as Map<String, dynamic>;
        expect(job, containsPair('status', 'unknown'));
        expect(job, containsPair('stderr_tail', 'status could not be read'));
        expect(
          toolNotifier.state.messages.last.content,
          contains('monitoring'),
        );
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage removes streamed completion claim when background process is still running',
    () async {
      const command = 'bash tool/release_ios_macos.sh';
      const jobId = 'proc_stream_release_running_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-start-release',
            name: 'process_start',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'release',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(
            content: 'The release is still running; I will wait again.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'The release failed with exit code 1.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'The iOS IPA export completed and the release is complete.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_start': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
        },
        queuedResults: {
          'process_wait': [
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Building App Store IPA...',
              'stderr_tail': '',
            }),
            jsonEncode({
              'ok': true,
              'status': 'running',
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': 'Building App Store IPA...',
              'stderr_tail': '',
            }),
            jsonEncode({
              'ok': true,
              'status': 'exited',
              'exit_code': 1,
              'job_id': jobId,
              'pid': 123,
              'command': command,
              'working_directory': '/tmp/project',
              'stdout_tail': '',
              'stderr_tail':
                  'exportArchive: export options require signingStyle manual',
            }),
          ],
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(
          statusResults: const {},
          queuedStatusResults: {
            jobId: [
              jsonEncode({
                'ok': true,
                'status': 'running',
                'job_id': jobId,
                'pid': 123,
                'command': command,
                'working_directory': '/tmp/project',
                'stdout_tail': 'Building App Store IPA...',
                'stderr_tail': '',
              }),
              jsonEncode({
                'ok': true,
                'status': 'exited',
                'exit_code': 1,
                'job_id': jobId,
                'pid': 123,
                'command': command,
                'working_directory': '/tmp/project',
                'stdout_tail': '',
                'stderr_tail':
                    'exportArchive: export options require signingStyle manual',
              }),
            ],
          },
        ),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolDataSource.toolResultBatches
              .expand((batch) => batch)
              .map((result) => result.name),
          contains('background_process_monitor'),
        );
        expect(toolService.executedToolNames, [
          'process_start',
          'process_wait',
          'process_wait',
          'process_wait',
        ]);
        final finalContent = toolNotifier.state.messages.last.content;
        expect(finalContent, isNot(contains('iOS IPA export completed')));
        expect(finalContent, isNot(contains('release is complete')));
        expect(finalContent, contains('exit code 1'));
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks streamed release success after exit zero partial failure',
    () async {
      const command = 'bash tool/release_ios_macos.sh';
      const jobId = 'proc_release_partial_failure_1';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'process-start-release-partial',
            name: 'process_start',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'release',
            },
          ),
          ToolCallInfo(
            id: 'process-wait-release-partial',
            name: 'process_wait',
            arguments: const {'job_id': jobId, 'wait_ms': 1000},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
          ChatCompletionResult(
            content:
                'macOS completed, but iOS failed because the App Store build number already exists.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'Release complete. iOS uploaded to App Store Connect and macOS uploaded to S3.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'process_start': jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
          }),
          'process_wait': jsonEncode({
            'ok': true,
            'status': 'exited',
            'exit_code': 0,
            'job_id': jobId,
            'pid': 123,
            'command': command,
            'working_directory': '/tmp/project',
            'stdout_tail': 'macOS Sparkle release uploaded successfully.',
            'stderr_tail':
                'Encountered error while creating the IPA: error: exportArchive The bundle version must be higher than the previously uploaded version: 17.',
          }),
        },
      );
      final monitorService = BackgroundProcessMonitorService(
        tools: _FakeBackgroundProcessTools(statusResults: const {}),
        pollInterval: const Duration(minutes: 1),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          backgroundProcessMonitorServiceProvider.overrideWithValue(
            monitorService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final monitorResults = toolDataSource.toolResultBatches
            .expand((batch) => batch)
            .where((result) => result.name == 'background_process_monitor')
            .toList(growable: false);
        expect(monitorResults, isNotEmpty);
        final monitorPayload =
            jsonDecode(monitorResults.single.result) as Map<String, dynamic>;
        expect(
          monitorPayload,
          containsPair('code', 'background_process_partial_failure'),
        );
        final finalContent = toolNotifier.state.messages.last.content;
        expect(finalContent, isNot(contains('iOS uploaded')));
        expect(finalContent, isNot(contains('Release complete')));
        expect(finalContent, contains('iOS failed'));
      } finally {
        monitorService.dispose();
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage flags streamed success claim after non-zero command exit',
    () async {
      const command = 'bash tool/release_ios_macos.sh';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'release-command',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'release check',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: const [
          'macOS upload completed successfully and the release is complete.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': '/tmp/project',
            'exit_code': -15,
            'stdout':
                'upload: build/macos_sparkle_updates/Caverno.zip to s3://bucket/Caverno.zip',
            'stderr': '',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');

        expect(toolService.executedToolNames, ['local_execute_command']);
        final finalContent = toolNotifier.state.messages.last.content;
        // Correction is prepended; the original answer remains in the log.
        expect(
          finalContent,
          startsWith('A command exited with non-zero exit code'),
        );
        expect(finalContent, contains('upload completed successfully'));
        expect(finalContent, contains('release is complete'));
        expect(finalContent, contains('non-zero exit code'));
        expect(finalContent, contains('-15'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage flags CJK committed claim after non-zero command exit',
    () async {
      const command = 'git commit -m "fix: update settings"';
      final committedClaim = String.fromCharCodes(const [
        0x524d,
        0x306e,
        0x30b3,
        0x30df,
        0x30c3,
        0x30c8,
        0x3067,
        0x65e2,
        0x306b,
        0x30b3,
        0x30df,
        0x30c3,
        0x30c8,
        0x6e08,
        0x307f,
        0x3060,
        0x3063,
        0x305f,
        0x3088,
        0x3046,
        0x3067,
        0x3059,
        0x3002,
      ]);
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'commit-command',
            name: 'local_execute_command',
            arguments: const {
              'command': command,
              'working_directory': '/tmp/project',
              'label': 'Commit changes',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: [committedClaim],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': '/tmp/project',
            'exit_code': 1,
            'stdout':
                'On branch fix/mobile-hide-desktop-settings\nnothing to commit, working tree clean\n',
            'stderr': '',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Commit the changes');

        expect(toolService.executedToolNames, ['local_execute_command']);
        final finalContent = toolNotifier.state.messages.last.content;
        // Correction is prepended; the original claim remains in the log.
        expect(
          finalContent,
          startsWith('A command exited with non-zero exit code'),
        );
        expect(finalContent, contains(committedClaim));
        expect(finalContent, contains('non-zero exit code'));
        expect(finalContent, contains('1'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage flags CJK normal operation claim after failed run_tests',
    () async {
      final normalOperationClaim = String.fromCharCodes(const [
        0x30c6,
        0x30b9,
        0x30c8,
        0x3092,
        0x5b9f,
        0x884c,
        0x3057,
        0x3001,
        0x6b63,
        0x5e38,
        0x306b,
        0x52d5,
        0x4f5c,
        0x3059,
        0x308b,
        0x3053,
        0x3068,
        0x3092,
        0x78ba,
        0x8a8d,
        0x3057,
        0x307e,
        0x3057,
        0x305f,
        0x3002,
      ]);
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'dart-test',
            name: 'run_tests',
            arguments: const {
              'test_path': 'test/prime_numbers_pkg_test.dart',
              'working_directory': '/tmp/project',
              'runner': 'dart',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(content: '', finishReason: 'stop'),
        ],
        finalAnswerChunks: [normalOperationClaim],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': "dart test 'test/prime_numbers_pkg_test.dart'",
            'working_directory': '/tmp/project',
            'exit_code': 1,
            'stdout': '00:00 +0 -1: Some tests failed.\n',
            'stderr': '',
          }),
        },
      );
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run the Dart package test');

        expect(toolService.executedToolNames, ['local_execute_command']);
        final finalContent = toolNotifier.state.messages.last.content;
        // Correction is prepended; the original claim remains in the log.
        expect(
          finalContent,
          startsWith('A command exited with non-zero exit code'),
        );
        expect(finalContent, contains(normalOperationClaim));
        expect(finalContent, contains('non-zero exit code'));
        expect(finalContent, contains('1'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage preserves success claim after later command success', () async {
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'create-branch',
          name: 'local_execute_command',
          arguments: const {
            'command': 'git checkout -b chore/update-fvm-3.44.1',
            'working_directory': '/tmp/project',
            'label': 'Create branch',
          },
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'stage-ignored-file',
              name: 'local_execute_command',
              arguments: const {
                'command': 'git add .fvm/fvm_config.json AGENTS.md',
                'working_directory': '/tmp/project',
                'label': 'Stage files',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: '.fvm is ignored, so I will stage AGENTS.md only.',
          toolCalls: [
            ToolCallInfo(
              id: 'stage-agents',
              name: 'local_execute_command',
              arguments: const {
                'command': 'git add AGENTS.md',
                'working_directory': '/tmp/project',
                'label': 'Stage AGENTS.md',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Staged AGENTS.md. I will commit it now.',
          toolCalls: [
            ToolCallInfo(
              id: 'commit-agents',
              name: 'local_execute_command',
              arguments: const {
                'command':
                    'git commit -m "chore: update FVM Flutter version from 3.44.0 to 3.44.1"',
                'working_directory': '/tmp/project',
                'label': 'Commit AGENTS.md',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ],
      finalAnswerChunks: const [
        'Done. Branch chore/update-fvm-3.44.1 was created and commit 1c387ff9 completed successfully.',
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'local_execute_command': ''},
      queuedResults: {
        'local_execute_command': [
          jsonEncode({
            'command': 'git checkout -b chore/update-fvm-3.44.1',
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout': '',
            'stderr': "Switched to a new branch 'chore/update-fvm-3.44.1'\n",
          }),
          jsonEncode({
            'command': 'git add .fvm/fvm_config.json AGENTS.md',
            'working_directory': '/tmp/project',
            'exit_code': 1,
            'stdout': '',
            'stderr':
                'The following paths are ignored by one of your .gitignore files:\n.fvm\n',
          }),
          jsonEncode({
            'command': 'git add AGENTS.md',
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout': '',
            'stderr': '',
          }),
          jsonEncode({
            'command':
                'git commit -m "chore: update FVM Flutter version from 3.44.0 to 3.44.1"',
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout':
                '[chore/update-fvm-3.44.1 1c387ff9] chore: update FVM Flutter version from 3.44.0 to 3.44.1\n',
            'stderr': '',
          }),
        ],
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create a branch and commit');

      expect(toolService.executedToolNames, [
        'local_execute_command',
        'local_execute_command',
        'local_execute_command',
        'local_execute_command',
      ]);
      final finalContent = toolNotifier.state.messages.last.content;
      expect(finalContent, contains('completed successfully'));
      expect(finalContent, isNot(contains('non-zero exit code')));
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'Foundation Models suppresses repeated successful content tool calls',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          '<tool_use>{"name":"echo_marker","arguments":{"marker":"FOUNDATION_REPEAT_OK"}}</tool_use>',
        ],
        [
          '<tool_use>{"name":"echo_marker","arguments":{"marker":"FOUNDATION_REPEAT_OK"}}</tool_use>',
        ],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {
          'echo_marker': '{"marker":"FOUNDATION_REPEAT_OK","status":"ok"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _AppleContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run the marker tool once.');
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, ['echo_marker']);
        expect(streamingDataSource.requests, hasLength(2));
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('already ran with the same arguments'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('<tool_use>')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('content tool results are exposed for workflow progress', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_call>{"name":"local_execute_command","arguments":{"command":"pwd"}}</tool_call>',
      ],
      ['Validation complete.'],
    ]);
    final toolService = _FakeMcpToolService(
      results: const {
        'local_execute_command':
            '{"command":"pwd","exit_code":0,"stdout":"/tmp/content-tools-project","stderr":""}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'tmp',
      rootPath: '/tmp/content-tools-project',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Run the saved validation command');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final latestResults = toolNotifier.takeLatestToolResults();
      expect(latestResults, hasLength(1));
      expect(latestResults.single.name, 'local_execute_command');
      expect(latestResults.single.arguments['command'], 'pwd');
      expect(latestResults.single.result, contains('"exit_code":0'));
      expect(toolNotifier.takeLatestToolResults(), isEmpty);
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'incomplete content tool calls are recovered before finalizing',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          'Checking clients.\n'
              '<tool_use>{"name":"arp","arguments":{"ip_version":"all"}}',
        ],
        ['Client analysis complete.'],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {
          'arp': '{"entries":15,"table":[{"ip":"192.168.100.1"}]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Deep dive clients');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, contains('arp'));
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Client analysis complete.'),
        );
        expect(
          toolNotifier.state.messages
              .map((message) => message.content)
              .join('\n'),
          isNot(contains('<tool_use>')),
        );

        final continuationRequest = streamingDataSource.requests.last;
        final assistantHistory = continuationRequest
            .where((message) => message.role == MessageRole.assistant)
            .map((message) => message.content)
            .join('\n');
        expect(assistantHistory, isNot(contains('<tool_use>')));
        expect(assistantHistory, isNot(contains('<tool_result>')));
        expect(continuationRequest.last.content, contains('[Result of arp]'));
        expect(
          continuationRequest.last.content,
          contains('Do not write <tool_result> tags'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'fenced tool-name continuation after incomplete tool call is recovered',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        ['Release docs lookup.\n<tool_use>...'],
        [
          'First I will inspect the release files.\n\n'
              '```tool_name\nread_file\n```\n\n'
              '```tool_name\nlist_directory\n```',
        ],
        ['No release command has been executed yet.'],
      ]);
      final toolService = _FakeMcpToolService(results: const {});
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Release the app');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(streamingDataSource.requests, hasLength(3));
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('No release command has been executed yet.'),
        );
        expect(
          toolNotifier.state.messages
              .map((message) => message.content)
              .join('\n'),
          isNot(contains('```tool_name')),
        );

        final continuationPrompt =
            streamingDataSource.requests.last.last.content;
        expect(
          continuationPrompt,
          contains('[Assistant tool-name block ignored]'),
        );
        expect(
          continuationPrompt,
          contains('No tool was executed from the fenced tool_name block'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('assistant-authored tool results are ignored and recovered', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_result>{"name":"arp","summary":"Completed","details":["entries: 15"]}</tool_result>',
      ],
      ['Answering from verified prior results only.'],
    ]);
    final toolService = _FakeMcpToolService(
      results: const {'arp': '{"entries":15}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Deep dive clients');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, isEmpty);
      expect(toolNotifier.state.isLoading, isFalse);
      expect(
        toolNotifier.state.messages.last.content,
        contains('Answering from verified prior results only.'),
      );
      expect(
        toolNotifier.state.messages
            .map((message) => message.content)
            .join('\n'),
        isNot(contains('<tool_result>')),
      );

      final continuationPrompt = streamingDataSource.requests.last.last.content;
      expect(
        continuationPrompt,
        contains('[Assistant-authored tool_result ignored]'),
      );
      expect(
        continuationPrompt,
        contains('Tool results must come from executed tools only.'),
      );
      expect(
        continuationPrompt,
        contains('exact no-tool recovery or echo requests'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'assistant-authored tool result empty continuation uses safe fallback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          '<tool_result>{"name":"arp","summary":"Completed","details":["entries: 15"]}</tool_result>',
        ],
        const <String>[],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {'arp': '{"entries":15}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Deep dive clients');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('I ignored an assistant-authored tool_result'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('No trusted tool result is available from that tag.'),
        );
        expect(
          toolNotifier.state.messages
              .map((message) => message.content)
              .join('\n'),
          isNot(contains('<tool_result>')),
        );

        final continuationPrompt =
            streamingDataSource.requests.last.last.content;
        expect(
          continuationPrompt,
          contains('[Assistant-authored tool_result ignored]'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'tool-aware no-tool response recovers assistant-authored tool results before stripping',
    () async {
      final conversationRepository = _FakeConversationRepository();
      const assistantToolResult =
          '<tool_result>{"name":"arp","summary":"Completed","details":["entries: 15"]}</tool_result>';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialStreamChunks: const [assistantToolResult],
        initialCompletionContent: assistantToolResult,
        finalAnswerChunks: const [
          'Answering from verified prior results only.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'arp': '{"entries":15}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Deep dive clients');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Answering from verified prior results only.'),
        );
        expect(
          toolNotifier.state.messages
              .map((message) => message.content)
              .join('\n'),
          isNot(contains('<tool_result>')),
        );
        expect(dataSource.finalAnswerRequestMessages, hasLength(1));
        expect(
          dataSource.finalAnswerRequestMessages.single.last.content,
          contains('[Assistant-authored tool_result ignored]'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'tool-aware no-tool response recovers incomplete content tool calls before stripping',
    () async {
      final conversationRepository = _FakeConversationRepository();
      const marker = 'INLINE_RECOVERY_OK';
      const toolName = 'inline_recovery_marker';
      const incompleteToolUse =
          'Starting inline recovery canary.\n'
          '<tool_use>{"name":"$toolName","arguments":{"marker":"$marker"}}';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialStreamChunks: const [
          'Starting inline recovery canary.\n',
          '<tool_use>{"name":"$toolName","arguments":{"marker":"$marker"}}',
        ],
        initialCompletionContent: incompleteToolUse,
        finalAnswerChunks: const [marker],
      );
      final toolService = _FakeMcpToolService(
        results: const {toolName: '{"marker":"$marker"}'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run inline recovery');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, contains(toolName));
        expect(toolNotifier.state.isLoading, isFalse);
        expect(toolNotifier.state.messages.last.content, contains(marker));
        expect(
          toolNotifier.state.messages
              .map((message) => message.content)
              .join('\n'),
          isNot(contains('<tool_use>')),
        );
        expect(dataSource.finalAnswerRequestMessages, hasLength(1));
        expect(
          dataSource.finalAnswerRequestMessages.single.last.content,
          contains('[Result of $toolName]'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage retries native tool stream format failures with embedded tags',
    () async {
      final dataSource = _NativeToolFormatFallbackDataSource([
        [
          '<tool_call>{"name":"read_file","arguments":{"path":"pubspec.yaml"}}</tool_call>',
        ],
        ['Recovered with embedded tool tags.'],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': '{"path":"pubspec.yaml","content":"name: caverno"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect pubspec');
        for (var i = 0; i < 8; i += 1) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(dataSource.toolAwareRequests, hasLength(1));
        expect(dataSource.plainRequests, hasLength(2));
        expect(
          dataSource.plainRequests.first
              .where((message) => message.role == MessageRole.system)
              .map((message) => message.content)
              .join('\n'),
          contains('use Caverno textual tool-call tags'),
        );
        expect(toolService.executedToolNames, ['read_file']);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered with embedded tool tags.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('content tool continuations ignore display-only print tool calls', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_call>{"name":"print","arguments":{"text":"preview"}}</tool_call>'
            '<tool_call>{"name":"write_file","arguments":{"path":"config/hosts.yaml","content":"hosts: []","create_parents":true}}</tool_call>',
      ],
      ['Continue with the available configuration tooling only.'],
    ]);
    final toolService = _SelectiveFakeMcpToolService(
      results: const {
        'write_file':
            '{"path":"/tmp/content-tools/config/hosts.yaml","bytes_written":9,"created":true}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'tmp',
      rootPath: '/tmp/content-tools-project',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create the config files');
      await Future<void>.delayed(Duration.zero);

      final pending = toolNotifier.state.pendingFileOperation;
      expect(pending, isNotNull);
      toolNotifier.resolveFileOperation(id: pending!.id, approved: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(streamingDataSource.requests, hasLength(2));
      final continuationPrompt = streamingDataSource.requests.last.last.content;
      expect(continuationPrompt, isNot(contains('[Result of print]')));
      expect(
        continuationPrompt,
        isNot(contains('"code":"tool_not_available"')),
      );
      expect(continuationPrompt, contains('[Result of write_file]'));
      expect(
        toolNotifier.state.messages.last.content,
        contains('Continue with the available configuration tooling only.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'content tool continuations fall back to non-streaming completion on stream errors',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final dataSource = _ContinuationFallbackChatDataSource();
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file':
              '{"path":"/tmp/content-tools-project/src/config_loader.py","content":"class ConfigLoader:\\n    pass\\n"}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'tmp',
        rootPath: '/tmp/content-tools-project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the config loader');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(dataSource.streamRequests, hasLength(2));
        expect(dataSource.completionRequests, isNotEmpty);
        expect(
          dataSource.completionRequests.first.last.content,
          contains('Continue the task using the following tool results.'),
        );
        expect(
          dataSource.completionRequests.first.last.content,
          contains('TOOL RESULT EXACT PRESERVATION:'),
        );
        expect(toolNotifier.state.isLoading, isFalse);
        expect(toolNotifier.state.error, isNull);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered continuation after stream failure.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage materializes a deferred coding draft thread', () async {
    final conversationRepository = _FakeConversationRepository();
    final dataSource = _QueuedStreamingChatDataSource(const [
      ['Draft thread created.'],
    ]);
    final project = CodingProject(
      id: 'project-1',
      name: 'caverno',
      rootPath: '/tmp/caverno',
      createdAt: DateTime(2026, 6, 3, 17),
      updatedAt: DateTime(2026, 6, 3, 17),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      threadContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
            createFreshOnFirstOpen: true,
            deferFreshConversationCreation: true,
          );
      expect(
        threadContainer.read(conversationsNotifierProvider).currentConversation,
        isNull,
      );
      expect(
        conversationRepository.getAll().where(
          (conversation) => conversation.workspaceMode == WorkspaceMode.coding,
        ),
        isEmpty,
      );

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Build the draft composer flow');

      final currentConversation = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(currentConversation, isNotNull);
      expect(currentConversation!.workspaceMode, WorkspaceMode.coding);
      expect(currentConversation.normalizedProjectId, project.id);
      expect(
        currentConversation.messages.first.content,
        'Build the draft composer flow',
      );
      expect(
        conversationRepository.getAll().where(
          (conversation) => conversation.workspaceMode == WorkspaceMode.coding,
        ),
        hasLength(1),
      );
      expect(
        dataSource.requests.single
            .where((message) => message.role == MessageRole.user)
            .single
            .content,
        'Build the draft composer flow',
      );
    } finally {
      threadContainer.dispose();
    }
  });

  test(
    'sendMessage auto-enters planning for a new coding thread when configured',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Add explicit planning state","constraints":["Keep behavior backward compatible"],"acceptanceCriteria":["Planning is stored per thread"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Persist planning state on conversations","targetFiles":["lib/features/chat/domain/entities/conversation.dart"],"validationCommand":"flutter test","notes":"Update entity serialization and notifier helpers."},{"title":"Validate planning state persistence","targetFiles":["test/features/chat/presentation/providers/conversations_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the stored planning metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-1',
              createIfMissing: true,
            );
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.sendMessage('Plan the next coding slice');

        final currentConversation = planContainer
            .read(conversationsNotifierProvider)
            .currentConversation;
        expect(currentConversation, isNotNull);
        expect(currentConversation!.isPlanningSession, isTrue);
        expect(currentConversation.messages, hasLength(1));
        expect(
          currentConversation.messages.single.content,
          'Plan the next coding slice',
        );
        expect(planNotifier.state.workflowProposalError, isNull);
        expect(planNotifier.state.taskProposalError, isNull);
        expect(planNotifier.state.isLoading, isFalse);
        expect(proposalDataSource.requests.length, greaterThanOrEqualTo(2));
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'planning proposals include hidden research context from read-only tools',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Add explicit planning state","constraints":["Keep behavior backward compatible"],"acceptanceCriteria":["Planning is stored per thread"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Persist planning state on conversations","targetFiles":["lib/features/chat/domain/entities/conversation.dart"],"validationCommand":"flutter test","notes":"Update entity serialization and notifier helpers."},{"title":"Validate planning state persistence","targetFiles":["test/features/chat/presentation/providers/conversations_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the stored planning metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final toolService = _PlanningResearchMcpToolService();
      final project = CodingProject(
        id: 'project-1',
        name: 'caverno',
        rootPath: '/tmp/planning-project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.sendMessage('Plan the next coding slice');

        final workflowPrompt = proposalDataSource.requests.first.last.content;
        expect(workflowPrompt, contains('Research context:'));
        expect(workflowPrompt, contains('pubspec.yaml'));
        expect(
          workflowPrompt,
          contains('class ChatNotifier extends Notifier<ChatState>'),
        );
        expect(toolService.executedToolNames, contains('list_directory'));
        expect(toolService.executedToolNames, contains('find_files'));
        expect(toolService.executedToolNames, contains('search_files'));
        expect(toolService.executedToolNames, contains('read_file'));
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'planning proposal keeps workflow and task drafts when message saves lag',
    () async {
      final conversationRepository = _DelayedConversationRepository(
        saveDelay: const Duration(milliseconds: 50),
      );
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Add explicit planning state","constraints":["Keep behavior backward compatible"],"acceptanceCriteria":["Planning is stored per thread"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Persist planning state on conversations","targetFiles":["lib/features/chat/domain/entities/conversation.dart"],"validationCommand":"flutter test","notes":"Update entity serialization and notifier helpers."},{"title":"Validate planning state persistence","targetFiles":["test/features/chat/presentation/providers/conversations_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the stored planning metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-1',
              createIfMissing: true,
            );
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.sendMessage('Plan the next coding slice');

        final chatState = planNotifier.state;
        final currentConversation = planContainer
            .read(conversationsNotifierProvider)
            .currentConversation;
        expect(chatState.workflowProposalDraft, isNotNull);
        expect(chatState.taskProposalDraft, isNotNull);
        expect(currentConversation?.planArtifact?.draftMarkdown, isNotNull);
        expect(
          currentConversation?.planArtifact?.draftMarkdown,
          contains('Persist planning state on conversations'),
        );
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'generatePlanProposal keeps the approved markdown while refreshing the draft',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Replan from the approved baseline","constraints":["Keep the approved execution plan stable"],"acceptanceCriteria":["A new draft is generated"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Refresh the draft plan","targetFiles":["README.md"],"validationCommand":"flutter test","notes":"Reuse the approved plan as context."},{"title":"Validate the refreshed draft context","targetFiles":["test/features/chat/presentation/providers/chat_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the regenerated draft metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = planContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown: '# Plan\n\n## Goal\nApproved baseline',
          ),
        );
        final chatNotifier = planContainer.read(chatNotifierProvider.notifier);

        await chatNotifier.generatePlanProposal();

        final currentConversation = planContainer
            .read(conversationsNotifierProvider)
            .currentConversation;
        expect(currentConversation, isNotNull);
        expect(
          currentConversation!.planArtifact?.normalizedApprovedMarkdown,
          '# Plan\n\n## Goal\nApproved baseline',
        );
        expect(
          currentConversation.planArtifact?.normalizedDraftMarkdown,
          contains('Refresh the draft plan'),
        );
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'generatePlanProposal persists task draft before ending task generation',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Create a small Python CLI","constraints":["Keep files minimal"],"acceptanceCriteria":["A runnable task plan is generated"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Create the CLI entrypoint","targetFiles":["main.py"],"validationCommand":"python3 main.py --help","notes":"Add argparse help output."},{"title":"Document the CLI usage","targetFiles":["README.md"],"validationCommand":"python3 main.py --help","notes":"Keep the README short."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      ProviderSubscription<ChatState>? subscription;

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-1',
              createIfMissing: true,
            );
        final taskCountsWhenGenerationEnds = <int>[];
        subscription = planContainer.listen<ChatState>(chatNotifierProvider, (
          previous,
          next,
        ) {
          if (!(previous?.isGeneratingTaskProposal ?? false) ||
              next.isGeneratingTaskProposal ||
              next.taskProposalDraft == null ||
              next.taskProposalError != null) {
            return;
          }
          final markdown = planContainer
              .read(conversationsNotifierProvider)
              .currentConversation
              ?.planArtifact
              ?.normalizedDraftMarkdown;
          if (markdown == null) {
            taskCountsWhenGenerationEnds.add(0);
            return;
          }
          final validation = ConversationPlanProjectionService.validateDocument(
            markdown: markdown,
            requireTasks: true,
          );
          taskCountsWhenGenerationEnds.add(validation.previewTasks.length);
        });
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.generatePlanProposal();

        expect(taskCountsWhenGenerationEnds, [2]);
      } finally {
        subscription?.close();
        planContainer.dispose();
      }
    },
  );

  test('generatePlanProposal includes execution progress when replanning', () async {
    final conversationRepository = _FakeConversationRepository();
    final proposalDataSource = _QueuedProposalDataSource([
      ChatCompletionResult(
        content:
            '{"kind":"proposal","workflowStage":"plan","goal":"Refresh the plan from current execution progress","constraints":["Keep the approved plan stable until a new draft is approved"],"acceptanceCriteria":["Execution progress shapes the next draft"],"openQuestions":[]}',
        finishReason: 'stop',
      ),
      ChatCompletionResult(
        content:
            '{"tasks":[{"title":"Update the draft from execution progress","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter test","notes":"Use completed tasks as context."},{"title":"Validate execution-aware replanning context","targetFiles":["test/features/chat/presentation/providers/chat_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover execution progress in the draft."}]}',
        finishReason: 'stop',
      ),
    ]);
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final planContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final conversationsNotifier = planContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );
      const approvedMarkdown =
          '# Plan\n'
          '\n'
          '## Stage\n'
          'implement\n'
          '\n'
          '## Goal\n'
          'Ground replans in current execution state\n'
          '\n'
          '## Tasks\n'
          '\n'
          '1. Ship the first execution improvement\n'
          '   - Status: pending\n'
          '   - Validation: flutter test\n';
      await conversationsNotifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown: approvedMarkdown,
        ),
      );
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'derived-task-1-legacy',
              title: 'Ship the first execution improvement',
              validationCommand: 'flutter test',
            ),
          ],
        ),
        workflowSourceHash: computeConversationPlanHash(
          approvedMarkdown.trim(),
        ),
        workflowDerivedAt: DateTime(2026, 4, 18, 13, 0),
        preserveWorkflowProjection: true,
      );
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: 'derived-task-1-legacy',
        status: ConversationWorkflowTaskStatus.completed,
        summary: 'Completed during the last implementation pass.',
        eventType: ConversationExecutionTaskEventType.completed,
      );
      final chatNotifier = planContainer.read(chatNotifierProvider.notifier);

      await chatNotifier.generatePlanProposal();

      final workflowPrompt = proposalDataSource.requests.first.last.content;
      expect(workflowPrompt, contains('Execution progress:'));
      expect(workflowPrompt, contains('projectionState: fresh'));
      expect(
        workflowPrompt,
        contains('[completed] Ship the first execution improvement'),
      );
      expect(
        workflowPrompt,
        contains('Completed during the last implementation pass.'),
      );
      expect(
        workflowPrompt,
        contains(
          'recentEvents: completed: Completed during the last implementation pass.',
        ),
      );
    } finally {
      planContainer.dispose();
    }
  });

  test(
    'generatePlanProposalWithContext includes blocker context in proposal prompts',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"clarify","goal":"Resolve the blocker before continuing implementation","constraints":["Preserve the approved plan unless the blocker requires a change"],"acceptanceCriteria":["The blocker is either removed or reflected in the next draft"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Unblock the missing host setup","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter test","notes":"Refresh the plan around the blocker."},{"title":"Validate the blocker-focused replan","targetFiles":["test/features/chat/presentation/providers/chat_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the blocker context in the draft."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = planContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        const approvedMarkdown =
            '# Plan\n'
            '\n'
            '## Stage\n'
            'implement\n'
            '\n'
            '## Goal\n'
            'Keep execution moving with blocker-aware replans\n'
            '\n'
            '## Tasks\n'
            '\n'
            '1. Bring the host setup online\n'
            '   - Status: blocked\n'
            '   - Validation: flutter test\n';
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown: approvedMarkdown,
          ),
        );
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: const ConversationWorkflowSpec(
            tasks: [
              ConversationWorkflowTask(
                id: 'derived-task-1-legacy',
                title: 'Bring the host setup online',
                validationCommand: 'flutter test',
              ),
            ],
          ),
          workflowSourceHash: computeConversationPlanHash(
            approvedMarkdown.trim(),
          ),
          workflowDerivedAt: DateTime(2026, 4, 18, 14, 30),
          preserveWorkflowProjection: true,
        );
        await conversationsNotifier.updateCurrentExecutionTaskProgress(
          taskId: 'derived-task-1-legacy',
          status: ConversationWorkflowTaskStatus.blocked,
          summary: 'The host setup is blocked on missing credentials.',
          blockedReason:
              'Missing SSH credentials for the shared development host.',
        );
        final chatNotifier = planContainer.read(chatNotifierProvider.notifier);

        await chatNotifier.generatePlanProposalWithContext(
          additionalPlanningContext:
              'Focus on the blocked host setup task and either unblock it or add the minimum follow-up work needed.',
        );

        expect(proposalDataSource.requests.length, greaterThanOrEqualTo(2));
        final workflowPrompt = proposalDataSource.requests.first.last.content;
        final taskPrompt = proposalDataSource.requests.last.last.content;
        expect(workflowPrompt, contains('Requested replan focus:'));
        expect(
          workflowPrompt,
          contains('Focus on the blocked host setup task'),
        );
        expect(
          workflowPrompt,
          contains(
            'blockedReason: Missing SSH credentials for the shared development host.',
          ),
        );
        expect(taskPrompt, contains('Requested replan focus:'));
        expect(
          taskPrompt,
          contains(
            'either unblock it or add the minimum follow-up work needed',
          ),
        );
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'planning sessions block write tools with permission_denied results',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': '/tmp/plan-notes.md',
              'content': 'draft plan',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': 'unexpected write'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        await conversationsNotifier.enterPlanningSession();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Inspect the plan before implementation',
          bypassPlanMode: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'write_file');
        expect(result.result, contains('"code":"permission_denied"'));
        expect(
          result.result,
          contains('planning_mode_requires_read_only_tools'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('planning sessions allow read-only local commands to execute', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {'command': 'pwd', 'working_directory': '/tmp'},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'local_execute_command': '{"command":"pwd","stdout":"/tmp"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final conversationsNotifier = toolContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );
      await conversationsNotifier.enterPlanningSession();
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Inspect the working directory first',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'local_execute_command');
      expect(result.result, isNot(contains('"code":"permission_denied"')));
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'planning sessions block git write commands with permission_denied results',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {
              'command': 'checkout -b temp-branch',
              'working_directory': '/tmp',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': 'unexpected git write'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        await conversationsNotifier.enterPlanningSession();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Inspect repository state only',
          bypassPlanMode: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'git_execute_command');
        expect(result.result, contains('"code":"permission_denied"'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote file mutations require approval in default permission mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {'path': 'README.md', 'content': 'remote update'},
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': 'unexpected write'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Write the README remotely',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingFileOperation == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingFileOperation;
        expect(pending, isNotNull);
        expect(pending!.origin, ChatInteractionOrigin.remote);
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveFileOperation(id: pending.id, approved: false);
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote non-read-only local commands require approval in default permission mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'rm -rf build',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unexpected command'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Run the remote cleanup command',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingLocalCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingLocalCommand;
        expect(pending, isNotNull);
        expect(pending!.origin, ChatInteractionOrigin.remote);
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveLocalCommand(
          id: pending.id,
          approval: const LocalCommandApproval(approved: false),
        );
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'run_tests reuses local command approval and preserves result name',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'run_tests',
            arguments: const {
              'test_path': 'test/widget_test.dart',
              'runner': 'flutter',
              'reason': 'Validate the widget change',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"flutter test test/widget_test.dart","exit_code":0,"stdout":"All tests passed.","stderr":""}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Run the scoped widget test',
          bypassPlanMode: true,
        );
        for (
          var i = 0;
          i < 20 && toolNotifier.state.pendingLocalCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingLocalCommand;
        expect(pending, isNotNull);
        expect(pending!.command, "flutter test 'test/widget_test.dart'");
        expect(pending.workingDirectory, '/tmp/project');
        expect(pending.reason, 'Validate the widget change');
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveLocalCommand(
          id: pending.id,
          approval: const LocalCommandApproval(approved: true),
        );
        await sendFuture;

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(
          toolService.executedToolArguments.single['command'],
          "flutter test 'test/widget_test.dart'",
        );
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'run_tests');
        expect(result.arguments['test_path'], 'test/widget_test.dart');
        expect(result.result, contains('"exit_code":0'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'run_tests avoids duplicating nested package path with working directory',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'run_tests',
            arguments: const {
              'test_path': 'prime_numbers_pkg/test/prime_numbers_pkg_test.dart',
              'working_directory': '/tmp/project/prime_numbers_pkg',
              'runner': 'dart',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"dart test test/prime_numbers_pkg_test.dart","exit_code":0,"stdout":"All tests passed.","stderr":""}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Run the nested package test',
          bypassPlanMode: true,
        );

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(
          toolService.executedToolArguments.single['command'],
          "dart test 'test/prime_numbers_pkg_test.dart'",
        );
        expect(
          toolService.executedToolArguments.single['working_directory'],
          '/tmp/project/prime_numbers_pkg',
        );
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'run_tests');
        expect(
          result.result,
          contains('"command":"dart test test/prime_numbers_pkg_test.dart"'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'run_tests infers nested package root for relative test paths',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_run_tests_nested_root_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final packageRoot = Directory('${projectRoot.path}/prime_numbers_pkg');
      await Directory('${packageRoot.path}/test').create(recursive: true);
      await File('${packageRoot.path}/pubspec.yaml').writeAsString('''
name: prime_numbers_pkg
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      await File(
        '${packageRoot.path}/test/prime_numbers_test.dart',
      ).writeAsString("void main() {}\n");
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'run_tests',
            arguments: const {
              'test_path': 'test/prime_numbers_test.dart',
              'runner': 'dart',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': "dart test 'test/prime_numbers_test.dart'",
            'working_directory': packageRoot.path,
            'exit_code': 0,
            'stdout': 'All tests passed.',
            'stderr': '',
          }),
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Run the Dart package test',
          bypassPlanMode: true,
        );

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(
          toolService.executedToolArguments.single['command'],
          "dart test 'test/prime_numbers_test.dart'",
        );
        expect(
          toolService.executedToolArguments.single['working_directory'],
          packageRoot.path,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('run_tests rejects test paths outside the active project', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'run_tests',
          arguments: const {
            'test_path': '../outside/widget_test.dart',
            'runner': 'dart',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'local_execute_command': 'unexpected command'},
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Run the escaped test path',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingLocalCommand, isNull);
      expect(toolService.executedToolNames, isEmpty);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'run_tests');
      expect(result.result, contains('"code":"test_path_outside_project"'));
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'remote saved deny rules block local commands before mobile approval',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'rm -rf build',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unexpected command'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledRemoteDenySettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Run the denied remote cleanup command',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolNotifier.state.pendingLocalCommand, isNull);
        expect(toolService.executedToolNames, isEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'local_execute_command');
        expect(
          result.result,
          contains('Local command was denied by a saved permission rule'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote read-only local commands can execute without approval',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'pwd',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command': '{"command":"pwd","stdout":"/tmp/project"}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Inspect the remote working directory',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolNotifier.state.pendingLocalCommand, isNull);
        expect(toolService.executedToolNames, ['local_execute_command']);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote git writes require approval in default permission mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {
              'command': 'checkout -b remote-branch',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': 'unexpected git write'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Create a branch remotely',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingGitCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingGitCommand;
        expect(pending, isNotNull);
        expect(pending!.origin, ChatInteractionOrigin.remote);
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveGitCommand(id: pending.id, approved: false);
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('auto-review allows file mutations without a pending approval', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': 'README.md', 'content': 'approved update'},
        ),
      ],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this scoped edit."}',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'write_file':
            '{"path":"/tmp/project/README.md","created":false,"bytes_written":15}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledAutoReviewSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Update README', bypassPlanMode: true);
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingFileOperation, isNull);
      expect(toolDataSource.autoReviewRequestMessages, hasLength(1));
      expect(toolService.executedToolNames, ['write_file']);
      expect(toolDataSource.finalAnswerMessages, isNotEmpty);
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains(
          'Operation note: write_file updated or overwrote an existing file',
        ),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('mention this existing-file update in the final answer'),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('end after the concise completion evidence'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage adds analyzer feedback after a successful Dart file mutation',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_diagnostic_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'void main() {}\n',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {'write_file': '{"path":"$changedPath","bytes_written":15}'},
      );
      final diagnosticFeedback = ToolResultInfo(
        id: 'diag-1',
        name: CodingDiagnosticFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
        },
        result: jsonEncode({
          'schema': CodingDiagnosticFeedbackService.schemaName,
          'diagnostic_count': 1,
          'diagnostics': [
            {
              'relative_path': 'lib/main.dart',
              'severity': 'Error',
              'line': 1,
              'column': 6,
              'message': 'Undefined name main.',
            },
          ],
        }),
      );
      final baseline = CodingDiagnosticFeedbackBaseline(
        providerName: 'dart_analyzer',
        projectRoot: projectRoot.path,
        changedPaths: const ['lib/main.dart'],
        diagnostics: [
          CodeDiagnostic(
            absolutePath: changedPath,
            severity: 'Warning',
            line: 1,
            column: 1,
            message: 'Existing warning.',
          ),
        ],
        telemetry: const CodingDiagnosticTelemetry(durationMs: 1, attempts: []),
      );
      final diagnosticService = _FakeCodingDiagnosticFeedbackService(
        diagnosticFeedback,
        baseline: baseline,
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            diagnosticService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Update the Dart entrypoint');

        expect(diagnosticService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(diagnosticService.baselineProjectRoots, [projectRoot.path]);
        expect(diagnosticService.baselineChangedPaths.single, [changedPath]);
        expect(diagnosticService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(diagnosticService.receivedBaselines, [same(baseline), isNull]);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file', CodingDiagnosticFeedbackService.toolName],
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage adds command output feedback for zero-exit artifact errors',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_command_output_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final command = 'python3 get_weather.py';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: {
              'command': command,
              'working_directory': projectRoot.path,
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': projectRoot.path,
            'exit_code': 0,
            'stdout':
                'Saved report to tokyo_weather.md\n\n# Error\n\nNo data found for 2026-06-02.\n',
            'stderr': '',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            _FakeCodingVerificationFeedbackService(null),
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the weather report');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          [
            'local_execute_command',
            CodingCommandOutputGuardrailService.toolName,
          ],
        );
        final feedback = toolDataSource.toolResultBatches.single.singleWhere(
          (result) =>
              result.name == CodingCommandOutputGuardrailService.toolName,
        );
        final payload = jsonDecode(feedback.result) as Map<String, dynamic>;
        expect(
          payload['schema'],
          CodingCommandOutputGuardrailService.schemaName,
        );
        expect(payload['success'], isFalse);
        expect(payload['validation_status'], 'failed');
        expect(jsonEncode(payload['issues']), contains(command));
        expect(jsonEncode(payload['issues']), contains('Markdown error'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage runs real analyzer feedback after a broken Dart mutation',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_real_diagnostic_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      await File('${projectRoot.path}/pubspec.yaml').writeAsString('''
name: caverno_diagnostic_feedback_fixture
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': '''
void main() {
  print(missingAnalyzerFeedbackCanarySymbol);
}
''',
            },
          ),
        ],
      );
      final toolService = _WritingFileMcpToolService(projectRoot);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Write a broken Dart entrypoint');

        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file', CodingDiagnosticFeedbackService.toolName],
        );
        final diagnosticResult = toolDataSource.toolResultBatches.single
            .singleWhere(
              (result) =>
                  result.name == CodingDiagnosticFeedbackService.toolName,
            );
        final payload =
            jsonDecode(diagnosticResult.result) as Map<String, dynamic>;
        expect(payload['schema'], CodingDiagnosticFeedbackService.schemaName);
        expect(payload['changed_paths'], ['lib/main.dart']);
        expect(payload['diagnostic_count'], greaterThanOrEqualTo(1));
        expect(
          jsonEncode(payload['diagnostics']),
          contains('missingAnalyzerFeedbackCanarySymbol'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'sendMessage blocks completion claims with coding verification feedback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will fix the failing test now.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback,
            null,
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(verificationService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(verificationService.requestedTriggers, [
          CodingVerificationTrigger.completionClaim,
          CodingVerificationTrigger.completionClaim,
        ]);
        expect(toolService.executedToolNames, ['write_file', 'write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[0].map((result) => result.name),
          ['write_file'],
        );
        expect(
          toolDataSource.toolResultBatches[1].map((result) => result.name),
          [CodingVerificationFeedbackService.toolName],
        );
        expect(
          toolDataSource.toolResultBatches[2].map((result) => result.name),
          ['write_file'],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, isNot(contains('is done')));
        expect(finalContent, contains('Validation passed'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage skips coding verification feedback when disabled',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_disabled_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final writeCall = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [writeCall],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': ['{"path":"$changedPath","bytes_written":18}'],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-disabled',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService(
        verificationFeedback,
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoVerificationSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, isEmpty);
        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file'],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('is complete'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage skips completion verification in request-only mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_request_only_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'int value() => 1;\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': ['{"path":"$changedPath","bytes_written":18}'],
        },
      );
      final verificationService = _FakeCodingVerificationFeedbackService(
        ToolResultInfo(
          id: 'verify-request-only',
          name: CodingVerificationFeedbackService.toolName,
          arguments: const {
            'project_root': 'project',
            'changed_paths': ['lib/main.dart'],
            'trigger': 'completionClaim',
          },
          result: jsonEncode({
            'schema': CodingVerificationFeedbackService.schemaName,
            'provider': 'dart_test_runner',
            'trigger': 'completionClaim',
            'validation_status': 'failed',
            'changed_paths': ['lib/main.dart'],
            'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
            'failing_tests': const [],
          }),
        ),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledRequestOnlyVerificationSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, isEmpty);
        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('is complete'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage records coding verification snapshots on execution progress',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_progress_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final testPath = '${projectRoot.path}/test/main_test.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will fix the failing test now.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final failedSnapshot = _codingVerificationSnapshot(
        projectRoot: projectRoot.path,
        changedPath: 'lib/main.dart',
        validationStatus: ConversationExecutionValidationStatus.failed,
        passedCount: 0,
        failedCount: 1,
        exitCode: 1,
        failures: [
          CodingVerificationFailure(
            testName: 'value returns two',
            absolutePath: testPath,
            line: 4,
            message: 'Expected: <2> Actual: <1>',
          ),
        ],
      );
      final passedSnapshot = _codingVerificationSnapshot(
        projectRoot: projectRoot.path,
        changedPath: 'lib/main.dart',
        validationStatus: ConversationExecutionValidationStatus.passed,
        passedCount: 1,
        failedCount: 0,
        exitCode: 0,
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-progress-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService.runs([
        CodingVerificationFeedbackRun(
          snapshot: failedSnapshot,
          toolResult: verificationFeedback,
        ),
        CodingVerificationFeedbackRun(
          snapshot: passedSnapshot,
          toolResult: null,
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown:
                '# Plan\n'
                '\n'
                '## Stage\n'
                'implement\n'
                '\n'
                '## Goal\n'
                'Fix a failing Dart test\n'
                '\n'
                '## Tasks\n'
                '\n'
                '1. Fix tests\n'
                '   - Status: inProgress\n'
                '   - Validation: flutter test\n',
          ),
        );
        await conversationsNotifier
            .refreshCurrentWorkflowProjectionFromApprovedPlan();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        final progress = toolContainer
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.executionProgress
            .single;
        expect(progress, isNotNull);
        expect(progress!.status, ConversationWorkflowTaskStatus.completed);
        expect(
          progress.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
        expect(
          progress.lastValidationCommand,
          'flutter test --machine test/main_test.dart',
        );
        expect(
          progress.lastValidationSummary,
          contains('Coding verification passed'),
        );
        final validationEvents = progress.events
            .where(
              (event) =>
                  event.type == ConversationExecutionTaskEventType.validated,
            )
            .toList(growable: false);
        expect(validationEvents, hasLength(2));
        expect(
          validationEvents.first.validationStatus,
          ConversationExecutionValidationStatus.failed,
        );
        expect(
          validationEvents.first.validationSummary,
          contains('Actual: <1>'),
        );
        expect(
          validationEvents.last.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks streamed completion claims with verification feedback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_stream_verification_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I wrote the requested Dart file.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will repair the failing test before finishing.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The task "Fix tests" is done.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-stream-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback,
            null,
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(verificationService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(verificationService.requestedTriggers, [
          CodingVerificationTrigger.completionClaim,
          CodingVerificationTrigger.completionClaim,
        ]);
        expect(toolService.executedToolNames, ['write_file', 'write_file']);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[0].map((result) => result.name),
          ['write_file'],
        );
        expect(
          toolDataSource.toolResultBatches[1].map((result) => result.name),
          [CodingVerificationFeedbackService.toolName],
        );
        expect(
          toolDataSource.toolResultBatches[2].map((result) => result.name),
          ['write_file'],
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops repeated verification repair for unchanged failures',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_convergence_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      ToolCallInfo writeCall(String id, String content) {
        return ToolCallInfo(
          id: id,
          name: 'write_file',
          arguments: {'path': 'lib/main.dart', 'content': content},
        );
      }

      ToolResultInfo verificationFeedback(String id) {
        return ToolResultInfo(
          id: id,
          name: CodingVerificationFeedbackService.toolName,
          arguments: const {
            'project_root': 'project',
            'changed_paths': ['lib/main.dart'],
            'trigger': 'completionClaim',
          },
          result: jsonEncode({
            'schema': CodingVerificationFeedbackService.schemaName,
            'provider': 'dart_test_runner',
            'trigger': 'completionClaim',
            'validation_status': 'failed',
            'changed_paths': ['lib/main.dart'],
            'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
            'failing_tests': [
              {
                'relative_path': 'test/main_test.dart',
                'test_name': 'value returns two',
                'line': 4,
                'message': 'Expected: <2> Actual: <1>',
              },
            ],
          }),
        );
      }

      final initialWrite = writeCall('tool-1', 'int value() => 1;\n');
      final firstRepairWrite = writeCall('tool-2', 'int value() => 2;\n');
      final secondRepairWrite = writeCall('tool-3', 'int value() => 3;\n');
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will repair the failing test.',
            toolCalls: [firstRepairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will try one more repair.',
            toolCalls: [secondRepairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback('verify-1'),
            verificationFeedback('verify-2'),
            verificationFeedback('verify-3'),
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(toolService.executedToolNames, [
          'write_file',
          'write_file',
          'write_file',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(5));
        expect(
          toolDataSource.toolResultBatches.map(
            (batch) => batch.map((result) => result.name).toList(),
          ),
          [
            ['write_file'],
            [CodingVerificationFeedbackService.toolName],
            ['write_file'],
            [CodingVerificationFeedbackService.toolName],
            ['write_file'],
          ],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('not complete'));
        expect(finalContent, contains('same failing tests persisted'));
        expect(finalContent, contains('value returns two'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'auto-review malformed output falls back to manual git approval',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {
              'command': 'checkout -b reviewed-branch',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        autoReviewResponses: [
          ChatCompletionResult(content: 'allow it', finishReason: 'stop'),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': 'unexpected git write'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledAutoReviewSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Create a branch',
          bypassPlanMode: true,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingGitCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingGitCommand;
        expect(pending, isNotNull);
        expect(toolDataSource.autoReviewRequestMessages, hasLength(1));
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveGitCommand(id: pending!.id, approved: false);
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );
}

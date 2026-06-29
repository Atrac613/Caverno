import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test('includes selected project context in coding mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      toolNames: const [
        'list_directory',
        'read_file',
        'write_file',
        'resolve_installed_dependency',
        'local_execute_command',
        'os_get_system_info',
        'os_log_read',
        'git_execute_command',
        'git_finish_worktree_session',
      ],
      projectName: 'caverno',
      projectRootPath: '/Users/noguwo/Documents/Workspace/Flutter/caverno',
    );

    expect(prompt, contains('Project name: "caverno".'));
    expect(
      prompt,
      contains(
        'Project root path: /Users/noguwo/Documents/Workspace/Flutter/caverno.',
      ),
    );
    expect(
      prompt,
      contains(
        'prefer this project root as the working directory if one is not explicitly provided',
      ),
    );
    expect(
      prompt,
      contains(
        'For codebase exploration, prefer list_directory, find_files, search_files, and read_file before using local shell commands.',
      ),
    );
    expect(
      prompt,
      contains(
        'When analyzing Caverno LLM session logs, treat each JSONL line as a caverno_llm_session_log_entry object',
      ),
    );
    expect(
      prompt,
      contains(
        'Separate user-facing chat turns from background secondary calls in Caverno session logs',
      ),
    );
    expect(prompt, contains('memory_extractor_system'));
    expect(
      prompt,
      contains(
        'do not '
        'substitute a nearby file as the requested one based on proximity',
      ),
    );
    expect(
      prompt,
      contains('stop investigating that copy instead of recursing'),
    );
    expect(
      prompt,
      contains('call resolve_installed_dependency before guessing'),
    );
    expect(
      prompt,
      contains(
        'Use os_get_system_info when the current machine operating system or version matters.',
      ),
    );
    expect(
      prompt,
      contains(
        'For local machine diagnostics, prefer os_log_read when you need recent WiFi, network, or authentication logs from the current computer.',
      ),
    );
    expect(
      prompt,
      contains(
        'Before interpreting local OS logs, call os_get_system_info first if the current OS or version is unclear.',
      ),
    );
    expect(
      prompt,
      contains(
        'If a tool result contains permission_denied or bookmark_restore_failed',
      ),
    );
    expect(
      prompt,
      contains(
        'Each git_execute_command call must contain exactly one git subcommand',
      ),
    );
    expect(
      prompt,
      contains(
        'Direct git write operations such as add, commit, checkout, merge',
      ),
    );
    expect(
      prompt,
      contains('Before creating a git tag, inspect existing tags'),
    );
    expect(
      prompt,
      contains(
        'use git_finish_worktree_session after all intended changes are committed',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not claim that local files were created, edited, moved, saved, or deleted unless an application-executed tool result confirms the successful operation.',
      ),
    );
    expect(
      prompt,
      contains(
        'If the user asks to delete a local project file and no dedicated file-delete tool is available',
      ),
    );
    expect(
      prompt,
      contains('Do not guess that an opaque identifier is an end-user device'),
    );
  });

  test('does not include project context in general mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      projectName: 'caverno',
      projectRootPath: '/Users/noguwo/Documents/Workspace/Flutter/caverno',
    );

    expect(prompt, isNot(contains('Project root path:')));
    expect(prompt, isNot(contains('Project name: "caverno".')));
  });

  test('includes participant role prompt in the system prompt', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 6, 23, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      participantRolePrompt: 'Respond as the senior engineering reviewer.',
    );

    expect(
      prompt,
      contains('Participant role instructions for this response:'),
    );
    expect(prompt, contains('Respond as the senior engineering reviewer.'));
  });

  test('includes the research-honesty instruction in every mode', () {
    for (final mode in AssistantMode.values) {
      final prompt = SystemPromptBuilder.build(
        now: DateTime(2026, 4, 13, 10, 30),
        assistantMode: mode,
        languageCode: 'en',
      );

      expect(
        prompt,
        contains('Do not claim to have searched'),
        reason: 'honesty instruction missing for $mode',
      );
    }
  });

  test('warns against fabricated browser_open URLs when browser tools '
      'are available', () {
    final withBrowser = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const ['browser_open', 'browser_snapshot', 'search_web'],
    );
    expect(withBrowser, contains('Do not fabricate deep URLs'));

    final withoutBrowser = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const ['search_web'],
    );
    expect(withoutBrowser, isNot(contains('Do not fabricate deep URLs')));
  });

  test('includes repository map context in coding mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      projectName: 'caverno',
      projectRootPath: '/workspace/caverno',
      repoMapContext: '''
Root: /workspace/caverno
Key files:
- lib/main.dart
Dart symbols:
- lib/main.dart: class AppRoot, function bootstrap
''',
    );

    expect(prompt, contains('Repository map for the active project.'));
    expect(prompt, contains('<repo_map>'));
    expect(prompt, contains('Root: /workspace/caverno'));
    expect(prompt, contains('class AppRoot'));
    expect(prompt, contains('</repo_map>'));
    expect(
      prompt,
      contains('verify current file contents with tools before editing'),
    );
  });

  test('does not include repository map context in general mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      repoMapContext: 'Root: /workspace/caverno',
    );

    expect(prompt, isNot(contains('<repo_map>')));
    expect(prompt, isNot(contains('Root: /workspace/caverno')));
  });

  test('includes exact preservation guidance in normal text prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 6, 10, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
    );

    expect(prompt, contains('EXACT PRESERVATION:'));
    expect(prompt, contains('URLs, file paths, file names'));
    expect(prompt, contains('IDs and opaque identifiers'));
    expect(prompt, contains('JSON keys and scalar values'));
    expect(prompt, contains('Keep 2026-06-12 as 2026-06-12'));
    expect(prompt, contains('keep \u00a53,980 exactly'));
  });

  test('keeps voice mode natural speech guidance separate', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 6, 10, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      isVoiceMode: true,
    );

    expect(prompt, contains('VOICE MODE:'));
    expect(prompt, contains('Never output URLs'));
    expect(prompt, contains('YYYY-MM-DD dates'));
    expect(prompt, contains('Express dates/times naturally'));
    expect(prompt, isNot(contains('EXACT PRESERVATION:')));
  });

  test('instructs tool search before missing tool claims', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const ['tool_search', 'get_current_datetime'],
    );

    expect(prompt, contains('Available tools:'));
    expect(
      prompt,
      contains(
        'If the task needs a tool or capability that is not listed in Available tools, call tool_search',
      ),
    );
    expect(prompt, contains('After tool_search returns a match'));
    expect(prompt, contains('Treat tool_search as free'));
    expect(
      prompt,
      contains('only state that something is unavailable after tool_search'),
    );
  });

  test('omits proactive tool_search guidance without tool_search', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const ['web_search'],
    );

    expect(prompt, isNot(contains('Treat tool_search as free')));
  });

  test('treats MCP search tools as web search tools', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const ['search_web', 'search_images'],
    );

    expect(prompt, contains('Use search_images, search_web for web search.'));
  });

  test('includes knowledge-cutoff humility and self-reference ban', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 6, 10, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
    );

    expect(
      prompt,
      contains('Your training knowledge may predate the current date above.'),
    );
    expect(
      prompt,
      contains('Mention your knowledge cutoff only when it is genuinely'),
    );
    expect(
      prompt,
      contains(
        'Do not attribute your behavior to your system prompt or internal',
      ),
    );
  });

  test('includes formatting minimization in normal but not voice prompts', () {
    final normal = SystemPromptBuilder.build(
      now: DateTime(2026, 6, 10, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
    );
    final voice = SystemPromptBuilder.build(
      now: DateTime(2026, 6, 10, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      isVoiceMode: true,
    );

    expect(normal, contains('Use the minimum formatting needed for clarity.'));
    expect(
      voice,
      isNot(contains('Use the minimum formatting needed for clarity.')),
    );
  });

  test('includes model capability guidance for weak tool-call profiles', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      toolNames: const ['get_current_datetime', 'edit_file'],
      modelCapabilityProfile: ModelCapabilityProfile(
        id: '',
        baseUrl: 'http://localhost:1234/v1',
        model: 'weak-tool-model',
        toolCallStyle: ModelToolCallStyle.embeddedToolTags,
        structuredOutputSupport: ModelStructuredOutputSupport.none,
        editFormatPreference: ModelEditFormatPreference.searchReplace,
        usableContextTokens: 4096,
      ).normalizedForPersistence(),
    );

    expect(prompt, contains('MODEL CAPABILITY PROFILE:'));
    expect(prompt, contains('Caverno textual tool-call tags'));
    expect(prompt, contains('<tool_call>{"name":"tool_name"'));
    expect(prompt, contains('weak structured-output adherence'));
    expect(prompt, contains('search-and-replace edit blocks'));
    expect(prompt, contains('4096 usable context tokens'));
    expect(prompt, contains('LL15 WEAK-MODEL EDIT HARNESS'));
    expect(prompt, contains('Example edit_file arguments'));
  });

  test('skips weak-model edit harness for strong structured profiles', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      toolNames: const ['read_file', 'edit_file'],
      modelCapabilityProfile: ModelCapabilityProfile(
        id: '',
        baseUrl: 'http://localhost:1234/v1',
        model: 'strong-tool-model',
        toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
        editFormatPreference: ModelEditFormatPreference.searchReplace,
        usableContextTokens: 32768,
      ).normalizedForPersistence(),
    );

    expect(prompt, contains('MODEL CAPABILITY PROFILE:'));
    expect(prompt, contains('reliable native tool calls'));
    expect(prompt, isNot(contains('LL15 WEAK-MODEL EDIT HARNESS')));
  });

  test('instructs browser tools to refresh refs before actions', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const [
        'browser_snapshot',
        'browser_fill',
        'browser_click',
        'browser_submit',
      ],
    );

    expect(
      prompt,
      contains('Do not claim the browser action is complete from prose'),
    );
    expect(prompt, contains('call browser_snapshot before using browser_fill'));
    expect(prompt, contains('Use only refs from the latest browser_snapshot'));
    expect(prompt, contains('do not guess refs'));
    expect(prompt, contains('prefer browser_submit'));
    expect(prompt, contains('element_not_found'));
    expect(prompt, contains('refresh refs before retrying'));
  });

  test(
    'instructs background execution and local_execute_command alternatives',
    () {
      final prompt = SystemPromptBuilder.build(
        now: DateTime(2026, 5, 3, 9, 0),
        assistantMode: AssistantMode.coding,
        languageCode: 'en',
        toolNames: const [
          'local_execute_command',
          'process_start',
          'process_status',
          'process_tail',
          'process_wait',
          'run_tests',
        ],
      );

      expect(
        prompt,
        contains(
          'For full project test suites such as flutter test, '
          'fvm flutter test, dart test, or fvm dart test with no specific '
          'test path, use local_execute_command with background=true or '
          'process_start instead of run_tests.',
        ),
      );
      expect(
        prompt,
        contains(
          'Use local_execute_command with background=true, or use process_start '
          'for builds, releases, migrations, uploads, long tests, or commands '
          'expected to run longer than roughly one minute.',
        ),
      );
      expect(
        prompt,
        contains(
          'include_finished: false) to find and refresh running jobs started '
          'with process_start or background local_execute_command',
        ),
      );
      expect(prompt, contains('do not merely wait silently'));
      expect(
        prompt,
        contains('report concise progress with the latest observed phase'),
      );
    },
  );

  test('marks injected session context as historical evidence', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 28, 13, 50),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      toolNames: const ['list_directory', 'read_file'],
      sessionMemoryContext: '''
[Recent Session Summaries]
- Investigation identified native byte processing as the root cause.
[Retrieved Memories]
- (high) Android BLE data reception is corrupted.
''',
    );

    expect(
      prompt,
      contains(
        'Treat [Recent Session Summaries] and [Retrieved Memories] as historical context',
      ),
    );
    expect(
      prompt,
      contains('not verified evidence about the current workspace'),
    );
    expect(
      prompt,
      contains(
        'do not present prior assistant conclusions from it as confirmed',
      ),
    );
    expect(
      prompt,
      contains('current application-executed tool results support them'),
    );
    expect(
      prompt,
      contains(
        'Investigation identified native byte processing as the root cause.',
      ),
    );
  });

  test('includes saved workflow context in coding mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      workflowStage: ConversationWorkflowStage.plan,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Ship a spec-lite workflow for coding threads',
        constraints: ['Keep the first slice lightweight'],
        acceptanceCriteria: ['Persist the workflow with the conversation'],
        openQuestions: ['Task graph can come later'],
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Add task persistence',
            status: ConversationWorkflowTaskStatus.inProgress,
            targetFiles: [
              'lib/features/chat/domain/entities/conversation_workflow.dart',
            ],
            validationCommand: 'flutter test',
          ),
        ],
      ),
    );

    expect(
      prompt,
      contains('Current workflow stage for this coding thread: plan.'),
    );
    expect(
      prompt,
      contains('Goal: Ship a spec-lite workflow for coding threads'),
    );
    expect(prompt, contains('Constraints: Keep the first slice lightweight'));
    expect(
      prompt,
      contains(
        'Acceptance criteria: Persist the workflow with the conversation',
      ),
    );
    expect(prompt, contains('Open questions: Task graph can come later'));
    expect(prompt, contains('Saved tasks:'));
    expect(prompt, contains('[in_progress] Add task persistence'));
    expect(
      prompt,
      contains(
        'files: lib/features/chat/domain/entities/conversation_workflow.dart',
      ),
    );
    expect(prompt, contains('validate: flutter test'));
    expect(
      prompt,
      contains(
        'When a saved task is complete, continue to the next pending saved task automatically instead of asking for confirmation between tasks.',
      ),
    );
    expect(
      prompt,
      contains(
        'When writing CLI validation scripts, assert success versus non-zero failure semantics unless the saved task explicitly requires a platform-specific exit code.',
      ),
    );
    expect(
      prompt,
      contains(
        'If normal file or command approvals are shown by the app, treat those approvals as sufficient and do not ask for duplicate permission in natural language.',
      ),
    );
  });

  test('includes plan mode guidance in plan prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.plan,
      languageCode: 'en',
      toolNames: const ['list_directory', 'read_file'],
      projectName: 'caverno',
      projectRootPath: '/Users/noguwo/Documents/Workspace/Flutter/caverno',
    );

    expect(
      prompt,
      contains(
        'When the user is planning software work, first produce a clear plan',
      ),
    );
    expect(prompt, contains('Project name: "caverno".'));
  });

  test('includes macOS computer-use operating policy when tools exist', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      toolNames: const [
        'computer_vision_observe',
        'computer_accessibility_snapshot',
        'computer_list_displays',
        'computer_list_windows',
        'computer_screenshot',
        'computer_screenshot_window',
        'computer_open_system_settings',
        'computer_click',
        'computer_type_text',
        'computer_switch_space',
      ],
    );

    expect(prompt, contains('start with computer_vision_observe'));
    expect(prompt, contains('For macOS Spaces'));
    expect(prompt, contains('space_scope=all_spaces'));
    expect(prompt, contains('computer_switch_space'));
    expect(
      prompt,
      contains(
        'observe again with computer_vision_observe before deciding the next desktop action',
      ),
    );
    expect(
      prompt,
      contains(
        'Use raw computer_list_displays, computer_list_windows, computer_screenshot',
      ),
    );
    expect(prompt, contains('Use computer_accessibility_snapshot'));
    expect(prompt, contains('current snapshot'));
    expect(prompt, contains('elementGrounding candidates'));
    expect(prompt, contains('element_id'));
    expect(prompt, contains('target.elementId'));
    expect(prompt, contains('target appName, windowTitle, role, label'));
    expect(
      prompt,
      contains(
        'Include window_id for window screenshots, source_width, source_height, coordinate_space, and vision_observation_id',
      ),
    );
    expect(prompt, contains('Read the actionProposalPolicy'));
    expect(prompt, contains('Treat productionActionPolicy'));
    expect(prompt, contains('execution result intake'));
    expect(prompt, contains('include the exact text to type'));
    expect(prompt, contains('target.risk=public_action'));
    expect(prompt, contains('target.risk to secure_field'));
    expect(prompt, contains('do not ask Caverno to execute'));
    expect(prompt, contains('observe-action-observe cycle'));
    expect(prompt, contains('follow the returned nextAction'));
    expect(
      prompt,
      contains('credential, payment, destructive, or external-send behavior'),
    );
  });

  test('includes plan document context in coding prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Ship an editable plan artifact',
      ),
      planArtifact: const ConversationPlanArtifact(
        draftMarkdown: '# Plan\n\n## Goal\nDraft',
        approvedMarkdown: '# Plan\n\n## Goal\nApproved',
      ),
    );

    expect(
      prompt,
      contains(
        'Approved plan document for this coding thread (source of truth while implementing):',
      ),
    );
    expect(prompt, contains('# Plan\n## Goal\nApproved'));
    expect(
      prompt,
      contains(
        'A newer draft plan document exists, but the last approved document remains the source of truth until the draft is approved.',
      ),
    );
    expect(
      prompt,
      contains(
        'Treat the structured workflow data below as a supporting execution projection, not as a separate source of truth.',
      ),
    );
  });

  test('injects active coding goals into coding mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      goal: ConversationGoal(
        id: 'goal-1',
        objective: 'Fix the login crash and verify the regression test',
        tokenBudget: 20000,
        tokenUsage: 5000,
        turnBudget: 5,
        turnsUsed: 2,
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
      ),
    );

    expect(prompt, contains('Active coding goal for this thread:'));
    expect(
      prompt,
      contains('Fix the login crash and verify the regression test'),
    );
    expect(prompt, contains('Goal token budget remaining: 15000'));
    expect(prompt, contains('Goal turn budget remaining: 3'));
    expect(prompt, contains('Continue moving it forward'));
    expect(prompt, contains('When the goal is complete'));
  });

  test('suppresses autonomous continuation guidance for exhausted goals', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      goal: ConversationGoal(
        id: 'goal-1',
        objective: 'Fix the login crash and verify the regression test',
        tokenBudget: 20000,
        tokenUsage: 20000,
        turnBudget: 5,
        turnsUsed: 5,
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
      ),
    );

    expect(prompt, contains('Active coding goal for this thread:'));
    expect(
      prompt,
      contains('Fix the login crash and verify the regression test'),
    );
    expect(prompt, contains('Goal token budget remaining: 0'));
    expect(prompt, contains('Goal turn budget remaining: 0'));
    expect(prompt, contains('The goal budget is exhausted.'));
    expect(prompt, isNot(contains('Continue moving it forward')));
    expect(prompt, isNot(contains('When the goal is complete')));
  });

  test(
    'does not inject completed goals even when their budget is exhausted',
    () {
      final prompt = SystemPromptBuilder.build(
        now: DateTime(2026, 5, 25, 10, 30),
        assistantMode: AssistantMode.coding,
        goal: ConversationGoal(
          id: 'goal-1',
          objective: 'Fix the login crash',
          status: ConversationGoalStatus.completed,
          tokenBudget: 100,
          tokenUsage: 100,
          turnBudget: 1,
          turnsUsed: 1,
          createdAt: DateTime(2026, 5, 25, 10),
          updatedAt: DateTime(2026, 5, 25, 10),
        ),
      );

      expect(prompt, isNot(contains('Active coding goal for this thread:')));
      expect(prompt, isNot(contains('Fix the login crash')));
      expect(prompt, isNot(contains('The goal budget is exhausted.')));
    },
  );

  test('does not inject disabled coding goals', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      goal: ConversationGoal(
        id: 'goal-1',
        objective: 'Fix the login crash',
        enabled: false,
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
      ),
    );

    expect(prompt, isNot(contains('Active coding goal for this thread:')));
    expect(prompt, isNot(contains('Fix the login crash')));
  });

  test('injects model harness config instruction surfaces', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      modelHarnessConfig: const ModelHarnessConfig(
        id: 'cfg',
        model: 'qwen-test',
        bootstrapInstruction: 'Identify the required output artifact first.',
        failureRecoveryInstruction: 'Re-read the file before retrying an edit.',
        explorationToEditNudgeEnabled: true,
      ),
    );

    expect(
      prompt,
      contains(
        'MODEL HARNESS GUIDANCE (bootstrap): '
        'Identify the required output artifact first.',
      ),
    );
    expect(
      prompt,
      contains(
        'MODEL HARNESS GUIDANCE (failure recovery): '
        'Re-read the file before retrying an edit.',
      ),
    );
    expect(prompt, contains('MODEL HARNESS GUIDANCE (exploration):'));
    // Surfaces left empty fall back to built-in guidance and emit nothing.
    expect(prompt, isNot(contains('MODEL HARNESS GUIDANCE (execution)')));
    expect(prompt, isNot(contains('MODEL HARNESS GUIDANCE (verification)')));
    // The recovery directive is gated on its own toggle.
    expect(prompt, isNot(contains('MODEL HARNESS GUIDANCE (recovery)')));
  });

  test('emits the recovery directive only when the toggle is enabled', () {
    final enabled = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      modelHarnessConfig: const ModelHarnessConfig(
        id: 'cfg',
        model: 'm',
        recoveryMiddlewareEnabled: true,
      ),
    );
    final disabled = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      modelHarnessConfig: const ModelHarnessConfig(id: 'cfg', model: 'm'),
    );

    expect(enabled, contains('MODEL HARNESS GUIDANCE (recovery):'));
    expect(enabled, contains('do not '));
    expect(disabled, isNot(contains('MODEL HARNESS GUIDANCE')));
  });

  test('omits harness guidance when config is absent or override-free', () {
    final withoutConfig = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
    );
    final overrideFree = SystemPromptBuilder.build(
      now: DateTime(2026, 5, 25, 10, 30),
      assistantMode: AssistantMode.coding,
      modelHarnessConfig: const ModelHarnessConfig(id: 'cfg', model: 'm'),
    );

    expect(withoutConfig, isNot(contains('MODEL HARNESS GUIDANCE')));
    expect(overrideFree, isNot(contains('MODEL HARNESS GUIDANCE')));
  });
}

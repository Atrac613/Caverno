import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';

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
        'local_execute_command',
        'os_get_system_info',
        'os_log_read',
        'git_execute_command',
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
      contains('Before creating a git tag, inspect existing tags'),
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
        ],
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
}

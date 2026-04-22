import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
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
}

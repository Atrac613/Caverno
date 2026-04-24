import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

class _FakeChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void main() {
  late ProviderContainer container;
  late ChatNotifier notifier;

  setUp(() {
    container = ProviderContainer(
      overrides: [chatNotifierProvider.overrideWith(_FakeChatNotifier.new)],
    );
    notifier = container.read(chatNotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('parses workflow proposal json payloads', () {
    final proposal = notifier.parseWorkflowProposalForTest('''
```json
{"workflowStage":"plan","goal":"Ship workflow approvals","constraints":["Keep the UI lightweight"],"acceptanceCriteria":["Users can review before saving"],"openQuestions":["Should quick fixes skip this flow?"]}
```
''');

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.goal, 'Ship workflow approvals');
    expect(proposal.workflowSpec.constraints, ['Keep the UI lightweight']);
    expect(proposal.workflowSpec.acceptanceCriteria, [
      'Users can review before saving',
    ]);
    expect(proposal.workflowSpec.openQuestions, [
      'Should quick fixes skip this flow?',
    ]);
  });

  test('treats empty assistant content as not visibly renderable', () {
    expect(notifier.assistantMessageHasVisibleContentForTest(''), isFalse);
    expect(notifier.assistantMessageHasVisibleContentForTest('   '), isFalse);
  });

  test('treats memory update only content as not visibly renderable', () {
    const content =
        '<tool_use>{"name":"memory_update","status":"updated"}</tool_use>';

    expect(notifier.assistantMessageHasVisibleContentForTest(content), isFalse);
  });

  test('treats thinking content as visibly renderable', () {
    const content = '<think>Inspecting the requirements file.</think>';

    expect(notifier.assistantMessageHasVisibleContentForTest(content), isTrue);
  });

  test('normalizes write_file contents alias into content', () {
    final resolved = notifier.normalizeWriteFileArgumentsForTest({
      'contents': '# README',
    });

    expect(resolved['content'], '# README');
  });

  test('parses workflow planning decision payloads', () {
    final decisions = notifier.parseWorkflowDecisionsForTest('''
{"kind":"decision","decisions":[
  {"id":"scope","question":"Which implementation scope should the plan target?","help":"Pick the slice you want first.","options":[
    {"id":"minimal","label":"Minimal slice","description":"Ship the smallest end-to-end version first."},
    {"id":"full","label":"Broader slice","description":"Cover the full workflow in one pass."}
  ]}
]}
''');

    expect(decisions, isNotNull);
    expect(decisions!, hasLength(1));
    expect(
      decisions.first.question,
      'Which implementation scope should the plan target?',
    );
    expect(decisions.first.help, 'Pick the slice you want first.');
    expect(decisions.first.options, hasLength(2));
    expect(decisions.first.options.first.label, 'Minimal slice');
    expect(
      decisions.first.options.first.description,
      'Ship the smallest end-to-end version first.',
    );
  });

  test('parses workflow free-text decision payloads', () {
    final decisions = notifier.parseWorkflowDecisionsForTest('''
{"kind":"decision","decisions":[
  {"id":"environment","question":"What is the deployment environment for this script?","help":"A short answer is enough.","inputMode":"freeText","placeholder":"staging / production / local","options":[]}
]}
''');

    expect(decisions, isNotNull);
    expect(decisions!, hasLength(1));
    expect(
      decisions.first.question,
      'What is the deployment environment for this script?',
    );
    expect(decisions.first.allowFreeText, isTrue);
    expect(decisions.first.freeTextPlaceholder, 'staging / production / local');
    expect(decisions.first.options, isEmpty);
  });

  test('promotes yes or no open questions into planning decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'Should quick fixes skip workflow generation?',
    ]);

    expect(decisions, hasLength(1));
    expect(
      decisions.first.question,
      'Should quick fixes skip workflow generation?',
    );
    expect(decisions.first.options.map((option) => option.label), [
      'Yes',
      'No',
    ]);
  });

  test('promotes alternative open questions into planning decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'Should we use polling or webhooks?',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.question, 'Should we use polling or webhooks?');
    expect(decisions.first.options.map((option) => option.label), [
      'polling',
      'webhooks',
    ]);
  });

  test('promotes three-way english open questions into decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'Which should we prioritize first: backend, API, or UI?',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.options.map((option) => option.label), [
      'backend',
      'API',
      'UI',
    ]);
  });

  test('promotes ordered english open questions into decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'Should we do backend first or UI first?',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.options.map((option) => option.label), [
      'backend first',
      'UI first',
    ]);
  });

  test('promotes sequence english open questions into decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'Should we do backend first, then UI or UI first, then backend?',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.options.map((option) => option.label), [
      'backend first, then UI',
      'UI first, then backend',
    ]);
  });

  test('promotes japanese alternative open questions into decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'CLI と UI のどちらを優先しますか？',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.options.map((option) => option.label), [
      'CLI',
      'UI',
    ]);
  });

  test('promotes three-way japanese open questions into decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'CLI、UI、API のどれを優先しますか？',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.options.map((option) => option.label), [
      'CLI',
      'UI',
      'API',
    ]);
  });

  test('promotes ordered japanese open questions into decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest(['CLI先行かUI先行か？']);

    expect(decisions, hasLength(1));
    expect(decisions.first.options.map((option) => option.label), [
      'CLI先行',
      'UI先行',
    ]);
  });

  test(
    'does not promote non-choice open questions into planning decisions',
    () {
      final decisions = notifier.promoteOpenQuestionsForTest([
        'What is the deployment environment for this script?',
      ]);

      expect(decisions, isEmpty);
    },
  );

  test(
    'does not promote example lists in open questions into planning decisions',
    () {
      final decisions = notifier.promoteOpenQuestionsForTest([
        'Which system metrics (e.g., CPU, RAM, Disk) should be prioritized in the next slice?',
      ]);

      expect(decisions, isEmpty);
    },
  );

  test('does not promote comma-only choice hints into planning decisions', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'Which operating systems (Linux, macOS, Windows) are the primary targets?',
    ]);

    expect(decisions, isEmpty);
  });

  test(
    'parses workflow proposal json payloads with localized stage values',
    () {
      final proposal = notifier.parseWorkflowProposalForTest('''
{"workflowStage":"計画","goal":"ワークフロー提案を保存できるようにする","constraints":["UI は軽量のままにする"],"acceptanceCriteria":["ユーザーが保存前に確認できる"],"openQuestions":[]}
''');

      expect(proposal, isNotNull);
      expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
      expect(proposal.workflowSpec.goal, 'ワークフロー提案を保存できるようにする');
    },
  );

  test('parses workflow proposal plain text sections', () {
    final proposal = notifier.parseWorkflowProposalForTest('''
Workflow Stage: Plan
Goal: Add workflow proposal approval
Constraints:
- Keep the first slice lightweight
Acceptance Criteria:
- Users can review the proposal before saving
Open Questions:
- Should quick fixes skip workflow generation?
''');

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.constraints, [
      'Keep the first slice lightweight',
    ]);
    expect(proposal.workflowSpec.openQuestions, [
      'Should quick fixes skip workflow generation?',
    ]);
  });

  test('parses truncated workflow proposal json payloads', () {
    final proposal = notifier.parseWorkflowProposalForTest('''
{"workflowStage":"plan","goal":"Refine the readiness plan","constraints":["Audit assets","Verify Android and iOS config"],"acceptanceCriteria":["The saved workflow covers the missing areas"],"openQuestions":[]
''');

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.constraints, [
      'Audit assets',
      'Verify Android and iOS config',
    ]);
  });

  test('parses workflow proposals from reasoning-only responses', () {
    final proposal = notifier.parseWorkflowProposalForTest('''
<think>
* Workflow Stage: Plan
* Goal: Build a Python host health checker
* Constraint: Keep the first slice lightweight
* Acceptance Criteria: The script checks the configured hosts successfully
</think>
''');

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.goal, 'Build a Python host health checker');
    expect(proposal.workflowSpec.constraints, [
      'Keep the first slice lightweight',
    ]);
    expect(proposal.workflowSpec.acceptanceCriteria, [
      'The script checks the configured hosts successfully',
    ]);
  });

  test('sanitizes polluted workflow proposals from reasoning-only responses', () {
    final proposal = notifier.parseWorkflowProposalForTest('''
<think>
* Workflow Stage: Plan
* Goal: Create a Python script to diagnose the health status of specific hosts. Recent Context: The user wants to create a Python script to diagnose the health status of specific hosts. 'kind': "proposal" 'workflowStage': "plan"
* Constraints: Python-based implementation.
* Acceptance Criteria: Successful connectivity verification.
* Open Questions: Which metrics are required?
</think>
''');

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(
      proposal.workflowSpec.goal,
      'Create a Python script to diagnose the health status of specific hosts.',
    );
    expect(proposal.workflowSpec.constraints, ['Python-based implementation.']);
    expect(proposal.workflowSpec.openQuestions, [
      'Which metrics are required?',
    ]);
  });

  test('parses workflow proposals from truncated narrative retries', () {
    final proposal = notifier.parseWorkflowProposalForTest('''
The user wants a workflow proposal for creating a Python CLI tool that pings specific hosts. The project name is tmp-live-ping-cli. The research context shows the project is currently empty. The user's request is "pythonで特定のhostにpingするcliスクリプトを作りたい".
''');

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.goal, 'pythonで特定のhostにpingするcliスクリプトを作りたい');
  });

  test(
    'builds workflow proposal fallback from reasoning-only truncation without punctuation',
    () {
      final conversation = Conversation(
        id: 'conversation-2',
        title: 'Ping CLI',
        messages: [
          Message(
            id: 'user-1',
            content: 'pythonで特定のhostにpingするcliスクリプトを作りたい',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 21, 19, 43),
          ),
        ],
        createdAt: DateTime(2026, 4, 21, 19, 43),
        updatedAt: DateTime(2026, 4, 21, 19, 43),
      );
      final proposal = notifier.buildWorkflowProposalTruncationFallbackForTest(
        currentConversation: conversation,
        rawContent: '''
<think>
The user wants to create a Python CLI script that pings a specific host The project name is tmp-live-ping-cli The current state is that the project root seems empty or lacks structure The user's request is "pythonで特定のhostにpingするcliスクリプトを作りたい"
</think>
''',
      );

      expect(proposal, isNotNull);
      expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
      expect(
        proposal.workflowSpec.goal,
        'create a Python CLI script that pings a specific host',
      );
    },
  );

  test('builds workflow fallback from truncated retries after decisions', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Ping CLI',
      messages: [
        Message(
          id: 'user-1',
          content: 'Create a Python CLI tool that pings specific hosts.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 19, 22, 30),
        ),
      ],
      createdAt: DateTime(2026, 4, 19, 22, 30),
      updatedAt: DateTime(2026, 4, 19, 22, 30),
    );

    final proposal = notifier.buildWorkflowProposalTruncationFallbackForTest(
      currentConversation: conversation,
      rawContent: '''
<think>
The user wants a workflow proposal for creating a Python CLI tool that pings specific hosts.
The project root appears empty, so the plan should keep the first slice lightweight.
</think>
''',
      decisionAnswers: const [
        WorkflowPlanningDecisionAnswer(
          decisionId: 'scope',
          question: 'What is the primary scope of the CLI tool?',
          optionId: 'single-host',
          optionLabel: 'Single-host reachability checks',
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
    expect(
      proposal.workflowSpec.goal,
      'Create a Python CLI tool that pings specific hosts.',
    );
    expect(
      proposal.workflowSpec.constraints,
      contains(
        'Resolved decision: What is the primary scope of the CLI tool? -> Single-host reachability checks',
      ),
    );
    expect(proposal.workflowSpec.acceptanceCriteria, isNotEmpty);
  });

  test('parses task proposal json payloads', () {
    final proposal = notifier.parseTaskProposalForTest('''
{"tasks":[
  {"title":"Add workflow proposal card","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter analyze","notes":"Keep approval UI compact"},
  {"title":"Hook proposal state into ChatState","targetFiles":["lib/features/chat/presentation/providers/chat_state.dart"],"validationCommand":"","notes":""}
]}
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(2));
    expect(proposal.tasks.first.title, 'Add workflow proposal card');
    expect(proposal.tasks.first.targetFiles, [
      'lib/features/chat/presentation/pages/chat_page.dart',
    ]);
    expect(proposal.tasks.first.validationCommand, 'flutter analyze');
    expect(proposal.tasks.first.notes, 'Keep approval UI compact');
    expect(
      proposal.tasks.every(
        (task) => task.status == ConversationWorkflowTaskStatus.pending,
      ),
      isTrue,
    );
  });

  test('parses inline numbered task plans from truncated reasoning text', () {
    final proposal = notifier.parseTaskProposalForTest('''
Plan: 1. Initialize the Python project structure and requirements.txt.
2. Implement the core ping logic in src/ping_engine.py.
3. Add a CLI entrypoint in src/main.py and validate it.
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks.length, greaterThanOrEqualTo(2));
    expect(
      proposal.tasks.map((task) => task.title),
      contains('Implement the core ping logic in src/ping_engine.py'),
    );
    expect(
      proposal.tasks.map((task) => task.title),
      contains('Add a CLI entrypoint in src/main.py and validate it'),
    );
  });

  test('drops placeholder task titles from task proposals', () {
    final proposal = notifier.parseTaskProposalForTest('''
{"tasks":[
  {"title":"Subsequent tasks should involve:","targetFiles":[],"validationCommand":"","notes":""},
  {"title":"Implement the core ping logic","targetFiles":["src/ping_cli/main.py"],"validationCommand":"python -m src.ping_cli.main --help","notes":"Keep the first version synchronous"},
  {"title":"Add CLI argument parsing","targetFiles":["src/ping_cli/main.py"],"validationCommand":"python -m src.ping_cli.main --help","notes":""}
]}
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(2));
    expect(
      proposal.tasks.map((task) => task.title),
      contains('Implement the core ping logic'),
    );
    expect(
      proposal.tasks.map((task) => task.title),
      isNot(contains('Subsequent tasks should involve:')),
    );
  });

  test(
    'finalizeTaskProposalForTest filters low-quality tasks and fixes README typos',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_task_quality_gate_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rawTasks = (fixture['tasks'] as List<dynamic>)
          .map((entry) => entry as Map<String, dynamic>)
          .map(ConversationWorkflowTask.fromJson)
          .toList(growable: false);

      final finalized = notifier.finalizeTaskProposalForTest(
        WorkflowTaskProposalDraft(tasks: rawTasks),
        projectLooksEmpty: true,
      );

      expect(finalized.tasks, hasLength(2));
      expect(finalized.tasks.first.title, 'Initialize project structure');
      expect(finalized.tasks.first.targetFiles, [
        'README.md',
        'requirements.txt',
        '.gitignore',
        'main.py',
      ]);
      expect(
        finalized.tasks.map((task) => task.title),
        isNot(
          contains(
            "Argparse, click, or typer? (I'll assume argparse for simplicity)",
          ),
        ),
      );
      expect(
        finalized.tasks.map((task) => task.title),
        isNot(contains('Host input: CLI arguments:')),
      );
    },
  );

  test(
    'marks single scaffold-only task proposals for retry in empty workspaces',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_task_proposal_too_short_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final proposal = notifier.parseTaskProposalForTest(
        fixture['rawContent'] as String,
      );

      expect(proposal, isNotNull);
      final finalized = notifier.finalizeTaskProposalForTest(
        proposal!,
        projectLooksEmpty: true,
      );

      expect(finalized.tasks, hasLength(1));
      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isTrue,
      );
    },
  );

  test('builds minimal retry context for short empty-workspace task lists', () {
    final context = notifier.buildTaskProposalRetryContextForTest(
      null,
      minimalRetry: true,
      projectLooksEmpty: true,
    );

    expect(context, isNotNull);
    expect(context, contains('Return two to four concrete tasks.'));
    expect(context, contains('Do not stop at a single generic setup'));
    expect(context, contains('The first task may scaffold the workspace'));
    expect(
      context,
      contains('Prefer a simple Python entrypoint such as main.py'),
    );
    expect(
      context,
      contains('Do not use generic validation such as "module importable"'),
    );
    expect(
      context,
      contains(
        'Prefer Python standard-library or subprocess-based implementations over third-party runtime dependencies unless the user explicitly asked for a package.',
      ),
    );
  });

  test('builds task proposal fallback from truncated planning retries', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/plan_mode_ping_cli_truncated_task_proposal_latest_replay.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final conversation = Conversation(
      id: 'conversation-2',
      title: 'Ping CLI',
      messages: [
        Message(
          id: 'user-2',
          content: 'Create a Python CLI tool that pings specific hosts.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 20, 21, 30),
        ),
      ],
      createdAt: DateTime(2026, 4, 20, 21, 30),
      updatedAt: DateTime(2026, 4, 20, 21, 30),
      workflowSpec: const ConversationWorkflowSpec(
        goal:
            'Develop a Python CLI tool for continuous pinging with JSON output support.',
        constraints: ['Python-based implementation', 'CLI-driven interface'],
        acceptanceCriteria: [
          'Support continuous pinging',
          'Output valid JSON behind a flag',
        ],
      ),
    );

    final proposal = notifier.buildTaskProposalTruncationFallbackForTest(
      currentConversation: conversation,
      rawContent: fixture['rawContent'] as String,
      projectLooksEmpty: true,
    );

    expect(proposal, isNotNull);
    expect(proposal!.tasks.length, greaterThanOrEqualTo(2));
    expect(
      proposal.tasks.first.title,
      'Initialize project structure and requirements.txt',
    );
    expect(
      proposal.tasks.map((task) => task.title),
      contains(
        'Implement core ping functionality and CLI arguments in main.py',
      ),
    );
    expect(
      proposal.tasks.map((task) => task.title),
      contains('Add continuous ping loop and interval options in main.py'),
    );
    expect(
      proposal.tasks.map((task) => task.title),
      contains('Add JSON output support in main.py'),
    );
  });

  test('marks weak implementation validation task proposals for retry', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/plan_mode_ping_cli_weak_validation_task_proposal_replay.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rawTasks = (fixture['tasks'] as List<dynamic>)
        .map((entry) => entry as Map<String, dynamic>)
        .map(ConversationWorkflowTask.fromJson)
        .toList(growable: false);
    final proposal = WorkflowTaskProposalDraft(tasks: rawTasks);

    final finalized = notifier.finalizeTaskProposalForTest(
      proposal,
      projectLooksEmpty: true,
    );

    expect(
      notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
      isTrue,
    );
  });

  test(
    'buildTaskProposalQualityGateFallbackForTest recovers from exhausted task proposal retries',
    () {
      final conversation = Conversation(
        id: 'conversation-quality-fallback',
        title: 'Ping CLI',
        messages: [
          Message(
            id: 'user-quality-fallback',
            content: 'Create a Python CLI tool that pings specific hosts.',
            role: MessageRole.user,
            timestamp: DateTime(2026, 4, 23, 13, 40),
          ),
        ],
        createdAt: DateTime(2026, 4, 23, 13, 40),
        updatedAt: DateTime(2026, 4, 23, 13, 40),
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Create a Python CLI tool that pings a host from the terminal.',
          constraints: ['Use subprocess', 'Keep the workspace lightweight'],
          acceptanceCriteria: [
            'The script exposes a CLI help screen',
            'The tool can verify ping execution with a bounded command',
          ],
        ),
      );
      final rejectedCandidate = WorkflowTaskProposalDraft(
        tasks: const [
          ConversationWorkflowTask(
            id: 'task-implement',
            title: 'Implement ping_cli.py using subprocess',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Create the Python entrypoint.',
          ),
          ConversationWorkflowTask(
            id: 'task-verify',
            title: 'Verify ping functionality',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py 8.8.8.8',
            notes: 'Run the CLI against a host.',
          ),
        ],
      );

      final fallback = notifier.buildTaskProposalQualityGateFallbackForTest(
        currentConversation: conversation,
        projectLooksEmpty: true,
        bestRetryCandidate: rejectedCandidate,
      );

      expect(fallback, isNotNull);
      expect(fallback!.tasks.length, greaterThanOrEqualTo(2));
      expect(
        notifier.taskProposalNeedsRetryForTest(fallback, fallback, true),
        isFalse,
      );
      expect(
        fallback.tasks.first.title,
        'Initialize project structure and requirements.txt',
      );
      expect(
        fallback.tasks.map((task) => task.title),
        contains(
          'Implement core ping functionality and CLI arguments in main.py',
        ),
      );
    },
  );

  test('marks duplicate verification tasks for retry', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/plan_mode_ping_cli_duplicate_verification_tasks_replay.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rawTasks = (fixture['tasks'] as List<dynamic>)
        .map((entry) => entry as Map<String, dynamic>)
        .map(ConversationWorkflowTask.fromJson)
        .toList(growable: false);
    final proposal = WorkflowTaskProposalDraft(tasks: rawTasks);

    final finalized = notifier.finalizeTaskProposalForTest(
      proposal,
      projectLooksEmpty: true,
    );

    expect(
      notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
      isTrue,
    );
  });

  test(
    'marks duplicate verification tasks with the same validator for retry',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_duplicate_verification_validation_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rawTasks = (fixture['tasks'] as List<dynamic>)
          .map((entry) => entry as Map<String, dynamic>)
          .map(ConversationWorkflowTask.fromJson)
          .toList(growable: false);
      final proposal = WorkflowTaskProposalDraft(tasks: rawTasks);

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isTrue,
      );
    },
  );

  test(
    'marks pytest-based verification tasks for retry in empty workspaces',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-setup',
            title: 'Initialize project configuration',
            targetFiles: ['requirements.txt', 'pyproject.toml'],
            validationCommand: 'ls requirements.txt pyproject.toml',
            notes: 'Create the initial Python project files.',
          ),
          const ConversationWorkflowTask(
            id: 'task-implement',
            title: 'Implement the core ping CLI logic in ping_cli.py',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Use subprocess for the first version.',
          ),
          const ConversationWorkflowTask(
            id: 'task-verify',
            title: 'Create a test script to verify the CLI functionality',
            targetFiles: ['tests/test_ping.py'],
            validationCommand: 'python3 -m pytest tests/test_ping.py',
            notes: 'Verify the script against a reachable host.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isTrue,
      );
    },
  );

  test(
    'marks external Python runtime dependency implementation tasks for retry in empty workspaces',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-setup',
            title: 'Initialize project configuration',
            targetFiles: ['requirements.txt'],
            validationCommand: 'ls requirements.txt',
            notes: 'Create the initial dependency file.',
          ),
          const ConversationWorkflowTask(
            id: 'task-implement',
            title: 'Implement ping CLI in main.py',
            targetFiles: ['main.py'],
            validationCommand: 'python3 main.py --help',
            notes: 'Implement the core logic using a ping library.',
          ),
          const ConversationWorkflowTask(
            id: 'task-verify',
            title: 'Verify ping functionality with a single packet',
            targetFiles: ['main.py'],
            validationCommand: 'python3 main.py 127.0.0.1 -c 1',
            notes: 'Verify the CLI against loopback.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isTrue,
      );
    },
  );

  test(
    'normalizes unbounded ping verification commands to a bounded validator',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-setup',
            title: 'Create project structure and README',
            targetFiles: ['README.md'],
            validationCommand: 'ls README.md',
            notes: 'Initialize the repository with basic documentation.',
          ),
          const ConversationWorkflowTask(
            id: 'task-implement',
            title: 'Implement ping CLI in main.py',
            targetFiles: ['main.py'],
            validationCommand: 'python3 main.py --help',
            notes: 'Use subprocess to call the system ping command.',
          ),
          const ConversationWorkflowTask(
            id: 'task-verify',
            title: 'Verify ping functionality with a local host',
            targetFiles: ['main.py'],
            validationCommand: 'python3 main.py 127.0.0.1',
            notes: 'Run the ping CLI against loopback.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        finalized.tasks.last.validationCommand,
        'python3 main.py 127.0.0.1 -c 1',
      );
      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isFalse,
      );
    },
  );

  test(
    'marks fragmented single-file implementation plans for retry in empty workspaces',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-implement-core',
            title: 'Implement ping_cli.py with subprocess-based ping logic',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Use argparse to accept a host and subprocess to run ping.',
          ),
          const ConversationWorkflowTask(
            id: 'task-implement-json',
            title: 'Implement JSON output formatting in ping_cli.py',
            targetFiles: ['ping_cli.py'],
            validationCommand:
                'python3 ping_cli.py 127.0.0.1 | python3 -m json.tool',
            notes: 'Ensure the output is a valid JSON object.',
          ),
          const ConversationWorkflowTask(
            id: 'task-verify',
            title: 'Verify ping_cli.py execution with a single ping',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py 127.0.0.1',
            notes: 'Run one bounded ping against loopback.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isTrue,
      );
    },
  );

  test('dedupes near-duplicate README and implementation tasks', () {
    final proposal = WorkflowTaskProposalDraft(
      tasks: [
        const ConversationWorkflowTask(
          id: 'task-readme-1',
          title: 'Create README.md with usage instructions',
          targetFiles: ['README.md'],
          validationCommand: 'cat README.md',
          notes: 'Document the first slice.',
        ),
        const ConversationWorkflowTask(
          id: 'task-readme-2',
          title: 'Create README.md with usage and installation instructions',
          targetFiles: ['README.md'],
          validationCommand: 'cat README.md',
          notes: 'Expand setup guidance.',
        ),
        const ConversationWorkflowTask(
          id: 'task-cli-1',
          title: 'Implement the ping CLI tool in ping_cli.py',
          targetFiles: ['ping_cli.py'],
          validationCommand: 'python3 ping_cli.py --help',
          notes: 'Keep the first version synchronous.',
        ),
        const ConversationWorkflowTask(
          id: 'task-cli-2',
          title:
              'Implement the core ping functionality and CLI interface in ping_cli.py',
          targetFiles: ['ping_cli.py'],
          validationCommand: 'python3 ping_cli.py --help',
          notes: 'Cover the same entrypoint in a second task.',
        ),
      ],
    );

    final finalized = notifier.finalizeTaskProposalForTest(
      proposal,
      projectLooksEmpty: true,
    );

    expect(finalized.tasks, hasLength(2));
    expect(
      finalized.tasks.map((task) => task.title),
      contains('Create README.md with usage instructions'),
    );
    expect(
      finalized.tasks.map((task) => task.title),
      contains('Implement the ping CLI tool in ping_cli.py'),
    );
    expect(
      finalized.tasks.map((task) => task.title),
      isNot(
        contains('Create README.md with usage and installation instructions'),
      ),
    );
    expect(
      finalized.tasks.map((task) => task.title),
      isNot(
        contains(
          'Implement the core ping functionality and CLI interface in ping_cli.py',
        ),
      ),
    );
    expect(
      notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
      isFalse,
    );
  });

  test(
    'dedupes near-duplicate implementation tasks from title-only targets',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-cli-1',
            title: 'Implement ping_cli.py with subprocess and argparse',
            targetFiles: [],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Use a simple Python CLI entrypoint.',
          ),
          const ConversationWorkflowTask(
            id: 'task-cli-2',
            title: 'Implement the ping CLI tool in ping_cli.py',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Cover the same file in a second task.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(finalized.tasks, hasLength(1));
      expect(
        finalized.tasks.single.title,
        'Implement ping_cli.py with subprocess and argparse',
      );
      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isTrue,
      );
    },
  );

  test('normalizes portable ls validation commands in task proposals', () {
    final proposal = WorkflowTaskProposalDraft(
      tasks: [
        const ConversationWorkflowTask(
          id: 'task-setup',
          title: 'Initialize project structure and requirements.txt',
          targetFiles: ['requirements.txt'],
          validationCommand: 'ls -F',
          notes: 'Create the initial dependency file.',
        ),
      ],
    );

    final finalized = notifier.finalizeTaskProposalForTest(
      proposal,
      projectLooksEmpty: true,
    );

    expect(finalized.tasks.single.validationCommand, 'ls');
  });

  test(
    'normalizes python validation commands to python3 in task proposals',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-cli',
            title: 'Implement ping_cli.py with subprocess logic',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python ping_cli.py --help',
            notes: 'Use argparse and subprocess.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        finalized.tasks.single.validationCommand,
        'python3 ping_cli.py --help',
      );
    },
  );

  test('drops placeholder task fields from truncated task proposals', () {
    final proposal = WorkflowTaskProposalDraft(
      tasks: [
        const ConversationWorkflowTask(
          id: 'task-setup',
          title: 'Initialize project structure and dependencies',
          targetFiles: ['requirements.txt', 'pyproject.toml'],
          validationCommand: 'string',
          notes: 'string',
        ),
        const ConversationWorkflowTask(
          id: 'task-cli-placeholder',
          title: 'Implement the ping CLI tool',
          targetFiles: ['string'],
          validationCommand: 'string',
          notes: 'string',
        ),
        const ConversationWorkflowTask(
          id: 'task-cli',
          title: 'Implement the ping CLI tool in ping_cli.py',
          targetFiles: ['ping_cli.py'],
          validationCommand: 'python3 ping_cli.py --help',
          notes: 'Use argparse and subprocess.',
        ),
      ],
    );

    final finalized = notifier.finalizeTaskProposalForTest(
      proposal,
      projectLooksEmpty: true,
    );

    expect(finalized.tasks, hasLength(2));
    expect(finalized.tasks.first.validationCommand, isEmpty);
    expect(finalized.tasks.first.notes, isEmpty);
    expect(
      finalized.tasks.map((task) => task.title),
      isNot(contains('Implement the ping CLI tool')),
    );
    expect(
      finalized.tasks.map((task) => task.title),
      contains('Implement the ping CLI tool in ping_cli.py'),
    );
  });

  test('drops non-path target file fragments from task proposals', () {
    final proposal = WorkflowTaskProposalDraft(
      tasks: [
        const ConversationWorkflowTask(
          id: 'task-readme',
          title: 'Create README.md with project description',
          targetFiles: [
            'README.md',
            'ls README.md',
            'The README will outline the validation approach.',
            'tasks',
            'title',
            'how it would be used',
          ],
          validationCommand: 'ls README.md',
          notes: 'Document the first slice.',
        ),
      ],
    );

    final finalized = notifier.finalizeTaskProposalForTest(
      proposal,
      projectLooksEmpty: true,
    );

    expect(finalized.tasks.single.targetFiles, ['README.md']);
  });

  test(
    'allows scaffold tasks with placeholder code files when follow-up validation is concrete',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: [
          const ConversationWorkflowTask(
            id: 'task-setup',
            title: 'Initialize project structure and pyproject.toml',
            targetFiles: [
              'pyproject.toml',
              'README.md',
              'src/ping_cli/__init__.py',
              'src/ping_cli/main.py',
            ],
            validationCommand: 'ls -R src',
            notes: 'Create the basic scaffold files.',
          ),
          const ConversationWorkflowTask(
            id: 'task-core',
            title: 'Implement core ping functionality using subprocess',
            targetFiles: ['src/ping_cli/main.py'],
            validationCommand: 'python3 -m src.ping_cli.main --help',
            notes: 'Use argparse and subprocess.',
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(
        notifier.taskProposalNeedsRetryForTest(proposal, finalized, true),
        isFalse,
      );
    },
  );

  test('parses task proposal plain text sections', () {
    final proposal = notifier.parseTaskProposalForTest('''
1. Add workflow proposal card
Target files:
- lib/features/chat/presentation/pages/chat_page.dart
Validation command: flutter analyze
Notes: Keep the approval UI compact

2. Add workflow proposal tests
Target files:
- test/features/chat/presentation/providers/chat_notifier_workflow_proposal_test.dart
Validation command: flutter test
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(2));
    expect(proposal.tasks.first.title, 'Add workflow proposal card');
    expect(proposal.tasks.first.targetFiles, [
      'lib/features/chat/presentation/pages/chat_page.dart',
    ]);
    expect(proposal.tasks.first.validationCommand, 'flutter analyze');
    expect(proposal.tasks.first.notes, 'Keep the approval UI compact');
  });

  test('parses truncated task proposal json payloads', () {
    final proposal = notifier.parseTaskProposalForTest('''
{"tasks":[{"title":"Add workflow proposal card","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter analyze","notes":"Keep approval UI compact"},
{"title":"Add proposal retry handling","targetFiles":["lib/features/chat/presentation/providers/chat_notifier.dart"],"validationCommand":"flutter test","notes":"Retry compact generation if truncated"}
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(2));
    expect(proposal.tasks.first.title, 'Add workflow proposal card');
    expect(proposal.tasks.last.validationCommand, 'flutter test');
  });

  test('salvages truncated task proposal json into multiple tasks', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/plan_mode_ping_cli_truncated_task_proposal_replay.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final proposal = notifier.parseTaskProposalForTest(
      fixture['rawContent'] as String,
    );

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(2));
    expect(proposal.tasks.first.title, 'Initialize project structure');
    expect(proposal.tasks.last.title, 'Implement ping CLI entrypoint');
    expect(proposal.tasks.last.targetFiles, ['main.py']);
  });

  test('parses task proposals from reasoning-only responses', () {
    final proposal = notifier.parseTaskProposalForTest('''
<think>
1. Add the host health checker script
Target files:
- scripts/health_check.py
Validation command: python scripts/health_check.py --help
Notes: Keep the first version minimal
</think>
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(1));
    expect(proposal.tasks.first.title, 'Add the host health checker script');
    expect(proposal.tasks.first.targetFiles, ['scripts/health_check.py']);
    expect(
      proposal.tasks.first.validationCommand,
      'python3 scripts/health_check.py --help',
    );
    expect(proposal.tasks.first.notes, 'Keep the first version minimal');
  });

  test('builds clarify fallback proposal from unresolved decisions', () {
    final proposal = notifier.buildWorkflowProposalFallbackForTest(
      decisions: const [
        WorkflowPlanningDecision(
          id: 'metrics',
          question: 'Which metrics should the script collect?',
          options: [
            WorkflowPlanningDecisionOption(
              id: 'cpu',
              label: 'CPU only',
              description: '',
            ),
            WorkflowPlanningDecisionOption(
              id: 'all',
              label: 'CPU, memory, and disk',
              description: '',
            ),
          ],
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.clarify);
    expect(proposal.workflowSpec.openQuestions, [
      'Which metrics should the script collect?',
    ]);
  });

  test('merges unresolved decisions into the latest proposal fallback', () {
    final proposal = notifier.buildWorkflowProposalFallbackForTest(
      latestProposal: WorkflowProposalDraft(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Build a host health checker',
          constraints: ['Keep the first slice lightweight'],
        ),
      ),
      decisions: const [
        WorkflowPlanningDecision(
          id: 'metrics',
          question: 'Which metrics should the script collect?',
          options: [
            WorkflowPlanningDecisionOption(
              id: 'cpu',
              label: 'CPU only',
              description: '',
            ),
            WorkflowPlanningDecisionOption(
              id: 'all',
              label: 'CPU, memory, and disk',
              description: '',
            ),
          ],
        ),
      ],
      decisionAnswers: const [
        WorkflowPlanningDecisionAnswer(
          decisionId: 'output',
          question: 'Which output format should the script use?',
          optionId: 'json',
          optionLabel: 'JSON',
        ),
      ],
    );

    expect(proposal, isNotNull);
    expect(proposal!.workflowStage, ConversationWorkflowStage.clarify);
    expect(proposal.workflowSpec.goal, 'Build a host health checker');
    expect(proposal.workflowSpec.openQuestions, [
      'Which metrics should the script collect?',
    ]);
  });
}

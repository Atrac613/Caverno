import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
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

  test('promotes non-choice open questions into free-text prompts', () {
    final decisions = notifier.promoteOpenQuestionsForTest([
      'What is the deployment environment for this script?',
    ]);

    expect(decisions, hasLength(1));
    expect(decisions.first.allowFreeText, isTrue);
    expect(
      decisions.first.question,
      'What is the deployment environment for this script?',
    );
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
      'python scripts/health_check.py --help',
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

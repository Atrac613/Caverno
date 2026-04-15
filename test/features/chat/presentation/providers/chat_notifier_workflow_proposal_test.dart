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
}

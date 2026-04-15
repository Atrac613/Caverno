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
}
